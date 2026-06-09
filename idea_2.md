# Research Idea: Runtime Context 对移动端 AI 调度器决策的影响

## 一、核心问题

移动端 AI 调度器（模型选择、Early Exit、Inference Filtering 等）普遍依赖一个**隐含假设**：

> 推理成本是稳定的 → 使用固定决策边界（如固定阈值 τ）是合理的

但这个假设在真实移动设备中未必成立。Runtime Context（CPU/GPU 竞争、后台应用、温度、DVFS）能造成**同一模型、同一输入下数倍的延迟/能耗差异**。

这意味着：
- 调度器决策逻辑没变，但决策背后的成本结构已经变了
- Idle 环境下的最优阈值，在其他 Context 下可能不再最优

---

## 二、以 InFi 为 Case Study

**目标不是改进 InFi 本身**，而是用它作为典型阈值型调度器来验证一个系统层面观察：

> Runtime Context 不仅影响推理性能，更会影响调度决策本身。

选择 InFi 的理由：
- 简单、干净：一个轻量 Gating Network → 评分 > τ → 执行重模型，否则跳过
- 阈值 τ 本质上反映了系统对推理成本的估计
- 固定 τ 就是典型的「静态成本假设」

### 核心假设

$$τ^* = τ^*(context) \quad \text{而非} \quad τ = constant$$

最优阈值应当依赖于当前运行环境。

### 不关注什么

不关注目标检测精度（mAP、Recall 等下游指标），只关注**调度本身的资源利用效率**。

### 如何评估当前调度器的好坏？

调度器的目标不是无脑节省成本，而是在**保留推理价值**和**节省推理成本**之间取得平衡。我们采用两种互补的评估方式：

---

#### 方法一：Utility 函数（λ-based）

定义综合效用函数，显式编码价值与成本的兑换关系：

$$Utility(τ, context) = Kept(τ) - \lambda \cdot TotalCost(τ, context)$$

其中：
- $D(x, τ) = 1$ 如果 $infiProbPerson(x) > τ$（执行重模型），否则 $0$（跳过）
- $Kept(τ)$ 是保留的图片数量（每张图片价值统一为 1）
- $TotalCost(τ, context)$ 是保留图片的总推理成本，**依赖 Context**
- $\lambda$ 是成本到价值的**兑换率**——「节省 1ms 推理时间相当于愿意牺牲多少张图片的推理结果」

当 $\lambda$ 固定时，$Utility(τ)$ 存在内部最优：
- τ → 0：保留所有图片（Kept 最大），但成本也最大 → Utility 受成本拖累
- τ → 1：过滤几乎所有图片（成本趋零），但 Kept 也趋零 → Utility 受价值损失拖累
- 最优 τ\* 在中间，由 $\lambda$ 和 Cost 分布共同决定

**$\lambda$ 的 Context 依赖性**：$\lambda$ 本质上反映了 Context 对「成本敏感度」的影响——Heavy Context 下推理昂贵（~404ms/img），同样的成本能换更多价值，等效 $\lambda$ 更大。

**局限性**：$\lambda$ 需要人为设定，不同的 $\lambda$ 导致不同的 τ\*，缺乏客观性。

---

#### 方法二：Pareto Tradeoff 分析（λ-free）

为避免人为设定 $\lambda$，直接绘制调度器的 **Value-Cost Tradeoff 曲线**，用 Pareto 前沿比较不同 Context：

对每个 Context，扫描 τ ∈ [0, 1]，计算两个**绝对量**指标：

$$TotalValue(τ) = Kept(τ) \quad \text{（保留的图片数量，Value=1/张）}$$

$$SavedCost(τ) = Cost_{all} - Cost_{kept}(τ) \quad \text{（跳过的图片节省的总成本，ms）}$$

两者的 tradeoff 是天然的：
- τ ↑ → Kept ↓ → TotalValue ↓，但 SavedCost ↑
- τ ↓ → Kept ↑ → TotalValue ↑，但 SavedCost ↓

**Pareto 前沿**：所有不被其他 τ 同时支配的点（不存在另一个 τ 同时拥有更高的 TotalValue 和更高的 SavedCost）。

**核心分析逻辑**：同一批图片在四个 Context 下拥有相同的 InFi score 分布，因此相同 τ 下的 TotalValue 完全相等。但由于每个 Context 的单图推理成本不同，**相同 TotalValue 对应的 SavedCost 不同**：

| τ | TotalValue | Idle | Light | Mid | Heavy | MaxΔ |
|---|-----------|------|-------|-----|-------|------|
| 0.50 | 2997 | 545s | 559s | 586s | **904s** | 359s |
| 0.60 | 2690 | 629s | 642s | 672s | **1028s** | 399s |
| 0.80 | 2191 | 760s | 778s | 810s | **1227s** | 466s |
| 0.95 | 1629 | 892s | 922s | 963s | **1448s** | 556s |

