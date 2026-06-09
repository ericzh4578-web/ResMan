# LLM/DNN 推理调度论文的 Latency 获取方式与 Context 感知分析

> 分析时间：2026-06-05
> 涵盖论文：FlexNN, Flex, Pantheon, RAMSIS, Vulcan, Phoenix

---

## 1. FlexNN (MobiCom '24)

**论文标题**: *FlexNN: Efficient and Adaptive DNN Inference on Memory-Constrained Edge Devices*

### 做了什么
FlexNN 面向内存受限的边缘设备（如智能手机、IoT 设备），提出了一种基于"切片-加载-计算联合规划"的 DNN 推理框架。其核心思路是通过对 DNN 层进行细粒度切片（weights slicing / input slicing），结合 Kernel 选择（Winograd / Im2col+GeMM / Direct Conv 之间的 latency-memory trade-off）和预加载感知的内存布局规划，在满足内存预算约束的前提下最小化推理延迟。FlexNN 在 NCNN 上实现，能在仅增加 3.64% 延迟的情况下减少 93.81% 的内存占用。

### Latency 是如何获取的
- **纯离线 Profiling**：在 offline 阶段对模型的每个 tensor 进行 memory size 和 lifecycle 的 profiling，同时对每层的不同 Kernel 实现（如 Winograd Conv、Im2col+GeMM Conv、Direct Conv）的 latency 和 memory 进行预先测量。
- **Latency-Memory Trade-off 表**：基于 profiled 数据，系统维护每层不同 Kernel 的 latency-memory 查找表。在线推理时，在满足内存约束的前提下选择 latency 最优的 Kernel。
- **规划优化目标**：内存规划算法将"最小化推理延迟"作为优化目标，但该延迟是基于 offline profiled 的固定值计算的。

### 是否考虑机器当前状态/Context 变化？
**基本不考慮。** FlexNN 的"动态性"仅指内存预算的动态变化（如不同设备或不同时刻可用内存不同），它会根据新的内存预算重用 offline profile 重新生成执行计划。但它**不感知**当前 CPU 负载、温度、频率调节（DVFS）、其他进程竞争等真实运行时状态。所有 latency 数值均假设在 isolated 的理想条件下测得。

---

## 2. Flex (EuroSys '25)

**论文标题**: *Flex: Fast, Accurate DNN Inference on Low-Cost Edges Using Heterogeneous Accelerator Execution*

### 做了什么
Flex 面向配备低成本加速器（LCA，如低精度 GPU/NPU/DSP）的边缘设备，提出了一种**逐输入动态**将 DNN 层分配到 CPU 或 LCA 上执行的系统。核心观察是：不同输入样本在 LCA 上的精度损失和加速效果不同，因此需要在 per-input 粒度上动态决定每层运行在哪里。Flex 使用随机森林回归器预测每层的推理时间和精度，并通过启发式方法或强化学习（RL）找到最优的 CPU/LCA 层分配方案。

### Latency 是如何获取的
- **Offline Profiling + 机器学习预测**：使用 TensorFlow benchmark 在云端进行 offline profiling，对不同的层分配方案（layer assignment）测量推理时间和精度。
- **随机森林回归器（RF-T, RF-A）**：基于 profiled 数据训练两个随机森林模型，分别预测给定层分配方案和输入的推理时间和精度。输入特征包括：结构参数（input/output dimensions, kernel size 等）、层分配方案、以及输入样本。
- **通信时间也纳入 Profiling**：CPU 与 LCA 之间的中间数据传输时间被包含在测量的推理时间内。
- **RL 方法中也依赖 Profiled Data**：RL 的 state space 包含 profiled 的层分配性能数据，用于计算 reward。

### 是否考虑机器当前状态/Context 变化？
**只考虑了输入变化，不考虑机器状态变化。** Flex 的"动态"体现在 per-input adaptation——不同输入可能导致不同的层分配决策。但它**完全不考虑**设备当前的负载、CPU/GPU 利用率、温度、功耗限制等运行时上下文。所有预测模型都基于 offline profiling 训练的，而 profiling 是在受控环境下进行的。

---

## 3. Pantheon (MobiSys '24)

**论文标题**: *Pantheon: Preemptible Multi-DNN Inference on Mobile Edge GPUs*

### 做了什么
Pantheon 面向移动边缘 GPU（如 NVIDIA Jetson 系列）上的多 DNN 并发推理场景，设计了一套细粒度的抢占式调度系统。核心贡献包括：(1) 利用 GPU 的两级 stream 优先级，通过软件设计实现 real-time 任务之间以及 real-time 对 best-effort 任务的抢占；(2) 利用 DNN 的嵌套冗余（nested redundancy）——通过 early exits 机制生成同一模型的多个变体，被抢占的任务恢复后可以选择更小的变体继续执行以满足 deadline；(3) 将 DNN 在 critical node 处切片以最小化上下文切换时的中间数据存储开销。

