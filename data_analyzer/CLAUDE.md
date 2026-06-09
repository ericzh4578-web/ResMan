# data_analyzer — YOLO+InFi 推理性能分析工具

## 项目概述

对 **YOLOv8l-bsz4 + InFi Gating** 在不同运行时上下文（Idle / Light / Mid / Heavy）下的推理性能数据进行离线分析。
核心指标：推理延迟（latencyMs）、预处理时间（prepMs）、总时间（totalMs）、温度（batteryTempC）、CPU 占用、准确率（Precision/Recall/F1），以及 InFi τ 阈值对效率的影响。

实验数据来自 HarmonyOS 设备上的自动化测试（每张图片执行 YOLO 目标检测 + InFi 人员判断），每条记录包含推理时间、系统状态快照和 InFi 置信度。

---

## 目录结构

```
data_analyzer/
├── scripts/                  # Python 分析脚本 (4个)
│   ├── analysis.py           # v1 单数据集分析 (Idle baseline)
│   ├── analysis_v2.py        # v2 多数据集对比分析 (Light vs Mid, 13维度)
│   ├── analysis_tau_scan.py  # 回溯式 τ 阈值扫描 (τ*寻优)
│   └── pareto_analysis.py    # Pareto前沿分析 (4 context Value-Cost权衡)
├── data/                     # 输入CSV数据 (7个)
│   ├── {context}_full.csv    # 完整数据集 (×4, 各5000行)
│   └── {context}_infi_0p5.csv# τ=0.5子集 (×3, 各2996行)
├── results/                  # 分析输出 (3个)
│   ├── pareto_results.csv    # τ扫描结果表
│   ├── pareto_results.json   # 结构化Pareto数据
│   └── pareto_tradeoff.png   # 权衡曲线图 (2-panel)
└── analysis_report.md        # 4组实验详细分析报告 (关键发现)
```

---

## 数据说明 (`data/`)

### 两种Schema

| Schema | 列数 | 文件 | 特征字段 |
|--------|------|------|---------|
| **v2 (完整)** | 29 | `_full.csv` (4个), `light_infi_0p5.csv`, `mid_infi_0p5.csv` | `tau`, `cpuProcPct`, `cpuSysPct`, `pssMb`, `availMemMb`, `totalMemMb`, `freeMemMb`, `cpuFreqsKhz`, `gpuFreqKhz`, `batterySocPct`, `batteryTempC`, `batteryCurrentMa`, `batteryVoltageMv`, `batteryPowerMw`, `thermalLevel` |
| **v1 (精简)** | 19 | `idle_infi_0p5.csv` | `deadlineMiss`, `snapshotCpu`, `snapshotTemp`, `snapshotFreqs` (无 tau 列) |

### v2 完整字段 (29列)

| 列名 | 类型 | 单位 | 说明 |
|------|------|------|------|
| `imgId` | int | — | 图片序号 (0-based) |
| `file` | str | — | 图片文件名 |
| `origResolution` | str | — | 原始分辨率 (如 `640x480`) |
| `infiPredPerson` | int | — | InFi 预测是否有人 (0/1) |
| `infiProbPerson` | float | — | InFi 人员置信度 [0, 1] — **核心调度分数** |
| `gtPerson` | int | — | Ground Truth 是否有人 (0/1) |
| `infiCorrect` | int | — | InFi 预测是否正确 (0/1) |
| `infiType` | str | — | 预测类型: TP / FP / FN / TN |
| `yoloModel` | str | — | YOLO 模型文件名 (如 `yolov8l_bsz4.ms`) |
| `latencyMs` | float | ms | 推理延迟 (YOLO + InFi) |
| `prepMs` | float | ms | 预处理时间 (图像缩放/归一化) |
| `totalMs` | float | ms | 总时间 = latencyMs + prepMs |
| `tau` | float | — | InFi 门控阈值 τ (固定值 0.5) |
| `stateName` | str | — | 运行时上下文: Idle / Light (Music+Nav) / Mid (Meeting) / Heavy |
| `cpuProcPct` | float | % | 本进程 CPU 占用 |
| `cpuSysPct` | float | % | 系统 CPU 占用 |
| `pssMb` | float | MB | 进程 PSS 内存 |
| `availMemMb` | float | MB | 系统可用内存 |
| `totalMemMb` | float | MB | 系统总内存 |
| `freeMemMb` | float | MB | 系统空闲内存 |
| `cpuFreqsKhz` | str | kHz | CPU 频率列表 |
| `gpuFreqKhz` | str | kHz | GPU 频率 |
| `batterySocPct` | float | % | 电池电量 |
| `batteryTempC` | float | °C | **电池温度** — 核心系统指标 |
| `batteryCurrentMa` | float | mA | 电池电流 (正=放电, 负=充电) |
| `batteryVoltageMv` | float | mV | 电池电压 |
| `batteryPowerMw` | float | mW | 电池功耗 |
| `thermalLevel` | int | — | 设备热等级 (0-7, 越高越热) |
| `preprocessMode` | str | — | 预处理模式 (fused) |

