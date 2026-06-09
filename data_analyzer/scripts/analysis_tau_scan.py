"""
analysis_tau_scan.py — Retroactive τ (threshold) scanning on existing Exp2 CSVs.

Key insight: All images were fully executed (we have totalMs for every image).
By using infiProbPerson, we can retroactively simulate different τ values:

  D(x, τ) = 1 if infiProbPerson >= τ, else 0

Then for each τ:
  - Kept Images = count of records where infiProbPerson >= τ
  - Total Cost   = sum of totalMs (or latencyMs) for kept records
  - Efficiency   = Kept Images / Total Cost  (images per ms)
  - Filter Rate  = (N - Kept) / N

The goal: plot Efficiency(τ) curves per Context, find τ* = argmax Efficiency,
and compare τ*(Light) vs τ*(Mid) to verify threshold drift.
"""
import os
import pandas as pd
import numpy as np
import sys

# ── File registry ──
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data')
FILES = {
    'Idle': {
        'path': os.path.join(DATA_DIR, 'idle_full.csv'),
        'skiprows': 1,
        'schema': 'v1',  # 18 cols, no tau column
    },
    'Light': {
        'path': os.path.join(DATA_DIR, 'light_full.csv'),
        'skiprows': 0,
        'schema': 'v2',  # 29 cols, has tau + full system metrics
    },
    'Mid': {
        'path': os.path.join(DATA_DIR, 'mid_full.csv'),
        'skiprows': 0,
        'schema': 'v2',
    },
}

# ── Load data ──
def load_csv(meta):
    df = pd.read_csv(meta['path'], skiprows=meta.get('skiprows', 0))

    # Normalize numeric columns
    for col in ['infiProbPerson', 'totalMs', 'latencyMs', 'prepMs',
                'batteryTempC', 'cpuProcPct', 'cpuSysPct', 'thermalLevel',
                'batteryPowerMw', 'batteryCurrentMa', 'batteryVoltageMv']:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce')

    # Derived
    if 'batteryPowerMw' in df.columns:
        df['batteryPowerW'] = df['batteryPowerMw'] / 1000.0
    if 'cpuProcPct' in df.columns and 'cpuSysPct' in df.columns:
        df['cpuTotalPct'] = df['cpuProcPct'] + df['cpuSysPct']

    return df

print("=" * 72)
print("  Retroactive τ Scanning — Efficiency(τ, context) Analysis")
print("=" * 72)

dfs = {}
for label, meta in FILES.items():
    dfs[label] = load_csv(meta)
    print(f"  [{label}] {len(dfs[label])} records, schema={meta['schema']}")
print()

# ── τ scan ──
# Idle has binary infiProbPerson → only τ ∈ {0, 1} meaningful, skip fine scan
# Light & Mid have continuous infiProbPerson → scan from 0.50 to 0.99

TAU_VALUES = np.arange(0.50, 0.99, 0.01)  # 0.50, 0.51, ..., 0.98

print("=" * 72)
print("【τ Scan: Efficiency = Kept Images / Total Cost】")
print("-" * 72)