### Latency 是如何获取的
- **Offline Profiling 每个 Chunk 的执行延迟**：在 offline preprocessing 阶段，DNN 被切片为多个 chunk，每个 chunk 的执行延迟 $t_j'$ 被提前测量。
- **Early Exit 变体的 Accuracy-Latency Profile**：每个 early exit 对应的模型变体的 accuracy 和执行延迟也被 offline profile，用于构建 Pareto frontier。
- **论文在 Discussion 中明确承认局限**：*"Given actual inputs and device runtime states, the performance of a model variant (e.g., accuracy) may differ from the profiled one. However, profiling is still widely adopted..."*

### 是否考虑机器当前状态/Context 变化？
**承认了问题但未解决。** Pantheon 的调度决策（选择哪个模型变体、何时抢占）完全依赖 offline profiled 的固定 latency 值。虽然系统动态地根据任务 deadline 和到达模式进行在线调度，但每个任务的执行时间假设是固定的 profiled 值。论文在 Discussion 中明确承认了运行时设备状态（如 GPU 温度、功率状态、内存带宽争抢）可能导致实际性能偏离 profiled 数据，但并未提出解决方案，仍将其列为 profiling 的固有限制。

---

## 4. RAMSIS (EuroSys '24)

**论文标题**: *Model Selection for Latency-Critical Inference Serving*

### 做了什么
RAMSIS 面向推理服务系统（Inference Serving System）中的模型选择与调度（MS&S）问题。现有方法仅按查询负载（query load）粒度做决策，RAMSIS 的 key insight 是：查询的随机到达模式中存在"到达间歇"（arrival lulls），在此期间可以安全地选择更高精度（但也更高延迟）的模型。RAMSIS 将 MS&S 问题建模为马尔可夫决策过程（MDP），在离线阶段为不同的查询负载和到达模式预计算最优 MS&S policy，在线阶段根据当前队列状态查表执行决策。

### Latency 是如何获取的
- **Offline Profiling 步骤**：与 Clipper、Nexus、INFaaS、Jellyfish 等先前工作一致，RAMSIS 要求对所有 model × worker × batch size 的组合进行 inference latency profiling。
- **假设 Latency 是可预测的确定值**：论文明确指出 *"inference latency is predictable"* 和 *"assumes deterministic, predictable inference response latency"*（Table 1）。这意味着每个 (worker, model, batch_size) 三元组的延迟被视为固定的 profiled 值。
- **MDP 模型的输入**：Profiled latency 作为 MDP 状态转移的已知参数，用于判断某个 MS&S 决策是否能在 deadline 前完成。

### 是否考虑机器当前状态/Context 变化？
**完全不考虑。** RAMSIS 的创新在于将查询的**到达模式**（query inter-arrival pattern）纳入了调度决策，而非仅考虑平均负载。但它对模型推理延迟本身采用最静态的处理方式——假设延迟是完全确定且固定的。Worker 的计算能力、GPU 利用率、内存带宽等实时状态完全不在 MDP 的状态空间内。论文明确声明的假设之一就是"deterministic, predictable inference response latency"。

---

## 5. Vulcan (NSDI '24)

**论文标题**: *Vulcan: Automatic Query Planning for Live ML Analytics*

### 做了什么
Vulcan 面向跨边缘层级（设备端 → 本地边缘 → 公共 MEC → 云）的实时 ML 分析查询，提供了一个端到端的自动查询规划系统。给定用户的查询规范和性能需求（accuracy/latency target），Vulcan 自动完成三件事：(1) 构建 ML pipeline（选择并排序过滤算子）；(2) 确定每个算子的物理部署位置（placement）；(3) 选择每个算子的配置参数（configuration）。此外，Vulcan 还支持部署后的在线自适应（online adaptation），通过监测 utility 变化来检测数据和资源动态，并触发低成本的 re-profiling。

### Latency 是如何获取的
- **Compute Latency**：通过 offline profiling 在数据中心实际运行 pipeline 来获取各算子的计算延迟。Vulcan 使用 pipeline 结果缓存（caching intermediate results）来降低搜索不同 placement 选择时的 profiling 成本。
- **Network Latency**：根据各算子的输出数据量和链路带宽**计算**额外的网络传输延迟，不需要实际部署到每个边缘节点测量。
- **Bayesian Optimization（BO）**：用于在巨大的配置空间中高效搜索最优配置，BO 每次迭代需要实际运行 pipeline 获取测量值。
- **Online Re-profiling**：当检测到 utility 变化（由于数据内容或资源变化），Vulcan 触发 re-profiling，在云端重新运行 pipeline 并更新模型。

### 是否考虑机器当前状态/Context 变化？
**部分考虑，但是以 reactive 方式。** Vulcan 是五篇论文中对运行时动态处理最完善的：
- **能检测资源变化**：明确提到 *"compute and network resource changes"* 会影响查询性能，并通过 monitoring utility 来检测。
- **能检测数据内容变化**：如光照变化、物体密度变化等对 pipeline 精度/延迟的影响。
- **但不直接读取机器状态**：Vulcan 的适应机制是"检测到 utility 下降 → 在云端重新 profiling → 更新配置"，而非直接读取当前 GPU 利用率、CPU 频率、内存带宽等硬件状态。它感知的是"结果变差了"而非"机器当前处于什么状态"。
- **Latency 仍是基于 Profiling 的估计值**：即使有 online adaptation，其 latency 预测仍依赖 re-profiling 的结果，而非实时硬件状态感知。

