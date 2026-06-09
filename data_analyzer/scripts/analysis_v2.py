import os
import pandas as pd
import numpy as np
import sys

# File paths and labels
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data')
FILES = {
    'Light': os.path.join(DATA_DIR, 'light_full.csv'),
    'Mid':   os.path.join(DATA_DIR, 'mid_full.csv'),
}

# New schema (27 columns)
new_names = [
    'imgId', 'file', 'origResolution',
    'infiPredPerson', 'infiProbPerson', 'gtPerson',
    'infiCorrect', 'infiType', 'yoloModel',
    'latencyMs', 'prepMs', 'totalMs', 'tau',
    'stateName',
    'cpuProcPct', 'cpuSysPct',        # process CPU%, system CPU%
    'pssMb',                           # PSS memory (MB)
    'availMemMb', 'totalMemMb', 'freeMemMb',  # system memory
    'cpuFreqsKhz', 'gpuFreqKhz',       # frequencies
    'batterySocPct', 'batteryTempC',   # battery state-of-charge, temp
    'batteryCurrentMa', 'batteryVoltageMv', 'batteryPowerMw',
    'thermalLevel',
    'preprocessMode'
]

def load_and_clean(path, label):
    df = pd.read_csv(path, skiprows=1, names=new_names)

    # Convert numeric columns
    numeric_cols = [
        'latencyMs', 'prepMs', 'totalMs', 'tau',
        'cpuProcPct', 'cpuSysPct', 'pssMb',
        'availMemMb', 'totalMemMb', 'freeMemMb',
        'batterySocPct', 'batteryTempC', 'batteryCurrentMa',
        'batteryVoltageMv', 'batteryPowerMw', 'thermalLevel',
        'infiCorrect',
    ]
    for col in numeric_cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce')

    # Derived columns
    df['cpuTotalPct'] = df['cpuProcPct'] + df['cpuSysPct']
    df['usedMemMb'] = df['totalMemMb'] - df['availMemMb']
    df['batteryPowerW'] = df['batteryPowerMw'] / 1000.0

    df['label'] = label
    print(f"  [{label}] Loaded {len(df)} records")
    return df

print("=" * 72)
print("  加载两个新数据集")
print("=" * 72)
dfs = {}
for label, path in FILES.items():
    dfs[label] = load_and_clean(path, label)
print()

# ============================================================
# 1. BASIC INFO + COMPARISON
# ============================================================
print("=" * 72)
print("【1. 数据集基本信息对比】")
print("-" * 72)
for label, df in dfs.items():
    print(f"  [{label}] 总记录: {len(df)} | 唯一图片: {df['file'].nunique()} | "
          f"状态: {df['stateName'].iloc[0]}")
    print(f"         预处理模式: {df['preprocessMode'].iloc[0]} | "
          f"模型: {df['yoloModel'].iloc[0]}")
print()

# ============================================================
# 2. INFERENCE TIME
# ============================================================
print("=" * 72)
print("【2. 推理时间分析 (ms)】")
print("-" * 72)

metrics = ['totalMs', 'latencyMs', 'prepMs']
for m in metrics:
    print(f"  --- {m} ---")
    for label, df in dfs.items():
        print(f"  [{label}] 总计={df[m].sum():,.0f} ms ({df[m].sum()/1000:,.0f}s) | "
              f"均值={df[m].mean():.1f} | 中位数={df[m].median():.1f} | "
              f"min={df[m].min():.1f} | max={df[m].max():.1f} | std={df[m].std():.1f}")
    print()

# Verify totalMs = latencyMs + prepMs
print("  [校验] totalMs vs (latencyMs + prepMs):")
for label, df in dfs.items():
    diff = df['totalMs'] - (df['latencyMs'] + df['prepMs'])
    print(f"    [{label}] max_diff={diff.max():.2f}, avg_diff={diff.mean():.2f}")
print()

# Throughput
for label, df in dfs.items():
    total_sec = df['totalMs'].sum() / 1000
    print(f"  [{label}] 吞吐量: {len(df)/total_sec:.2f} 张/秒 "
          f"(总推理 {total_sec:.1f}s / {len(df)} 张图片)")
print()

# ============================================================
# 3. TAU (deadline ratio) analysis
# ============================================================
print("=" * 72)
print("【3. TAU (截止时间比例) 分析】")
print("-" * 72)
for label, df in dfs.items():
    print(f"  [{label}] tau 分布: mean={df['tau'].mean():.3f} | "
          f"median={df['tau'].median():.3f} | min={df['tau'].min():.3f} | "
          f"max={df['tau'].max():.3f} | std={df['tau'].std():.3f}")
    for val, count in df['tau'].value_counts().sort_index().items():
        print(f"         tau={val:.3f}: {count} ({count/len(df)*100:.1f}%)")
print()