for label in ['Light', 'Mid']:
    df = dfs[label]
    N = len(df)
    prob = df['infiProbPerson']

    print(f"\n  [{label}] (N={N})")
    print(f"  {'τ':>6}  {'Kept':>6}  {'Filter%':>7}  "
          f"{'SumTotalMs':>12}  {'SumLatencyMs':>12}  "
          f"{'Eff(total)':>12}  {'Eff(lat)':>12}  {'AvgMs/Img':>10}  {'ΔEff%':>8}")
    print(f"  {'─'*6}  {'─'*6}  {'─'*7}  "
          f"{'─'*12}  {'─'*12}  "
          f"{'─'*12}  {'─'*12}  {'─'*10}  {'─'*8}")

    # Baseline at τ=0.50 (essentially all images kept)
    baseline_mask = prob >= 0.50
    baseline_kept = baseline_mask.sum()
    baseline_sum_total = df.loc[baseline_mask, 'totalMs'].sum()
    baseline_eff = baseline_kept / baseline_sum_total if baseline_sum_total > 0 else 0

    results = []
    for tau in TAU_VALUES:
        mask = prob >= tau
        kept = mask.sum()
        if kept == 0:
            results.append((tau, 0, 0.0, 0, 0, 0.0, 0.0, 0.0, 0.0))
            continue

        filtered_pct = (N - kept) / N * 100
        sum_total = df.loc[mask, 'totalMs'].sum()
        sum_latency = df.loc[mask, 'latencyMs'].sum()
        eff_total = kept / sum_total if sum_total > 0 else 0
        eff_lat = kept / sum_latency if sum_latency > 0 else 0
        avg_ms = sum_total / kept
        delta_eff = (eff_total - baseline_eff) / baseline_eff * 100 if baseline_eff > 0 else 0

        results.append((tau, kept, filtered_pct, sum_total, sum_latency,
                        eff_total, eff_lat, avg_ms, delta_eff))

        print(f"  {tau:>5.2f}  {kept:>6}  {filtered_pct:>6.1f}%  "
              f"{sum_total:>10.0f} ms  {sum_latency:>10.0f} ms  "
              f"{eff_total:>10.6f}  {eff_lat:>10.6f}  {avg_ms:>8.1f} ms  {delta_eff:>+7.1f}%")

    # Find τ*
    best = max(results, key=lambda r: r[5])  # argmax eff_total
    print(f"\n  ★ τ*(total) = {best[0]:.2f}  (Eff = {best[5]:.6f} img/ms, "
          f"Kept = {best[1]}, Filter = {best[2]:.1f}%)")
    best_lat = max(results, key=lambda r: r[6])
    print(f"  ★ τ*(lat)   = {best_lat[0]:.2f}  (Eff = {best_lat[6]:.6f} img/ms, "
          f"Kept = {best_lat[1]}, Filter = {best_lat[2]:.1f}%)")

print()

# ═══════════════════════════════════════════════════════════════
# Cross-context comparison
# ═══════════════════════════════════════════════════════════════
print("=" * 72)
print("【Cross-Context Comparison: τ* Drift】")
print("-" * 72)

comparison = []
for label in ['Light', 'Mid']:
    df = dfs[label]
    prob = df['infiProbPerson']
    N = len(df)

    best_tau = None
    best_eff = -1
    best_info = None

    for tau in TAU_VALUES:
        mask = prob >= tau
        kept = mask.sum()
        if kept == 0:
            continue
        sum_total = df.loc[mask, 'totalMs'].sum()
        sum_lat = df.loc[mask, 'latencyMs'].sum()
        eff_total = kept / sum_total
        eff_lat = kept / sum_lat

        if eff_total > best_eff:
            best_eff = eff_total
            best_tau = tau
            best_info = {
                'tau': tau, 'kept': kept,
                'filter_pct': (N - kept) / N * 100,
                'sum_total_ms': sum_total,
                'sum_lat_ms': sum_lat,
                'eff_total': eff_total,
                'eff_lat': eff_lat,
                'avg_ms': sum_total / kept,
            }

    comparison.append((label, best_info))

    # Also compute fixed-τ (0.5) baseline
    mask_05 = prob >= 0.50
    kept_05 = mask_05.sum()
    sum_05 = df.loc[mask_05, 'totalMs'].sum()
    eff_05 = kept_05 / sum_05 if sum_05 > 0 else 0

    print(f"  [{label}]")
    print(f"    τ* = {best_tau:.2f}  (optimal for Efficiency_total)")
    print(f"    Efficiency(τ*)  = {best_info['eff_total']:.6f} img/ms")
    print(f"    Efficiency(0.5) = {eff_05:.6f} img/ms (fixed baseline)")
    print(f"    Δ Efficiency    = {(best_info['eff_total'] - eff_05) / eff_05 * 100:+.2f}%")
    print(f"    Filter Rate @τ* = {best_info['filter_pct']:.1f}%")
    print(f"    Avg totalMs @τ* = {best_info['avg_ms']:.1f} ms")
    print()

# ═══════════════════════════════════════════════════════════════
# Efficiency curve summary (compact)
# ═══════════════════════════════════════════════════════════════
print("=" * 72)
print("【Efficiency Curve (Eff_total vs τ) — Compact View】")
print("-" * 72)
print(f"  {'τ':>5}  {'Light Eff':>12}  {'Mid Eff':>12}  {'Δ(L-M)/L':>10}")
print(f"  {'─'*5}  {'─'*12}  {'─'*12}  {'─'*10}")