---

## 6. Phoenix (ACM TECS '26)

**论文标题**: *Phoenix: Thermal-Aware On-Device Inference of Multi-Instance DNNs for Mobile Video Applications*

### 做了什么
Phoenix 面向移动设备上同时运行多个 DNN 推理任务的视频应用（如 VTuber、AR/VR），提出了一个**热感知（thermal-aware）**的推理调度系统。其核心贡献分为两层：(1) 使用强化学习（DQN）学习一个热感知的任务分配策略，将多个 DNN 任务动态分配到异构处理器（CPU/GPU/NNAPI DSP）上，以延缓热限频（thermal throttling）的发生；(2) 当热限频不可避免发生后，通过多出口网络（multi-exit network）动态选择更浅的 early exit 来降低计算量，维持目标帧率。Phoenix 还使用 NAS（神经网络架构搜索）为每个处理器在限频条件下的减速模式（slowdown pattern）定制最优的 early exit 架构。运行时提供两种调度器：Best-Effort（最大化当前精度）和 Sustained Performance（基于 PID 控制主动提前降低出口深度以维持长期稳定性能）。

### Latency 是如何获取的
Phoenix 的 latency 获取方式与前述五篇论文有**本质区别**——它不是依赖静态的 offline profiling 定值，而是直接**实时测量**：

- **RL 训练阶段（Offline）**：每个 episode 中，系统在真实设备上实际运行推理，直接测量 `Lnow`（当前配置下的执行时间）和 `Lnormal`（无热限频条件下的参考延迟）。RL agent 的 state 中包含 slowdown ratio = `Lnow / Lnormal`，这是实时测量值而非预估值。
- **NAS 搜索阶段（Offline）**：采用 **hardware-in-the-loop** 方式——直接设置手机 CPU/GPU 频率来模拟热限频条件，然后在真实设备上实际运行 early exit 网络并测量执行时间。这确保了获取的延迟数据反映的是**真实硬件在限频状态下的性能**。
- **运行时（Online）**：在每个推理周期，调度器直接测量当前 exit 的实际执行延迟（`latencyOfCurrentExit(dnn_i)`），并据此判断是否违反延迟约束。Sustained Performance 调度器还持续监控实时温度和延迟反馈，用 PID 控制器动态调整 exit 选择。
- **仅 `Lnormal` 作为离线参考值**：Phoenix 仅在计算 slowdown ratio 时使用 profiled 的 `Lnormal`（无热限频条件下的延迟）作为归一化基准，实际的调度决策依赖实时测量值。

### 是否考虑机器当前状态/Context 变化？
**是 — Phoenix 是六篇论文中唯一将机器实时状态作为一级调度输入的。这也是其核心创新所在。**

Phoenix 的 RL agent 的 **State Space 直接包含**：
- CPU/GPU 的当前**利用率**（utilization）
- CPU/GPU 的当前**运行频率**（operational frequency）
- CPU/GPU 的当前**温度**（temperature）
- 每个处理器的**减速比率**（slowdown proxy = `Lnow / Lnormal`）
- **热余量**（thermal headroom）

运行时部署的 Rule Table 以 CPU/GPU 当前频率对为索引，通过移动平均平滑瞬时频率波动。Sustained Performance 调度器使用 PID 控制理论，以**实时温度和延迟作为反馈信号**，持续调整 exit 深度。

Phoenix 处理了两类 Context 变化：
1. **热状态变化**：温度上升 → 处理器降频 → 推理变慢。Phoenix 同时通过预防（RL 任务分配延缓升温）和适应（early exit 应对降频）两种机制处理。
2. **处理器异构减速模式**：不同处理器（CPU/GPU/DSP）在热限频下的性能退化模式不同（如 GPU 在 640MHz 和 285MHz 两档之间切换，延迟增加 1.2~2.3 倍），Phoenix 的 NAS 为这些不同的减速模式定制 early exit 架构。

---

## 总结对比

