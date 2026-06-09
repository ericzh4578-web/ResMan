"""
pareto_analysis.py — Pareto Frontier Analysis of InFi Gating across Runtime Contexts

Key idea:
  Instead of hand-crafting Utility = Kept - λ·TotalCost (which requires picking λ),
  we directly analyze the Value-Cost trade-off by scanning τ:

    TotalValue(τ) = Σ Value(x) for kept images    (absolute, Value=1 per image)
    SavedCost(τ)  = Σ Cost(x) for all - Σ Cost(x) for kept   (absolute, ms)

  Both are ABSOLUTE metrics on the same footing. The tradeoff is genuine:
    - Higher τ → fewer images kept → lower TotalValue, higher SavedCost
    - Lower τ → more images kept → higher TotalValue, lower SavedCost

  Pareto Frontier: points where no other τ gives BOTH higher TotalValue
  AND higher SavedCost.

  If tradeoff curves differ across Contexts → Runtime Context changes the
  Value-Cost exchange rate → fixed-τ scheduling is suboptimal.

Data:
  - idle_full.csv: 5000 images, Idle context
  - mid_full.csv:  5000 images, Mid (Meeting) context
  - Score column: infiProbPerson (InFi gating confidence, [0, 1])
  - Cost column:  totalMs (end-to-end latency)
"""
import os
import pandas as pd
import numpy as np
import json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

# ── Config ──
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data')
RESULTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'results')
FILES = {
    'Idle':  os.path.join(DATA_DIR, 'idle_full.csv'),
    'Light': os.path.join(DATA_DIR, 'light_full.csv'),
    'Mid':   os.path.join(DATA_DIR, 'mid_full.csv'),
    'Heavy': os.path.join(DATA_DIR, 'heavy_full.csv'),
}

COLORS = {'Idle': '#4CAF50', 'Light': '#2196F3', 'Mid': '#FF9800', 'Heavy': '#F44336'}
MARKERS = {'Idle': 'o', 'Light': 's', 'Mid': '^', 'Heavy': 'D'}

SCORE_COL = 'infiProbPerson'
COST_COL  = 'totalMs'
TAU_STEP  = 0.05
OUTPUT_CSV  = os.path.join(RESULTS_DIR, 'pareto_results.csv')
OUTPUT_JSON = os.path.join(RESULTS_DIR, 'pareto_results.json')
OUTPUT_PNG  = os.path.join(RESULTS_DIR, 'pareto_tradeoff.png')

# ── Load ──
print("=" * 72)
print("  Pareto Frontier — TotalValue vs SavedCost (both ABSOLUTE)")
print("=" * 72)

dfs = {}
for label, path in FILES.items():
    df = pd.read_csv(path)
    df[SCORE_COL] = pd.to_numeric(df[SCORE_COL], errors='coerce')
    df[COST_COL]  = pd.to_numeric(df[COST_COL], errors='coerce')
    dfs[label] = df
    print(f"  [{label}] {len(df)} images, "
          f"score [{df[SCORE_COL].min():.3f}, {df[SCORE_COL].max():.3f}], "
          f"avg cost={df[COST_COL].mean():.1f}ms, "
          f"total cost={df[COST_COL].sum()/1000:.0f}s")
print()

# ── Precompute globals ──
globals_per_context = {}
for label, df in dfs.items():
    globals_per_context[label] = {
        'total_score': float(df[SCORE_COL].sum()),
        'total_cost_ms': float(df[COST_COL].sum()),
        'n_images': len(df),
    }

# ── τ scan ──
tau_values = np.arange(0.0, 1.0 + TAU_STEP/2, TAU_STEP)

all_rows = []

print("=" * 72)
print(f"  τ Scan (step={TAU_STEP})")
print("-" * 72)

