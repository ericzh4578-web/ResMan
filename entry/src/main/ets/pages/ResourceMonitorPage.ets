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

import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { batteryInfo, thermal } from '@kit.BasicServicesKit';
import { hidebug, hilog } from '@kit.PerformanceAnalysisKit';
import { TitleComponent } from '../view/TitleComponent';

const TAG = 'ResourceMonitorPage';
const SAMPLE_INTERVAL_MS = 2000;
const RECORD_DIR_NAME = 'resource-monitor';

interface ResourceSample {
  timestamp: number;
  elapsedMs: number;
  cpuUsage: number;
  systemCpuUsage: number;
  pssMb: number;
  totalMemMb: number;
  freeMemMb: number;
  availableMemMb: number;
  thermalLevel: number;
  batterySOC: number;
  batteryTemp: number;
  batteryCurrent: number;
  batteryVoltage: number;
}

interface MonitorSummary {
  durationMs: number;
  sampleCount: number;
  avgCpuUsage: number;
  peakCpuUsage: number;
  avgSystemCpuUsage: number;
  peakSystemCpuUsage: number;
  peakPssMb: number;
  minAvailableMemMb: number;
  maxThermalLevel: number;
  batterySocDrop: number;
  maxBatteryTemp: number;
}

interface MonitorSessionFile {
  id: string;
  name: string;
  startedAt: number;
  endedAt: number;
  sampleIntervalMs: number;
  summary: MonitorSummary;
  samples: ResourceSample[];
}

interface MonitorRecordMeta {
  id: string;
  name: string;
  fileName: string;
  startedAt: number;
  endedAt: number;
  sampleCount: number;
  sizeBytes: number;
  avgCpuUsage: number;
  peakCpuUsage: number;
  peakPssMb: number;
}

function roundToOne(value: number): number {
  return Math.round(value * 10) / 10;
}

