/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import libentry from 'libentry.so';
import { hidebug, hilog } from '@kit.PerformanceAnalysisKit';
import { thermal, batteryInfo } from '@kit.BasicServicesKit';
import { mindSporeLite } from '@kit.MindSporeLiteKit';
import { common } from '@kit.AbilityKit';
import { TitleComponent } from '../view/TitleComponent';

const TAG = 'TestDashboardPage';
const POLL_INTERVAL_MS = 1000;

// ── Model lists ──
const INFI_MODELS: string[] = ['infi_coco_full_bsz1.ms'];
const YOLO_MODELS: string[] = [
  'yolov8n_bsz4.ms',
  'yolov8s_bsz4.ms',
  'yolov8m_bsz4.ms',
  'yolov8l_bsz4.ms',
  'yolov8x_bsz4.ms',
];

// ── Simulator level labels ──
const CPU_LEVELS: string[] = ['0%', '25%', '50%', '75%', '100%'];
const MEM_LEVELS: string[] = ['10%', '15%', '20%', '25%'];
const IO_LEVELS: string[] = ['Weak', 'Medium', 'Strong'];

// ── Typed options for Select ──
interface SelectOption {
  value: string;
}

function toSelectOptions(arr: string[]): SelectOption[] {
  return arr.map((v: string): SelectOption => ({ value: v }));
}

@Component
export struct TestDashboardPage {
  @Consume('pageInfos') pageInfos: NavPathStack;

  // ── Monitor state ──
  @State cpuUsage: number = 0;
  @State systemCpuUsage: number = 0;
  @State pssMb: string = '-';
  @State sysMemInfo: string = '-';
  @State thermalLevel: number = 0;
  @State batterySOC: number = 0;
  @State batteryTemp: number = 0;

  // ── Simulator state ──
  @State cpuLevel: number = 0;
  @State cpuActive: boolean = false;
  @State memLevel: number = 0;
  @State memActive: boolean = false;
  @State ioLevel: number = 0;
  @State ioActive: boolean = false;

  // ── Model state ──
  @State selectedInfi: string = INFI_MODELS[0];
  @State selectedYolo: string = YOLO_MODELS[3];
  @State modelStatus: string = 'Idle';
  @State modelResult: string = '';

  // ── Inference benchmark state ──
  @State inferCount: number = 10;
  @State inferBatchSize: number = 4;
  @State inferRunning: boolean = false;
  @State inferStatus: string = 'Idle';
  @State inferResult: string = '';

  private pollTimer: number = -1;
  private infiOptions: SelectOption[] = toSelectOptions(INFI_MODELS);
  private yoloOptions: SelectOption[] = toSelectOptions(YOLO_MODELS);

