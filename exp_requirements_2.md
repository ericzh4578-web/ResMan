# 实验总要求

1. ✅ 新开一个页面 — `ExperimentPage2.ets` (6-Tab: Exp1 Cost / Exp2 InFi / Exp3 Predict / Exp4 Scheduler / Exp5 Dynamic / Exp6 Budget)
2. ✅ 参考当前归纳的实现 `CLAUDE.md`
3. ✅ 记录目前的实验情况到该文件中
4. ✅ 禁用一切 git 操作
5. ✅ 实验路径参考但不完全遵从，保持了论文逻辑

---

# 一、代码结构

```
entry/src/main/
├── cpp/
│   ├── SysfsReader/
│   │   ├── SysfsReader.h          # CPU/GPU 频率读取
│   │   └── SysfsReader.cpp
│   ├── napi_init.cpp              # NAPI 注册
│   └── types/libentry/Index.d.ts  # TypeScript 类型声明
│
├── ets/
│   ├── experiments2/
│   │   ├── ExperimentTypes.ts           # 共享类型 + InFi/COCO 常量
│   │   ├── SystemStateManager.ts        # 混合模式: 手动App + ResourceSimulator
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
│   │   ├── ExperimentPage.ets           # Experiment Dashboard 1 (3-Tab)
│   │   ├── ExperimentPage2.ets          # Experiment Dashboard 2 (6-Tab, 2149行)
│   │   └── Index.ets                    # 导航主页
│   │
│   └── utils/
│       ├── CsvLogger.ts
│       └── ExperimentRunner.ts
│
└── resources/rawfile/
    └── data_config/
        ├── onnx_person_val2017_100.json
        ├── onnx_person_val2017_200.json
        ├── onnx_person_val2017_500.json
        ├── onnx_person_val2017_1000.json
        ├── onnx_person_val2017_2000.json
        └── onnx_person_val2017_sorted.json
```

---

# 二、实验设计

整体逻辑: Motivation → Observation (×4) → Method (Oracle + Ablation) → System

| # | 实验 | Phase | 核心目标 |
|---|------|-------|---------|
| 1 | Cost Variability under Runtime Interference | Observation-1 | 同一模型 Cost 随系统状态剧烈变化 |
| 2 | InFi Static Baseline | Observation-2 | 真实 COCO 图片上的 YOLO 基线延迟 |
| 3 | Gain Predictability | Method | 图像特征 → 增益预测 |
| 4 | Gain-aware Scheduler vs Baselines | System | 调度策略对比 |
| 5 | Dynamic System Interference | System | 场景切换下的调度表现 |
| 6 | Budget-Constrained Video | System | 能耗预算约束下的模型分配 |

---

# 三、各实验实现详情

## Exp 1: Cost Variability under Runtime Interference

**目的**: 量化同一 YOLO 模型在 5 种系统状态下的推理 Cost 变化。

**系统状态**: Idle / Light (Music+Nav) / Mid (Meeting) / Heavy (All) / Extreme (All+Load)

**实现**:
- 用户手动设置 App 场景 + 代码 ResourceSimulator 叠加负载
- 每轮: 冷却等待 → 提示用户 → 稳定 30s → 连续推理 N 分钟
- 记录: `latencyMs`, `energyMw`, `cpuUsage%`, `cpuFreqs`, `fps`, `temp`
- 支持逐状态勾选、冷却温度阈值可调

**状态**: ✅ 可运行

---

## Exp 2: InFi Static Baseline

**目的**: 使用预计算 InFi 结果 + 真实 COCO 图片，建立 YOLO 推理基线。

**数据源**:
- InFi 结果: `rawfile/data_config/` JSON (预计算, 无需跑 InFi 模型)
- COCO 图片: 设备沙箱 `COCO_val/` (5000 张 JPEG)

**三阶段流程**:
1. `InfiResultLoader.loadFromRawfile()` → 解析 JSON gating 决策
2. `loadYoloModel()` → 加载 yolov8{n,s,m,l}_bsz4.ms
3. bsz4 批推理循环

**bsz4 批推理**:
```
每 4 张图为一个 batch:
  Image[0..3] → decodeAndPreprocessFused() → CHW[3,640,640]
  → stack 为 4×3×640×640 NCHW → model.predict() 一次
  → batch_latency / 4 = per_image_latency
```

**融合预处理** (`CocoImagePreprocessor.decodeAndPreprocessFused`):
```
RGBA bytes → 一趟循环 → CHW[3,640,640]
  每像素: 查 RGBA 源坐标 → /255 → 写入 CHW 平面
  pad 区域: fill(114/255)
5 步计时: open / jpeg / read / params / loop
```

**UI 指标**:
| 指标 | 含义 |
|------|------|
| Prep | 单张图融合预处理耗时 (decode+letterbox+CHW) |
| Infer | 单 batch predict 耗时 |
| Pass | InFi pred_person=1 的图片数 |
| Skip | InFi pred_person=0 的图片数 |
| Miss | per-image latency > deadline 的图片数 |
| Gate toggle | ON = 跳过 pred_person=0 的图片 (不分批、不解码、不推理) |

