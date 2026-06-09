import os
import pandas as pd
import numpy as np

# Read raw CSV without assuming header maps correctly
# The data has 19 fields, header has 18 names (one extra column between prepMs and totalMs)
correct_names = [
    'imgId', 'file', 'origResolution',
    'infiPredPerson', 'infiProbPerson', 'gtPerson',
    'infiCorrect', 'infiType', 'yoloModel',
    'latencyMs', 'prepMs',
    '_unnamed_extra',
    'totalMs', 'deadlineMiss',
    'stateName', 'snapshotCpu',
    'snapshotTemp', 'snapshotFreqs',
    'preprocessMode'
]

DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data')

df = pd.read_csv(
    os.path.join(DATA_DIR, 'idle_full.csv'),
    skiprows=1,
    names=correct_names
)

# Drop the unnamed column
df = df.drop(columns=['_unnamed_extra'])

# Convert types
df['latencyMs'] = pd.to_numeric(df['latencyMs'])
df['prepMs'] = pd.to_numeric(df['prepMs'])
df['totalMs'] = pd.to_numeric(df['totalMs'])
df['snapshotTemp'] = pd.to_numeric(df['snapshotTemp'])
df['snapshotCpu'] = pd.to_numeric(df['snapshotCpu'])
df['deadlineMiss'] = pd.to_numeric(df['deadlineMiss'])
df['infiCorrect'] = pd.to_numeric(df['infiCorrect'])

# ==========================================
print("=" * 65)
print("【数据集基本信息】")
print(f"  总记录数: {len(df)}")
print(f"  唯一图片数: {df['file'].nunique()}")
print()

# ==========================================
print("=" * 65)
print("【推理时间分析 (单位: ms)】")
print("-" * 45)
print(f"  totalMs (总推理时间 = latencyMs + prepMs):")
print(f"    总计:     {df['totalMs'].sum():,.2f} ms")
print(f"              = {df['totalMs'].sum()/1000:,.2f} 秒")
print(f"              = {df['totalMs'].sum()/60000:,.2f} 分钟")
print(f"    平均:     {df['totalMs'].mean():.2f} ms")
print(f"    中位数:   {df['totalMs'].median():.2f} ms")
print(f"    最小值:   {df['totalMs'].min():.2f} ms")
print(f"    最大值:   {df['totalMs'].max():.2f} ms")
print(f"    标准差:   {df['totalMs'].std():.2f} ms")
print()
print(f"  latencyMs (推理延迟):")
print(f"    总计:     {df['latencyMs'].sum():,.2f} ms")
print(f"    平均:     {df['latencyMs'].mean():.2f} ms")
print(f"    中位数:   {df['latencyMs'].median():.2f} ms")
print(f"    最小值:   {df['latencyMs'].min():.2f} ms")
print(f"    最大值:   {df['latencyMs'].max():.2f} ms")
print(f"    标准差:   {df['latencyMs'].std():.2f} ms")
print()
print(f"  prepMs (预处理时间):")
print(f"    总计:     {df['prepMs'].sum():,.2f} ms")
print(f"    平均:     {df['prepMs'].mean():.2f} ms")
print(f"    中位数:   {df['prepMs'].median():.2f} ms")
print(f"    最小值:   {df['prepMs'].min():.2f} ms")
print(f"    最大值:   {df['prepMs'].max():.2f} ms")
print(f"    标准差:   {df['prepMs'].std():.2f} ms")
print()

# Verify totalMs = latencyMs + prepMs
diff = df['totalMs'] - (df['latencyMs'] + df['prepMs'])
print(f"  [校验] totalMs vs (latencyMs+prepMs) 差异: max={diff.max():.2f}, avg={diff.mean():.2f}")
print()

# ==========================================
print("=" * 65)
print("【温度分析 (snapshotTemp, 单位: degC)】")
print("-" * 45)
print(f"  起始温度 (第1条):    {df['snapshotTemp'].iloc[0]:.2f} degC")
print(f"  最终温度 (最后1条):  {df['snapshotTemp'].iloc[-1]:.2f} degC")
print(f"  平均温度:            {df['snapshotTemp'].mean():.2f} degC")
print(f"  中位数温度:          {df['snapshotTemp'].median():.2f} degC")
print(f"  最低温度:            {df['snapshotTemp'].min():.2f} degC")
print(f"  最高温度:            {df['snapshotTemp'].max():.2f} degC")
print(f"  标准差:              {df['snapshotTemp'].std():.2f} degC")
print(f"  温度变化 (末-始):    {df['snapshotTemp'].iloc[-1] - df['snapshotTemp'].iloc[0]:.2f} degC")
print()

print(f"  温度分布:")
for temp, count in df['snapshotTemp'].value_counts().sort_index().items():
    bar = '#' * int(count / len(df) * 100)
    print(f"    {temp:>5.0f} degC: {count:>5} records ({count/len(df)*100:5.1f}%) {bar}")
print()

print(f"  温度变化趋势 (每500条):")
for i in range(0, len(df), 500):
    temp_val = df['snapshotTemp'].iloc[i]
    print(f"    Record #{i+1:>5}:  {temp_val:.2f} degC")
