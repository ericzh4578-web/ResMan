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

import { mindSporeLite } from '@kit.MindSporeLiteKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog, hidebug } from '@kit.PerformanceAnalysisKit';
import { thermal, batteryInfo } from '@kit.BasicServicesKit';
import libentry from 'libentry.so';

import {
  YOLO_MODELS, MODEL_SHORT_NAMES, SystemStateDef, ExpProgress, getBatchSize,
} from './ExperimentTypes';
import { SystemStateManager } from './SystemStateManager';
import { SyntheticImageGenerator, DifficultyLevel, SynthImageConfig } from './SyntheticImageGenerator';

const TAG = 'BaseExpRunner';

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
    let cpuFreqsCsv: string = '';
    let gpuFreqKHz: number = 0;
    try {
      cpuFreqsCsv = libentry.readCpuFreqsCsv() || '';
      gpuFreqKHz = libentry.readGpuFreq() || 0;
    } catch (_) {}

    const systemMemInfo = hidebug.getSystemMemInfo();

    let sample: ExperimentSample = {
      timestamp: Date.now(),
      elapsedMs: elapsedMs,
      cpuUsagePercent: Math.max(0, hidebug.getCpuUsage()) * 100,
      systemCpuUsagePercent: hidebug.getSystemCpuUsage() * 100,
      cpuFreqsCsv: cpuFreqsCsv,
      gpuFreqKHz: gpuFreqKHz,
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
    return sample;
  }
}

export class BaseExperimentRunner {
  protected stateManager: SystemStateManager = new SystemStateManager();
  protected models: (mindSporeLite.Model | null)[] = [null, null, null, null];
  protected modelLoaded: boolean[] = [false, false, false, false];
  protected filesDir: string = '';
  protected expDir: string = '';
  protected csvFd: number = -1;
  protected csvPath: string = '';

  protected _status: string = 'idle';
  protected _phase: string = '';
  protected _elapsedMs: number = 0;
  protected _sampleCount: number = 0;
  protected _currentFps: number = 0;
  protected _currentTemp: number = 0;
  protected _currentCpu: number = 0;
  protected _currentEnergyMw: number = 0;
  protected _message: string = '';
  protected _csvPath: string = '';

  protected running: boolean = false;
  protected startTime: number = 0;

  protected context: common.UIAbilityContext | null = null;

  get progress(): ExpProgress {
    let p: ExpProgress = {
      status: this._status,
      phase: this._phase,
      elapsedMs: this._elapsedMs,
      sampleCount: this._sampleCount,
      currentFps: this._currentFps,
      currentTemp: this._currentTemp,
      currentCpu: this._currentCpu,
      currentEnergyMw: this._currentEnergyMw,
      message: this._message,
      csvPath: this._csvPath,
    };
    return p;
  }

  init(context: common.UIAbilityContext): void {
    this.context = context;
    this.filesDir = context.filesDir;
    this.expDir = this.filesDir + '/experiments2';
    try { fileIo.mkdirSync(this.expDir, true); } catch (_) {}
  }

  async loadModel(modelIndex: number): Promise<boolean> {
    if (this.modelLoaded[modelIndex]) return true;
    if (this.context === null) return false;

    const modelName = YOLO_MODELS[modelIndex];
    try {
      const modelBuffer = await this.context.resourceManager.getRawFileContent(modelName);
      let msCtx: mindSporeLite.Context = {
        target: ['nnrt'],
        nnrt: { performanceMode: 3 },
      } as mindSporeLite.Context;
      const model = await mindSporeLite.loadModelFromBuffer(modelBuffer.buffer.slice(0), msCtx);
      this.models[modelIndex] = model;
      this.modelLoaded[modelIndex] = true;
      hilog.info(0x0000, TAG, 'Loaded %{public}s', modelName);
      return true;
    } catch (e) {
      hilog.error(0x0000, TAG, 'Failed to load %{public}s: %{public}s', modelName, JSON.stringify(e));
      return false;
    }
  }

  async loadAllModels(): Promise<boolean> {
    for (let i = 0; i < YOLO_MODELS.length; i++) {
      const ok = await this.loadModel(i);
      if (!ok) return false;
    }
    return true;
  }

  getModel(index: number): mindSporeLite.Model | null {
    if (index < 0 || index >= this.models.length) return null;
    return this.models[index];
  }

  protected getEnergyMw(sample: ExperimentSample): number {
    return sample.batteryCurrent * sample.batteryVoltage / 1000;
  }

  // ── CSV helpers ──

  async openCsv(fileName: string, columns: string[]): Promise<void> {
    if (this.csvFd >= 0) await this.closeCsv();
    this._csvPath = this.expDir + '/' + fileName;
    this.csvPath = this._csvPath;
    try {
      const file = await fileIo.open(this._csvPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      this.csvFd = file.fd;
      await fileIo.write(this.csvFd, columns.join(',') + '\n');
    } catch (e) {
      hilog.error(0x0000, TAG, 'CSV open failed: %{public}s', JSON.stringify(e));
    }
  }

  async writeCsvRow(values: (string | number)[]): Promise<void> {
    if (this.csvFd < 0) return;
    try {
      await fileIo.write(this.csvFd, values.join(',') + '\n');
    } catch (e) {
      hilog.error(0x0000, TAG, 'CSV write failed: %{public}s', JSON.stringify(e));
    }
  }

  async closeCsv(): Promise<void> {
    if (this.csvFd >= 0) {
      try { await fileIo.close(this.csvFd); } catch (_) {}
      this.csvFd = -1;
    }
  }

  // ── Progress helpers ──

  protected updateProgress(): void {
    this._elapsedMs = Date.now() - this.startTime;
    try {
      this._currentTemp = (batteryInfo.batteryTemperature as number) / 10.0;
    } catch (_) {}
    try {
      this._currentCpu = Math.max(0, hidebug.getCpuUsage()) * 100;
    } catch (_) {}
  }

  // ── Lifecycle ──

  releaseModels(): void {
    for (let i = 0; i < this.models.length; i++) {
      this.models[i] = null;
      this.modelLoaded[i] = false;
    }
  }

  abort(): void {
    this.running = false;
    this._status = 'failed';
    this.stateManager.stopAll();
    this.releaseModels();
    this.closeCsv();
  }

  cleanup(): void {
    this.running = false;
    this.stateManager.stopAll();
    this.releaseModels();
    this.closeCsv();
  }
}
