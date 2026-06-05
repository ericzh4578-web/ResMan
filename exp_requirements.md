[暂时废弃 推理容量实验]

# 实验总要求
1. ✅ 新开一个页面 — ExperimentPage.ets (3个Tab: Capacity Curve / Context Impact / SRDC)
2. ✅ 参考当前归纳的实现 claude.md
3. ✅ 记录目前的实验情况到该文件中
4. ✅ 禁用一切git操作！
5. ✅ 实验路径参考但不完全遵从，保持了论文逻辑

---

## 实现进度 — 2026-06-01

### 已完成

#### C++ 层 (1 个新模块)
- ✅ `SysfsReader/SysfsReader.h` + `.cpp` — 读取 CPU/GPU 频率
    - `readCpuFreq(coreIndex)` — 单核频率 (kHz)
    - `readAllCpuFreqs()` — 所有核 [{core, freqKHz}]
    - `readGpuFreq()` — GPU 频率 (kHz)，尝试多个 sysfs 路径
    - `readCpuFreqsCsv()` — CSV 格式字符串，供日志直接使用
    - 已注册到 napi_init.cpp / CMakeLists.txt / Index.d.ts

#### ArkTS 工具层 (2 个新文件)
- ✅ `utils/CsvLogger.ts` — CSV 文件写入器 (fileIo 模式)
- ✅ `utils/ExperimentRunner.ts` — 实验基类
    - `MetricsCollector.captureSample()` — 统一采样 (hidebug + thermal + battery + sysfs)
    - `ExperimentSample` 接口 — 14 个指标字段
    - `ExperimentRunner` 类 — start/stop/tick 生命周期 + CSV 持久化

#### ArkTS 页面层 (1 个新页面)
- ✅ `pages/ExperimentPage.ets` — 实验仪表盘 (3个Tab)

#### 集成
- ✅ `Index.ets` — 已添加 "Experiment Dashboard" 按钮 + PageMap 注册

### 三个实验实现说明

**Tab 1: Capacity Curve (实验1)**
- 选择 YOLO 模型 + 时长 (1-60min)
- 连续推理 + 每秒采集指标 → CSV
- 证明: Peak FPS ≠ 可持续 FPS (热曲线)
- CSV: timestamp, elapsedMs, fps, avgLatencyMs, cpuUsage, cpuFreqs, gpuFreq, pss, thermal, battery, throughput

**Tab 2: Context Impact (实验2)**
- 5 个 Context 通过 ResourceSimulator 模拟:
    - Idle (无负载), Meeting (CPU 50%), Video (IO Medium), Game (CPU 75%+Mem 15%), Navigation (IO Weak+Mem 10%)
- 每轮: 稳定 60s → 推理 N 分钟 → CSV
- 证明: 同一模型在不同 Context 下 FPS 差异显著
- CSV: 比 Tab 1 多 `context` 列

**Tab 3: Same Resource Different Capacity (实验3 - 最重要)**
- 4 个 Profile: Idle-baseline, CPU-bound, IO-bound, Mixed-load
- 自动顺序运行: 稳定 → 推理 → 记录 → 切换
- 运行完毕后输出对比表: 相同 CPU≈50% 状态下，不同 Profile → 不同 avg FPS
- 证明: Context 携带了资源指标无法捕获的隐藏信息 (核心论文贡献)

### 关键技术适配

| 原始设计 (Python) | HarmonyOS 实现 |
|---|---|
| adb shell am start (启动真实应用) | ResourceSimulator C++ 模块模拟负载 |
| /proc/stat, /sys/class/thermal | SysfsReader C++ 模块读取 sysfs |
| Python csv.writer | CsvLogger ArkTS 工具 (fileIo) |
| fps_collector.py (time-based) | 推理循环内 Date.now() 计时 + 10 次滚动平均 |
| run_yolov8.py (while True) | setInterval + model.predict 异步循环 |

### 后续工作