  private get infiIndex(): number {
    const i = INFI_MODELS.indexOf(this.selectedInfi);
    return i >= 0 ? i : 0;
  }
  private get yoloIndex(): number {
    const i = YOLO_MODELS.indexOf(this.selectedYolo);
    return i >= 0 ? i : 0;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────────────

  aboutToAppear(): void {
    this.pollTimer = setInterval(() => {
      this.refreshMonitor();
      this.refreshSimulator();
    }, POLL_INTERVAL_MS) as number;
  }

  aboutToDisappear(): void {
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
    this.stopAll();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Monitor
  // ──────────────────────────────────────────────────────────────────────────

  private refreshMonitor(): void {
    this.cpuUsage = Math.max(0, hidebug.getCpuUsage()) * 100;
    this.systemCpuUsage = hidebug.getSystemCpuUsage() * 100;
    this.thermalLevel = thermal.getThermalLevel();
    this.batterySOC = batteryInfo.batterySOC;
    this.batteryTemp = batteryInfo.batteryTemperature / 10;

    this.pssMb = (Number(hidebug.getPss()) / 1024).toFixed(2) + ' MB';

    const m = hidebug.getSystemMemInfo();
    const t = (Number(m.totalMem) / 1024).toFixed(0);
    const f = (Number(m.freeMem) / 1024).toFixed(0);
    const a = (Number(m.availableMem) / 1024).toFixed(0);
    this.sysMemInfo = `Total: ${t}MB | Free: ${f}MB | Avail: ${a}MB`;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Simulator
  // ──────────────────────────────────────────────────────────────────────────

  private refreshSimulator(): void {
    try {
      const s = libentry.getSimulatorStatus();
      this.cpuActive = s.cpuActive;
      this.memActive = s.memActive;
      this.ioActive = s.ioActive;
    } catch (e) {
      // ignore
    }
  }

  private applyCpu(lvl: number): void {
    this.cpuLevel = lvl;
    try { libentry.startCpuLoad(lvl); this.cpuActive = lvl > 0; } catch (e) {}
  }

  private applyMem(lvl: number): void {
    this.memLevel = lvl;
    try { libentry.startMemoryLoad(lvl); this.memActive = true; } catch (e) {}
  }

  private stopMem(): void {
    try { libentry.stopMemoryLoad(); this.memActive = false; } catch (e) {}
  }

  private applyIo(lvl: number): void {
    this.ioLevel = lvl;
    const dir = (getContext(this) as common.UIAbilityContext).filesDir;
    try { libentry.startIoLoad(lvl, dir); this.ioActive = true; } catch (e) {}
  }

  private stopIo(): void {
    try { libentry.stopIoLoad(); this.ioActive = false; } catch (e) {}
  }

  private stopAll(): void {
    try { libentry.stopCpuLoad(); libentry.stopMemoryLoad(); libentry.stopIoLoad(); } catch (e) {}
    this.cpuActive = false;
    this.memActive = false;
    this.ioActive = false;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Model test-load
  // ──────────────────────────────────────────────────────────────────────────

  private async testModels(): Promise<void> {
    this.modelStatus = 'Loading…';
    this.modelResult = '';
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const rm = ctx.resourceManager;

      const t0 = Date.now();
      const b1 = await rm.getRawFileContent(this.selectedInfi);
      const m1 = await mindSporeLite.loadModelFromBuffer(b1.buffer.slice(0), {
        target: ['cpu'],
        cpu: { threadNum: 4, threadAffinityMode: 1, threadAffinityCoreList: [0, 1, 2], precisionMode: 'enforce_fp32' }
      } as mindSporeLite.Context);
      const t1 = Date.now() - t0;

      const t2 = Date.now();
      const b2 = await rm.getRawFileContent(this.selectedYolo);
      const m2 = await mindSporeLite.loadModelFromBuffer(b2.buffer.slice(0), {
        target: ['nnrt'],
        nnrt: { performanceMode: 3 }
      } as mindSporeLite.Context);
      const t2e = Date.now() - t2;

      this.modelStatus = 'OK';
      this.modelResult = `InFi (${this.selectedInfi}): ${t1}ms\n`
        + `YOLO (${this.selectedYolo}): ${t2e}ms\n`
        + `Total: ${t1 + t2e}ms`;
      hilog.info(0x0000, TAG, 'testModels ok infi=%{public}dms yolo=%{public}dms', t1, t2e);
    } catch (e) {
      this.modelStatus = 'Failed';
      this.modelResult = JSON.stringify(e);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Inference benchmark
  // ──────────────────────────────────────────────────────────────────────────

  private getBatchSize(modelName: string): number {
    const m = modelName.match(/_bsz(\d+)/);
    return m ? parseInt(m[1]) : 1;
  }

  private generateRandomInput(batchSize: number): ArrayBuffer {
    const INPUT_SIZE = 640;
    const CHANNELS = 3;
    const totalFloats = INPUT_SIZE * INPUT_SIZE * CHANNELS * batchSize;
    const buf = new Float32Array(totalFloats);
    for (let i = 0; i < totalFloats; i++) {
      buf[i] = Math.random();
    }
    return buf.buffer;
  }

  private async runYoloBenchmark(): Promise<void> {
    this.inferRunning = true;
    this.inferStatus = 'Loading YOLO model…';
    this.inferResult = '';

    let model: mindSporeLite.Model | null = null;
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const rm = ctx.resourceManager;

      // Load YOLO model
      const tLoad0 = Date.now();
      const modelBuffer = await rm.getRawFileContent(this.selectedYolo);
      const yoloCtx: mindSporeLite.Context = {
        target: ['nnrt'],
        nnrt: { performanceMode: 3 }
      } as mindSporeLite.Context;
      model = await mindSporeLite.loadModelFromBuffer(modelBuffer.buffer.slice(0), yoloCtx);
      const tLoad = Date.now() - tLoad0;
      hilog.info(0x0000, TAG, 'Benchmark: YOLO model loaded in %{public}dms', tLoad);

      // Determine batch size from model name
      const bs = this.getBatchSize(this.selectedYolo);
      this.inferBatchSize = bs;

      // Generate random input data matching model input shape
      this.inferStatus = `Generating input (${640}x${640}x3 × bs=${bs})…`;
      const inputBuffer = this.generateRandomInput(bs);

      // Prepare model inputs
      const modelInputs = model.getInputs();
      modelInputs[0].setData(inputBuffer);

      // Warm-up inference
      this.inferStatus = 'Warm-up…';
      await model.predict(modelInputs);

      // Benchmark loop
      this.inferStatus = `Running ${this.inferCount} inferences…`;
      const totalStart = Date.now();
      for (let i = 0; i < this.inferCount; i++) {
        const inputs = model.getInputs();
        inputs[0].setData(this.generateRandomInput(bs));
        await model.predict(inputs);
      }
      const totalTime = Date.now() - totalStart;

      const avgMs = (totalTime / this.inferCount).toFixed(2);
      const fps = (this.inferCount / (totalTime / 1000)).toFixed(2);
      const throughput = ((this.inferCount * bs) / (totalTime / 1000)).toFixed(2);

      this.inferStatus = 'OK';
      this.inferResult =
        `Model: ${this.selectedYolo} (batch=${bs})\n` +
        `Load time: ${tLoad}ms\n` +
        `Inferences: ${this.inferCount} × bs${bs}\n` +
        `Total time: ${totalTime}ms\n` +
        `Avg per inference: ${avgMs}ms\n` +
        `Inference FPS: ${fps}\n` +
        `Throughput (images/s): ${throughput}`;

      hilog.info(0x0000, TAG, 'Benchmark done: %{public}d iters, %{public}dms total, avg=%{public}s ms',
        this.inferCount, totalTime, avgMs);
    } catch (e) {
      this.inferStatus = 'Failed';
      this.inferResult = JSON.stringify(e);
      hilog.error(0x0000, TAG, 'Benchmark failed: %{public}s', JSON.stringify(e));
    } finally {
      this.inferRunning = false;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // UI helpers
  // ──────────────────────────────────────────────────────────────────────────

  @Builder
  sectionTitle(t: string): void {
    Text(t)
      .fontSize(15)
      .fontWeight(FontWeight.Bold)
      .width('100%')
  }

  @Builder
  metricRow(label: string, value: string): void {
    Row() {
      Text(label).fontSize(12).fontColor('#666666').layoutWeight(1)
      Text(value).fontSize(12).fontColor('#333333').layoutWeight(1)
    }
    .width('100%')
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 14 }) {

          // =================================================================
          // SECTION 1 — Resource Monitor
          // =================================================================
          Column({ space: 8 }) {
            this.sectionTitle('Resource Monitor')

            Row() {
              Text(`App CPU: ${this.cpuUsage.toFixed(1)}%`).fontSize(12).layoutWeight(1)
              Text(`Sys CPU: ${this.systemCpuUsage.toFixed(1)}%`).fontSize(12).layoutWeight(1)
            }.width('100%')

            Text(`PSS: ${this.pssMb}`).fontSize(12).width('100%')
            Text(`Sys Mem: ${this.sysMemInfo}`).fontSize(12).width('100%')

            Row() {
              Text(`Thermal: ${this.thermalLevel}`).fontSize(12).layoutWeight(1)
              Text(`Battery: ${this.batterySOC}%`).fontSize(12).layoutWeight(1)
              Text(`${this.batteryTemp.toFixed(1)}°C`).fontSize(12).layoutWeight(1)
            }.width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#EEF6FF')
          .borderRadius(8)

          // =================================================================
          // SECTION 2 — Resource Simulator
          // =================================================================
          Column({ space: 12 }) {
            this.sectionTitle('Resource Simulator')

            // CPU
            Column({ space: 6 }) {
              Row() {
                Text('CPU Load').fontSize(13).fontWeight(FontWeight.Medium).layoutWeight(1)
                Text(this.cpuActive ? `Active (${CPU_LEVELS[this.cpuLevel]})` : 'Idle')
                  .fontSize(11)
                  .fontColor(this.cpuActive ? '#007DFF' : '#888888')
              }.width('100%')

              Row({ space: 4 }) {
                ForEach(CPU_LEVELS, (label: string, idx: number) => {
                  Button(label)
                    .layoutWeight(1)
                    .height(32)
                    .fontSize(11)
                    .fontColor(this.cpuLevel === idx ? '#FFF' : '#333')
                    .backgroundColor(this.cpuLevel === idx ? '#007DFF' : '#E0E0E0')
                    .onClick(() => { this.applyCpu(idx); })
                })
              }.width('100%')
            }

            // Memory
            Column({ space: 6 }) {
              Row() {
                Text('Memory Load').fontSize(13).fontWeight(FontWeight.Medium).layoutWeight(1)
                Text(this.memActive ? `Allocated (${MEM_LEVELS[this.memLevel]})` : 'Not allocated')
                  .fontSize(11)
                  .fontColor(this.memActive ? '#FF9800' : '#888888')
              }.width('100%')

              Row({ space: 4 }) {
                ForEach(MEM_LEVELS, (label: string, idx: number) => {
                  Button(label)
                    .layoutWeight(1)
                    .height(32)
                    .fontSize(11)
                    .fontColor(this.memActive && this.memLevel === idx ? '#FFF' : '#333')
                    .backgroundColor(this.memActive && this.memLevel === idx ? '#FF9800' : '#E0E0E0')
                    .onClick(() => { this.applyMem(idx); })
                })
                Button('Free')
                  .layoutWeight(1)
                  .height(32)
                  .fontSize(11)
                  .enabled(this.memActive)
                  .backgroundColor('#C62828')
                  .fontColor('#FFF')
                  .onClick(() => { this.stopMem(); })
              }.width('100%')
            }

            // I/O
            Column({ space: 6 }) {
              Row() {
                Text('I/O Load').fontSize(13).fontWeight(FontWeight.Medium).layoutWeight(1)
                Text(this.ioActive ? `Running (${IO_LEVELS[this.ioLevel]})` : 'Idle')
                  .fontSize(11)
                  .fontColor(this.ioActive ? '#4CAF50' : '#888888')
              }.width('100%')

              Row({ space: 4 }) {
                ForEach(IO_LEVELS, (label: string, idx: number) => {
                  Button(label)
                    .layoutWeight(1)
                    .height(32)
                    .fontSize(11)
                    .fontColor(this.ioActive && this.ioLevel === idx ? '#FFF' : '#333')
                    .backgroundColor(this.ioActive && this.ioLevel === idx ? '#4CAF50' : '#E0E0E0')
                    .onClick(() => { this.applyIo(idx); })
                })
                Button('Stop')
                  .layoutWeight(1)
                  .height(32)
                  .fontSize(11)
                  .enabled(this.ioActive)
                  .backgroundColor('#C62828')
                  .fontColor('#FFF')
                  .onClick(() => { this.stopIo(); })
              }.width('100%')
            }

            Button('Stop All Loads')
              .width('100%')
              .fontWeight(500)
              .fontSize(14)
              .backgroundColor('#C62828')
              .onClick(() => { this.stopAll(); })
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#FAFAFA')
          .borderRadius(8)

          // =================================================================
          // SECTION 3 — Model Selector
          // =================================================================
          Column({ space: 10 }) {
            this.sectionTitle('Model Selector')

            Column({ space: 4 }) {
              Text('InFi Model').fontSize(13).fontWeight(FontWeight.Medium).width('100%')
              Select(this.infiOptions)
                .width('100%')
                .height(36)
                .selected(this.infiIndex)
                .onSelect((idx: number) => { this.selectedInfi = INFI_MODELS[idx]; })
            }.width('100%')

            Column({ space: 4 }) {
              Text('YOLO Model').fontSize(13).fontWeight(FontWeight.Medium).width('100%')
              Select(this.yoloOptions)
                .width('100%')
                .height(36)
                .selected(this.yoloIndex)
                .onSelect((idx: number) => { this.selectedYolo = YOLO_MODELS[idx]; })
            }.width('100%')

            Button('Test Load Models')
              .width('100%')
              .fontWeight(500)
              .fontSize(14)
              .onClick(() => { this.testModels(); })

            Text(`Status: ${this.modelStatus}`)
              .fontSize(12)
              .fontColor(this.modelStatus === 'OK' ? '#4CAF50' :
                this.modelStatus === 'Failed' ? '#C62828' : '#333')
              .width('100%')

            if (this.modelResult.length > 0) {
              Text(this.modelResult)
                .fontSize(11)
                .fontColor('#333')
                .width('100%')
                .padding(8)
                .backgroundColor('#F5F5F5')
                .borderRadius(4)
            }

            Divider().margin({ top: 4, bottom: 4 })

            // ── YOLO Inference Benchmark ──
            Text('YOLO Inference Benchmark')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .width('100%')

            Row({ space: 8 }) {
              Text('Count:').fontSize(12).width(50)
              TextInput({ text: this.inferCount.toString(), placeholder: '10' })
                .layoutWeight(1)
                .height(36)
                .fontSize(13)
                .type(InputType.Number)
                .onChange((v: string) => {
                  const n = parseInt(v);
                  if (n > 0 && n <= 1000) { this.inferCount = n; }
                })
            }.width('100%').alignItems(VerticalAlign.Center)

            Text(`Batch size: ${this.inferBatchSize} (from model name)`)
              .fontSize(12)
              .fontColor('#666666')
              .width('100%')

            Button(this.inferRunning ? 'Running…' : 'Run YOLO Inference')
              .width('100%')
              .fontWeight(500)
              .fontSize(14)
              .enabled(!this.inferRunning)
              .backgroundColor('#9C27B0')
              .onClick(() => { this.runYoloBenchmark(); })

            Text(`Status: ${this.inferStatus}`)
              .fontSize(12)
              .fontColor(this.inferStatus === 'OK' ? '#4CAF50' :
                this.inferStatus === 'Failed' ? '#C62828' :
                this.inferStatus.indexOf('Running') >= 0 ? '#FF9800' : '#333')
              .width('100%')

            if (this.inferResult.length > 0) {
              Text(this.inferResult)
                .fontSize(11)
                .fontColor('#333')
                .width('100%')
                .padding(8)
                .backgroundColor('#F3E5F5')
                .borderRadius(4)
            }
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#FAFAFA')
          .borderRadius(8)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
    }
    .backgroundColor($r('app.color.background_color'))
    .title(TitleComponent('Test Dashboard', 'Monitor · Simulator · Models'))
  }
}