**解读**：要交付同样的 2690 张图片，Heavy 比 Idle 多省 399s。因为 Heavy 中每张图成本是 Idle 的 1.6x（404ms vs 252ms），过滤同样数量的图片在 Heavy 中省得更多。

**结论**：Value-Cost 兑换率是 context-dependent 的。固定 τ 在所有 Context 下交付相同的 TotalValue，但在 Heavy 中留下了大量未实现的潜在节省（或等价地，在 Idle 中过度过滤了）。

---

#### 两种方法的关系

| | 方法一 (Utility) | 方法二 (Pareto) |
|---|---|---|
| 需要 λ？ | ✅ 需要手动设定 | ❌ 不需要 |
| 输出 | 单一最优 τ\* | 完整 Tradeoff 曲线 |
| 优势 | 可得出具体 τ\* 建议 | 客观、无参、可视化 |
| 劣势 | λ 选择影响结论 | 不能直接给出「最优 τ」 |
| 用途 | 给定 λ 下的策略优化 | 证明 Context 改变了调度基本 tradeoff |

两种方法互补：Pareto 分析先**证明现象存在**（Context 改变了 Value-Cost tradeoff），Utility 函数再在给定部署偏好（λ）下**量化最优 τ\***。

### 目标

在每个 Context 下找到最优阈值：
$$τ^*(context) = \arg\max\ Utility(τ, context)$$

然后比较不同 Context 下的最优阈值：
$$τ^*(cold) \neq τ^*(warm) \neq τ^*(hot)$$

验证**固定阈值在真实移动设备上并非总是最优**。

---

## 三、研究思路

| 步骤 | 发现/问题 | 方法 |
|------|----------|------|
| **Step 1** | $Cost(M, Context) \neq Cost(M)$ — 推理成本随 Context 变化 | Exp 1: 同一模型在多种系统状态下测量延迟/能耗变化 |
| **Step 2** | $τ^*(cold) \neq τ^*(hot)$ — 最优阈值会漂移 | Exp 2: 在不同 Context 下扫描 τ，绘制 Efficiency 曲线 |
| **Step 3** | 如果 τ\* 随 Context 变化，如何**在运行时获得当前 Context 下的最优 τ\***？ | 自然引出：Context-aware online threshold prediction |

整个工作本质上是在提出并验证一个系统观察：

> Runtime Context 不仅影响推理性能，更会影响调度决策本身。

InFi 只是证明这一现象的代表性案例。未来这一结论可以推广到其他基于静态成本假设的移动 AI 调度器（模型选择、Early Exit、多模型调度、端侧 Agent 推理系统等）。

---

## 四、实验（2+ 个实验）

整体逻辑：**Motivation → Observation (×4) → Method (Oracle + Ablation) → System**

| # | 实验 | Phase | 核心目标 | 状态 |
|---|------|-------|---------|------|
| 1 | Cost Variability under Runtime Interference | Observation | 同一模型 Cost 随系统状态剧烈变化 | ✅ |
| 2 | InFi Static Baseline | Observation | 真实 COCO 图片 + YOLO 推理基线 + τ 扫描 | ✅ |
| 3 | Budget-Constrained Video | System | 能耗预算约束下的模型分配 | ✅ |

---

## 五、实验设计详情

### Exp 1: Cost Variability under Runtime Interference

**目的**: 量化同一 YOLO 模型在多种系统状态下的推理 Cost 变化。

**系统状态**: Idle / Light (Music+Nav) / Mid (Meeting) / Heavy (All) / Extreme (All+Load)

**实现**: 用户手动设置 App 场景 + ResourceSimulator 叠加负载 → 冷却等待 → 稳定 30s → 连续推理 N 分钟。支持逐状态勾选、冷却温度阈值可调。

**记录指标**: `latencyMs`, `energyMw`, `cpuUsage%`, `cpuFreqs`, `fps`, `temp`

### Exp 2: InFi Static Baseline

**目的**: 使用预计算 InFi 结果 + 真实 COCO 图片，建立 YOLO 推理基线，扫描 τ 值分析调度效率。

**核心公式**:
$$Utility(τ, context) = \sum_{x} D(x, τ, context) \cdot Benefit(x) - \sum_{x} D(x, τ, context) \cdot Cost(x, context)$$

其中 $D(x, τ, context)$ 是 gating 决策（1 = 执行重模型，0 = 跳过），$Benefit(x)$ 是单张图片价值（可固定为 1）。

**数据源**:
- InFi 结果: `rawfile/data_config/` JSON（预计算 gating 决策）
- COCO 图片: 设备沙箱 `COCO_val/`（5000 张 JPEG）

