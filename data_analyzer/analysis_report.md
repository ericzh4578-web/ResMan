##
文件名：exp2_infi_coco_Idle_full_1780639447663.csv
描述：YOLOv8l-bsz4 COCO 推理基准测试，2,996张图片，fused预处理，Idle状态运行 (gating OFF)

## 推理时间
- 总时间: 750,085 ms (≈750秒 ≈12.5分钟)
- 平均 totalMs: 250.36 ms (中位数 240.00 ms)
- 平均 latencyMs: 132.67 ms (推理延迟，范围 110.75–175.50)
- 平均 prepMs: 117.69 ms (预处理时间，范围 81.00–147.25)
- 吞吐量: 3.99 张/秒
- totalMs = latencyMs + prepMs 校验通过

## 温度
- 起始温度: 33.00°C
- 最终温度: 40.00°C (+7.00°C，单调上升)
- 平均温度: 37.86°C (中位数 39.00°C)
- 温度与 totalMs 相关系数: 0.686 (强正相关)
- 温度与 latencyMs 相关系数: 0.715 (热 throttling 影响推理)
- 温度与 prepMs 相关系数: 0.015 (预处理不受温度影响)
- 33°C时 avg totalMs=227ms → 40°C时 avg totalMs=277ms (慢了22%)

## 状态
- stateName: Idle (100%)
- infiCorrect: 正确 2,386 (79.6%), 错误 610 (20.4%)
- infiType: TP=2386, FP=610, FN=0, TN=0
- deadlineMiss: 未超时 1,844 (61.5%), 超时 1,152 (38.5%)
- yoloModel: yolov8l_bsz4.ms (100%)
- preprocessMode: fused (100%)

## 准确率
- Precision: 79.64%
- Recall: 100.00% (无漏检)
- F1-Score: 88.67%
- Accuracy: 79.64%

## CPU
- 起始: 9.15%, 最终: 4.23%, 平均: 4.62%, 峰值: 14.92%

## 关键发现
1. 温度是核心影响因素：温度↑ → latencyMs↑ (热 throttling)，prepMs 不受影响
2. 超时率 38.5%，与高温区间 (39-40°C) 高度重合
3. Recall 100% 但不漏检，Precision 79.6% (误检率 20.4%)，模型倾向于多报

---

##
文件名：exp2_infi_coco_Light_full_1780743288773.csv
描述：YOLOv8l-bsz4 COCO 推理基准测试，2,996张图片，fused预处理，Light (Music + Nav) 状态运行 (gating OFF)

## 推理时间
- 总时间: 677,450 ms (≈677秒 ≈11.3分钟)
- 平均 totalMs: 226.1 ms (中位数 225.5 ms)
- 平均 latencyMs: 110.1 ms (推理延迟，范围 105.8–193.2)
- 平均 prepMs: 116.0 ms (预处理时间，范围 84.2–151.8)
- 吞吐量: 4.42 张/秒
- totalMs = latencyMs + prepMs 校验通过

## 温度 (batteryTempC)
- 起始温度: 33°C
- 最终温度: 38°C (+5°C)
- 平均温度: 36.3°C (中位数 37°C)
- 温度与 totalMs 相关系数: 0.254 (弱正相关)
- 温度与 latencyMs 相关系数: 0.152 (弱相关)
- 温度与 prepMs 相关系数: 0.191 (弱相关)
- Thermal Level: 2 (23.1%), 3 (42.1%), 4 (34.8%)
- 33°C时 avg totalMs=219ms → 38°C时 avg totalMs=231ms (慢了5.5%)

## 状态
- stateName: Light (Music + Nav) (100%)
- infiCorrect: 正确 2,386 (79.6%), 错误 610 (20.4%)
- infiType: TP=2386, FP=610, FN=0, TN=0
- tau: 0.500 (100%, 恒定)
- yoloModel: yolov8l_bsz4.ms (100%)
- preprocessMode: fused (100%)

## 准确率
- Precision: 79.64%
- Recall: 100.00% (无漏检)
- F1-Score: 88.67%
- Accuracy: 79.64%

## CPU
- Process CPU: 平均 5.6%, 范围 3.3%–25.0%
- System CPU: 平均 13.3%, 范围 8.5%–41.5%
- Total CPU: 平均 18.9%, 范围 13.7%–46.2%

## 内存
- PSS (进程): 平均 350 MB (范围 287–1004 MB)
- 系统可用: 平均 2,673 MB / 总计 11,499 MB (11.2 GB)
- 系统已用: 平均 8,827 MB

## 电池/功耗
- 电量 (SoC): 72% (恒定)
- 平均功耗: +1,610 mW (放电)
- 放电占比: 96.4%, 充电占比: 3.6%

## 关键发现
1. Light 负载下推理性能良好：平均 226ms，吞吐 4.42 张/秒
2. 温度控制较好：最高仅 38°C，Thermal Level 最高 4 级
3. 温度对推理时间影响弱 (r=0.25)，未触发严重 thermal throttling
4. 准确率与 Idle 基准一致：Precision 79.6%, Recall 100%

---

##
文件名：exp2_infi_coco_Mid_full_1780816112706.csv
描述：YOLOv8l-bsz4 COCO 推理基准测试，2,996张图片，fused预处理，Mid (Meeting) 状态运行 (gating OFF)

## 推理时间
- 总时间: 1,144,522 ms (≈1,145秒 ≈19.1分钟)
- 平均 totalMs: 382.0 ms (中位数 394.2 ms)
- 平均 latencyMs: 221.7 ms (推理延迟，范围 114.8–249.8)
- 平均 prepMs: 160.3 ms (预处理时间，范围 72.8–312.0)
- 吞吐量: 2.62 张/秒
- totalMs = latencyMs + prepMs 校验通过

