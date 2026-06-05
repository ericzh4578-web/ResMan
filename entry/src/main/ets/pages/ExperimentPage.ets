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
import { fileIo } from '@kit.CoreFileKit';
import { TitleComponent } from '../view/TitleComponent';
import { ExperimentRunner, ExperimentSample, MetricsCollector } from '../utils/ExperimentRunner';

const TAG = 'ExperimentPage';

// ── Model lists ──
const YOLO_MODELS: string[] = [
  'yolov8n_bsz4.ms',
  'yolov8s_bsz4.ms',
  'yolov8m_bsz4.ms',
  'yolov8l_bsz4.ms',
];

const CPU_LEVELS: string[] = ['0%', '25%', '50%', '75%', '100%'];
const MEM_LEVELS: string[] = ['10%', '15%', '20%', '25%'];
const IO_LEVELS: string[] = ['Weak', 'Medium', 'Strong'];

interface SelectOption { value: string; }

function toSelectOptions(arr: string[]): SelectOption[] {
  let result: SelectOption[] = [];
  for (let i = 0; i < arr.length; i++) {
    result.push({ value: arr[i] } as SelectOption);
  }
  return result;
}

// ── Context definitions (Exp 2) ──
interface ContextDef {
  name: string;
  cpuLevel: number;
  memLevel: number;
  ioLevel: number;
}

const CONTEXTS: ContextDef[] = [
  { name: 'Idle',           cpuLevel: 0, memLevel: -1, ioLevel: -1 },
  { name: 'Meeting',        cpuLevel: 2, memLevel: -1, ioLevel: -1 },
  { name: 'Video',          cpuLevel: 0, memLevel: -1, ioLevel: 1 },
  { name: 'Game',           cpuLevel: 3, memLevel: 1,  ioLevel: -1 },
  { name: 'Navigation',     cpuLevel: 1, memLevel: 0,  ioLevel: 0 },
];

// ── Profile definitions (Exp 3) ──
const SRDC_PROFILES: ContextDef[] = [
  { name: 'Idle-baseline',   cpuLevel: 0, memLevel: -1, ioLevel: -1 },
  { name: 'CPU-bound',       cpuLevel: 2, memLevel: -1, ioLevel: -1 },
  { name: 'IO-bound',        cpuLevel: 0, memLevel: -1, ioLevel: 2 },
  { name: 'Mixed-load',      cpuLevel: 1, memLevel: 1,  ioLevel: 1 },
];

interface SrResultEntry {
  profile: string;
  avgFps: number;
  avgCpu: number;
  avgTemp: number;
  sampleCount: number;
  csvFile: string;
}

// ──────────────────────────────────────────────────────────────────────────────
// ExperimentPage
// ──────────────────────────────────────────────────────────────────────────────

@Component
export struct ExperimentPage {
  @Consume('pageInfos') pageInfos: NavPathStack;

  // ── Tab state ──
  @State currentTabIndex: number = 0;
  private tabTitles: string[] = ['Capacity Curve', 'Context Impact', 'Same Res Diff Cap'];

  // ── Shared experiment state ──
  @State expStatus: string = 'Idle';
  @State expMessage: string = '';
  @State expElapsedSec: number = 0;
  @State expSampleCount: number = 0;
  @State expFps: number = 0;
  @State expTotalInferences: number = 0;
  @State expThroughput: number = 0;
  @State expCpuUsage: number = 0;
  @State expSystemCpu: number = 0;
  @State expPssMb: string = '-';
  @State expAvailMemMb: string = '-';
  @State expTemp: number = 0;
  @State expThermal: number = 0;
  @State expBatterySOC: number = 0;
  @State expBatteryCurrent: number = 0;
  @State expCpuFreqs: string = '';
  @State expCsvPath: string = '';
  @State expRunning: boolean = false;

  private inferCounter: number = 0;
  private inferBatchSize: number = 1;

  // ── Exp1 state ──
  @State e1Model: string = YOLO_MODELS[2];
  @State e1DurationMin: number = 30;
  @State e1Status: string = 'Idle';

  // ── Exp1 auto-run state ──
  @State e1AutoRunning: boolean = false;
  @State e1AutoModelIndex: number = -1;
  @State e1AutoPhase: string = '';
  @State e1AutoResults: string = '';
  @State e1TargetTemp: number = 36;

  // ── Exp2 state ──
  @State e2Context: ContextDef = CONTEXTS[0];
  @State e2Model: string = YOLO_MODELS[2];
  @State e2DurationMin: number = 10;
  @State e2Phase: string = 'Idle';
  @State e2PhaseRemainSec: number = 0;
  @State e2Results: string = '';

  // ── Exp3 state ──
  @State e3Model: string = YOLO_MODELS[2];
  @State e3DurationMin: number = 5;
  @State e3Phase: string = 'Idle';
  @State e3CurrentProfile: string = '';
  @State e3ProfileIndex: number = -1;
  @State e3Results: string = '';
  @State e3Running: boolean = false;

  // ── Internal ──
  private modelOptions: SelectOption[] = toSelectOptions(YOLO_MODELS);
  private contextOptions: SelectOption[] = toSelectOptions(CONTEXTS.map(c => c.name));
  private pollTimer: number = -1;
  private model: mindSporeLite.Model | null = null;
  private expRunner: ExperimentRunner | null = null;
  private inferTimer: number = -1;