# ============================================================
# 4. TEMPERATURE (battery)
# ============================================================
print("=" * 72)
print("【4. 电池温度分析 (batteryTempC, degC)】")
print("-" * 72)
for label, df in dfs.items():
    t = df['batteryTempC']
    print(f"  [{label}] 起始={t.iloc[0]:.0f}°C | 最终={t.iloc[-1]:.0f}°C | "
          f"变化={t.iloc[-1] - t.iloc[0]:.0f}°C")
    print(f"         均值={t.mean():.1f} | 中位数={t.median():.0f} | "
          f"min={t.min():.0f} | max={t.max():.0f} | std={t.std():.1f}")

    # Temp distribution
    print(f"         温度分布:")
    for temp in sorted(t.unique()):
        sub = df[df['batteryTempC'] == temp]
        bar = '#' * int(len(sub) / len(df) * 50)
        print(f"           {int(temp):>3}°C: {len(sub):>5} ({len(sub)/len(df)*100:5.1f}%) "
              f"avg_totalMs={sub['totalMs'].mean():.1f} {bar}")
    print()

# ============================================================
# 5. CPU ANALYSIS
# ============================================================
print("=" * 72)
print("【5. CPU 使用率分析 (%)】")
print("-" * 72)
for label, df in dfs.items():
    print(f"  [{label}]")
    for col, cname in [('cpuProcPct', 'Process CPU'), ('cpuSysPct', 'System CPU'), ('cpuTotalPct', 'Total CPU')]:
        s = df[col]
        print(f"         {cname}: 均值={s.mean():.1f}% | 中位数={s.median():.1f}% | "
              f"min={s.min():.1f}% | max={s.max():.1f}% | std={s.std():.1f}%")
    print()

# ============================================================
# 6. MEMORY ANALYSIS
# ============================================================
print("=" * 72)
print("【6. 内存分析 (MB)】")
print("-" * 72)
for label, df in dfs.items():
    print(f"  [{label}]")
    for col, cname in [
        ('pssMb', 'PSS (进程内存)'),
        ('usedMemMb', 'Used System Mem'),
        ('availMemMb', 'Available Mem'),
        ('freeMemMb', 'Free Mem'),
    ]:
        s = df[col]
        print(f"         {cname}: 均值={s.mean():.0f}MB | 中位数={s.median():.0f}MB | "
              f"min={s.min():.0f}MB | max={s.max():.0f}MB | std={s.std():.0f}MB")
    print(f"         Total System Mem: {df['totalMemMb'].iloc[0]:.0f} MB ({df['totalMemMb'].iloc[0]/1024:.1f} GB)")
    print()

# ============================================================
# 7. BATTERY / POWER ANALYSIS
# ============================================================
print("=" * 72)
print("【7. 电池 / 功耗分析】")
print("-" * 72)
for label, df in dfs.items():
    print(f"  [{label}]")
    for col, cname, unit in [
        ('batterySocPct', '电量 (SoC)', '%'),
        ('batteryCurrentMa', '电流', 'mA'),
        ('batteryVoltageMv', '电压', 'mV'),
        ('batteryPowerW', '功耗', 'W'),
    ]:
        s = df[col]
        print(f"         {cname}: 均值={s.mean():.1f}{unit} | 中位数={s.median():.1f}{unit} | "
              f"min={s.min():.1f}{unit} | max={s.max():.1f}{unit} | std={s.std():.1f}{unit}")
    # derive: discharge vs charge
    pos = (df['batteryCurrentMa'] > 0).sum()
    neg = (df['batteryCurrentMa'] < 0).sum()
    print(f"         放电(>0mA): {pos} | 充电(<0mA): {neg}")
    print()

# ============================================================
# 8. THERMAL LEVEL
# ============================================================
print("=" * 72)
print("【8. Thermal Level 分析】")
print("-" * 72)
for label, df in dfs.items():
    print(f"  [{label}]:")
    for val, count in df['thermalLevel'].value_counts().sort_index().items():
        print(f"         Level {int(val)}: {count} ({count/len(df)*100:.1f}%)")
    print()

# ============================================================
# 9. ACCURACY
# ============================================================
print("=" * 72)
print("【9. 准确率分析】")
print("-" * 72)
for label, df in dfs.items():
    tp = (df['infiType'] == 'TP').sum()
    fp = (df['infiType'] == 'FP').sum()
    fn = (df['infiType'] == 'FN').sum()
    tn = (df['infiType'] == 'TN').sum()
    correct = df['infiCorrect'].sum()
    incorrect = len(df) - correct

    print(f"  [{label}] TP={tp} | FP={fp} | FN={fn} | TN={tn}")
    print(f"         infiCorrect: 正确={correct} ({correct/len(df)*100:.1f}%) "
          f"错误={incorrect} ({incorrect/len(df)*100:.1f}%)")
    if tp + fp > 0:
        prec = tp/(tp+fp)
        print(f"         Precision: {prec*100:.2f}%")
    if tp + fn > 0:
        rec = tp/(tp+fn)
        print(f"         Recall:    {rec*100:.2f}%")
    if tp + fp > 0 and tp + fn > 0:
        f1 = 2*prec*rec/(prec+rec)
        print(f"         F1-Score:  {f1*100:.2f}%")
    print()