## 温度 (batteryTempC)
- 起始温度: 34°C
- 最终温度: 46°C (+12°C，严重升温)
- 平均温度: 41.5°C (中位数 42°C)
- 温度与 totalMs 相关系数: 0.833 (极强正相关)
- 温度与 latencyMs 相关系数: 0.602 (强正相关)
- 温度与 prepMs 相关系数: 0.775 (强正相关)
- Thermal Level: 2 (2.7%), 3 (4.9%), 4 (18.2%), 5 (15.5%), 6 (47.5%), 7 (11.2%)
- ThermalLevel 与 totalMs 相关系数: 0.905 (极强正相关)
- 34°C时 avg totalMs=219ms → 46°C时 avg totalMs=457ms (慢了109%)

## 状态
- stateName: Mid (Meeting) (100%)
- infiCorrect: 正确 2,386 (79.6%), 错误 610 (20.4%)
- infiType: TP=2386, FP=610, FN=0, TN=0
- tau: 0.500 (100%, 恒定)
- yoloModel: yolov8l_bsz4.ms (100%)
- preprocessMode: fused (100%)

## 准确率
- Precision: 79.64%
- Recall: 100.00% (无漏检)
- F1-Score: 88.67%
- Accuracy: 79.64%

## CPU
- Process CPU: 平均 4.9%, 范围 2.6%–9.9%
- System CPU: 平均 33.7%, 范围 25.4%–73.4%
- Total CPU: 平均 38.7%, 范围 28.9%–78.0%

## 内存
- PSS (进程): 平均 358 MB (范围 287–827 MB)
- 系统可用: 平均 2,245 MB / 总计 11,499 MB (11.2 GB)
- 系统已用: 平均 9,254 MB

## 电池/功耗
- 电量 (SoC): 68% (范围 67%–69%)
- 平均功耗: -1,003 mW (充电中)
- 放电占比: 0.4%, 充电占比: 99.6%

## 关键发现
1. Mid (Meeting) 负载下推理性能严重下降：平均 382ms，比 Light 慢 69%，比 Idle 慢 53%
2. 严重 thermal throttling：温度飙至 46°C，Thermal Level 达 6-7 级 (47.5% 在 Level 6)
3. ThermalLevel 与 totalMs 相关系数 0.905 — 温度几乎是推理时间的决定性因素
4. System CPU 高达 33.7% (Light 仅 13.3%)，Meeting 后台任务抢占大量系统资源
5. 设备处于充电状态但仍无法抑制升温，说明散热能力已达极限
6. 准确率不受影响，三组实验完全一致

---

## Retroactive τ Scanning Results (analysis_tau_scan.py)

基于现有 CSV 中的 `infiProbPerson` 字段进行回溯式 τ 扫描。
原理：D(x, τ) = 1 if infiProbPerson >= τ, else 0（所有图片均已全量执行，有完整 totalMs）。

Idle 数据集 infiProbPerson 仅为 0 或 1（二值），无法进行 τ 扫描。Light 和 Mid 为连续值 [0.50, 1.0]。

### Efficiency(τ) = Kept Images / Total Cost (img/ms)

| τ | Light Eff | Mid Eff | Light Gain% | Mid Gain% |
|---|-----------|---------|-------------|-----------|
| 0.50 | 0.004422 | 0.002618 | +0.00% | +0.00% |
| 0.60 | 0.004428 | 0.002684 | +0.12% | +2.53% |
| 0.70 | 0.004433 | 0.002715 | +0.24% | +3.71% |
| 0.80 | 0.004435 | 0.002740 | +0.28% | +4.66% |
| 0.90 | 0.004473 | 0.002786 | +1.15% | +6.44% |
| 0.95 | 0.004476 | 0.002834 | +1.20% | +8.25% |
| 0.97 | 0.004480 | 0.002863 | +1.31% | +9.39% |
| 0.98 | 0.004481 | 0.002890 | +1.31% | +10.41% |
| 0.99 | 0.004482 | 0.002939 | +1.35% | +12.29% |

### τ* (精细搜索 0.90-0.995, step=0.001)

| Context | τ* | Eff(τ*) | Kept | Filter% | Eff(0.5) | Δ Gain |
|---------|-----|---------|------|---------|----------|--------|
| Light | 0.989 | 0.004483 | 1306 | 56.4% | 0.004422 | +1.37% |
| Mid | 0.994 | 0.002970 | 1202 | 59.9% | 0.002618 | +13.47% |

### 关键结论

1. **τ* 漂移确认**：Light: 0.989 vs Mid: 0.994 (Δτ = +0.005)
   - Mid 负载下需要更激进的过滤（更高阈值、过滤更多图片）

2. **固定 τ 的代价是 context-dependent**（更重要）：
   - Light 用 τ=0.5 仅损失 1.4% → 固定阈值在轻负载下近似最优
   - Mid 用 τ=0.5 损失 13.5% → 重负载下固定阈值的代价急剧放大
   - 差距约 10x：**Context 越差，正确选择 τ 越重要**

3. Efficiency 曲线呈单调递增：Efficiency(τ) 随 τ 单调上升
   - infiProbPerson 分布偏斜（中位数 0.97），高分图片数量少但单位成本效率高
   - 在 0.50-0.85 区间效率几乎平坦，0.90+ 开始显著上升

4. **Light vs Mid 绝对效率差距始终 ~38-41%**，且不随 τ 减小 — Context 差异是结构性的