  private get yoloIndex(): number {
    const i = YOLO_MODELS.indexOf(this.e1Model);
    return i >= 0 ? i : 0;
  }
  private get e2ModelIndex(): number {
    const i = YOLO_MODELS.indexOf(this.e2Model);
    return i >= 0 ? i : 0;
  }
  private get e3ModelIndex(): number {
    const i = YOLO_MODELS.indexOf(this.e3Model);
    return i >= 0 ? i : 0;
  }
  private get e2CtxIndex(): number {
    const i = CONTEXTS.findIndex(c => c.name === this.e2Context.name);
    return i >= 0 ? i : 0;
  }

  private getBatchSize(modelName: string): number {
    const m = modelName.match(/_bsz(\d+)/);
    return m ? parseInt(m[1]) : 1;
  }

  private generateRandomInput(batchSize: number): ArrayBuffer {
    const totalFloats = 640 * 640 * 3 * batchSize;
    const buf = new Float32Array(totalFloats);
    for (let i = 0; i < totalFloats; i++) { buf[i] = Math.random(); }
    return buf.buffer;
  }

  private stopAllSimulators(): void {
    try { libentry.stopCpuLoad(); libentry.stopMemoryLoad(); libentry.stopIoLoad(); } catch (_) {}
  }

  private applyContext(ctx: ContextDef): void {
    this.stopAllSimulators();
    if (ctx.cpuLevel > 0) { try { libentry.startCpuLoad(ctx.cpuLevel); } catch (_) {} }
    if (ctx.memLevel >= 0) { try { libentry.startMemoryLoad(ctx.memLevel); } catch (_) {} }
    if (ctx.ioLevel >= 0) {
      try { libentry.startIoLoad(ctx.ioLevel, (getContext(this) as common.UIAbilityContext).filesDir); } catch (_) {}
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Model loading
  // ──────────────────────────────────────────────────────────────────────────

  private async loadYoloModel(modelName: string): Promise<mindSporeLite.Model> {
    const ctx = getContext(this) as common.UIAbilityContext;
    const rm = ctx.resourceManager;
    const modelBuffer = await rm.getRawFileContent(modelName);
    const msCtx: mindSporeLite.Context = {
      target: ['nnrt'],
      nnrt: { performanceMode: 3 }
    } as mindSporeLite.Context;
    const m = await mindSporeLite.loadModelFromBuffer(modelBuffer.buffer.slice(0), msCtx);
    hilog.info(0x0000, TAG, 'Model loaded: %{public}s', modelName);
    return m;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Polling
  // ──────────────────────────────────────────────────────────────────────────

  startPolling(): void {
    if (this.pollTimer !== -1) return;
    this.pollTimer = setInterval(() => {
      try {
        this.expCpuUsage = Math.max(0, hidebug.getCpuUsage()) * 100;
        this.expSystemCpu = hidebug.getSystemCpuUsage() * 100;
        this.expTemp = batteryInfo.batteryTemperature as number / 10.0;
        this.expThermal = thermal.getThermalLevel();
        this.expBatterySOC = batteryInfo.batterySOC;
        this.expBatteryCurrent = batteryInfo.nowCurrent;
        this.expPssMb = (Number(hidebug.getPss()) / 1024).toFixed(1) + ' MB';
        const mem = hidebug.getSystemMemInfo();
        this.expAvailMemMb = (Number(mem.availableMem) / 1024).toFixed(0) + ' MB';
        try { this.expCpuFreqs = libentry.readCpuFreqsCsv() || ''; } catch (_) {}
      } catch (_) {}
    }, 1000) as number;
  }

  stopPolling(): void {
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Cooldown helper — wait until battery temp drops below target
  // ──────────────────────────────────────────────────────────────────────────

  private getDeviceTemp(): number {
    return batteryInfo.batteryTemperature as number / 10.0;
  }

  private async waitForCooldown(targetTemp: number, timeoutSec: number): Promise<boolean> {
    const deadline = Date.now() + timeoutSec * 1000;
    while (Date.now() < deadline) {
      let temp = this.getDeviceTemp();
      if (temp <= targetTemp) {
        return true;
      }
      this.e1Status = `Cooling: ${temp.toFixed(1)}°C → target ${targetTemp}°C...`;
      await new Promise<void>(r => setTimeout(r, 2000));
    }
    return false;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Exp 1: Capacity Curve (single model)
  // ──────────────────────────────────────────────────────────────────────────

  private async runExp1(modelOverride?: string): Promise<void> {
    if (this.expRunning) return;
    this.expRunning = true;
    const modelName = modelOverride || this.e1Model;
    this.e1Status = `Loading ${modelName}...`;
    this.expStatus = 'Loading';
    this.expSampleCount = 0;
    this.expTotalInferences = 0;
    this.expCsvPath = '';

    try {
      this.model = await this.loadYoloModel(modelName);
      const bs = this.getBatchSize(modelName);
      this.inferCounter = 0;
      this.inferBatchSize = bs;
      const durationMs = this.e1DurationMin * 60 * 1000;
      const expDir = `${(getContext(this) as common.UIAbilityContext).filesDir}/experiments`;

      try { fileIo.mkdirSync(expDir, true); } catch (_) {}
      const csvFile = `capacity_curve_${modelName.replace('.ms', '')}_${Date.now()}.csv`;
      this.expCsvPath = `${expDir}/${csvFile}`;

      let fd = -1;
      try {
        const f = await fileIo.open(this.expCsvPath,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        fd = f.fd;
        const cols = 'timestamp,elapsedMs,fps,avgLatencyMs,cpuUsagePercent,systemCpuUsagePercent,' +
          'cpuFreqsCsv,gpuFreqKHz,pssMb,availableMemMb,' +
          'thermalLevel,batterySOC,batteryTemp,batteryCurrent,batteryVoltage,throughput\n';
        await fileIo.write(fd, cols);
      } catch (e) {
        this.e1Status = `CSV error: ${JSON.stringify(e)}`;
        this.expRunning = false;
        return;
      }

      this.e1Status = 'Running...';
      this.expStatus = 'Running';
      this.startPolling();

      const startTime = Date.now();
      let rowCount = 0;
      const inferenceTimes: number[] = [];
      let intervalId = setInterval(async () => {
        const elapsed = Date.now() - startTime;
        if (elapsed >= durationMs || !this.expRunning) {
          clearInterval(intervalId);

          // Final sample
          const finalSample = MetricsCollector.captureSample(elapsed);
          this.expSampleCount = rowCount + 1;
          this.expElapsedSec = Math.floor(elapsed / 1000);
          try { await fileIo.write(fd, this.buildExp1Row(finalSample, inferenceTimes, modelName)); } catch (_) {}
          try { await fileIo.close(fd); } catch (_) {}

          this.e1Status = `Done. ${this.expSampleCount} samples, ${this.expTotalInferences} infers, ${(elapsed / 60000).toFixed(1)}min`;
          this.expStatus = 'Done';
          this.expRunning = false;
          this.stopPolling();
          hilog.info(0x0000, TAG, 'Exp1 done: %{public}d rows → %{public}s', rowCount + 1, this.expCsvPath);
          return;
        }

        try {
          const inputs = this.model!.getInputs();
          inputs[0].setData(this.generateRandomInput(bs));
          await this.model!.predict(inputs);
          inferenceTimes.push(Date.now());
          this.inferCounter++;
          this.expTotalInferences = this.inferCounter;
        } catch (_) {}

        const sample = MetricsCollector.captureSample(elapsed);
        this.expFps = sample.fps;
        this.expThroughput = this.expFps * this.inferBatchSize;
        this.expElapsedSec = Math.floor(elapsed / 1000);
        rowCount++;
        this.expSampleCount = rowCount;

        if (inferenceTimes.length >= 2) {
          const recent = inferenceTimes.slice(-10);
          const dt = recent[recent.length - 1] - recent[0];
          if (dt > 0) {
            sample.fps = (recent.length / dt) * 1000;
            sample.avgLatencyMs = dt / recent.length;
          }
        }

        try { await fileIo.write(fd, this.buildExp1Row(sample, inferenceTimes, modelName)); } catch (_) {}
      }, 1000) as number;
    } catch (e) {
      this.e1Status = `Failed: ${JSON.stringify(e)}`;
      this.expRunning = false;
      this.expStatus = 'Failed';
    }
  }

  private buildExp1Row(sample: ExperimentSample, _times: number[], modelName: string): string {
    return [
      sample.timestamp, sample.elapsedMs,
      sample.fps.toFixed(2), sample.avgLatencyMs.toFixed(2),
      sample.cpuUsagePercent.toFixed(2), sample.systemCpuUsagePercent.toFixed(2),
      sample.cpuFreqsCsv, sample.gpuFreqKHz,
      sample.pssMb.toFixed(2), sample.availableMemMb.toFixed(2),
      sample.thermalLevel, sample.batterySOC, sample.batteryTemp.toFixed(1),
      sample.batteryCurrent, sample.batteryVoltage,
      sample.fps > 0 ? (sample.fps * this.getBatchSize(modelName)).toFixed(2) : '0',
    ].join(',') + '\n';
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Exp 1: Auto-run all models (n → s → m → l) with cooldown between each
  // ──────────────────────────────────────────────────────────────────────────

  private async autoRunAllModels(): Promise<void> {
    if (this.e1AutoRunning) return;
    this.e1AutoRunning = true;
    this.e1AutoResults = '';
    const models = YOLO_MODELS;
    const rows: string[] = [];

    for (let i = 0; i < models.length; i++) {
      if (!this.e1AutoRunning) break;
      const m = models[i];
      this.e1AutoModelIndex = i;
      this.e1AutoPhase = `Cooldown → ${this.e1TargetTemp}°C`;

      // Step 1: wait for device to cool to target temp
      const cooled = await this.waitForCooldown(this.e1TargetTemp, 600);
      if (!cooled) {
        this.e1AutoPhase = `Warning: temp still above ${this.e1TargetTemp}°C, starting anyway`;
        await new Promise<void>(r => setTimeout(r, 3000));
      }

      // Step 2: run capacity curve for this model
      this.e1AutoPhase = `Running ${m} (${i + 1}/${models.length})`;
      await this.runExp1(m);

      // Wait for runExp1 to finish (it sets expRunning=false when done)
      while (this.expRunning) {
        await new Promise<void>(r => setTimeout(r, 1000));
      }

      const temp = this.getDeviceTemp();
      const row = `${m} | ${this.expFps.toFixed(2)} fps | ${this.expCpuUsage.toFixed(1)}% CPU | ${temp.toFixed(1)}°C | ${this.expCsvPath}`;
      rows.push(row);
      this.e1AutoResults = rows.join('\n');

      // Step 3: brief pause before next model
      if (i < models.length - 1) {
        this.e1AutoPhase = `Pause before next model...`;
        await new Promise<void>(r => setTimeout(r, 5000));
      }
    }

    this.e1AutoPhase = 'Done';
    this.e1AutoModelIndex = -1;
    this.e1AutoRunning = false;
    this.expRunning = false;
    this.stopPolling();
  }

  private async runExp2(): Promise<void> {
    if (this.expRunning) return;
    this.expRunning = true;
    this.e2Phase = 'Loading model...';
    this.expStatus = 'Loading';
    this.e2Results = '';
    this.expSampleCount = 0;

    try {
      this.model = await this.loadYoloModel(this.e2Model);
      const bs = this.getBatchSize(this.e2Model);
      const ctx = this.e2Context;

      // Phase 1: Apply context + stabilize
      this.e2Phase = `Stabilizing (${ctx.name})...`;
      this.expStatus = 'Stabilizing';
      this.applyContext(ctx);
      this.e2PhaseRemainSec = 60;
      const stabilizeInterval = setInterval(() => {
        this.e2PhaseRemainSec--;
        if (this.e2PhaseRemainSec <= 0) clearInterval(stabilizeInterval);
      }, 1000);
      await new Promise<void>(resolve => setTimeout(resolve, 60000));

      // Phase 2: Run inference + log
      this.e2Phase = `Running (${ctx.name})...`;
      this.expStatus = 'Running';
      const durationMs = this.e2DurationMin * 60 * 1000;
      const expDir = `${(getContext(this) as common.UIAbilityContext).filesDir}/experiments`;
      try { fileIo.mkdirSync(expDir, true); } catch (_) {}
      const csvFile = `context_impact_${ctx.name.toLowerCase()}_${Date.now()}.csv`;
      this.expCsvPath = `${expDir}/${csvFile}`;

      let fd = -1;
      try {
        const f = await fileIo.open(this.expCsvPath,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        fd = f.fd;
        const cols = 'timestamp,elapsedMs,context,fps,avgLatencyMs,cpuUsagePercent,systemCpuUsagePercent,' +
          'cpuFreqsCsv,gpuFreqKHz,pssMb,availableMemMb,' +
          'thermalLevel,batterySOC,batteryTemp,batteryCurrent,batteryVoltage\n';
        await fileIo.write(fd, cols);
      } catch (e) {
        this.e2Phase = `CSV error: ${JSON.stringify(e)}`;
        this.expRunning = false;
        this.stopAllSimulators();
        return;
      }

      this.startPolling();
      const startTime = Date.now();
      let rowCount = 0;
      this.inferCounter = 0;
      this.expTotalInferences = 0;

      const intervalId = setInterval(async () => {
        const elapsed = Date.now() - startTime;
        if (elapsed >= durationMs || !this.expRunning) {
          clearInterval(intervalId);
          if (fd >= 0) try { await fileIo.close(fd); } catch (_) {}

          this.stopAllSimulators();
          this.e2Phase = `Done (${ctx.name})`;
          this.expStatus = 'Done';
          this.expRunning = false;
          this.stopPolling();
          this.e2Results = `Context: ${ctx.name}\nModel: ${this.e2Model}\nInfers: ${this.inferCounter}\nSamples: ${rowCount}\nCSV: ${csvFile}`;
          return;
        }

        try {
          const inputs = this.model!.getInputs();
          inputs[0].setData(this.generateRandomInput(bs));
          await this.model!.predict(inputs);
          this.inferCounter++;
          this.expTotalInferences = this.inferCounter;
        } catch (_) {}

        const sample = MetricsCollector.captureSample(elapsed);
        this.expElapsedSec = Math.floor(elapsed / 1000);
        if (this.expElapsedSec > 0) {
          this.expFps = this.inferCounter / this.expElapsedSec;
        }
        this.expThroughput = this.expFps * this.inferBatchSize;
        rowCount++;
        this.expSampleCount = rowCount;

        try {
          const row = [
            sample.timestamp, sample.elapsedMs, ctx.name,
            this.expFps.toFixed(2), '0',
            sample.cpuUsagePercent.toFixed(2), sample.systemCpuUsagePercent.toFixed(2),
            sample.cpuFreqsCsv, sample.gpuFreqKHz,
            sample.pssMb.toFixed(2), sample.availableMemMb.toFixed(2),
            sample.thermalLevel, sample.batterySOC, sample.batteryTemp.toFixed(1),
            sample.batteryCurrent, sample.batteryVoltage,
          ].join(',') + '\n';
          await fileIo.write(fd, row);
        } catch (_) {}
      }, 1000) as number;
    } catch (e) {
      this.e2Phase = `Failed: ${JSON.stringify(e)}`;
      this.expRunning = false;
      this.expStatus = 'Failed';
      this.stopAllSimulators();
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Exp 3: Same Resource Different Capacity
  // ──────────────────────────────────────────────────────────────────────────

  private async runExp3(): Promise<void> {
    if (this.e3Running) return;
    this.e3Running = true;
    this.expRunning = true;
    this.e3Results = '';
    this.expCsvPath = '';

    try {
      this.model = await this.loadYoloModel(this.e3Model);
    } catch (e) {
      this.e3Phase = `Model load failed: ${JSON.stringify(e)}`;
      this.e3Running = false;
      this.expRunning = false;
      return;
    }

    const bs = this.getBatchSize(this.e3Model);
    const durationMs = this.e3DurationMin * 60 * 1000;
    const filesDir = (getContext(this) as common.UIAbilityContext).filesDir;
    const expDir = `${filesDir}/experiments`;
    try { fileIo.mkdirSync(expDir, true); } catch (_) {}

    let allResults: SrResultEntry[] = [];

    for (let pi = 0; pi < SRDC_PROFILES.length; pi++) {
      if (!this.e3Running) break;
      const profile = SRDC_PROFILES[pi];
      this.e3ProfileIndex = pi;
      this.e3CurrentProfile = profile.name;
      this.e3Phase = `Stabilizing (${profile.name})...`;
      this.expStatus = 'Stabilizing';

      // Apply context
      this.applyContext(profile);
      this.e2PhaseRemainSec = 60;
      const stabilizeInterval = setInterval(() => {
        this.e2PhaseRemainSec--;
        if (this.e2PhaseRemainSec <= 0) clearInterval(stabilizeInterval);
      }, 1000);
      await new Promise<void>(resolve => setTimeout(resolve, 60000));

      // Run inference with logging
      this.e3Phase = `Running (${profile.name})...`;
      this.expStatus = 'Running';
      const csvFile = `srdc_${profile.name.toLowerCase()}_${Date.now()}.csv`;
      const csvPath = `${expDir}/${csvFile}`;

      let fd = -1;
      try {
        const f = await fileIo.open(csvPath,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        fd = f.fd;
        const cols = 'timestamp,elapsedMs,profile,fps,avgLatencyMs,cpuUsagePercent,systemCpuUsagePercent,' +
          'cpuFreqsCsv,gpuFreqKHz,pssMb,availableMemMb,' +
          'thermalLevel,batterySOC,batteryTemp,batteryCurrent,batteryVoltage\n';
        await fileIo.write(fd, cols);
      } catch (e) {
        continue;
      }

      this.startPolling();
      const startTime = Date.now();
      let rowCount = 0;
      this.inferCounter = 0;
      this.expTotalInferences = 0;
      let fpsSum = 0;
      let cpuSum = 0;
      let tempSum = 0;
      let metricCount = 0;

      await new Promise<void>((resolve) => {
        const intervalId = setInterval(async () => {
          const elapsed = Date.now() - startTime;
          if (elapsed >= durationMs || !this.e3Running) {
            clearInterval(intervalId);
            if (fd >= 0) try { await fileIo.close(fd); } catch (_) {}
            this.stopAllSimulators();
            let entry: SrResultEntry = {
              profile: profile.name,
              avgFps: metricCount > 0 ? fpsSum / metricCount : 0,
              avgCpu: metricCount > 0 ? cpuSum / metricCount : 0,
              avgTemp: metricCount > 0 ? tempSum / metricCount : 0,
              sampleCount: rowCount,
              csvFile: csvFile,
            };
            allResults.push(entry);
            resolve();
            return;
          }

          try {
            const inputs = this.model!.getInputs();
            inputs[0].setData(this.generateRandomInput(bs));
            await this.model!.predict(inputs);
            this.inferCounter++;
            this.expTotalInferences = this.inferCounter;
          } catch (_) {}

          const sample = MetricsCollector.captureSample(elapsed);
          this.expFps = sample.fps;
          this.expThroughput = this.expFps * this.inferBatchSize;
          this.expElapsedSec = Math.floor(elapsed / 1000);
          rowCount++;
          this.expSampleCount = rowCount;

          if (this.inferCounter >= 2) {
            sample.fps = this.expFps;
          }

          fpsSum += sample.fps;
          cpuSum += sample.cpuUsagePercent;
          tempSum += sample.batteryTemp;
          metricCount++;

          try {
            const row = [
              sample.timestamp, sample.elapsedMs, profile.name,
              sample.fps.toFixed(2), sample.avgLatencyMs.toFixed(2),
              sample.cpuUsagePercent.toFixed(2), sample.systemCpuUsagePercent.toFixed(2),
              sample.cpuFreqsCsv, sample.gpuFreqKHz,
              sample.pssMb.toFixed(2), sample.availableMemMb.toFixed(2),
              sample.thermalLevel, sample.batterySOC, sample.batteryTemp.toFixed(1),
              sample.batteryCurrent, sample.batteryVoltage,
            ].join(',') + '\n';
            await fileIo.write(fd, row);
          } catch (_) {}
        }, 1000) as number;
      });
    }

    this.stopPolling();
    this.stopAllSimulators();
    this.e3Running = false;
    this.expRunning = false;
    this.e3Phase = 'Done';
    this.expStatus = 'Done';

    // Build comparison
    let report = '=== Same Resource, Different Capacity ===\n\n';
    report += 'Profile | Avg FPS | Avg CPU% | Avg Temp°C | Samples\n';
    report += '--------|---------|---------|-----------|--------\n';
    for (const r of allResults) {
      report += `${r.profile} | ${r.avgFps.toFixed(2)} | ${r.avgCpu.toFixed(2)}% | ${r.avgTemp.toFixed(1)}°C | ${r.sampleCount}\n`;
    }
    report += '\nKey insight: Similar resource snapshots do NOT predict future FPS.\n';
    report += 'The profile (Context) determines sustainable compute capacity.\n';

    this.e3Results = report;
    this.expSampleCount = allResults.reduce((s, r) => s + r.sampleCount, 0);
    hilog.info(0x0000, TAG, 'Exp3 done: %{public}s', report);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────────────

  aboutToAppear(): void {
    this.startPolling();
  }

  aboutToDisappear(): void {
    this.expRunning = false;
    this.e3Running = false;
    this.stopPolling();
    this.stopAllSimulators();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // UI Builders
  // ──────────────────────────────────────────────────────────────────────────

  @Builder
  sectionTitle(t: string): void {
    Text(t)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .width('100%')
  }

  @Builder
  statusBar(): void {
    Column({ space: 3 }) {
      // Row 1: Status + experiment summary
      Row() {
        Text(`Status: ${this.expStatus}`)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.expRunning ? '#007DFF' : '#333')
          .layoutWeight(1)
        Text(`Infers: ${this.expTotalInferences}`)
          .fontSize(12)
          .fontColor(this.expTotalInferences > 0 ? '#007DFF' : '#666')
          .layoutWeight(1)
        Text(`FPS: ${this.expFps.toFixed(2)}`)
          .fontSize(12)
          .fontColor(this.expFps > 0 ? '#007DFF' : '#666')
          .layoutWeight(1)
        Text(`Thru: ${this.expThroughput.toFixed(1)} img/s`)
          .fontSize(12)
          .fontColor('#666')
          .layoutWeight(1)
      }.width('100%')

      // Row 2: CPU + Temperature + Time
      Row() {
        Text(`Samples: ${this.expSampleCount}`)
          .fontSize(12)
          .fontColor('#666')
          .layoutWeight(1)
        Text(`Time: ${this.expElapsedSec}s`)
          .fontSize(12)
          .fontColor('#666')
          .layoutWeight(1)
        Text(`CPU: ${this.expCpuUsage.toFixed(1)}%`)
          .fontSize(12)
          .layoutWeight(1)
        Text(`Temp: ${this.expTemp.toFixed(1)}°C`)
          .fontSize(12)
          .fontColor(this.expTemp > 40 ? '#C62828' : '#333')
          .layoutWeight(1)
      }.width('100%')

      // Row 3: Memory + Battery
      Row() {
        Text(`PSS: ${this.expPssMb}`)
          .fontSize(12)
          .layoutWeight(1)
        Text(`Avail: ${this.expAvailMemMb}`)
          .fontSize(12)
          .layoutWeight(1)
        Text(`Bat: ${this.expBatterySOC}%`)
          .fontSize(12)
          .layoutWeight(1)
        Text(`${this.expBatteryCurrent}mA`)
          .fontSize(12)
          .layoutWeight(1)
      }.width('100%')

      // Row 4: CPU Freqs (compact)
      if (this.expCpuFreqs.length > 0) {
        Text(`Freqs: ${this.expCpuFreqs}`)
          .fontSize(10)
          .fontColor('#888')
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      // Row 5: CSV path
      if (this.expCsvPath.length > 0) {
        Text(`CSV: ${this.expCsvPath}`)
          .fontSize(10)
          .fontColor('#888')
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding(8)
    .backgroundColor('#EEF6FF')
    .borderRadius(6)
  }

  // ── Tab 1: Capacity Curve ──
  @Builder
  tab1CapacityCurve(): void {
    Column({ space: 12 }) {
      this.sectionTitle('Experiment 1: Sustainable Compute Capacity Characterization')
      Text('Purpose: Prove that Peak FPS ≠ long-term sustainable FPS.\n'
        + 'Runs continuous YOLO inference for N minutes, records FPS/Temp/CPU every second.')
        .fontSize(11)
        .fontColor('#666')
        .width('100%')

      Column({ space: 4 }) {
        Text('Model').fontSize(12).fontWeight(FontWeight.Medium).width('100%')
        Select(this.modelOptions)
          .width('100%')
          .height(36)
          .selected(this.yoloIndex)
          .onSelect((idx: number) => { this.e1Model = YOLO_MODELS[idx]; })
      }.width('100%')

      Column({ space: 4 }) {
        Text(`Duration: ${this.e1DurationMin} minutes`).fontSize(12).fontWeight(FontWeight.Medium).width('100%')
        Slider({
          value: this.e1DurationMin,
          min: 1,
          max: 60,
          step: 1,
          style: SliderStyle.InSet
        })
          .width('100%')
          .onChange((v: number) => { this.e1DurationMin = v; })
      }.width('100%')

      Row({ space: 8 }) {
        Button(this.expRunning ? 'Running...' : 'Start Exp 1')
          .layoutWeight(1)
          .fontWeight(500)
          .fontSize(14)
          .enabled(!this.expRunning && !this.e1AutoRunning)
          .onClick(() => { this.runExp1(); })
        Button('Stop')
          .layoutWeight(1)
          .fontWeight(500)
          .fontSize(14)
          .enabled(this.expRunning || this.e1AutoRunning)
          .backgroundColor('#C62828')
          .onClick(() => {
            this.expRunning = false;
            this.e1AutoRunning = false;
            this.stopPolling();
          })
      }.width('100%')

      Text(`Phase: ${this.e1Status}`)
        .fontSize(12)
        .fontColor(this.e1Status.startsWith('Done') ? '#4CAF50' : '#333')
        .width('100%')

      Divider().margin({ top: 8, bottom: 8 })

      // ── Auto-run all models ──
      this.sectionTitle('One-click: Measure All Models (n→s→m→l)')

      Column({ space: 4 }) {
        Text(`Target temp before start: ${this.e1TargetTemp.toFixed(1)}°C`)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .width('100%')
        Slider({
          value: this.e1TargetTemp,
          min: 30,
          max: 45,
          step: 0.5,
          style: SliderStyle.InSet
        })
          .width('100%')
          .onChange((v: number) => { this.e1TargetTemp = v; })
      }.width('100%')

      Text('Auto-control: waits for device to cool to target temp before each model.\n'
        + `Will run ${YOLO_MODELS.length} models (${YOLO_MODELS.join(', ')}), `
        + `${this.e1DurationMin} min each.`)
        .fontSize(11)
        .fontColor('#666')
        .width('100%')

      Button(this.e1AutoRunning ? `Running ${this.e1AutoPhase}` : `Run All ${YOLO_MODELS.length} Models (n→l)`)
        .width('100%')
        .fontWeight(500)
        .fontSize(14)
        .enabled(!this.expRunning && !this.e1AutoRunning)
        .backgroundColor('#4CAF50')
        .onClick(() => { this.autoRunAllModels(); })

      if (this.e1AutoResults.length > 0) {
        Column({ space: 4 }) {
          Text('Results:')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .width('100%')
          Text(this.e1AutoResults)
            .fontSize(10)
            .fontColor('#333')
            .width('100%')
            .fontFamily('monospace')
        }
        .width('100%')
        .padding(8)
        .backgroundColor('#E8F5E9')
        .borderRadius(4)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FAFAFA')
    .borderRadius(8)
  }

  // ── Tab 2: Context Impact ──
  @Builder
  tab2ContextImpact(): void {
    Column({ space: 12 }) {
      this.sectionTitle('Experiment 2: Context Impact Study')
      Text('Purpose: Same model (YOLOv8m) across different simulated contexts.\n'
        + 'Uses ResourceSimulator to emulate Meeting/Video/Game/Navigation loads.')
        .fontSize(11)
        .fontColor('#666')
        .width('100%')

      Column({ space: 4 }) {
        Text('Simulated Context').fontSize(12).fontWeight(FontWeight.Medium).width('100%')
        Select(this.contextOptions)
          .width('100%')
          .height(36)
          .selected(this.e2CtxIndex)
          .onSelect((idx: number) => { this.e2Context = CONTEXTS[idx]; })
      }.width('100%')

      // Context detail
      Text(`→ CPU: ${CPU_LEVELS[this.e2Context.cpuLevel]} | `
        + `Mem: ${this.e2Context.memLevel >= 0 ? MEM_LEVELS[this.e2Context.memLevel] : 'None'} | `
        + `IO: ${this.e2Context.ioLevel >= 0 ? IO_LEVELS[this.e2Context.ioLevel] : 'None'}`)
        .fontSize(11)
        .fontColor('#888')
        .width('100%')

      Column({ space: 4 }) {
        Text('Model').fontSize(12).fontWeight(FontWeight.Medium).width('100%')
        Select(this.modelOptions)
          .width('100%')
          .height(36)
          .selected(this.e2ModelIndex)
          .onSelect((idx: number) => { this.e2Model = YOLO_MODELS[idx]; })
      }.width('100%')

      Column({ space: 4 }) {
        Text(`Duration: ${this.e2DurationMin} min`).fontSize(12).fontWeight(FontWeight.Medium).width('100%')
        Slider({
          value: this.e2DurationMin,
          min: 1,
          max: 30,
          step: 1,
          style: SliderStyle.InSet
        })
          .width('100%')
          .onChange((v: number) => { this.e2DurationMin = v; })
      }.width('100%')

      Row({ space: 8 }) {
        Button(this.expRunning ? 'Running...' : 'Start Exp 2')
          .layoutWeight(1)
          .fontWeight(500)
          .fontSize(14)
          .enabled(!this.expRunning)
          .onClick(() => { this.runExp2(); })
        Button('Stop')
          .layoutWeight(1)
          .fontWeight(500)
          .fontSize(14)
          .enabled(this.expRunning)
          .backgroundColor('#C62828')
          .onClick(() => { this.expRunning = false; this.stopPolling(); this.stopAllSimulators(); })
      }.width('100%')

      Text(`Phase: ${this.e2Phase}`)
        .fontSize(12)
        .fontColor(this.e2Phase.startsWith('Done') ? '#4CAF50' : '#333')
        .width('100%')

      if (this.e2PhaseRemainSec > 0) {
        Text(`Stabilizing: ${this.e2PhaseRemainSec}s remaining`)
          .fontSize(12)
          .fontColor('#FF9800')
          .width('100%')
      }

      if (this.e2Results.length > 0) {
        Text(this.e2Results)
          .fontSize(11)
          .fontColor('#333')
          .width('100%')
          .padding(8)
          .backgroundColor('#F5F5F5')
          .borderRadius(4)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FAFAFA')
    .borderRadius(8)
  }

  // ── Tab 3: Same Resource Different Capacity ──
  @Builder
  tab3SameResource(): void {
    Column({ space: 12 }) {
      this.sectionTitle('Experiment 3: Same Resource ≠ Same Capacity')
      Text('THE KEY EXPERIMENT. Tests each profile at "similar" resource state,\n'
        + 'measures future 5-min FPS trajectory to prove Context determines capacity.')
        .fontSize(11)
        .fontColor('#666')
        .width('100%')

      // Profile list
      Column({ space: 4 }) {
        Text('Profiles (run sequentially):').fontSize(12).fontWeight(FontWeight.Medium).width('100%')
        ForEach(SRDC_PROFILES, (p: ContextDef, idx: number) => {
          Row() {
            Text(`${idx + 1}. ${p.name}`)
              .fontSize(12)
              .fontWeight(this.e3ProfileIndex === idx ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.e3ProfileIndex === idx ? '#007DFF' : '#333')
              .layoutWeight(1)
            Text(`CPU:${CPU_LEVELS[p.cpuLevel]} `
              + `Mem:${p.memLevel >= 0 ? MEM_LEVELS[p.memLevel] : 'None'} `
              + `IO:${p.ioLevel >= 0 ? IO_LEVELS[p.ioLevel] : 'None'}`)
              .fontSize(10)
              .fontColor('#888')
          }
          .width('100%')
        })
      }
      .width('100%')
      .padding(8)
      .backgroundColor('#FFF9E8')
      .borderRadius(6)

      Column({ space: 4 }) {
        Text('Model').fontSize(12).fontWeight(FontWeight.Medium).width('100%')
        Select(this.modelOptions)
          .width('100%')
          .height(36)
          .selected(this.e3ModelIndex)
          .onSelect((idx: number) => { this.e3Model = YOLO_MODELS[idx]; })
      }.width('100%')

      Column({ space: 4 }) {
        Text(`Duration per profile: ${this.e3DurationMin} min`).fontSize(12).fontWeight(FontWeight.Medium).width('100%')
        Slider({
          value: this.e3DurationMin,
          min: 1,
          max: 15,
          step: 1,
          style: SliderStyle.InSet
        })
          .width('100%')
          .onChange((v: number) => { this.e3DurationMin = v; })
      }.width('100%')

      Row({ space: 8 }) {
        Button(this.e3Running ? 'Running...' : 'Run All Profiles')
          .layoutWeight(1)
          .fontWeight(500)
          .fontSize(14)
          .enabled(!this.e3Running)
          .backgroundColor('#9C27B0')
          .onClick(() => { this.runExp3(); })
        Button('Stop')
          .layoutWeight(1)
          .fontWeight(500)
          .fontSize(14)
          .enabled(this.e3Running)
          .backgroundColor('#C62828')
          .onClick(() => { this.e3Running = false; this.stopPolling(); this.stopAllSimulators(); })
      }.width('100%')

      if (this.e3CurrentProfile.length > 0) {
        Text(`Current: ${this.e3CurrentProfile} | Phase: ${this.e3Phase}`)
          .fontSize(12)
          .fontColor('#FF9800')
          .width('100%')
      }

      if (this.e2PhaseRemainSec > 0 && this.e3Phase.startsWith('Stabilizing')) {
        Text(`Stabilizing: ${this.e2PhaseRemainSec}s remaining`)
          .fontSize(12)
          .fontColor('#FF9800')
          .width('100%')
      }

      if (this.e3Results.length > 0) {
        Text(this.e3Results)
          .fontSize(11)
          .fontColor('#333')
          .width('100%')
          .padding(8)
          .backgroundColor('#F3E5F5')
          .borderRadius(4)
          .fontFamily('monospace')
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FAFAFA')
    .borderRadius(8)
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────────────────

  build() {
    NavDestination() {
      Column() {
        this.statusBar();

        Tabs({ index: this.currentTabIndex }) {
          TabContent() {
            Scroll() {
              Column() { this.tab1CapacityCurve() }
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 16 })
            }
            .scrollable(ScrollDirection.Vertical)
            .scrollBar(BarState.Auto)
          }
          .tabBar(this.tabTitles[0])

          TabContent() {
            Scroll() {
              Column() { this.tab2ContextImpact() }
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 16 })
            }
            .scrollable(ScrollDirection.Vertical)
            .scrollBar(BarState.Auto)
          }
          .tabBar(this.tabTitles[1])

          TabContent() {
            Scroll() {
              Column() { this.tab3SameResource() }
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 16 })
            }
            .scrollable(ScrollDirection.Vertical)
            .scrollBar(BarState.Auto)
          }
          .tabBar(this.tabTitles[2])
        }
        .width('100%')
        .layoutWeight(1)
        .vertical(false)
        .barMode(BarMode.Fixed)
        .barWidth('100%')
        .onChange((idx: number) => { this.currentTabIndex = idx; })
      }
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('app.color.background_color'))
    .title(TitleComponent('Experiment Dashboard', 'Capacity Curve · Context Impact · SRDC'))
  }
}