**bsz4 批推理流程**:
```
每 4 张图为一个 batch:
  Image[0..3] → decodeAndPreprocessFused() → CHW[3,640,640]
  → stack 为 4×3×640×640 NCHW → model.predict() 一次
  → batch_latency / 4 = per_image_latency
```

**融合预处理** (`decodeAndPreprocessFused`): RGBA bytes → 一趟循环 → CHW[3,640,640]，5 步计时（open / jpeg / read / params / loop）。

**UI 指标**:

| 指标 | 含义 |
|------|------|
| Prep | 单张图融合预处理耗时 |
| Infer | 单 batch predict 耗时 |
| Pass | InFi pred_person=1 的图片数 |
| Skip | InFi pred_person=0 的图片数 |
| Miss | per-image latency > deadline 的图片数 |
| Gate toggle | ON = 跳过 pred_person=0 的图片 |

**CSV 输出**: 29 列全量系统指标：

| # | 列名 | 来源 | 说明 |
|---|------|------|------|
| 1-4 | imgId, file, origResolution, infiPredPerson | InFi JSON | 图像标识 + gating 决策 |
| 5-8 | infiProbPerson, gtPerson, infiCorrect, infiType | InFi JSON | 置信度 + GT + 混淆矩阵类型 |
| 9 | yoloModel | 参数 | YOLO 模型文件名 |
| 10 | latencyMs | 测量 | 单图推理延迟 |
| 11 | prepMs | 测量 | 单图融合预处理耗时 |
| 12 | totalMs | 计算 | prepMs + latencyMs |
| 13 | deadlineMiss | 计算 | 是否超 deadline |
| 14 | stateName | 参数 | 系统状态名 |
| 15-16 | cpuProcPct, cpuSysPct | hidebug | 进程/系统 CPU% |
| 17 | pssMb | hidebug | 进程 PSS 内存 |
| 18-20 | availMemMb, totalMemMb, freeMemMb | hidebug | 系统内存 |
| 21 | cpuFreqsKhz | libentry | CPU 核心频率 (CSV) |
| 22 | gpuFreqKhz | libentry | GPU 频率 |
| 23 | batterySocPct | batteryInfo | 电池电量% |
| 24 | batteryTempC | batteryInfo | 电池温度°C |
| 25-26 | batteryCurrentMa, batteryVoltageMv | batteryInfo | 电流/电压 |
| 27 | batteryPowerMw | 计算 | 瞬时功率 |
| 28 | thermalLevel | thermal | 热等级 |
| 29 | preprocessMode | 固定 | `'fused'` |

### Exp 3: ToDo
---

## 六、当前进展：Exp 2 数据采集与分析

### 已采集的 4 个数据集

使用 YOLOv8l-bsz4 模型，COCO 5,000 张图片，fused 预处理：

| 数据集 (CSV) | 系统状态 | 温度范围 | 平均 totalMs | 总成本 | vs Idle |
|-------------|---------|---------|-------------|--------|---------|
| `idle_full` | **Idle** | — | 252 ms | 1,259s | 1.00x |
| `light_full` | **Light** (Music+Nav) | 33→42°C | 257 ms | 1,284s | 1.02x |
| `mid_full` | **Mid** (Meeting) | — | 267 ms | 1,336s | 1.06x |
| `heavy_full` | **Heavy** (Music+Nav+Meeting) | 35→47°C | **404 ms** | 2,018s | **1.60x** |

### 关键发现

1. **Cost 受 Context 显著影响，且呈阶梯式分布**
   - Idle/Light/Mid 聚为一簇（252-267ms，差距 <6%）
   - Heavy 单独拉开（**404ms，是 Idle 的 1.60x**）
   - Heavy 总推理成本 2,018s，比 Idle 多出 760s（+60%）

2. **温度是最强 Cost 预测因子**（Mid 数据验证）
   - batteryTempC 单独解释 **83.5%** 的 latencyMs 方差（R²=0.835, r=0.914）
   - thermalLevel、freeMemMb、batteryVoltageMv 与温度高度共线（r>0.85）
   - 加入更多指标仅增加 R² 1.3% → 测温就够了
   - prepMs 与所有系统指标 r≈0 → 预处理不受 Context 影响

3. **准确率完全不受 Context 影响** — Context 只改变 Cost，不改变模型输出质量

### 分析工具

| 文件 | 用途 |
|------|------|
| `data_analyzer/analysis.py` | 单文件深度分析（温度分布、相关性、准确率、分辨率分布） |
| `data_analyzer/analysis_v2.py` | 双文件对比分析（13 个维度，含 Light vs Mid 总结表） |
| `data_analyzer/archive.md` | 3 个数据集的核心统计量归档 |

### Pareto Tradeoff 分析结果（2025-06-08）

利用四组 Context 的 CSV 数据，扫描 τ ∈ [0, 1]，计算 TotalValue（保留图片数）vs SavedCost（节省的总推理时间）。

