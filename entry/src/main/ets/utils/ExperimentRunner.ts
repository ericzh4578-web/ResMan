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

import { hidebug, hilog } from '@kit.PerformanceAnalysisKit';
import { thermal, batteryInfo } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import libentry from 'libentry.so';

const TAG = 'MetricsCollector';

export interface ExperimentSample {
  timestamp: number;
  elapsedMs: number;
  cpuUsagePercent: number;
  systemCpuUsagePercent: number;
  cpuFreqsCsv: string;
  gpuFreqKHz: number;
  pssMb: number;
  availableMemMb: number;
  thermalLevel: number;
  batterySOC: number;
  batteryTemp: number;
  batteryCurrent: number;
  batteryVoltage: number;
  fps: number;
  avgLatencyMs: number;
}

export class MetricsCollector {

  static captureSample(elapsedMs: number): ExperimentSample {
    let cpuFreqsCsv = '';
    let gpuFreqKHz = 0;
    try {
      cpuFreqsCsv = libentry.readCpuFreqsCsv() || '';
      gpuFreqKHz = libentry.readGpuFreq() || 0;
    } catch (_) {
      // sysfs read may fail — proceed without frequency data
    }

    const systemMemInfo = hidebug.getSystemMemInfo();

    return {
      timestamp: Date.now(),
      elapsedMs,
      cpuUsagePercent: Math.max(0, hidebug.getCpuUsage()) * 100,
      systemCpuUsagePercent: hidebug.getSystemCpuUsage() * 100,
      cpuFreqsCsv,
      gpuFreqKHz,
      pssMb: Number(hidebug.getPss()) / 1024,
      availableMemMb: Number(systemMemInfo.availableMem) / 1024,
      thermalLevel: thermal.getThermalLevel(),
      batterySOC: batteryInfo.batterySOC,
      batteryTemp: (batteryInfo.batteryTemperature as number) / 10.0,
      batteryCurrent: batteryInfo.nowCurrent,
      batteryVoltage: batteryInfo.voltage,
      fps: 0,
      avgLatencyMs: 0,
    };
  }
}

export interface ExperimentConfig {
  name: string;
  durationMs: number;
  sampleIntervalMs: number;
}

export interface ExperimentProgress {
  status: 'idle' | 'running' | 'stabilizing' | 'completed' | 'failed';
  elapsedMs: number;
  sampleCount: number;
  currentFps: number;
  currentTemp: number;
  currentCpuUsage: number;
  message: string;
  csvPath: string;
}

const CSV_COLUMNS = [
  'timestamp', 'elapsedMs',
  'cpuUsagePercent', 'systemCpuUsagePercent', 'cpuFreqsCsv', 'gpuFreqKHz',
  'pssMb', 'availableMemMb',
  'thermalLevel', 'batterySOC', 'batteryTemp', 'batteryCurrent', 'batteryVoltage',
  'fps', 'avgLatencyMs',
];

export class ExperimentRunner {
  protected config: ExperimentConfig;
  protected status: ExperimentProgress['status'] = 'idle';
  protected message: string = '';
  protected sampleCount: number = 0;
  protected elapsedMs: number = 0;
  protected currentFps: number = 0;
  protected currentTemp: number = 0;
  protected currentCpuUsage: number = 0;
  protected csvPath: string = '';

  protected sampleTimer: number = -1;
  protected startTime: number = 0;
  protected samples: ExperimentSample[] = [];
  protected inferenceTimes: number[] = [];
  protected expDir: string = '';
  protected csvInitialized: boolean = false;
  protected csvFd: number = -1;

  constructor(config: ExperimentConfig, filesDir: string) {
    this.config = config;
    this.expDir = `${filesDir}/experiments`;
  }

  get progress(): ExperimentProgress {
    return {
      status: this.status,
      elapsedMs: this.elapsedMs,
      sampleCount: this.sampleCount,
      currentFps: this.currentFps,
      currentTemp: this.currentTemp,
      currentCpuUsage: this.currentCpuUsage,
      message: this.message,
      csvPath: this.csvPath,
    };
  }

  getCsvColumns(): string[] {
    return CSV_COLUMNS;
  }

  getExtraColumns(): string[] {
    return [];
  }

  getCsvFileName(): string {
    return `experiment_${Date.now()}.csv`;
  }

  /** Override in subclass to run setup before sampling starts. */
  async onSetup(): Promise<void> {}

  /** Override in subclass to run per-tick work (e.g., one inference). Called before each sample. */
  async onTick(): Promise<void> {}

  /** Override in subclass for cleanup. */
  async onTeardown(): Promise<void> {}

  /** Override to add extra values to each CSV row. */
  getExtraValues(_sample: ExperimentSample): (string | number)[] {
    return [];
  }