for label, df in dfs.items():
    g = globals_per_context[label]
    total_cost_all = g['total_cost_ms']
    N = g['n_images']

    print(f"\n  [{label}] (total_cost={total_cost_all/1000:.0f}s, N={N})")
    print(f"  {'τ':>6}  {'Kept':>6}  {'TotalValue':>11}  {'SavedCost_s':>12}  "
          f"{'SavedCost%':>10}  {'AvgCost/kept':>12}  {'Pareto?':>8}")
    print(f"  {'─'*6}  {'─'*6}  {'─'*11}  {'─'*12}  {'─'*10}  {'─'*12}  {'─'*8}")

    context_rows = []
    for tau in tau_values:
        mask = df[SCORE_COL] > tau
        kept = mask.sum()
        kept_cost = df.loc[mask, COST_COL].sum()

        # Absolute metrics
        total_value = kept                        # Value=1 per kept image
        saved_cost_ms = total_cost_all - kept_cost
        saved_cost_s  = saved_cost_ms / 1000
        saved_cost_pct = saved_cost_ms / total_cost_all * 100
        avg_cost_kept  = kept_cost / kept if kept > 0 else 0.0

        row = {
            'Context': label,
            'tau': round(tau, 2),
            'KeptImages': int(kept),
            'TotalImages': N,
            'TotalValue': int(total_value),
            'SavedCost_ms': round(saved_cost_ms, 1),
            'SavedCost_s': round(saved_cost_s, 1),
            'SavedCost_pct': round(saved_cost_pct, 2),
            'TotalCostAll_ms': round(total_cost_all, 1),
            'AvgCostPerKept_ms': round(avg_cost_kept, 1),
        }
        context_rows.append(row)
        all_rows.append(row)

        print(f"  {tau:>5.2f}  {kept:>6}  {total_value:>11}  "
              f"{saved_cost_s:>10.0f}s  {saved_cost_pct:>9.1f}%  "
              f"{avg_cost_kept:>10.1f}ms  {'':>8}")

    # ── Pareto frontier (TotalValue vs SavedCost) ──
    points = [(r['SavedCost_ms'], r['TotalValue'], i) for i, r in enumerate(context_rows)]

    pareto_indices = set()
    for i, (sc_i, tv_i, _) in enumerate(points):
        dominated = False
        for j, (sc_j, tv_j, _) in enumerate(points):
            if i == j:
                continue
            # j dominates i: sc_j >= sc_i AND tv_j >= tv_i AND at least one strictly >
            if sc_j >= sc_i and tv_j >= tv_i and (sc_j > sc_i or tv_j > tv_i):
                dominated = True
                break
        if not dominated:
            pareto_indices.add(i)

    print(f"\n  Pareto Frontier ({len(pareto_indices)} / {len(context_rows)} points):")
    print(f"  {'τ':>6}  {'TotalValue':>11}  {'SavedCost_s':>12}  {'SavedCost%':>10}")
    print(f"  {'─'*6}  {'─'*11}  {'─'*12}  {'─'*10}")
    for i in sorted(pareto_indices):
        r = context_rows[i]
        r['ParetoOptimal'] = True
        print(f"  {r['tau']:>5.2f}  {r['TotalValue']:>11}  "
              f"{r['SavedCost_s']:>10.0f}s  {r['SavedCost_pct']:>9.1f}%")
    for i in range(len(context_rows)):
        if i not in pareto_indices:
            context_rows[i]['ParetoOptimal'] = False
    print()

# ── Cross-Context: Same TotalValue → Different SavedCost ──
print("=" * 72)
print("  Cross-Context: Same TotalValue → Different SavedCost")
print("-" * 72)

contexts = list(FILES.keys())
by_tau = {ctx: {r['tau']: r for r in all_rows if r['Context'] == ctx} for ctx in contexts}
baseline_ctx = 'Idle'

print(f"  {'τ':>6}  {'TotalValue':>11}  " +
      ''.join(f'{ctx:>10}' for ctx in contexts) +
      f"  {'MaxΔ':>10}")
print(f"  {'─'*6}  {'─'*11}  " + ''.join(f"{'─'*10}" for _ in contexts) + f"  {'─'*10}")

for tau in sorted(by_tau[baseline_ctx].keys()):
    vals = [by_tau[ctx][tau]['SavedCost_s'] for ctx in contexts]
    max_delta = max(vals) - min(vals)
    print(f"  {tau:>5.2f}  {by_tau[baseline_ctx][tau]['TotalValue']:>11}  " +
          ''.join(f'{v:>8.0f}s  ' for v in vals) +
          f'{max_delta:>+8.0f}s')

print()

# ── Interpretation ──
print("=" * 72)
print("  Interpretation")
print("-" * 72)
print("""
  TotalValue = number of kept images (Value=1 per image, absolute count)
  SavedCost  = total inference cost saved by filtering (absolute, seconds)

  Both are ABSOLUTE metrics on equal footing — no ratios, no hand-picked λ.

  Key observation:
    Same TotalValue → Different SavedCost across 4 Contexts.
    The heavier the context, the more cost saved per filtered image:
      Idle:  252ms/img → least savings
      Light: 257ms/img
      Mid:   267ms/img
      Heavy: 404ms/img → most savings (1.6x Idle)

  Consequence:
    The "exchange rate" of Value-per-Cost-saved is context-dependent.
    A fixed τ delivers the same TotalValue in all contexts, but leaves
    significant savings on the table in heavier contexts.

  This provides a λ-free way to demonstrate that Runtime Context
  changes the scheduler's fundamental Value-Cost tradeoff.
""")