> 四组 Context 使用同一批 5,000 张 COCO 图片和同一个 InFi 模型，因此 score 分布完全相同。相同 τ 下的 TotalValue 严格相等，差异仅体现在 SavedCost。

#### Tradeoff 核心数据

| τ | TotalValue | Idle Saved | Light Saved | Mid Saved | Heavy Saved | MaxΔ(Heavy-Idle) |
|---|-----------|-----------|------------|----------|------------|-------------------|
| 0.20 | 3976 | 282s | 289s | 303s | **467s** | +185s |
| 0.40 | 3295 | 465s | 477s | 501s | **780s** | +315s |
| 0.50 | 2997 | 545s | 559s | 586s | **904s** | +359s |
| 0.60 | 2690 | 629s | 642s | 672s | **1028s** | +399s |
| 0.80 | 2191 | 760s | 778s | 810s | **1227s** | +466s |
| 0.95 | 1629 | 892s | 922s | 963s | **1448s** | +556s |

#### 关键结论

1. **Value-Cost 兑换率是 context-dependent**：同样保留 2,690 张图片，Heavy 省 1,028s，Idle 只省 629s——Heavy 中每过滤一张图省得更多

2. **Context 差距随 τ 增大而放大**：MaxΔ 从 τ=0.20 的 185s 扩大到 τ=0.95 的 556s（+200%）——过滤越激进，Context 差异越显著

3. **Idle/Light/Mid 聚为一簇**（差距 <6%），Heavy 单独拉开（1.60x）——说明要看到显著 Context 效应需要足够的负载差异

4. **所有 21 个 τ 点均在 Pareto 前沿上**（曲线严格单调）——每个 τ 都是不可支配的，不存在「免费的午餐」

---

## 七、代码结构

```
entry/src/main/
├── cpp/
│   ├── SysfsReader/          # CPU/GPU 频率读取
│   ├── napi_init.cpp          # NAPI 注册
│   └── types/libentry/Index.d.ts
│
├── ets/
│   ├── experiments2/
│   │   ├── ExperimentTypes.ts           # 共享类型 + 常量
│   │   ├── SystemStateManager.ts        # 混合模式状态管理
│   │   ├── SyntheticImageGenerator.ts   # Easy/Medium/Hard 合成图像
│   │   ├── QualityScorer.ts             # 置信度代理评分
│   │   ├── ImageFeatureExtractor.ts     # 图像特征提取 (HWC)
│   │   ├── GainPredictor.ts             # 增益预测 (线性启发式)
│   │   ├── YoloPreprocessor.ts          # YOLO 6-step 预处理流水线
│   │   ├── InfiResultLoader.ts          # InFi JSON 加载器
│   │   ├── CocoImagePreprocessor.ts     # COCO JPEG 解码 + 融合预处理
│   │   └── BaseExperimentRunner.ts      # 多模型基类 + MetricsCollector
│   │
│   ├── pages/
│   │   ├── ExperimentPage.ets           # Dashboard 1 (3-Tab)
│   │   ├── ExperimentPage2.ets          # Dashboard 2 (6-Tab, ~2149行)
│   │   └── Index.ets                    # 导航主页
│   │
│   └── utils/
│       ├── CsvLogger.ts
│       └── ExperimentRunner.ts
│
└── resources/rawfile/data_config/
    ├── onnx_person_val2017_100.json
    ├── onnx_person_val2017_200.json
    ├── onnx_person_val2017_500.json
    ├── onnx_person_val2017_1000.json
    ├── onnx_person_val2017_2000.json
    └── onnx_person_val2017_sorted.json
```

---

## 八、下一步方向

按照三段论逻辑，Step 1（Cost Variability）和 Step 2（τ 扫描 + 阈值漂移验证）已完成。

### 已完成

1. ✅ Step 1 — Cost Variability：确认 Cost 随 Context 显著变化，Heavy (404ms) 是 Idle (252ms) 的 **1.60x**
2. ✅ Step 2 — Pareto Tradeoff：λ-free 方式证明 Same TotalValue → Different SavedCost，Value-Cost 兑换率是 context-dependent 的
3. ✅ Cost Predictor：batteryTempC 单独解释 **83.5%** 的推理延迟方差，可作为 Context → Cost 的单特征代理

### 短期

- 用方法一（Utility 函数）确定 λ 取值策略 → 量化 τ\* → 验证 τ\* 漂移
- 补充更极端的 Context（如 Extreme = All+Load）拉大曲线间距

### 中期（Step 3 探索）

- **Context → τ\* 映射**：用 batteryTempC 等特征在线预测最优阈值
- **Cost prediction model**：温度 → Cost 的单变量回归即可实现高效的在线成本估计
- **Online adaptation**：运行时感知 Context 变化，动态调整 τ
