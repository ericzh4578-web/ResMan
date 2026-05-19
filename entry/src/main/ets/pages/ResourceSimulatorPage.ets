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
import { TitleComponent } from '../view/TitleComponent';
import { common } from '@kit.AbilityKit';

const TAG = 'ResourceSimulatorPage';
const STATUS_INTERVAL_MS = 1000;

const CPU_LEVEL_LABELS: string[] = ['0%', '25%', '50%', '75%', '100%'];
const MEM_LEVEL_LABELS: string[] = ['25%', '50%', '80%'];
const IO_LEVEL_LABELS: string[] = ['Weak', 'Medium', 'Strong'];

@Component
export struct ResourceSimulatorPage {
  @Consume('pageInfos') pageInfos: NavPathStack;

  // ── Simulator state ──
  @State cpuLevel: number = 0;
  @State cpuActive: boolean = false;
  @State memLevel: number = 0;
  @State memActive: boolean = false;
  @State ioLevel: number = 0;
  @State ioActive: boolean = false;

  // ── Live system metrics ──
  @State cpuUsage: number = 0;
  @State systemCpuUsage: number = 0;
  @State memoryInfo: string = '-';
  @State systemMemoryInfo: string = '-';
  @State thermalLevel: number = 0;
  @State batterySOC: number = 0;
  @State batteryTemp: number = 0;

  private statusTimer: number = -1;

  // ────────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ────────────────────────────────────────────────────────────────────────────

  aboutToAppear(): void {
    this.statusTimer = setInterval(() => {
      this.pollStatus();
      this.pollMetrics();
    }, STATUS_INTERVAL_MS) as number;
  }