function roundToTwo(value: number): number {
  return Math.round(value * 100) / 100;
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

function formatTime(timestamp: number): string {
  const date = new Date(timestamp);
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())} `
    + `${pad2(date.getHours())}:${pad2(date.getMinutes())}:${pad2(date.getSeconds())}`;
}

function formatDuration(durationMs: number): string {
  const totalSeconds = Math.floor(durationMs / 1000);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  return `${pad2(hours)}:${pad2(minutes)}:${pad2(seconds)}`;
}

@Component
export struct ResourceMonitorPage {
  @Consume('pageInfos') pageInfos: NavPathStack;

  @State sessionName: string = 'External Task Evaluation';
  @State status: string = 'Idle';
  @State isMonitoring: boolean = false;
  @State sessionStartText: string = '-';
  @State elapsedText: string = '00:00:00';
  @State sampleCount: number = 0;
  @State cpuUsage: number = 0;
  @State systemCpuUsage: number = 0;
  @State memoryInfo: string = '-';
  @State systemMemoryInfo: string = '-';
  @State thermalLevel: number = 0;
  @State batterySOC: number = 0;
  @State batteryTemp: number = 0;
  @State batteryCurrent: number = 0;
  @State batteryVoltage: number = 0;
  @State recordsDir: string = '';
  @State recordList: MonitorRecordMeta[] = [];
  @State selectedRecordText: string = 'No saved record';
  @State selectedRecordFileName: string = '';
  @State editRecordName: string = '';

  private monitoringTimer: number = -1;
  private sessionStartAt: number = 0;
  private samples: ResourceSample[] = [];

  private getAbilityContext(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private getRecordsDir(): string {
    return `${this.getAbilityContext().filesDir}/${RECORD_DIR_NAME}`;
  }

  private async ensureRecordsDir(): Promise<void> {
    const dir = this.getRecordsDir();
    this.recordsDir = dir;
    try {
      await fileIo.mkdir(dir, true);
    } catch (e) {
      const message = JSON.stringify(e);
      if (message.indexOf('13900015') === -1) {
        hilog.error(0x0000, TAG, 'ensureRecordsDir failed: %{public}s', message);
        throw new Error(message);
      }
    }
  }

  private buildSample(elapsedMs: number): ResourceSample {
    const cpuUsage = Math.max(0, hidebug.getCpuUsage()) * 100;
    const systemCpuUsage = hidebug.getSystemCpuUsage() * 100;
    const thermalLevel = thermal.getThermalLevel();
    const batterySOC = batteryInfo.batterySOC;
    const batteryTemp = batteryInfo.batteryTemperature / 10;
    const batteryCurrent = batteryInfo.nowCurrent;
    const batteryVoltage = batteryInfo.voltage;
    const pssMb = Number(hidebug.getPss()) / 1024;
    const systemMemInfo = hidebug.getSystemMemInfo();
    const totalMemMb = Number(systemMemInfo.totalMem) / 1024;
    const freeMemMb = Number(systemMemInfo.freeMem) / 1024;
    const availableMemMb = Number(systemMemInfo.availableMem) / 1024;

    return {
      timestamp: Date.now(),
      elapsedMs,
      cpuUsage: roundToTwo(cpuUsage),
      systemCpuUsage: roundToTwo(systemCpuUsage),
      pssMb: roundToTwo(pssMb),
      totalMemMb: roundToTwo(totalMemMb),
      freeMemMb: roundToTwo(freeMemMb),
      availableMemMb: roundToTwo(availableMemMb),
      thermalLevel,
      batterySOC,
      batteryTemp: roundToOne(batteryTemp),
      batteryCurrent,
      batteryVoltage,
    };
  }

  private applySample(sample: ResourceSample): void {
    this.cpuUsage = sample.cpuUsage;
    this.systemCpuUsage = sample.systemCpuUsage;
    this.thermalLevel = sample.thermalLevel;
    this.batterySOC = sample.batterySOC;
    this.batteryTemp = sample.batteryTemp;
    this.batteryCurrent = sample.batteryCurrent;
    this.batteryVoltage = sample.batteryVoltage;
    this.memoryInfo = `${sample.pssMb.toFixed(2)} MB`;
    this.systemMemoryInfo = `Total: ${sample.totalMemMb.toFixed(2)}MB | Free: ${sample.freeMemMb.toFixed(2)}MB | Avail: ${sample.availableMemMb.toFixed(2)}MB`;
  }

  private captureSample(): void {
    const elapsedMs = this.sessionStartAt > 0 ? Date.now() - this.sessionStartAt : 0;
    const sample = this.buildSample(elapsedMs);
    this.samples.push(sample);
    this.sampleCount = this.samples.length;
    this.elapsedText = formatDuration(elapsedMs);
    this.applySample(sample);
  }

  private startMonitoring(): void {
    if (this.isMonitoring) {
      return;
    }
    this.isMonitoring = true;
    this.status = 'Sampling';
    this.sessionStartAt = Date.now();
    this.sessionStartText = formatTime(this.sessionStartAt);
    this.elapsedText = '00:00:00';
    this.samples = [];
    this.sampleCount = 0;
    this.captureSample();
    this.monitoringTimer = setInterval(() => {
      this.captureSample();
    }, SAMPLE_INTERVAL_MS) as number;
  }

  private stopMonitoring(): void {
    if (this.monitoringTimer !== -1) {
      clearInterval(this.monitoringTimer);
      this.monitoringTimer = -1;
    }
    this.isMonitoring = false;
  }

  private buildSummary(samples: ResourceSample[]): MonitorSummary {
    if (samples.length === 0) {
      return {
        durationMs: 0,
        sampleCount: 0,
        avgCpuUsage: 0,
        peakCpuUsage: 0,
        avgSystemCpuUsage: 0,
        peakSystemCpuUsage: 0,
        peakPssMb: 0,
        minAvailableMemMb: 0,
        maxThermalLevel: 0,
        batterySocDrop: 0,
        maxBatteryTemp: 0,
      };
    }

    let cpuSum = 0;
    let systemCpuSum = 0;
    let peakCpuUsage = samples[0].cpuUsage;
    let peakSystemCpuUsage = samples[0].systemCpuUsage;
    let peakPssMb = samples[0].pssMb;
    let minAvailableMemMb = samples[0].availableMemMb;
    let maxThermalLevel = samples[0].thermalLevel;
    let maxBatteryTemp = samples[0].batteryTemp;

    for (let i = 0; i < samples.length; i++) {
      const item = samples[i];
      cpuSum += item.cpuUsage;
      systemCpuSum += item.systemCpuUsage;
      peakCpuUsage = Math.max(peakCpuUsage, item.cpuUsage);
      peakSystemCpuUsage = Math.max(peakSystemCpuUsage, item.systemCpuUsage);
      peakPssMb = Math.max(peakPssMb, item.pssMb);
      minAvailableMemMb = Math.min(minAvailableMemMb, item.availableMemMb);
      maxThermalLevel = Math.max(maxThermalLevel, item.thermalLevel);
      maxBatteryTemp = Math.max(maxBatteryTemp, item.batteryTemp);
    }

    const lastSample = samples[samples.length - 1];
    const firstSample = samples[0];
    return {
      durationMs: lastSample.elapsedMs,
      sampleCount: samples.length,
      avgCpuUsage: roundToTwo(cpuSum / samples.length),
      peakCpuUsage: roundToTwo(peakCpuUsage),
      avgSystemCpuUsage: roundToTwo(systemCpuSum / samples.length),
      peakSystemCpuUsage: roundToTwo(peakSystemCpuUsage),
      peakPssMb: roundToTwo(peakPssMb),
      minAvailableMemMb: roundToTwo(minAvailableMemMb),
      maxThermalLevel,
      batterySocDrop: firstSample.batterySOC - lastSample.batterySOC,
      maxBatteryTemp: roundToOne(maxBatteryTemp),
    };
  }

  private buildRecordPreview(session: MonitorSessionFile): string {
    return `Name: ${session.name}