### 数据集清单

| 文件名 | 行数 | Schema | Context | 原始文件名 |
|--------|------|--------|---------|-----------|
| `idle_full.csv` | 5000 | v2 | **Idle** (空闲) | `exp2_infi_coco_Idle_full_1780639447663.csv` |
| `light_full.csv` | 5000 | v2 | **Light** (Music+Nav) | `exp2_infi_coco_Light_full_1780743288773.csv` |
| `mid_full.csv` | 5000 | v2 | **Mid** (Meeting) | `exp2_infi_coco_Mid_full_1780816112706.csv` |
| `heavy_full.csv` | 5000 | v2 | **Heavy** (高负载) | — |
| `idle_infi_0p5.csv` | 2996 | v1 | Idle, τ=0.5 | `exp2_infi_coco_baseline_1780639447663.csv` |
| `light_infi_0p5.csv` | 2996 | v2 | Light, τ=0.5 | `exp2_infi_coco_baseline_1780743288773.csv` |
| `mid_infi_0p5.csv` | 2996 | v2 | Mid, τ=0.5 | `exp2_infi_coco_baseline_1780816112706.csv` |

- `_full.csv`: 5000 张图片，全量执行（不做过滤），用于回溯式 τ 扫描
- `_infi_0p5.csv`: ~2996 张图片，τ=0.5 子集（InFi gating 开启，仅高分图片执行推理）

---

## 脚本说明 (`scripts/`)

所有脚本使用基于脚本位置的相对路径，从 `scripts/` 目录运行或从项目根运行均可。

### 1. `pareto_analysis.py` — Pareto 前沿分析 ⭐ (当前活跃)

**功能**：扫描 τ ∈ [0, 1] (step=0.05)，计算每个 τ 下的 TotalValue（保留图片数）和 SavedCost（节省的推理时间），找出 Pareto 最优 τ 值，并对比 4 个 Context 的 Value-Cost 权衡曲线。

**输入**：`data/{context}_full.csv` (4个) → `infiProbPerson` (分数列) + `totalMs` (成本列)

**输出**：
- `results/pareto_results.csv` — 所有 τ 值的完整扫描结果
- `results/pareto_results.json` — 结构化 Pareto 数据 (含每 context 的 Pareto 最优点)
- `results/pareto_tradeoff.png` — 双面板图: (左) 4 context 权衡曲线, (右) ΔSavedCost vs Idle baseline

**关键发现**：
- 相同 TotalValue → 不同 SavedCost，Context 越重节省越多 (Heavy 是 Idle 的 1.6x)
- Value-Cost 交换率是 context-dependent → 固定 τ 在重负载下损失显著

**运行**：
```bash
cd data_analyzer
python scripts/pareto_analysis.py
```

### 2. `analysis_tau_scan.py` — 回溯式 τ 扫描

**功能**：基于 `infiProbPerson` 字段回溯式模拟不同 τ 阈值，计算 Efficiency(τ) = Kept Images / Total Cost，找到 τ\* = argmax Efficiency，验证 τ\* 在 Light vs Mid 下的漂移。

**输入**：`data/{context}_full.csv` (3个: Idle/Light/Mid) → `infiProbPerson` + `totalMs` + `latencyMs`