# ============================================================
# 10. RESOLUTION
# ============================================================
print("=" * 72)
print("【10. 图像分辨率分布】")
print("-" * 72)
for label, df in dfs.items():
    top = df['origResolution'].value_counts().head(5)
    print(f"  [{label}] Top 5 resolutions ({df['origResolution'].nunique()} unique):")
    for res, count in top.items():
        print(f"         {res}: {count} ({count/len(df)*100:.1f}%)")
    print()

# ============================================================
# 11. CORRELATION ANALYSIS
# ============================================================
print("=" * 72)
print("【11. 相关性分析】")
print("-" * 72)

corr_pairs = [
    ('batteryTempC', 'totalMs', 'Temp vs TotalMs'),
    ('batteryTempC', 'latencyMs', 'Temp vs LatencyMs'),
    ('batteryTempC', 'prepMs', 'Temp vs PrepMs'),
    ('cpuTotalPct', 'totalMs', 'CPU% vs TotalMs'),
    ('thermalLevel', 'totalMs', 'ThermalLevel vs TotalMs'),
    ('batteryTempC', 'cpuTotalPct', 'Temp vs CPU%'),
    ('batteryPowerW', 'batteryTempC', 'Power vs Temp'),
]

for col_a, col_b, desc in corr_pairs:
    print(f"  {desc}:")
    for label, df in dfs.items():
        corr = df[col_a].corr(df[col_b])
        print(f"    [{label}] r = {corr:+.4f}")
    print()

# ============================================================
# 12. PER-TEMPERATURE BREAKDOWN
# ============================================================
print("=" * 72)
print("【12. 按温度分组的推理时间】")
print("-" * 72)
for label, df in dfs.items():
    print(f"  [{label}]:")
    for temp in sorted(df['batteryTempC'].unique()):
        sub = df[df['batteryTempC'] == temp]
        print(f"    {int(temp):>3}°C: n={len(sub):>4} | "
              f"totalMs={sub['totalMs'].mean():.1f} | "
              f"latencyMs={sub['latencyMs'].mean():.1f} | "
              f"prepMs={sub['prepMs'].mean():.1f} | "
              f"cpuTotal={sub['cpuTotalPct'].mean():.1f}% | "
              f"power={sub['batteryPowerW'].mean():.1f}W")
    print()

# ============================================================
# 13. CROSS-COMPARISON SUMMARY
# ============================================================
print("=" * 72)
print("【13. Light vs Mid 对比总结】")
print("-" * 72)

light = dfs['Light']
mid = dfs['Mid']

comparisons = [
    ('totalMs', 'avg_totalMs', 'ms', 'lower_better'),
    ('latencyMs', 'avg_latencyMs', 'ms', 'lower_better'),
    ('prepMs', 'avg_prepMs', 'ms', 'lower_better'),
    ('batteryTempC', 'avg_temp', '°C', 'lower_better'),
    ('cpuTotalPct', 'avg_cpu', '%', 'lower_better'),
    ('batteryPowerW', 'avg_power', 'W', 'lower_better'),
    ('pssMb', 'avg_pss', 'MB', 'lower_better'),
]

print(f"  {'指标':<20} {'Light':>12} {'Mid':>12} {'差异':>12} {'变化%':>10}")
print(f"  {'-'*20} {'-'*12} {'-'*12} {'-'*12} {'-'*10}")
for col, name, unit, _ in comparisons:
    lv = light[col].mean()
    mv = mid[col].mean()
    diff = mv - lv
    pct = (diff / lv * 100) if lv != 0 else 0
    print(f"  {name:<20} {lv:>10.1f}{unit}  {mv:>10.1f}{unit}  {diff:>+10.1f}{unit}  {pct:>+9.1f}%")

# Accuracy comparison
for label, df in dfs.items():
    tp = (df['infiType'] == 'TP').sum()
    fp = (df['infiType'] == 'FP').sum()
    fn = (df['infiType'] == 'FN').sum()
    prec = tp/(tp+fp) if tp+fp > 0 else 0
    rec = tp/(tp+fn) if tp+fn > 0 else 0
    f1 = 2*prec*rec/(prec+rec) if (prec+rec) > 0 else 0
    print(f"  [{label}] Precision={prec*100:.1f}% Recall={rec*100:.1f}% F1={f1*100:.1f}%")

print()
print("=" * 72)
print("Analysis Complete!")
print("=" * 72)