| 维度 | FlexNN | Flex | Pantheon | RAMSIS | Vulcan | **Phoenix** |
|------|--------|------|----------|--------|--------|-------------|
| **Latency 获取方式** | 离线 Profile Kernel 延迟表 | 离线 Profile + 随机森林预测 | 离线 Profile Chunk/Exit 延迟 | 离线 Profile (model,worker,bs) 延迟 | 离线 Profile 计算延迟 + 带宽计算网络延迟 | **实时测量 + Hardware-in-the-loop NAS** |
| **是否为定值** | ✅ 是 | ✅ 是 | ✅ 是 | ✅ 是 | ✅ 基本是 | **❌ 否（实时测量 `Lnow`，仅 `Lnormal` 为参考基准值）** |
| **是否考虑输入变化** | ❌ 否 | ✅ 是（per-input 层分配） | ❌ 否 | ❌ 否（仅考虑 arrival pattern） | ✅ 是 | ❌ 否（视频帧流，输入连续相同类型） |
| **是否考虑机器当前状态** | ❌ 否 | ❌ 否 | ❌ 否（承认问题但未解决） | ❌ 否 | ⚠️ 间接 | **✅ 是（CPU/GPU 频率、利用率、温度、slowdown ratio、热余量均为 RL State 的一部分）** |
| **动态适配机制** | 内存预算变化时重新规划 | Per-input 动态分配 CPU/LCA | 抢占调度 + early exit 动态选变体 | MDP policy 按负载/到达模式查表 | BO re-profiling + online adaptation | **RL 热感知任务分配 + PID 控制的 early exit 调度** |
| **对 Context 变化的敏感度** | 无 | 无 | 无 | 无 | 间接感知"效果变化" | **直接感知硬件状态（频率/温度/利用率）** |

### 关键发现

**六篇论文中，前五篇均使用 offline profiling 的固定 latency 值作为调度决策依据，只有 Phoenix 直接将机器的实时运行状态作为调度系统的核心输入。**

- FlexNN、Flex、Pantheon、RAMSIS 将 latency 视为在 isolation 环境下测量的确定值。
- Vulcan 最接近"context-aware"（在五篇中），但感知方式是"结果导向"（utility 下降了）而非"状态导向"（GPU 利用率达到 90%）。
- **Phoenix 是唯一的例外**：它的 RL state space 直接包含 CPU/GPU 频率、温度、利用率和实测 slowdown ratio；运行时调度器持续监控实时温度和延迟反馈。其核心问题域（热限频）天然要求它必须感知硬件状态——温度上升→降频→延迟增加这个因果链是 Phoenix 调度决策的基础。

这反映了一个重要的 **domain-driven design 差异**：前五篇论文面向的场景（云端推理服务、边缘 GPU、内存受限设备）倾向于假设硬件性能是稳定的，调度优化主要关注 workload 侧的变化（query 负载、到达模式、内存预算等）。而 Phoenix 面向的移动设备热限频场景**天然不允许这个假设**——热限频导致同一设备上同一模型的推理延迟可波动 2× 以上，迫使调度系统必须将硬件状态纳入决策。这也意味着，如果前五篇系统中的某些部署场景确实面临显著的硬件状态波动（如多租户 GPU 竞争、云实例性能抖动），引入类似 Phoenix 的硬件状态感知机制可能带来显著收益。

---

## 7. 优化目标的统一建模：value − λ·cost 分析

> 核心问题：六篇论文的最优化调度目标是否可以共性建模为 value − λ·cost 模式（其中 value 可以是 accuracy 等质量指标，cost 可以是 latency 等资源消耗指标）？

### 7.1 各论文优化目标原始表述

| 论文 | 原始目标 | 数学形式 |
|------|---------|---------|
| **FlexNN** | 在内存预算约束下最小化推理延迟 | min Latency, s.t. Memory ≤ Budget |
| **Flex** | 最大化 α·(A−A_goal) + (1−α)·(T_goal−T) | O = α·A(L) − (1−α)·T(L) + const |
| **Pantheon** | 在 deadline 约束下最大化所选 DNN 变体的总 accuracy | max Σ Acc(v_j), s.t. finish_time ≤ d_j |
| **RAMSIS** | 最大化期望 accuracy，且仅当 SLO 满足时给予奖励 | R = Accuracy(a) × SLOSatisfied(s,a) |
| **Vulcan** | 最大化 utility = 精度收益 + 延迟 slack − 资源消耗 | U = γ·α_A·(A−A_m) + (1−γ)·α_L·(L_m−L) − R_cost |
| **Phoenix** | 满足帧率约束下最大化 accuracy，同时最小化热代价 | Reward = −Penalty_latency − Penalty_thermal − ΔT |

### 7.2 统一改写

六篇论文的优化目标均可改写为以下范式：

\[
\max \; \text{Value}(decision) - \lambda \cdot \text{Cost}(decision)
\]

具体改写如下。

**FlexNN** — Value = −Latency, Cost = Memory

原始形式 `min Latency s.t. Memory ≤ Budget` 经拉格朗日松弛后等价于：

\[
\max \; (-\text{Latency}) - \lambda \cdot \text{Memory}
\]

λ 的语义是内存的"影子价格"——单位内存紧张程度所折算的延迟代价。FlexNN 的 memory budget 动态性可理解为 λ 随设备可用内存变化而自适应调整。

**Flex** — 最直接符合该模式

\[
O = \alpha \cdot A(L) + (\alpha-1) \cdot T(L) = \alpha \cdot \left[A(L) - \frac{1-\alpha}{\alpha} \cdot T(L)\right]
\]

令 λ = (1−α)/α，即：

\[
\max \; \text{Accuracy} - \lambda \cdot \text{Latency}
\]

用户通过 α 显式控制 accuracy 与 latency 的边际替代率。α → 1 时 λ → 0（只看 accuracy），α → 0 时 λ → ∞（只看 latency）。