**关键发现**：
- τ\*(Light) = 0.989 vs τ\*(Mid) = 0.994 (Δτ = +0.005) — 阈值漂移确认
- Mid 用 τ=0.5 损失 13.5% 效率 (Light 仅 1.4%) — 重负载下固定阈值代价放大 ~10x

**运行**：
```bash
python scripts/analysis_tau_scan.py
```

### 3. `analysis_v2.py` — Light vs Mid 多维对比分析

**功能**：对 Light 和 Mid 数据集进行 13 维详细对比分析：推理时间、τ 分布、温度、CPU、内存、电池/功耗、Thermal Level、准确率、分辨率、相关性、按温度分组、对比总结。

**输入**：`data/light_full.csv` + `data/mid_full.csv` (v2 schema, 29列)

**运行**：
```bash
python scripts/analysis_v2.py
```

### 4. `analysis.py` — 单数据集分析 (v1)

**功能**：对单个 v1 格式数据集进行基础分析：推理时间统计、温度分布、状态分布、CPU 使用率、准确率 (TP/FP/FN/TN)、分辨率分布、吞吐量、温度-时间相关性。

**输入**：`data/idle_full.csv` (v1 schema, `skiprows=1` + 手动列名)

> ⚠️ 此脚本使用 v1 schema (`skiprows=1`)，直接运行可能因列结构变化报错。推荐使用 `pareto_analysis.py` 代替。

---

## 结果文件 (`results/`)

| 文件 | 格式 | 说明 |
|------|------|------|
| `pareto_results.csv` | CSV | τ 扫描全量结果：Context, τ, KeptImages, TotalValue, SavedCost_ms, SavedCost_s, SavedCost_pct, ParetoOptimal |
| `pareto_results.json` | JSON | 结构化 Pareto 数据，按 Context 分组，含 `pareto_points` 和 `all_points` |
| `pareto_tradeoff.png` | PNG | 双面板图 (16×6 inch, 150dpi): (左) Value-Cost 权衡曲线 (右) ΔSavedCost vs Idle baseline |

---

## 核心概念

### InFi Gating 机制

```
D(x, τ) = 1 if infiProbPerson >= τ, else 0
```

- `infiProbPerson` = InFi 模型对"图片中有人"的置信度 [0, 1]
- τ = 门控阈值：低于 τ 的图片跳过推理（节省成本），高于 τ 的图片执行 YOLO 推理
- `_full.csv` 数据集：τ 未实际生效（所有 5000 张全量执行），但 `infiProbPerson` 字段允许回溯式 τ 扫描

### 关键指标

| 指标 | 定义 | 说明 |
|------|------|------|
| **Efficiency(τ)** | KeptImages / TotalCost | 单位成本（ms）保留的图片数 |
| **TotalValue(τ)** | KeptImages | 保留图片数 (Value=1 per image) |
| **SavedCost(τ)** | TotalCost(τ=0) − TotalCost(τ) | 通过过滤节省的推理时间 (ms) |
| **τ\*** | argmax Efficiency(τ) | 最优门控阈值 |

### 四个运行时上下文

| Context | stateName | 系统负载 | Thermal 风险 |
|---------|-----------|---------|-------------|
| **Idle** | Idle | 无后台任务 | 低 (≤40°C) |
| **Light** | Light (Music + Nav) | 音乐 + 导航 | 中 (≤38°C) |
| **Mid** | Mid (Meeting) | 视频会议 | 高 (≤46°C, Level 6-7) |
| **Heavy** | Heavy | 高负载 | 最高 |

---

## 依赖

```bash
pip install pandas numpy matplotlib
```

---

## 典型工作流

```bash
# 1. 运行 Pareto 分析 (4 context 全量扫描)
python scripts/pareto_analysis.py

# 2. 查看结果
cat results/pareto_results.csv
# 或打开 results/pareto_tradeoff.png

# 3. 如需 τ* 精细搜索
python scripts/analysis_tau_scan.py

# 4. 阅读详细报告
cat analysis_report.md
```

---

## 相关文件

- `../CLAUDE.md` — NativeCase 项目整体开发指南
- `../entry/src/main/ets/pages/TestDashboardPage.ets` — 数据采集端 (HarmonyOS 测试面板)
- `../exp_requirements_2.md` — 实验需求文档