- [ ] Exp 1: 模型文件需放入 rawfile (yolov8n/s/m/l/x_bsz4.ms)
- [ ] Exp 2: 可添加真实应用 Context (需要 root/instrumentation)
- [ ] Exp 3: 可添加统计分析 (置信区间、T检验)
- [ ] 跨设备验证 (实验9) — 需多台 HarmonyOS 设备
- [ ] 实验 4-8 的分析脚本 (可用导出的 CSV 做离线分析)


我建议你把论文的逻辑先固定下来，因为**实验是为论文故事服务的**。

目前我认为最合理、最有创新性的故事线是：

```text
Observation:
相同资源状态下，不同Context的AI性能差异巨大

↓

Insight:
CPU/GPU/Temperature无法完整描述设备AI能力

↓

Finding:
Application Context决定设备未来可持续计算预算
(Sustainable Compute Budget)

↓

Abstraction:
提出Context-dependent Compute Budget

↓

System:
利用Compute Budget进行模型选择

↓

Benefit:
获得更好的Accuracy/Performance/Thermal Tradeoff
```

这里最重要的是：

```text
Compute Budget
```

是论文贡献。

```text
Model Selection
```

是证明这个贡献有价值。

不要把Model Selection当贡献。

---

## 实验1：Sustainable Compute Capacity Characterization

实验目的：

证明手机AI推理能力是动态变化的。

回答问题：

```text
Peak Performance
是否能够代表
长期AI能力？
```

实验输入：

YOLOv8n
YOLOv8s
YOLOv8m
YOLOv8l

实验步骤：

1. 手机静置30分钟。

2. 清理后台。

3. 启动模型。

4. 连续推理30分钟。

5. 每秒采集：

CPU Frequency

CPU Utilization

GPU Frequency

GPU Utilization

Temperature

Battery Current

Battery Voltage

FPS

Latency

实验输出：

capacity_curve.csv

格式：

timestamp,
fps,
temp,
cpu_freq,
gpu_freq

代码设计：

collector/

thermal_collector.py

负责读取：

```bash
/sys/class/thermal/*
```

cpu_collector.py

负责读取：

```bash
/proc/stat
```

fps_collector.py

负责统计：

```python
start=time()
model(frame)
end=time()
fps=1/(end-start)
```

runner/

run_yolov8.py

负责：

```python
while True:
    infer()
    log()
```

最终图：

```text
FPS
↑
|
|
|
+----------------→ Time
```

---

## 实验2：Context Impact Study

实验目的：

证明Context影响Compute Budget。

回答问题：

```text
同一个模型

在不同Context下

是否表现不同？
```

实验Context：

Idle

Tencent Meeting

Video

Navigation

Game

固定模型：

YOLOv8m

实验步骤：

1. 启动Context。

2. 等待稳定3分钟。

3. 启动YOLOv8m。

4. 运行10分钟。

5. 记录：

FPS

Temp

CPU

GPU

Power

代码设计：

activity/

launch_meeting.py

launch_video.py

launch_game.py

每个脚本负责：

```bash
adb shell am start ...
```

最终输出：

context_capacity.csv

```text
context,
avg_fps,
peak_temp,
avg_power
```

---

## 实验3：Same Resource Different Capacity

这是论文最重要实验。

实验目的：

证明：

```text
Resource State

≠

Compute Budget
```

实验步骤：

收集大量Context运行数据。

寻找：

CPU≈50%

GPU≈30%

Temp≈40℃

的状态。

在这些状态下：

运行YOLOv8m。

记录未来5分钟：

FPS

Temp

Frequency

代码设计：

dataset/

state_matcher.py

输入：

历史日志

输出：

满足条件状态：

```python
if abs(cpu-50)<5:
    ...
```

最终输出：

```text
Meeting

CPU=50%
GPU=30%
Temp=40

Future FPS=18
```

```text
Video

CPU=50%
GPU=30%
Temp=40

Future FPS=30
```

核心结论：

Context携带隐藏信息。