**Pantheon** — 硬约束等价于 λ → ∞

原始形式 `max Σ Acc(v_j) s.t. finish_time ≤ d_j`，引入指示函数后：

\[
\max \; \sum \text{Acc}(v_j) - \sum \lambda_j \cdot \max(0, \text{finish\_time}_j - d_j)
\]

其中每个任务的 λ_j = ∞，构成硬 deadline。若将 deadline 违反改为软惩罚（如线性或二次惩罚项），即退化为标准的软约束 value − λ·cost 形式。

**RAMSIS** — 同样硬约束转软

SLOSatisfied(s,a) ∈ {0,1} 等价于：

\[
\max \; \text{Accuracy}(a) - M \cdot (1 - \text{SLOSatisfied}(s,a))
\]

其中 M → ∞。RAMSIS 的 reward 本质是带极端 λ 的 value − λ·cost。其创新在于 λ 并非静态——MDP 的 value iteration 使得 λ 随 query inter-arrival pattern 和当前队列状态隐式变化：在 arrival lull 期间有效 λ 降低（允许选更准但更慢的模型），在 burst 期间有效 λ 升高（强制选更快模型）。

**Vulcan** — 该模式的**最完整显式示范**

\[
U = \underbrace{\gamma \cdot \alpha_A \cdot A + (1-\gamma) \cdot \alpha_L \cdot (L_m - L)}_{\text{Value}} - \underbrace{(\alpha_{gpu} \cdot R_{gpu} + \alpha_{net} \cdot R_{net})}_{\lambda \cdot \text{Cost}} + const
\]

Vulcan 的特殊之处在于：
- **Value 侧是双项**：accuracy gain + latency headroom（即不仅奖励"更准"，也奖励"更快"）
- **Cost 侧是多维**：GPU 资源消耗 + 网络带宽消耗
- **λ 向量化**：(α_gpu, α_net) 分别编码算力成本和带宽成本

是六篇中唯一将"quality − multi-resource cost"显式写在同一个目标函数中的工作。

**Phoenix** — 多维 cost + 物理约束

\[
\text{Reward} = -\underbrace{\alpha \cdot \max(0, L - L_{app})}_{\text{Latency violation cost}} - \underbrace{\text{Penalty}_{thermal}}_{\text{Throttling cost}} - \underbrace{(\Delta T_{cpu} + \beta \cdot \Delta T_{gpu})}_{\text{Thermal ramp cost}}
\]

Phoenix 声明的高层目标是"maximizing accuracy while ensuring frame rate"，因此完整形式为：

\[
\max \; \text{Accuracy} - \lambda_1 \cdot \text{LatencyViolation} - \lambda_2 \cdot \text{ThermalThrottling} - \lambda_3 \cdot \text{TemperatureRise}
\]

Phoenix 的两点独特之处：
1. **Cost 是实时测量的而非 profiled**：L_now 在每个推理周期真实测量，Penalty_thermal 依赖实际热限频事件，ΔT 来自物理温度传感器。这使得 cost 函数从静态估计变成了动态信号。
2. **λ 具有物理因果性**：λ_2 和 λ_3 不是用户调的超参数，而是由热物理定律（处理器 TDP、热容、散热系数）决定的——温度上升→降频→延迟增加这个因果链使得 thermal cost 天然以非线性的方式折算为 latency cost。

### 7.3 统一视角

六篇论文的优化目标具有**同构的数学结构**：

\[
\boxed{\max_{d \in \mathcal{D}} \; Q(d) - \sum_{k} \lambda_k \cdot C_k(d)}
\]

其中：
- **Q(d)**：决策 d 带来的质量收益（accuracy、负延迟、throughput 等）
- **C_k(d)**：第 k 维资源/约束代价（latency、memory、GPU 资源、网络带宽、热代价等）
- **λ_k**：第 k 维代价到质量的兑换率

六篇论文在这个统一框架下的差异归纳如下表：

| 维度 | FlexNN | Flex | Pantheon | RAMSIS | Vulcan | Phoenix |
|------|--------|------|----------|--------|--------|---------|
| **Value (Q) 的定义** | −Latency | Accuracy | Accuracy | Accuracy | Accuracy + Latency slack | Accuracy |
| **Cost 维度数** | 1 | 1 | 1 | 1 | 2 (GPU + Net) | 3 (Latency + Thermal + ΔT) |
| **λ 的性质** | 硬件预算决定 | 用户偏好参数 | 硬约束 (λ=∞) | 硬约束 (λ=∞) | 用户偏好参数 | 物理约束 + 超参数 |
| **λ 是否动态** | 随内存预算变 | 固定 | 固定 | 隐式（MDP value） | 固定 | 物理驱动 |
| **Cost 获取方式** | Offline profiling | Offline profiling | Offline profiling | Offline profiling | Offline profiling | **实时测量** |
| **约束硬度** | 硬约束 | 软 trade-off | 硬约束 | 硬约束 | 软 trade-off | 软 trade-off |

### 7.4 深层共性与本质差异