  private async initCsv(): Promise<void> {
    if (this.csvInitialized) return;
    try {
      const mkdirResult = fileIo.mkdirSync(this.expDir, true);
    } catch (_) {}

    this.csvPath = `${this.expDir}/${this.getCsvFileName()}`;
    try {
      const file = await fileIo.open(this.csvPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      this.csvFd = file.fd;
      const allColumns = [...this.getCsvColumns(), ...this.getExtraColumns()];
      await fileIo.write(this.csvFd, allColumns.join(',') + '\n');
      this.csvInitialized = true;
      hilog.info(0x0000, TAG, 'CSV opened: %{public}s', this.csvPath);
    } catch (e) {
      hilog.error(0x0000, TAG, 'CSV init failed: %{public}s', JSON.stringify(e));
    }
  }

  private async writeCsvRow(sample: ExperimentSample): Promise<void> {
    if (this.csvFd < 0) return;
    try {
      const values: (string | number)[] = [
        sample.timestamp, sample.elapsedMs,
        sample.cpuUsagePercent.toFixed(2), sample.systemCpuUsagePercent.toFixed(2),
        sample.cpuFreqsCsv, sample.gpuFreqKHz,
        sample.pssMb.toFixed(2), sample.availableMemMb.toFixed(2),
        sample.thermalLevel, sample.batterySOC, sample.batteryTemp.toFixed(1),
        sample.batteryCurrent, sample.batteryVoltage,
        sample.fps.toFixed(2), sample.avgLatencyMs.toFixed(2),
        ...this.getExtraValues(sample),
      ];
      await fileIo.write(this.csvFd, values.join(',') + '\n');
    } catch (e) {
      hilog.error(0x0000, TAG, 'CSV write failed: %{public}s', JSON.stringify(e));
    }
  }

  private async closeCsv(): Promise<void> {
    if (this.csvFd >= 0) {
      try {
        await fileIo.close(this.csvFd);
        hilog.info(0x0000, TAG, 'CSV closed: %{public}d samples', this.sampleCount);
      } catch (e) {
        hilog.error(0x0000, TAG, 'CSV close failed: %{public}s', JSON.stringify(e));
      }
      this.csvFd = -1;
    }
  }

  async start(): Promise<void> {
    if (this.status === 'running') return;
    this.status = 'running';
    this.message = 'Initializing...';
    this.samples = [];
    this.inferenceTimes = [];
    this.sampleCount = 0;
    this.elapsedMs = 0;
    this.currentFps = 0;
    this.csvInitialized = false;

    await this.initCsv();
    await this.onSetup();

    this.startTime = Date.now();
    this.message = 'Running...';

    this.sampleTimer = setInterval(async () => {
      await this.captureSample();
    }, this.config.sampleIntervalMs) as number;

    if (this.config.durationMs > 0) {
      setTimeout(() => this.stop(), this.config.durationMs);
    }
  }

  private async captureSample(): Promise<void> {
    if (this.status !== 'running') return;
    this.elapsedMs = Date.now() - this.startTime;

    await this.onTick();

    const sample = MetricsCollector.captureSample(this.elapsedMs);

    if (this.inferenceTimes.length >= 2) {
      const recent = this.inferenceTimes.slice(-10);
      const totalTime = recent[recent.length - 1] - recent[0];
      if (totalTime > 0) {
        sample.fps = (recent.length / totalTime) * 1000;
        sample.avgLatencyMs = totalTime / recent.length;
      }
    }

    this.samples.push(sample);
    this.sampleCount = this.samples.length;
    this.currentFps = sample.fps;
    this.currentTemp = sample.batteryTemp;
    this.currentCpuUsage = sample.cpuUsagePercent;

    await this.writeCsvRow(sample);
  }

  protected recordInference(): void {
    this.inferenceTimes.push(Date.now());
  }

  async stop(): Promise<void> {
    if (this.status !== 'running') return;
    this.message = 'Stopping...';

    if (this.sampleTimer !== -1) {
      clearInterval(this.sampleTimer);
      this.sampleTimer = -1;
    }

    this.elapsedMs = Date.now() - this.startTime;
    const finalSample = MetricsCollector.captureSample(this.elapsedMs);
    await this.writeCsvRow(finalSample);
    this.sampleCount++;

    await this.onTeardown();
    await this.closeCsv();

    this.status = 'completed';
    this.message = `Done. ${this.sampleCount} samples, ${(this.elapsedMs / 1000).toFixed(0)}s`;
    hilog.info(0x0000, TAG, 'Experiment completed: %{public}d samples, %{public}d ms',
      this.sampleCount, this.elapsedMs);
  }

  async abort(): Promise<void> {
    this.status = 'failed';
    this.message = 'Aborted';
    if (this.sampleTimer !== -1) {
      clearInterval(this.sampleTimer);
      this.sampleTimer = -1;
    }
    await this.onTeardown();
    await this.closeCsv();
  }
}