  aboutToDisappear(): void {
    if (this.statusTimer !== -1) {
      clearInterval(this.statusTimer);
      this.statusTimer = -1;
    }
    // Stop all loads when leaving the page
    this.stopAllLoads();
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Simulator control
  // ────────────────────────────────────────────────────────────────────────────

  private getFilesDir(): string {
    return (getContext(this) as common.UIAbilityContext).filesDir;
  }

  private pollStatus(): void {
    try {
      const s = libentry.getSimulatorStatus();
      this.cpuActive = s.cpuActive;
      this.memActive = s.memActive;
      this.ioActive = s.ioActive;
    } catch (e) {
      hilog.warn(0x0000, TAG, 'pollStatus failed: %{public}s', JSON.stringify(e));
    }
  }

  private pollMetrics(): void {
    this.cpuUsage = Math.max(0, hidebug.getCpuUsage()) * 100;
    this.systemCpuUsage = hidebug.getSystemCpuUsage() * 100;
    this.thermalLevel = thermal.getThermalLevel();
    this.batterySOC = batteryInfo.batterySOC;
    this.batteryTemp = batteryInfo.batteryTemperature / 10;

    const pss = Number(hidebug.getPss()) / 1024;
    this.memoryInfo = `${pss.toFixed(2)} MB`;

    const sysMem = hidebug.getSystemMemInfo();
    const total = (Number(sysMem.totalMem) / 1024).toFixed(2);
    const free = (Number(sysMem.freeMem) / 1024).toFixed(2);
    const avail = (Number(sysMem.availableMem) / 1024).toFixed(2);
    this.systemMemoryInfo = `Total: ${total}MB | Free: ${free}MB | Avail: ${avail}MB`;
  }

  private applyCpuLevel(level: number): void {
    this.cpuLevel = level;
    try {
      libentry.startCpuLoad(level);
      this.cpuActive = level > 0;
    } catch (e) {
      hilog.error(0x0000, TAG, 'startCpuLoad failed: %{public}s', JSON.stringify(e));
    }
  }

  private applyMemLevel(level: number): void {
    this.memLevel = level;
    try {
      libentry.startMemoryLoad(level);
      this.memActive = true;
    } catch (e) {
      hilog.error(0x0000, TAG, 'startMemoryLoad failed: %{public}s', JSON.stringify(e));
    }
  }

  private stopMemory(): void {
    try {
      libentry.stopMemoryLoad();
      this.memActive = false;
    } catch (e) {
      hilog.error(0x0000, TAG, 'stopMemoryLoad failed: %{public}s', JSON.stringify(e));
    }
  }

  private applyIoLevel(level: number): void {
    this.ioLevel = level;
    try {
      libentry.startIoLoad(level, this.getFilesDir());
      this.ioActive = true;
    } catch (e) {
      hilog.error(0x0000, TAG, 'startIoLoad failed: %{public}s', JSON.stringify(e));
    }
  }

  private stopIo(): void {
    try {
      libentry.stopIoLoad();
      this.ioActive = false;
    } catch (e) {
      hilog.error(0x0000, TAG, 'stopIoLoad failed: %{public}s', JSON.stringify(e));
    }
  }

  private stopAllLoads(): void {
    try {
      libentry.stopCpuLoad();
      libentry.stopMemoryLoad();
      libentry.stopIoLoad();
    } catch (e) {
      // ignore
    }
    this.cpuActive = false;
    this.memActive = false;
    this.ioActive = false;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // UI builders
  // ────────────────────────────────────────────────────────────────────────────

  @Builder
  private sectionHeader(title: string): void {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .width('100%')
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 16 }) {

          // ── CPU Load ──────────────────────────────────────────────────────
          Column({ space: 8 }) {
            this.sectionHeader('CPU Load Simulation')
            Text('Simulates CPU load via busy-loop worker threads. Level controls duty cycle.')
              .fontSize(12)
              .fontColor('#666666')
              .width('100%')

            Row({ space: 6 }) {
              ForEach(CPU_LEVEL_LABELS, (label: string, idx: number) => {
                Button(label)
                  .layoutWeight(1)
                  .height(36)
                  .fontSize(13)
                  .fontColor(this.cpuLevel === idx ? '#FFFFFF' : '#333333')
                  .backgroundColor(this.cpuLevel === idx ? '#007DFF' : '#E0E0E0')
                  .onClick(() => { this.applyCpuLevel(idx); })
              })
            }
            .width('100%')

            Row({ space: 12 }) {
              Text(`Status: ${this.cpuActive ? `Running (level ${this.cpuLevel})` : 'Idle'}`)
                .fontSize(12)
                .fontColor(this.cpuActive ? '#007DFF' : '#888888')
                .layoutWeight(1)
              Button('Stop')
                .height(30)
                .fontSize(12)
                .enabled(this.cpuActive)
                .onClick(() => { this.applyCpuLevel(0); })
            }
            .width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)

          // ── Memory Load ───────────────────────────────────────────────────
          Column({ space: 8 }) {
            this.sectionHeader('Memory Load Simulation')
            Text('Allocates and pins a percentage of total physical RAM.')
              .fontSize(12)
              .fontColor('#666666')
              .width('100%')

            Row({ space: 6 }) {
              ForEach(MEM_LEVEL_LABELS, (label: string, idx: number) => {
                Button(label)
                  .layoutWeight(1)
                  .height(36)
                  .fontSize(13)
                  .fontColor(this.memActive && this.memLevel === idx ? '#FFFFFF' : '#333333')
                  .backgroundColor(this.memActive && this.memLevel === idx ? '#FF9800' : '#E0E0E0')
                  .onClick(() => { this.applyMemLevel(idx); })
              })
            }
            .width('100%')

            Row({ space: 12 }) {
              Text(`Status: ${this.memActive ? `Allocated (level ${this.memLevel})` : 'Not allocated'}`)
                .fontSize(12)
                .fontColor(this.memActive ? '#FF9800' : '#888888')
                .layoutWeight(1)
              Button('Release')
                .height(30)
                .fontSize(12)
                .enabled(this.memActive)
                .onClick(() => { this.stopMemory(); })
            }
            .width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)

          // ── I/O Load ──────────────────────────────────────────────────────
          Column({ space: 8 }) {
            this.sectionHeader('I/O Load Simulation')
            Text('Random read/write on a 64 MB temporary file in the app sandbox.')
              .fontSize(12)
              .fontColor('#666666')
              .width('100%')

            Row({ space: 6 }) {
              ForEach(IO_LEVEL_LABELS, (label: string, idx: number) => {
                Button(label)
                  .layoutWeight(1)
                  .height(36)
                  .fontSize(13)
                  .fontColor(this.ioActive && this.ioLevel === idx ? '#FFFFFF' : '#333333')
                  .backgroundColor(this.ioActive && this.ioLevel === idx ? '#4CAF50' : '#E0E0E0')
                  .onClick(() => { this.applyIoLevel(idx); })
              })
            }
            .width('100%')

            Row({ space: 12 }) {
              Text(`Status: ${this.ioActive ? `Running (level ${this.ioLevel})` : 'Idle'}`)
                .fontSize(12)
                .fontColor(this.ioActive ? '#4CAF50' : '#888888')
                .layoutWeight(1)
              Button('Stop')
                .height(30)
                .fontSize(12)
                .enabled(this.ioActive)
                .onClick(() => { this.stopIo(); })
            }
            .width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)

          // ── Stop All ──────────────────────────────────────────────────────
          Button('Stop All Loads')
            .width('100%')
            .fontWeight(500)
            .fontSize(16)
            .backgroundColor('#C62828')
            .onClick(() => { this.stopAllLoads(); })

          // ── Live System Metrics ───────────────────────────────────────────
          Column({ space: 8 }) {
            this.sectionHeader('Live System Metrics')
            Row() {
              Text(`App CPU: ${this.cpuUsage.toFixed(1)}%`)
                .fontSize(12)
                .layoutWeight(1)
              Text(`System CPU: ${this.systemCpuUsage.toFixed(1)}%`)
                .fontSize(12)
                .layoutWeight(1)
            }
            .width('100%')
            Text(`PSS: ${this.memoryInfo}`)
              .fontSize(12)
              .width('100%')
            Text(`System mem: ${this.systemMemoryInfo}`)
              .fontSize(12)
              .width('100%')
            Row() {
              Text(`Thermal: ${this.thermalLevel}`)
                .fontSize(12)
                .layoutWeight(1)
              Text(`Battery: ${this.batterySOC}%`)
                .fontSize(12)
                .layoutWeight(1)
            }
            .width('100%')
            Text(`Battery temp: ${this.batteryTemp.toFixed(1)}°C`)
              .fontSize(12)
              .width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#EEF6FF')
          .borderRadius(8)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
    }
    .backgroundColor($r('app.color.background_color'))
    .title(TitleComponent('Resource Simulator', 'CPU / Memory / I/O load simulation'))
  }
}