---

## 实验4：Context Capacity Map

实验目的：

建立：

```text
Context
↓
Capacity Budget
```

映射关系。

实验步骤：

遍历：

Context

×

YOLOv8n

YOLOv8s

YOLOv8m

YOLOv8l

记录：

Average FPS

Temperature

Throttling Time

Power

代码设计：

experiment/

capacity_mapper.py

```python
for context in contexts:
    for model in models:
        run()
```

输出：

capacity_map.csv

```text
Context,n,s,m,l
Idle,√,√,√,√
Meeting,√,√,√,×
Game,√,√,×,×
```

---

## 实验5：Model Cost Profiling

实验目的：

建立模型计算代价。

实验步骤：

分别运行：

n

s

m

l

记录：

Average Power

Average Temperature Rise

Latency

Memory

代码设计：

profiler/

model_profiler.py

输出：

model_cost.csv

```text
model,cost
n,1
s,2
m,3
l,4
```

或者：

```text
model,gflops
```

---

## 实验6：Compute Budget Definition

实验目的：

定义统一Compute Budget。

核心思想：

设备容量：

```text
Budget
```

模型需求：

```text
Cost
```

若：

```text
Cost ≤ Budget
```

则模型可持续运行。

实验步骤：

利用实验4和5结果。

建立：

```text
Budget Scale

1
2
3
4
```

例如：

```text
Budget 1
支持n

Budget 2
支持s

Budget 3
支持m

Budget 4
支持l
```

输出：

budget_table.csv

---

## 实验7：Budget-aware Model Selection

实验目的：

设计模型选择机制。

输入：

Context

CPU

GPU

Temp

Battery

输出：

Budget

↓

Model

代码设计：

scheduler/

budget_estimator.py

```python
budget=f(context,state)
```

selector.py

```python
if budget>=4:
    model=l

elif budget>=3:
    model=m

elif budget>=2:
    model=s

else:
    model=n
```

注意：

这里可以先用规则实现。

后面再升级。

---

## 实验8：Runtime Evaluation

实验目的：

证明Budget有实际价值。

Baseline：

Always-n

Always-s

Always-m

Always-l

Temperature-based

CPU-based

Budget-based

实验场景：

Idle

Meeting

Video

Game

动态切换：

```text
Idle
↓
Meeting
↓
Game
↓
Video
```

评价指标：

Average Accuracy

Average FPS

Power

Temperature

Throttling Count

代码设计：

evaluation/

runtime_eval.py

负责：

自动切换Context

自动切换模型

自动统计指标

输出：

```text
method,
accuracy,
fps,
temp,
power
```

---

## 实验9：Cross-device Validation

实验目的：

证明现象普遍存在。

设备：

Phone A

Phone B

Phone C

实验步骤：

重复实验2~8。

输出：

不同设备Capacity Map。

---

## 最终代码结构

```text
project/

collector/
│
├── cpu_collector.py
├── gpu_collector.py
├── thermal_collector.py
├── battery_collector.py
├── fps_collector.py

runner/
│
├── yolov8n_runner.py
├── yolov8s_runner.py
├── yolov8m_runner.py
├── yolov8l_runner.py

activity/
│
├── launch_meeting.py
├── launch_video.py
├── launch_navigation.py
├── launch_game.py

dataset/
│
├── logger.py
├── state_matcher.py
├── build_capacity_map.py

profiler/
│
├── model_profiler.py

scheduler/
│
├── budget_estimator.py
├── selector.py

evaluation/
│
├── runtime_eval.py
├── plot_capacity_curve.py
├── plot_capacity_map.py
├── compare_baselines.py
```

如果以 MobiSys/MobiCom 标准来看，我会把精力投入比例设成：

```text
实验1：10%
实验2：15%
实验3：30%   ← 最重要
实验4：15%
实验5：5%
实验6：5%
实验7：5%
实验8：10%
实验9：5%
```