**共性**：六篇论文本质上都在求解同一个 **multi-objective optimization** 问题——在推理质量（accuracy/throughput）和资源消耗（latency/memory/thermal/bandwidth）之间寻找 Pareto 最优点。`value − λ·cost` 是该多目标问题的 **scalarization**，λ 编码了"一个单位 cost 换取多少单位 value"的边际替代率。

**本质差异不在于"是否可以用 value − λ·cost 描述"，而在于三个层面**：

1. **Value/Cost 的语义空间扩展**。六篇论文可看作该范式在不同物理维度上的实例化：
   - FlexNN 开创了 **memory** 作为 cost 维度
   - Flex/Pantheon/RAMSIS 聚焦 **latency** 作为 cost 维度，在如何让 λ 随 workload 自适应上各有创新
   - Vulcan 扩展到 **pipeline-level multi-resource cost**（GPU + 网络）
   - Phoenix 引入了 **thermal** 作为全新 cost 维度，将热物理约束纳入调度优化

2. **λ 的动态化程度**。从静态 λ（Flex、Vulcan）到随输入/负载动态变化（FlexNN 的内存预算、RAMSIS 的 arrival pattern），再到由物理定律实时驱动（Phoenix 的 thermal dynamics），λ 的自适应能力逐步增强。这一演进反映了调度系统从"固定环境的静态优化"向"动态环境的在线决策"的迁移趋势。

3. **Cost 函数的 fidelity**。前五篇使用 offline profiling 的固定 cost 估计值，Phoenix 使用实时物理测量。这一差异源于 domain requirements：当 cost 是稳定的（如云端 GPU 的固定算力），profiling 足够；当 cost 本身是状态的函数（如移动设备的热限频使同一模型延迟可波动 2×+），实时测量是必需的。这暗示了一个更一般的洞察——**λ 的动态性和 cost 的 fidelity 应该匹配环境的 non-stationarity 程度**。

### 7.5 启示

将六篇论文统一到 value − λ·cost 框架下，暴露出当前研究的两条未充分探索的路径：

1. **多维 cost 的联合优化**：仅 Vulcan（GPU + 网络）和 Phoenix（延迟 + 热 + 温升）处理了多维 cost，且 Phoenix 是唯一将物理状态 cost 与性能 cost 联合优化的。将 FlexNN 的 memory cost、Pantheon 的 preemption overhead、Phoenix 的 thermal cost 整合进统一的 multi-cost 框架是一个开放方向。

2. **λ 的在线学习**：当前所有论文的 λ 要么是预先指定的（Flex、Vulcan），要么是硬约束隐式给定的（Pantheon、RAMSIS），要么是物理定律决定的（Phoenix）。一个自然的推广是让 λ 通过在线学习自适应调整——例如用 contextual bandit 在运行时学习用户对 accuracy/latency 的真实偏好，或用 Bayesian optimization 动态估计当前硬件状态下的有效 cost 函数。

---

## 8. Phoenix 的缺点与局限性分析

Phoenix 是六篇论文中最接近 context-aware scheduling 的工作，但仍然存在若干结构性和概念性局限。以下从六个维度展开分析。

### 8.1 Context 感知范围过窄：仅覆盖热维度

Phoenix 的 RL state space 包含 CPU/GPU 频率、利用率、温度和 slowdown ratio，但这些都是**热相关的指标**。移动设备的 Runtime Context 远不止热：

| Context 维度 | Phoenix 是否感知 | 现实影响 |
|-------------|-----------------|---------|
| 热状态 (温度/频率) | ✅ 核心设计 | DVFS 降频导致延迟波动 2×+ |
| **CPU 竞争 (后台 App)** | ❌ 不感知 | 后台 Music/Nav/Meeting 抢占 CPU，preprocessing 变慢 |
| **内存压力** | ❌ 不感知 | 低内存时 GC 频繁、模型换出、分配变慢 |
| **IO 竞争** | ❌ 不感知 | 存储 I/O 影响模型加载和图片读取 |
| **网络状态** | ❌ 不感知 | 云端协同推理时带宽波动 |
| **电量水平** | ❌ 不感知 | 低电量触发系统级节能策略 |

Phoenix 仅处理了 Context 空间的一个子集（热），且其机制是热特异性的（thermal-specific）：通过任务分配延缓升温 + early exit 应对降频。这套机制无法泛化到非热 Context（如后台 App CPU 竞争导致的延迟增加，不伴随温度变化）。

**与本研究的关系**：我们的 Exp 2 数据表明，Mid (Meeting) 状态下的延迟恶化并非仅有热因素——System CPU 从 13.3% 飙升至 33.7%，prepMs 从 116ms 增至 160ms（预处理变慢与温度无关，r=0.015）。Phoenix 面对 Meeting 场景中的 CPU 竞争将完全"失明"——它看到温度上升、触发 early exit，但看不到 CPU 被后台抢占才是延迟增加的真正原因。

### 8.2 离线训练成本高，设备依赖性极强

Phoenix 需要两阶段离线训练，且均依赖 **hardware-in-the-loop**：