**Config 选择器**: 短标签 (`200 samples`, `500 samples` 等), 决定数据集大小

**CSV 输出**: `exp2_infi_coco_baseline_{timestamp}.csv` (14 列)

**运行前需要**:
- COCO 图片推送到设备: `hdc file send .../val2017/*.jpg data/storage/el2/base/files/COCO_val/`
- 设备冷却、关后台、连充电器

**状态**: ✅ 已适配 (gate toggle + 融合预处理 + 分步计时)

---

## Exp 3: Gain Predictability

**目的**: 图像特征 → 增益预测 (Nano vs Large 模型质量差)。

**实现**: 加载 Nano + Large 模型, 合成图像推理, ImageFeatureExtractor 提取特征, GainPredictor 预测增益, CSV 输出。

**状态**: ✅ 已适配 NCHW 输入

---

## Exp 4: Gain-aware Scheduler vs Baselines

**目的**: 5 种调度策略对比 (Always-n / Always-l / Confidence / Difficulty / Gain+State)。

**实现**: 指定系统状态下, 每张图跑 Nano → 决策 → 可能跑更大模型 → 对比质量/能耗/延迟。

**状态**: ✅ 已适配 NCHW 输入

---

## Exp 5: Dynamic System Interference

**目的**: 场景切换 (Idle→Music→Idle 等) 下调度策略的动态表现。

**实现**: 按 Scenario 定义的状态序列自动切换, 每种策略跑完整个场景。

**状态**: ✅ 已适配 NCHW 输入

---

## Exp 6: Budget-Constrained Video

**目的**: 固定能耗预算下, 不同分配策略的质量/帧数对比。

**实现**: Uniform / Random / Confidence / Gain-based 四种策略, 超过预算则强制降级为 Nano。

**状态**: ✅ 已适配 NCHW 输入

---

# 四、构建与调试

## 构建命令

```bash
cd C:/Users/20732/Desktop/ResMan && node "D:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js" --mode module -p module=entry@default -p product=default -p requiredDeviceType=phone assembleHap --analyze=normal --parallel --incremental --daemon
```

## 常见 ArkTS 严格模式约束

| 规则 | 说明 |
|------|------|
| `arkts-no-untyped-obj-literals` | 对象字面量必须有 interface/class |
| `arkts-no-obj-literals-as-types` | 类型声明不能内联对象字面量 |
| `arkts-no-in` | 不支持 `in` 运算符 |
| `arkts-no-any` | 禁止 `any`/`unknown` |

## 关键 API 适配

| 发现 | 说明 |
|------|------|
| `model.predict(inputs)` → `Promise<MSTensor[]>` | outputs 从返回值获取 |
| `@State` getter 在 async 中失效 | 在函数入口立即取值 `const x = arr[this.idx]` |
| NNRT 401 错误 | 添加 CPU 后端回退 |
| `getContext()` / `getThermalLevel()` deprecated | 不影响功能 |
| YOLO .ms 模型输入格式 | NCHW (batch×channel×height×width), float32 [0,1] |
| bsz4 模型固定 batch | 必须送入 4×3×640×640, 不能单独送 1×3×640×640 |
| JSON 解析无 TextDecoder | 改用逐字节 `String.fromCharCode()` |

## 调试记录

| 日期 | 问题 | 修复 |
|------|------|------|
| 06-01 | 首次构建 6 ERROR (arkts 严格模式) | 类型声明 + interface 规范化 |
| 06-02 | Status 卡在 "Initializing..." | 模型加载加 try-catch + 状态更新 |
| 06-02 | `selectedE1ModelName` getter 返回 undefined | 改直接取值 |
| 06-02 | 模型加载 401 (NNRT 失败) | 添加 CPU 后端回退 |
| 06-02 | Status 卡在 "Loading..." → getBatchSize 崩 | 变量名修正 |
| 06-04 | `TextDecoder` 不存在 | 逐字节拼字符串 |
| 06-04 | `UIAbilityContext` 不兼容 `Record<string,Object>` | 改构造函数类型 |
| 06-04 | Config 名太长 (Select 显示不全) | 新增 `INFI_CONFIG_LABELS` 短标签 |
| 06-04 | bs=1 送入 bsz4 模型 (shape 不匹配) | 4 张图 stack 为 NCHW batch |
| 06-04 | PP 预处理 ~900ms (3 轮全量数组循环) | `decodeAndPreprocessFused()` 融合为 1 轮 |
| 06-04 | Pad fill 600+ 次 fill() 调用 | 改回全平面 3 次 fill + 覆盖 |
| 06-04 | Inner loop 冗余计算 | 缓存 plane 偏移、预计算行起始、`* norm` 替代 `/ 255` |
| 06-04 | InFi skip 图片仍被推理 | 新增 Gate toggle + 分批前过滤 |
| 06-04 | `git checkout -- .` 误回退 Index.ets / Index.d.ts | 手动恢复路由 + NAPI 类型声明 |