if (len(df) - 1) % 500 != 0:
    print(f"    Record #{len(df):>5}:  {df['snapshotTemp'].iloc[-1]:.2f} degC")
print()

# ==========================================
print("=" * 65)
print("【状态分析】")
print("-" * 45)
print(f"  stateName distribution:")
for state, count in df['stateName'].value_counts().items():
    print(f"    {state}: {count} ({count/len(df)*100:.1f}%)")
print()

print(f"  infiCorrect (inference correctness):")
correct_count = df['infiCorrect'].sum()
print(f"    Correct (1):   {correct_count} ({correct_count/len(df)*100:.1f}%)")
print(f"    Incorrect (0): {len(df) - correct_count} ({(len(df)-correct_count)/len(df)*100:.1f}%)")
print()

print(f"  infiType (inference result type):")
for val, count in df['infiType'].value_counts().items():
    print(f"    {val}: {count} ({count/len(df)*100:.1f}%)")
print()

print(f"  deadlineMiss:")
for val, count in df['deadlineMiss'].value_counts().items():
    label = "No Miss" if val == 0 else "Missed"
    print(f"    {label} ({val}): {count} ({count/len(df)*100:.1f}%)")
print()

print(f"  yoloModel (top 10):")
for val, count in df['yoloModel'].value_counts().head(10).items():
    print(f"    {val}: {count}")
print()

print(f"  preprocessMode:")
for val, count in df['preprocessMode'].value_counts().items():
    print(f"    {val}: {count}")
print()

# ==========================================
print("=" * 65)
print("【CPU使用率分析 (snapshotCpu, unit: %)】")
print("-" * 45)
print(f"  Starting CPU:  {df['snapshotCpu'].iloc[0]:.2f}%")
print(f"  Ending CPU:    {df['snapshotCpu'].iloc[-1]:.2f}%")
print(f"  Average CPU:   {df['snapshotCpu'].mean():.2f}%")
print(f"  Max CPU:       {df['snapshotCpu'].max():.2f}%")
print(f"  Min CPU:       {df['snapshotCpu'].min():.2f}%")
print(f"  Std Dev:       {df['snapshotCpu'].std():.2f}%")
print()

# ==========================================
print("=" * 65)
print("【准确率分析】")
print("-" * 45)
tp = (df['infiType'] == 'TP').sum()
fp = (df['infiType'] == 'FP').sum()
fn = (df['infiType'] == 'FN').sum()
tn = (df['infiType'] == 'TN').sum()
print(f"  TP (True Positive):   {tp}")
print(f"  FP (False Positive):  {fp}")
print(f"  FN (False Negative):  {fn}")
print(f"  TN (True Negative):   {tn}")
print()
if tp + fp > 0:
    print(f"  Precision: {tp/(tp+fp)*100:.2f}%")
if tp + fn > 0:
    print(f"  Recall:    {tp/(tp+fn)*100:.2f}%")
if tp + fp > 0 and tp + fn > 0:
    p = tp/(tp+fp)
    r = tp/(tp+fn)
    print(f"  F1-Score:  {2*p*r/(p+r)*100:.2f}%")
if tp+tn+fp+fn > 0:
    print(f"  Accuracy:  {(tp+tn)/(tp+tn+fp+fn)*100:.2f}%")
print()

# ==========================================
print("=" * 65)
print("【图像分辨率分布 (Top 10)】")
print("-" * 45)
for res, count in df['origResolution'].value_counts().head(10).items():
    print(f"    {res}: {count} ({count/len(df)*100:.1f}%)")
print(f"    Unique resolutions: {df['origResolution'].nunique()}")
print()

# ==========================================
print("=" * 65)
print("【推理吞吐量】")
print("-" * 45)
total_time_sec = df['totalMs'].sum() / 1000
print(f"  Total images:        {len(df)}")
print(f"  Total inference time: {total_time_sec:.2f} sec")
print(f"  Throughput:          {len(df)/total_time_sec:.2f} images/sec")
print(f"  Avg time per image:  {df['totalMs'].mean():.2f} ms")
print()

# ==========================================
# Correlation analysis
print("=" * 65)
print("【温度 vs 推理时间 相关性】")
print("-" * 45)
corr = df['snapshotTemp'].corr(df['totalMs'])
print(f"  Pearson correlation: {corr:.4f}")
corr_l = df['snapshotTemp'].corr(df['latencyMs'])
print(f"  Temp vs Latency correlation: {corr_l:.4f}")
corr_p = df['snapshotTemp'].corr(df['prepMs'])
print(f"  Temp vs Prep correlation: {corr_p:.4f}")
print()

# Per-temperature time stats
print(f"  Per-temperature avg totalMs:")
for temp in sorted(df['snapshotTemp'].unique()):
    sub = df[df['snapshotTemp'] == temp]
    print(f"    {temp:>5.0f} degC: avg={sub['totalMs'].mean():.2f} ms, n={len(sub)}, "
          f"latency={sub['latencyMs'].mean():.2f} ms, prep={sub['prepMs'].mean():.2f} ms")

print()
print("=" * 65)
print("Analysis Complete!")