1. **NAS**：为每个处理器（CPU/GPU/DSP）的每种减速模式（slowdown pattern）定制 early exit 架构。需要实际设置手机频率来模拟各种限频条件，在真实设备上测量每个候选架构的执行时间。
2. **RL (DQN)**：在真实设备上运行数千个 episode，每个 episode 中实际执行推理并测量 `Lnow`。

换一部手机（不同 SoC/散热设计）需要全部重做。这使 Phoenix 更像一个设备定制的离线优化方案，而非通用的运行时调度框架。

### 8.3 无法支撑 AI Flow

> "AI Flow" 指具有**阶段依赖、条件分支、数据传递**的 AI 推理流水线。典型实例如：
> - InFi gating → YOLO 推理（轻量判断 → 条件执行重模型）
> - Detect → Classify → Track（检测 → 分类 → 追踪）
> - Agent loop: Observe → Plan → Act → Observe → ...
> - RAG: Retrieve → Rerank → Generate

#### 架构假设 vs AI Flow 的需求

| 维度 | Phoenix 的假设 | AI Flow 的需求 | 是否兼容 |
|------|---------------|---------------|---------|
| **任务关系** | 多个独立 DNN **并行**运行 | 阶段间有**顺序依赖**，后阶段等前阶段输出 | ❌ 根本矛盾 |
| **任务集** | **固定**的 DNN 集合 | **动态**的任务集（gating 可能跳过重模型，pipeline 可能分支） | ❌ |
| **优化粒度** | 每个 DNN 独立满足帧率约束 | **端到端**延迟/吞吐优化 | ❌ |
| **决策类型** | 选处理器 + 选 exit | 选模型 + 选是否执行 + 选执行路径 | ❌ 不匹配 |
| **数据流** | 各 DNN 独立输入（视频帧并行喂入） | 前阶段**输出**是后阶段**输入**（bbox → crop → classify） | ❌ |
| **条件执行** | 无 — 所有 DNN 始终运行 | 有条件跳过（如 InFi: 评分 < τ → 跳过 YOLO） | ❌ |

#### 逐层失效分析

##### Layer 1: 任务分配（RL → Rule Table）

Phoenix 的 RL agent 做的是：给定 N 个独立的 DNN 任务和 M 个处理器，输出一个分配矩阵 `assign(dnn_i, processor_j)`。

```
Phoenix action space: {CPU, GPU, DSP} × {exit_1, exit_2, ..., exit_k}
                              ↑                      ↑
                         每个 DNN 独立选            每个 DNN 独立选
```

AI Flow 需要的决策完全不同：

```
AI Flow action space:
  1. 是否执行阶段 2？（取决于阶段 1 的输出）          ← Phoenix 没有这个维度
  2. 如果执行，用哪个模型？（Nano / Medium / Large）   ← Phoenix 没有跨模型选择
  3. 分配到哪个处理器？                              ← Phoenix 能做
  4. 用哪个 exit？                                   ← Phoenix 能做
```

**关键失效**：Phoenix 无法表达「不执行」。它的 action space 假设所有 DNN 始终运行，只是选择在哪儿运行、用哪个 exit。在 InFi 场景中，这意味着 Phoenix **必须始终执行 YOLO**，无法做出「跳过重模型」的决策。

##### Layer 2: 调度目标

Phoenix 的 reward 函数：

```
R = -α·max(0, L_i - L_app) - Penalty_thermal - ΔT
     ↑                      ↑                   ↑
  每个 DNN 独立            热限频事件          温升速率
  满足帧率约束
```

问题在于 `L_i` 是单个 DNN 的延迟约束。AI Flow 需要的是**端到端延迟** `L_e2e = L_stage1 + L_stage2 + ...`，且端到端约束可能比各 stage 约束之和更紧（pipeline 并行时）或更松（stage 间有 slack 时）。

**关键失效**：Phoenix 无法优化端到端延迟。它会把各 stage 独立优化，可能导致：
- Stage 1 选了高精度慢模型 → stage 2 时间不够 → 端到端超时
- 或者 Stage 1 选了低精度快模型 → stage 2 有充足时间但精度受限于 stage 1 的输出质量

##### Layer 3: Multi-Exit 机制

Phoenix 的 early exit 是**模型内部**的（同一个 DNN 的不同深度出口）：

```
Input → [Layer1] → [Layer2] → [Exit1] → [Layer3] → [Exit2] → ... → [Final Exit]
                ↑                      ↑
           浅层出口（快，低精度）      深层出口（慢，高精度）
```

InFi-style AI Flow 需要的是**跨模型**的条件执行：

```
Input → [InFi Gate] ──┬── score ≥ τ ──→ [YOLO] → Detection Result
                       │
                       └── score < τ  ──→ Skip (No Detection)
```

**关键失效**：Phoenix 的 early exit 只能在同一模型内降级（如从 YOLOv8l 的第 8 层出口换到第 5 层出口），但无法实现「完全跳过 YOLO，不做检测」。这两者的语义完全不同：