因为真正能让审稿人眼前一亮的，不是最后模型选得多好，而是实验3能否证明：

```text
相同资源状态
≠
相同AI能力

Application Context
是决定Compute Budget的隐藏维度
```

这是整个故事里最有机会形成新系统抽象的地方。

---

## 构建与调试记录 — 2026-06-01

### 构建命令

```bash
# Windows 下必须通过 node 调用（Git Bash 中不能直接执行 .js）
cd C:/Users/20732/Desktop/ResMan && node "D:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js" --mode module -p module=entry@default -p product=default -p requiredDeviceType=phone assembleHap --analyze=normal --parallel --incremental --daemon
```

### 首次构建：6 ERROR + 33 WARN → 修复后 BUILD SUCCESSFUL

#### 修复 1: `arkts-no-untyped-obj-literals` (Line 43)

**问题：** `arr.map(v => ({ value: v }))` 中箭头函数返回的对象字面量没有显式类型。

**修复：**
```typescript
// 前（错误）
function toSelectOptions(arr: string[]): SelectOption[] {
  return arr.map(v => ({ value: v }));
}

// 后（正确）
function toSelectOptions(arr: string[]): SelectOption[] {
  let result: SelectOption[] = [];
  for (let i = 0; i < arr.length; i++) {
    result.push({ value: arr[i] } as SelectOption);
  }
  return result;
}
```

#### 修复 2: `arkts-no-in` (Lines 166–167)

**问题：** ArkTS 严格模式不支持 `in` 运算符。`applyContext` 中用 `'memLevel' in ctx` 判断字段存在。

**原因：** `ContextDef` 和 `ProfileDef` 是相同结构的 interface（都有 `name/cpuLevel/memLevel/ioLevel`），`in` 判断是多余的。

**修复：** 删除 `in` 运算符，直接访问属性；合并 `ProfileDef` 为 `ContextDef`。
```typescript
// 前（错误）
private applyContext(ctx: ContextDef | ProfileDef): void {
  if ('memLevel' in ctx && ctx.memLevel >= 0) { ... }
  if ('ioLevel' in ctx && ctx.ioLevel >= 0) { ... }
}

// 后（正确）
private applyContext(ctx: ContextDef): void {
  if (ctx.memLevel >= 0) { ... }
  if (ctx.ioLevel >= 0) { ... }
}
```

#### 修复 3: `arkts-no-obj-literals-as-types` (Line 461)

**问题：** 数组变量类型声明中使用了内联对象字面量。
```typescript
const allResults: { profile: string; avgFps: number; ... }[] = [];
```

**修复：** 提取为命名 interface。
```typescript
interface SrResultEntry {
  profile: string;
  avgFps: number;
  avgCpu: number;
  avgTemp: number;
  sampleCount: number;
  csvFile: string;
}
let allResults: SrResultEntry[] = [];
```

#### 修复 4: `arkts-no-untyped-obj-literals` (Line 515)

**问题：** `allResults.push({ profile: ..., avgFps: ... })` 中的对象字面量未声明类型。

**修复：** 先创建类型化变量再 push。
```typescript
// 前（错误）
allResults.push({
  profile: profile.name,
  avgFps: metricCount > 0 ? fpsSum / metricCount : 0,
  ...
});

// 后（正确）
let entry: SrResultEntry = {
  profile: profile.name,
  avgFps: metricCount > 0 ? fpsSum / metricCount : 0,
  ...
};
allResults.push(entry);
```

### 常见 ArkTS 严格模式约束

| 规则 | 说明 |
|---|---|
| `arkts-no-untyped-obj-literals` | 对象字面量必须有对应的 interface/class，不能裸写 `{...}` |
| `arkts-no-obj-literals-as-types` | 类型声明不能使用内联对象字面量，必须用命名 interface |
| `arkts-no-in` | 不支持 JS 的 `in` 运算符，用 `interface` 的字段访问代替 |
| `akrts-no-any` | 禁止使用 `any`/`unknown` 类型 |