for i, tau in enumerate(TAU_VALUES):
    if i % 2 != 0:
        continue  # print every other for compactness
    vals = {}
    for label in ['Light', 'Mid']:
        mask = dfs[label]['infiProbPerson'] >= tau
        kept = mask.sum()
        sum_total = dfs[label].loc[mask, 'totalMs'].sum()
        vals[label] = kept / sum_total if sum_total > 0 else 0
    delta = (vals['Light'] - vals['Mid']) / vals['Light'] * 100 if vals['Light'] > 0 else 0
    print(f"  {tau:>5.2f}  {vals['Light']:>12.8f}  {vals['Mid']:>12.8f}  {delta:>+9.1f}%")

print()

# ═══════════════════════════════════════════════════════════════
# Context-aware insight: does τ* differ between Light and Mid?
# ═══════════════════════════════════════════════════════════════
print("=" * 72)
print("【Key Finding: Threshold Drift Verification】")
print("-" * 72)

light_best = comparison[0][1]
mid_best = comparison[1][1]

if abs(light_best['tau'] - mid_best['tau']) > 0.01:
    print(f"  ✅ THRESHOLD DRIFT CONFIRMED")
    print(f"     τ*(Light) = {light_best['tau']:.2f}  ≠  τ*(Mid) = {mid_best['tau']:.2f}")
    print(f"     Δτ = {mid_best['tau'] - light_best['tau']:+.2f}")
else:
    print(f"  ⚠ τ* is the same for Light and Mid with current granularity")
    print(f"     τ*(Light) = {light_best['tau']:.2f}, τ*(Mid) = {mid_best['tau']:.2f}")

print()
print(f"  Fixed-τ (0.5) efficiency gap:")
for label, info in comparison:
    df = dfs[label]
    mask_05 = df['infiProbPerson'] >= 0.50
    kept_05 = mask_05.sum()
    eff_05 = kept_05 / df.loc[mask_05, 'totalMs'].sum()
    gap = (info['eff_total'] - eff_05) / eff_05 * 100
    print(f"    [{label}] Using τ* instead of τ=0.5 improves efficiency by {gap:+.2f}%")

print()

# ═══════════════════════════════════════════════════════════════
# Fine-grained τ* for each context
# ═══════════════════════════════════════════════════════════════
print("=" * 72)
print("【Fine-Grained τ* Search (0.001 step around best region)】")
print("-" * 72)

for label in ['Light', 'Mid']:
    df = dfs[label]
    prob = df['infiProbPerson']

    # Find coarse best first
    best_coarse = max(
        ((tau, (prob >= tau).sum() / df.loc[prob >= tau, 'totalMs'].sum())
         for tau in TAU_VALUES if (prob >= tau).sum() > 0),
        key=lambda x: x[1]
    )

    # Fine search around best
    center = best_coarse[0]
    fine_taus = np.arange(max(0.50, center - 0.02), min(0.99, center + 0.02), 0.001)
    fine_results = []
    for tau in fine_taus:
        mask = prob >= tau
        kept = mask.sum()
        if kept == 0:
            continue
        eff = kept / df.loc[mask, 'totalMs'].sum()
        fine_results.append((tau, kept, eff))

    best_fine = max(fine_results, key=lambda r: r[2])

    # Fixed-τ (0.5) baseline
    m05 = prob >= 0.50
    eff_05 = m05.sum() / df.loc[m05, 'totalMs'].sum()

    print(f"  [{label}]")
    print(f"    Coarse τ* = {best_coarse[0]:.2f} (Eff = {best_coarse[1]:.6f})")
    print(f"    Fine   τ* = {best_fine[0]:.3f} (Eff = {best_fine[2]:.6f}, Kept = {best_fine[1]})")
    print(f"    Eff(0.5)   = {eff_05:.6f}")
    print(f"    ΔEff       = {(best_fine[2] - eff_05) / eff_05 * 100:+.3f}%")
    print()

print("=" * 72)
print("Analysis Complete!")
print("=" * 72)