| | Phoenix Early Exit | InFi-style Gating |
|---|---|---|
| 机制 | 模型内部 exit 选择 | 模型间条件跳过 |
| 决策依据 | 热状态 → 选浅出口 | 输入特征 → 决定是否执行 |
| 精度影响 | 同一模型浅出口精度略低 | 完全跳过 = 零精度/零成本 |
| Cost 节省 | ~20-50% | ~100%（对跳过的图片） |

##### Layer 4: 依赖性处理

Phoenix 假设所有 DNN 可以独立并行执行，各自接收视频帧输入。它不做任何 pipeline 调度：

```
Phoenix 模型:
  Frame(t) → DNN_A (姿态估计)  ─→ 输出 A
  Frame(t) → DNN_B (面部捕捉)  ─→ 输出 B
  Frame(t) → DNN_C (背景分割)  ─→ 输出 C
  （三个 DNN 无依赖，可并行）

AI Flow 模型:
  Frame(t) → [InFi Gate] → D(x,τ)=1 → [YOLO Detect] → bbox → [Classifier] → label
                ↑                          ↑                        ↑
            必须最先执行              依赖 Gate 输出            依赖 Detect 输出
```

**关键失效**：Phoenix 无法表达和调度有依赖关系的流水线。它不知道 Stage 2 必须等 Stage 1 完成，也不知道如果 Stage 1 决定跳过，Stage 2 根本不需要执行。

#### 本质矛盾

Phoenix 和 AI Flow 的矛盾不是工程层面的（可以通过修改代码解决），而是**架构哲学层面的**：

```
Phoenix 的世界观:
  世界 = {固定的 DNN 集合} × {固定的处理器集合}
  问题 = 如何分配 DNN 到处理器 + 选哪个 exit
  目标 = 每个 DNN 满足帧率 + 不触发热限频
  假设 = DNN 之间独立、始终运行、输入同质

AI Flow 的世界观:
  世界 = {有依赖关系的计算阶段} × {条件分支} × {动态任务集}
  问题 = 是否执行每个阶段 × 用哪个模型 × 分配到哪个处理器
  目标 = 端到端延迟/能耗/质量最优
  假设 = 阶段间有依赖、任务可能被跳过、输入决定执行路径
```

Phoenix 的核心机制（RL 任务分配 + multi-exit 降级）在 AI Flow 场景下：
- **RL 任务分配** → 可以复用（分配 stage 到处理器），但需要改造 action space
- **Multi-exit** → 不能直接复用，需要改为跨模型选择 + 条件跳过
- **热感知** → 可以复用（感知硬件状态），但需要扩展 context 维度
- **调度目标** → 需要从 per-DNN 帧率改为端到端延迟

#### InFi Pipeline 实例推演

假设强行把 InFi → YOLO 的 pipeline 塞进 Phoenix：

```
Phoenix 看到的:
  DNN_1: InFi Gate (轻量，~1ms)
  DNN_2: YOLO (重量，~200ms)

Phoenix 会做的:
  - 把 InFi 分配到 CPU，YOLO 分配到 GPU/NPU
  - 当温度升高时，给 YOLO 选更浅的 early exit
  - 但：它永远无法做出"InFi 评分低 → 不跑 YOLO"的决策
  - 因为：Phoenix 的 action space 里没有"不执行"这个选项
```

这意味着 Phoenix 在 InFi 场景下**丧失了 InFi 最核心的价值**——过滤掉不需要重模型推理的图片。无论温度多高、Context 多恶劣，Phoenix 都会跑 YOLO（可能用浅出口），而不是聪明地跳过。

#### 更根本的局限

回到一个更深层的问题：**Phoenix 为什么不做条件跳过？**

因为 Phoenix 的场景（VTuber 面部捕捉 + 姿态估计 + 背景分割）中，所有 DNN **必须每帧都跑**才能输出完整结果。它不需要条件跳过，所以它的架构里就没有这个维度。

这恰恰暴露了 Phoenix 设计中的一个隐含假设：**所有模型都是必需的**。这个假设在视频多任务场景中成立，但在 AI Flow（有 gating、有分支、有动态模型选择）中不成立。

而你的 InFi case study 恰恰是**挑战这个假设**的——有些推理是可以跳过的，关键是「什么时候跳过是对的」取决于 Context。

#### 结论

**Phoenix 不能支撑 AI Flow，不是工程问题，是架构基因决定的。**

| 问题 | 原因 |
|------|------|
| 无法条件跳过 | action space 没有"不执行"选项 |
| 无法处理依赖 | 假设所有 DNN 独立并行 |
| 无法端到端优化 | 目标函数是 per-DNN 帧率 |
| 无法跨模型选择 | 只有 exit 选择，没有模型选择 |
| 无法动态任务集 | 假设固定 DNN 集合始终运行 |

这恰恰是 **Phoenix 留下的研究空白**——它证明了感知硬件状态有价值，但它的调度范式（固定任务集 × 并行独立 × 无条件分支）天然排斥 AI Flow。一个能够同时感知 Runtime Context **和** Pipeline 结构的调度器，是 Phoenix 和当前 SOTA 都没有覆盖的方向。