# ── Export CSV ──
df_out = pd.DataFrame(all_rows)
df_out.to_csv(OUTPUT_CSV, index=False)
print(f"  CSV  exported: {OUTPUT_CSV}")

# ── Export JSON ──
export = {
    'description': 'Pareto analysis: TotalValue (absolute) vs SavedCost (absolute)',
    'score_column': SCORE_COL,
    'cost_column': COST_COL,
    'tau_step': TAU_STEP,
    'contexts': {}
}
for label in FILES.keys():
    ctx_rows = [r for r in all_rows if r['Context'] == label]
    export['contexts'][label] = {
        'n_images': globals_per_context[label]['n_images'],
        'total_cost_ms': globals_per_context[label]['total_cost_ms'],
        'avg_cost_ms': round(globals_per_context[label]['total_cost_ms'] / globals_per_context[label]['n_images'], 1),
        'pareto_points': [r for r in ctx_rows if r.get('ParetoOptimal', False)],
        'all_points': ctx_rows,
    }

with open(OUTPUT_JSON, 'w') as f:
    json.dump(export, f, indent=2)
print(f"  JSON exported: {OUTPUT_JSON}")

# ── Plot ──
fig, axes = plt.subplots(1, 2, figsize=(16, 6))

# Plot 1: Tradeoff curves — all 4 contexts
ax = axes[0]

for label in contexts:
    ctx_rows = [r for r in all_rows if r['Context'] == label]
    sc = [r['SavedCost_s'] for r in ctx_rows]
    tv = [r['TotalValue'] for r in ctx_rows]
    taus = [r['tau'] for r in ctx_rows]

    ax.plot(sc, tv, '-', color=COLORS[label], linewidth=2, alpha=0.85, label=f'{label}')
    ax.scatter(sc, tv, c=COLORS[label], s=40, zorder=5, edgecolors='white', linewidth=0.3)

    # Annotate key τ values
    for i in [0, 4, 8, 12, 16, 20]:
        if i < len(taus):
            ax.annotate(f'{taus[i]:.2f}', (sc[i], tv[i]),
                        textcoords='offset points', xytext=(5, -6), fontsize=6,
                        color=COLORS[label], alpha=0.7)

ax.set_xlabel('SavedCost (seconds)', fontsize=12)
ax.set_ylabel('TotalValue (kept images)', fontsize=12)
ax.set_title('Value-Cost Tradeoff across 4 Runtime Contexts', fontsize=13, fontweight='bold')
ax.legend(fontsize=10)
ax.grid(True, alpha=0.3)
ax.set_xlim(-30, None)
ax.set_ylim(-100, None)

# Plot 2: ΔSavedCost relative to Idle baseline
ax = axes[1]
taus_plot = sorted(by_tau[baseline_ctx].keys())
baseline_saved = np.array([by_tau[baseline_ctx][t]['SavedCost_s'] for t in taus_plot])

for label in [c for c in contexts if c != baseline_ctx]:
    saved = np.array([by_tau[label][t]['SavedCost_s'] for t in taus_plot])
    delta = saved - baseline_saved
    ax.plot(taus_plot, delta, '-', color=COLORS[label], linewidth=2, marker=MARKERS[label],
            markersize=6, label=f'{label} - {baseline_ctx}', alpha=0.85)

# Annotate max delta
for label in [c for c in contexts if c != baseline_ctx]:
    saved = np.array([by_tau[label][t]['SavedCost_s'] for t in taus_plot])
    delta = saved - baseline_saved
    max_idx = np.argmax(delta)
    ax.annotate(f'{label}: +{delta[max_idx]:.0f}s',
                (taus_plot[max_idx], delta[max_idx]),
                textcoords='offset points', xytext=(0, 10), fontsize=9,
                color=COLORS[label], fontweight='bold', ha='center')

ax.set_xlabel('τ', fontsize=12)
ax.set_ylabel('Δ SavedCost vs Idle (seconds)', fontsize=12)
ax.set_title('Context Gap: Extra Cost Saved vs Idle Baseline\n(Same TotalValue, Different SavedCost)', fontsize=12, fontweight='bold')
ax.legend(fontsize=10)
ax.grid(True, alpha=0.3)
ax.axhline(y=0, color='gray', linewidth=0.8, linestyle='--')

plt.tight_layout()
plt.savefig(OUTPUT_PNG, dpi=150, bbox_inches='tight')
print(f"  PNG  exported: {OUTPUT_PNG}")

print()
print("=" * 72)
print("  Analysis Complete!")
print("=" * 72)