Start: ${formatTime(session.startedAt)}
End: ${formatTime(session.endedAt)}
Duration: ${formatDuration(session.summary.durationMs)}
Samples: ${session.summary.sampleCount}
Avg app CPU: ${session.summary.avgCpuUsage.toFixed(2)}%
Peak app CPU: ${session.summary.peakCpuUsage.toFixed(2)}%
Avg system CPU: ${session.summary.avgSystemCpuUsage.toFixed(2)}%
Peak system CPU: ${session.summary.peakSystemCpuUsage.toFixed(2)}%
Peak PSS: ${session.summary.peakPssMb.toFixed(2)}MB
Min available memory: ${session.summary.minAvailableMemMb.toFixed(2)}MB
Max thermal level: ${session.summary.maxThermalLevel}
Max battery temp: ${session.summary.maxBatteryTemp.toFixed(1)}C
Battery delta: -${session.summary.batterySocDrop}%`;
  }

  private async saveCurrentSession(): Promise<void> {
    if (this.samples.length === 0 || this.sessionStartAt === 0) {
      this.status = 'No samples to save';
      return;
    }

    await this.ensureRecordsDir();
    const endedAt = Date.now();
    const summary = this.buildSummary(this.samples);
    const sessionId = `${endedAt}`;
    const safeName = this.sessionName.trim().length > 0 ? this.sessionName.trim() : 'Unnamed Task';
    const fileName = `resource-session-${sessionId}.json`;
    const filePath = `${this.recordsDir}/${fileName}`;
    const sessionFile: MonitorSessionFile = {
      id: sessionId,
      name: safeName,
      startedAt: this.sessionStartAt,
      endedAt,
      sampleIntervalMs: SAMPLE_INTERVAL_MS,
      summary,
      samples: this.samples,
    };

    const file = await fileIo.open(filePath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, JSON.stringify(sessionFile, null, 2));
    } finally {
      await fileIo.close(file.fd);
    }

    this.status = `Saved ${summary.sampleCount} samples`;
    this.selectedRecordText = this.buildRecordPreview(sessionFile);
    await this.loadRecordList();
  }

  private async loadRecordList(): Promise<void> {
    await this.ensureRecordsDir();
    let fileNames: string[] = [];
    try {
      fileNames = await fileIo.listFile(this.recordsDir);
    } catch (e) {
      hilog.error(0x0000, TAG, 'loadRecordList listFile failed: %{public}s', JSON.stringify(e));
      this.recordList = [];
      return;
    }

    const records: MonitorRecordMeta[] = [];
    for (let i = 0; i < fileNames.length; i++) {
      const fileName = fileNames[i];
      if (!fileName.endsWith('.json')) {
        continue;
      }
      const filePath = `${this.recordsDir}/${fileName}`;
      try {
        const content = await fileIo.readText(filePath);
        const stat = await fileIo.stat(filePath);
        const session = JSON.parse(content) as MonitorSessionFile;
        records.push({
          id: session.id,
          name: session.name,
          fileName,
          startedAt: session.startedAt,
          endedAt: session.endedAt,
          sampleCount: session.summary.sampleCount,
          sizeBytes: stat.size,
          avgCpuUsage: session.summary.avgCpuUsage,
          peakCpuUsage: session.summary.peakCpuUsage,
          peakPssMb: session.summary.peakPssMb,
        });
      } catch (e) {
        hilog.warn(0x0000, TAG, 'skip invalid record %{public}s: %{public}s', fileName, JSON.stringify(e));
      }
    }

    records.sort((a: MonitorRecordMeta, b: MonitorRecordMeta) => b.startedAt - a.startedAt);
    this.recordList = records;
  }

  private async loadRecordDetail(fileName: string): Promise<void> {
    try {
      const content = await fileIo.readText(`${this.recordsDir}/${fileName}`);
      const session = JSON.parse(content) as MonitorSessionFile;
      this.selectedRecordFileName = fileName;
      this.editRecordName = session.name;
      this.selectedRecordText = this.buildRecordPreview(session);
    } catch (e) {
      this.selectedRecordFileName = '';
      this.editRecordName = '';
      this.selectedRecordText = `Read failed: ${JSON.stringify(e)}`;
    }
  }

  private async renameRecord(fileName: string, newName: string): Promise<void> {
    const safeName = newName.trim();
    if (safeName.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: 'Name cannot be empty', duration: 1500 });
      return;
    }

    try {
      const filePath = `${this.recordsDir}/${fileName}`;
      const content = await fileIo.readText(filePath);
      const session = JSON.parse(content) as MonitorSessionFile;
      session.name = safeName;

      const file = await fileIo.open(filePath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        await fileIo.write(file.fd, JSON.stringify(session, null, 2));
      } finally {
        await fileIo.close(file.fd);
      }

      this.editRecordName = safeName;
      this.selectedRecordText = this.buildRecordPreview(session);
      await this.loadRecordList();
      this.getUIContext().getPromptAction().showToast({ message: 'Record name updated', duration: 1500 });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: 'Rename failed', duration: 1500 });
      hilog.error(0x0000, TAG, 'renameRecord failed: %{public}s', JSON.stringify(e));
    }
  }

  private async deleteRecord(fileName: string): Promise<void> {
    try {
      await fileIo.unlink(`${this.recordsDir}/${fileName}`);
      if (this.recordList.length === 1) {
        this.selectedRecordText = 'No saved record';
        this.selectedRecordFileName = '';
        this.editRecordName = '';
      } else if (this.selectedRecordFileName === fileName) {
        this.selectedRecordText = 'No saved record';
        this.selectedRecordFileName = '';
        this.editRecordName = '';
      }
      await this.loadRecordList();
      this.getUIContext().getPromptAction().showToast({ message: 'Record deleted', duration: 1500 });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: 'Delete failed', duration: 1500 });
      hilog.error(0x0000, TAG, 'deleteRecord failed: %{public}s', JSON.stringify(e));
    }
  }

  aboutToAppear(): void {
    this.recordsDir = this.getRecordsDir();
    this.loadRecordList().catch((e: Error) => {
      hilog.error(0x0000, TAG, 'aboutToAppear loadRecordList failed: %{public}s', e.message);
    });
  }

  aboutToDisappear(): void {
    this.stopMonitoring();
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 8 }) {
            Text('Test Goal')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .width('100%')
            Text('Reuses the VideoInferencePage sampling logic and records resource changes during other device tasks.')
              .fontSize(12)
              .fontColor('#666666')
              .width('100%')
            Text(`Sample interval: ${SAMPLE_INTERVAL_MS / 1000}s`)
              .fontSize(12)
              .fontColor('#666666')
              .width('100%')
            Text(`Sandbox dir: ${this.recordsDir}`)
              .fontSize(12)
              .fontColor('#666666')
              .width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)

          Column({ space: 8 }) {
            Text('Session Name')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .width('100%')
            TextInput({ text: this.sessionName, placeholder: 'Example: download plus video call' })
              .fontSize(14)
              .onChange((value: string) => {
                this.sessionName = value;
              })
          }
          .width('100%')

          Column({ space: 6 }) {
            Text(`Status: ${this.status}`)
              .fontSize(14)
              .fontColor(this.isMonitoring ? '#007DFF' : '#333333')
              .width('100%')
            Text(`Started at: ${this.sessionStartText}`)
              .fontSize(12)
              .width('100%')
            Text(`Elapsed: ${this.elapsedText}`)
              .fontSize(12)
              .width('100%')
            Text(`Samples: ${this.sampleCount}`)
              .fontSize(12)
              .width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#EEF6FF')
          .borderRadius(8)

          Column({ space: 8 }) {
            Text('Live Metrics')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .width('100%')
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
            Text(`System memory: ${this.systemMemoryInfo}`)
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
            Row() {
              Text(`Battery temp: ${this.batteryTemp.toFixed(1)}C`)
                .fontSize(12)
                .layoutWeight(1)
              Text(`Voltage: ${(this.batteryVoltage / 1000).toFixed(2)}V`)
                .fontSize(12)
                .layoutWeight(1)
            }
            .width('100%')
            Text(`Current: ${this.batteryCurrent}mA`)
              .fontSize(12)
              .width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)

          Row({ space: 12 }) {
            Button('Start Sampling')
              .layoutWeight(1)
              .enabled(!this.isMonitoring)
              .onClick(() => {
                this.startMonitoring();
              })
            Button('Stop and Save')
              .layoutWeight(1)
              .enabled(this.isMonitoring)
              .onClick(async () => {
                this.stopMonitoring();
                await this.saveCurrentSession();
              })
          }
          .width('100%')

          Row({ space: 12 }) {
            Button('Refresh Records')
              .layoutWeight(1)
              .onClick(async () => {
                await this.loadRecordList();
              })
            Button('Stop Only')
              .layoutWeight(1)
              .enabled(this.isMonitoring)
              .onClick(() => {
                this.stopMonitoring();
                this.status = 'Stopped without saving';
              })
          }
          .width('100%')

          Column({ space: 8 }) {
            Text('Record Preview')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .width('100%')
            TextInput({
              text: this.editRecordName,
              placeholder: 'Select a record, then edit its name'
            })
              .fontSize(14)
              .enabled(this.selectedRecordFileName.length > 0)
              .onChange((value: string) => {
                this.editRecordName = value;
              })
            Button('Update Record Name')
              .width('100%')
              .enabled(this.selectedRecordFileName.length > 0)
              .onClick(async () => {
                await this.renameRecord(this.selectedRecordFileName, this.editRecordName);
              })
            Text(this.selectedRecordText)
              .fontSize(12)
              .fontColor('#666666')
              .width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#FFF9E8')
          .borderRadius(8)

          Column({ space: 8 }) {
            Row() {
                Text('Saved Records')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .layoutWeight(1)
              Text(`${this.recordList.length} items`)
                .fontSize(12)
                .fontColor('#666666')
            }
            .width('100%')

            if (this.recordList.length === 0) {
              Text('No saved records yet')
                .fontSize(12)
                .fontColor('#888888')
                .width('100%')
            } else {
              ForEach(this.recordList, (item: MonitorRecordMeta) => {
                Column({ space: 6 }) {
                  Text(item.name)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .width('100%')
                  Text(`${formatTime(item.startedAt)} | ${item.sampleCount} samples | ${(item.sizeBytes / 1024).toFixed(1)} KB`)
                    .fontSize(12)
                    .fontColor('#666666')
                    .width('100%')
                  Text(`Avg CPU ${item.avgCpuUsage.toFixed(2)}% | Peak CPU ${item.peakCpuUsage.toFixed(2)}% | Peak PSS ${item.peakPssMb.toFixed(2)}MB`)
                    .fontSize(12)
                    .fontColor('#666666')
                    .width('100%')
                  Row({ space: 12 }) {
                    Button('View')
                      .layoutWeight(1)
                      .height(36)
                      .onClick(async () => {
                        await this.loadRecordDetail(item.fileName);
                      })
                    Button('Delete')
                      .layoutWeight(1)
                      .height(36)
                      .backgroundColor('#FDEDED')
                      .fontColor('#C62828')
                      .onClick(async () => {
                        await this.deleteRecord(item.fileName);
                      })
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(12)
                .backgroundColor('#FFFFFF')
                .borderRadius(8)
              }, (item: MonitorRecordMeta) => item.id)
            }
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
    }
    .backgroundColor($r('app.color.background_color'))
    .title(TitleComponent('Resource Monitor Test', 'Sample and save sandbox records'))
  }
}
