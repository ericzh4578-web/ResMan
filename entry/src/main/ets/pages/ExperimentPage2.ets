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
import {
  YOLO_MODELS, MODEL_SHORT_NAMES, CPU_LEVELS, MEM_LEVELS, IO_LEVELS,
  SystemStateDef, SYSTEM_STATES, SelectOption, toSelectOptions, getBatchSize,
  PerImageQuality, GainDistribution, FeatureSample, ModelDecision, DecisionMetrics,
  BaselineMethod, ALL_BASELINES, ScenarioDef, SCENARIOS, ScenarioResult,
  AllocationStrategy, ALL_STRATEGIES, BudgetResult, ExpProgress,
  InfiResultEntry, InfiSummary, InfiDataset,
  INFI_CONFIG_FILES, INFI_CONFIG_LABELS, COCO_IMAGES_DIR,
  Exp2ImageRecord,
} from '../experiments2/ExperimentTypes';
import { SystemStateManager } from '../experiments2/SystemStateManager';
import { SyntheticImageGenerator, DifficultyLevel, SynthImageConfig } from '../experiments2/SyntheticImageGenerator';
import { QualityScorer } from '../experiments2/QualityScorer';
import { ImageFeatureExtractor } from '../experiments2/ImageFeatureExtractor';
import { GainPredictor } from '../experiments2/GainPredictor';
import { BaseExperimentRunner, MetricsCollector, ExperimentSample } from '../experiments2/BaseExperimentRunner';
import { YoloPreprocessor, PreprocessMetadata } from '../experiments2/YoloPreprocessor';
import { InfiResultLoader } from '../experiments2/InfiResultLoader';
import { CocoImagePreprocessor, CocoPreprocessResult } from '../experiments2/CocoImagePreprocessor';

const TAG = 'ExperimentPage2';

// ── Options ──

const STATE_OPTIONS: SelectOption[] = toSelectOptions(SYSTEM_STATES.map((s: SystemStateDef): string => s.name));
const SCENARIO_OPTIONS: SelectOption[] = toSelectOptions(SCENARIOS.map((s: ScenarioDef): string => s.name));
const MODEL_OPTIONS: SelectOption[] = toSelectOptions(YOLO_MODELS);
const BASELINE_OPTIONS: SelectOption[] = toSelectOptions(ALL_BASELINES.map((b: BaselineMethod): string => b as string));
const STRATEGY_OPTIONS: SelectOption[] = toSelectOptions(
  ALL_STRATEGIES.map((s: AllocationStrategy): string => s as string)
);

function baselineLabel(b: BaselineMethod): string { return b as string; }
function strategyLabel(s: AllocationStrategy): string { return s as string; }

// ── Exp1 result type ──

interface Exp1Cell {
  stateName: string;
  modelName: string;
  avgLatencyMs: number;
  avgEnergyMw: number;
  avgCpuPercent: number;
  avgFps: number;
  sampleCount: number;
}

// ── Exp2 result type ──

interface Exp2GainEntry {
  modelPair: string;
  meanGain: number;
  medianGain: number;
  p80Gain: number;
  p90Gain: number;
  fractionNearZero: number;
}

// ── Exp3 result type ──

interface Exp3Summary {
  samples: number;
  meanGain: number;
  stdGain: number;
  corrEntropyGain: number;
  corrConfidenceGain: number;
}

// ── Exp4 result type ──

interface Exp4BaselineResult {
  method: string;
  totalQuality: number;
  totalEnergyMw: number;
  avgLatencyMs: number;
  avgFps: number;
  modelDist: string;
}

// ── Exp5 result type ──

interface Exp5ScenarioResult {
  scenario: string;
  method: string;
  totalQuality: number;
  totalEnergyMw: number;
  avgLatencyMs: number;
  failures: number;
}

// ── Exp6 result type ──

interface Exp6StrategyResult {
  strategy: string;
  totalQuality: number;
  totalEnergyMw: number;
  framesProcessed: number;
  efficiency: number;
  modelDist: string;
}

@Component
export struct ExperimentPage2 {
  @Consume('pageInfos') pageInfos: NavPathStack;

  // ── Tab state ──
  @State currentTabIndex: number = 0;
  private tabTitles: string[] = [
    'Exp1: Cost',
    'Exp2: InFi Baseline',
    'Exp3: Predict',
    'Exp4: Scheduler',
    'Exp5: Dynamic',
    'Exp6: Budget',
  ];

  // ── Shared status bar ──
  @State expStatus: string = 'Idle';
  @State expFps: number = 0;
  @State expCpuUsage: number = 0;
  @State expSystemCpu: number = 0;
  @State expPssMb: string = '-';
  @State expAvailMemMb: string = '-';
  @State expTemp: number = 0;
  @State expThermal: number = 0;
  @State expBatterySOC: number = 0;
  @State expBatteryCurrent: number = 0;
  @State expCpuFreqs: string = '';
  @State expSampleCount: number = 0;
  @State expTotalInferences: number = 0;
  @State expThroughput: number = 0;
  @State expElapsedSec: number = 0;
  @State expCsvPath: string = '';
  @State expEnergyMw: number = 0;
  @State expRunning: boolean = false;

  // ── Exp1 state ──
  @State e1StateIdx: number = 0;
  @State e1ModelIdx: number = 2;
  @State e1DurationMin: number = 2;
  @State e1Status: string = 'Idle';
  @State e1Results: string = '';
  @State e1Running: boolean = false;
  @State e1StateRunStatus: string[] = ['', '', '', '', ''];
  @State e1StateResults: (Exp1Cell | null)[] = [null, null, null, null, null];
  @State e1CurrentStateIdx: number = -1;
  @State e1StateSelections: boolean[] = [true, true, true, true, true];

  // ── Exp2 state ──
  @State e2ConfigIdx: number = 2;         // which INFI_CONFIG_FILES (default: 200 samples)
  @State e2ModelIdx: number = 3;          // which YOLO model (0=n,1=s,2=m,3=l)
  @State e2DeadlineMs: number = 150;
  @State e2Status: string = 'Idle';
  @State e2Results: string = '';
  @State e2Running: boolean = false;
  @State e2CurrentImage: number = 0;
  @State e2CurrentImageFile: string = '';
  @State e2DecodeMs: number = 0;
  @State e2PreprocessMs: number = 0;
  @State e2InferMs: number = 0;
  @State e2TimingOpen: number = 0;     // [1] file open ms
  @State e2TimingDecode: number = 0;   // [2] JPEG decode ms
  @State e2TimingRead: number = 0;     // [3] readPixels ms
  @State e2TimingParams: number = 0;   // [4] letterbox params ms
  @State e2TimingLoop: number = 0;     // [5] fused loop ms
  @State e2GatingPass: number = 0;
  @State e2GatingSkip: number = 0;
  @State e2DeadlineMiss: number = 0;
  @State e2InfiSummary: string = '';
  @State e2Phase: string = '';           // current phase: 'load_json' | 'load_model' | 'inference' | 'done'
  @State e2JsonLoaded: boolean = false;
  @State e2ModelLoaded: boolean = false;
  @State e2EnableGating: boolean = false;   // true = skip images where InFi pred_person=0

  // ── Exp3 state ──
  @State e3ImageCount: number = 30;
  @State e3Status: string = 'Idle';
  @State e3Results: string = '';
  @State e3Running: boolean = false;

  // ── Exp4 state ──
  @State e4ImageCount: number = 30;
  @State e4StateIdx: number = 1;
  @State e4Status: string = 'Idle';
  @State e4Results: string = '';
  @State e4Running: boolean = false;

  // ── Exp5 state ──
  @State e5ScenarioIdx: number = 0;
  @State e5Status: string = 'Idle';
  @State e5Results: string = '';
  @State e5Running: boolean = false;

  // ── Exp6 state ──
  @State e6FrameCount: number = 200;
  @State e6BudgetMw: number = 50000;
  @State e6Status: string = 'Idle';
  @State e6Results: string = '';
  @State e6Running: boolean = false;

  // ── Internal ──
  private pollTimer: number = -1;
  private inferCounter: number = 0;
  private inferBatchSize: number = 1;

  // ── Helpers ──

  private get selectedState(): SystemStateDef {
    if (this.e1StateIdx < 0 || this.e1StateIdx >= SYSTEM_STATES.length) return SYSTEM_STATES[0];
    return SYSTEM_STATES[this.e1StateIdx];
  }

  private get selectedE1ModelName(): string {
    if (this.e1ModelIdx < 0 || this.e1ModelIdx >= YOLO_MODELS.length) return YOLO_MODELS[0];
    return YOLO_MODELS[this.e1ModelIdx];
  }

  private get selectedScenario(): ScenarioDef {
    if (this.e5ScenarioIdx < 0 || this.e5ScenarioIdx >= SCENARIOS.length) return SCENARIOS[0];
    return SCENARIOS[this.e5ScenarioIdx];
  }

  // ── Polling ──

  startPolling(): void {
    if (this.pollTimer !== -1) return;
    this.pollTimer = setInterval(() => {
      try {
        this.expCpuUsage = Math.max(0, hidebug.getCpuUsage()) * 100;
        this.expSystemCpu = hidebug.getSystemCpuUsage() * 100;
        this.expTemp = (batteryInfo.batteryTemperature as number) / 10.0;
        this.expThermal = thermal.getThermalLevel();
        this.expBatterySOC = batteryInfo.batterySOC;
        this.expBatteryCurrent = batteryInfo.nowCurrent;
        this.expEnergyMw = this.expBatteryCurrent * batteryInfo.voltage / 1000;
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

  // ── Model loading ──

  async loadYoloModel(modelName: string): Promise<mindSporeLite.Model> {
    const ctx = getContext(this) as common.UIAbilityContext;
    const rm = ctx.resourceManager;

    // Step 1: read raw file
    let modelBuffer: Uint8Array;
    try {
      modelBuffer = await rm.getRawFileContent(modelName);
      hilog.info(0x0000, TAG, 'Rawfile read OK: %{public}s (%{public}d bytes)',
        modelName, modelBuffer.length);
    } catch (e) {
      throw new Error('File read failed: ' + modelName + ' — ' + JSON.stringify(e));
    }

    // Step 2: try NNRT first, fall back to CPU
    const backends: string[][] = [['nnrt'], ['cpu']];
    let lastError: string = '';

    for (let bi = 0; bi < backends.length; bi++) {
      try {
        let msCtx: mindSporeLite.Context = {
          target: backends[bi],
          nnrt: { performanceMode: 3 },
        } as mindSporeLite.Context;
        const m = await mindSporeLite.loadModelFromBuffer(
          modelBuffer.buffer.slice(0) as ArrayBuffer, msCtx);
        hilog.info(0x0000, TAG, 'Model loaded [%{public}s]: %{public}s',
          backends[bi][0], modelName);
        return m;
      } catch (e) {
        lastError = backends[bi][0] + ': ' + JSON.stringify(e);
        hilog.warn(0x0000, TAG, 'Backend %{public}s failed, trying next...', backends[bi][0]);
      }
    }

    throw new Error('All backends failed for ' + modelName + ' — ' + lastError);
  }

  async loadAllModels(): Promise<(mindSporeLite.Model | null)[]> {
    let result: (mindSporeLite.Model | null)[] = [null, null, null, null];
    for (let i = 0; i < YOLO_MODELS.length; i++) {
      try {
        result[i] = await this.loadYoloModel(YOLO_MODELS[i]);
      } catch (e) {
        hilog.error(0x0000, TAG, 'Failed: %{public}s', YOLO_MODELS[i]);
        result[i] = null;
      }
    }
    return result;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Exp 1: Model Cost vs System State
  // ──────────────────────────────────────────────────────────────────────────

  private stateManager: SystemStateManager = new SystemStateManager();
  @State e1WaitingForUser: boolean = false;
  @State e1CurrentPrompt: string = '';

  private async promptUserForState(state: SystemStateDef): Promise<void> {
    if (state.name === 'Idle') {
      this.e1CurrentPrompt = '';
      this.e1WaitingForUser = false;
      return;
    }
    // Show prompt, wait for user to press Continue
    this.e1CurrentPrompt = state.description;
    this.e1WaitingForUser = true;
    this.e1Status = 'Waiting: ' + state.name;
    await new Promise<void>((resolve) => {
      this.e1UserResolve = resolve;
    });
    this.e1WaitingForUser = false;
    this.e1CurrentPrompt = '';
  }

  private e1UserResolve: (() => void) | null = null;

  e1UserContinue(): void {
    if (this.e1UserResolve) {
      const r = this.e1UserResolve;
      this.e1UserResolve = null;
      r();
    }
  }

  // ── Temperature helpers for Exp1 cooldown ──
  @State e1TargetTemp: number = 35;

  private getDeviceTemp(): number {
    return (batteryInfo.batteryTemperature as number) / 10.0;
  }

  private async waitForCooldown(targetTemp: number, timeoutSec: number): Promise<boolean> {
    const deadline = Date.now() + timeoutSec * 1000;
    while (Date.now() < deadline && this.e1Running) {
      let temp = this.getDeviceTemp();
      if (temp <= targetTemp) return true;
      this.e1Status = 'Cooldown: ' + temp.toFixed(1) + '°C → ' + targetTemp.toFixed(0) + '°C';
      this.expStatus = 'Cooldown';
      await new Promise<void>(r => setTimeout(r, 3000));
    }
    return this.getDeviceTemp() <= targetTemp;
  }

  private updateE1Report(): void {
    let report = 'State | AvgLat(ms) | AvgFPS | AvgCPU% | AvgEnergy(mW)\n';
    report += '------|------------|--------|---------|--------------\n';
    for (let si = 0; si < SYSTEM_STATES.length; si++) {
      const c = this.e1StateResults[si];
      if (c) {
        report += c.stateName + ' | ' + c.avgLatencyMs.toFixed(1) + ' | '
          + c.avgFps.toFixed(2) + ' | ' + c.avgCpuPercent.toFixed(1) + '% | '
          + c.avgEnergyMw.toFixed(1) + '\n';
      } else {
        const st = this.e1StateRunStatus[si];
        report += SYSTEM_STATES[si].name + ' | ' + (st || 'pending') + ' | - | - | -\n';
      }
    }
    this.e1Results = report;
  }

  async runExp1(): Promise<void> {
    if (this.e1Running) return;
    this.e1Running = true;
    this.expRunning = true;
    this.expStatus = 'Loading';
    this.e1Results = '';

    // Reset per-pair tracking
    this.e1StateResults = [null, null, null, null, null];
    this.e1StateRunStatus = ['', '', '', '', ''];
    this.e1CurrentStateIdx = -1;

    const filesDir = (getContext(this) as common.UIAbilityContext).filesDir;
    this.stateManager.setFilesDir(filesDir);
    try { fileIo.mkdirSync(filesDir + '/experiments2', true); } catch (_) {}

    const e1ModelName = YOLO_MODELS[this.e1ModelIdx];
    const bs = getBatchSize(e1ModelName);
    this.inferBatchSize = bs;
    this.startPolling();

    const baselineTemp = this.getDeviceTemp();
    const cooldownTarget = Math.max(baselineTemp, this.e1TargetTemp);

    for (let si = 0; si < SYSTEM_STATES.length; si++) {
      if (!this.e1Running) break;
      if (!this.e1StateSelections[si]) {
        this.e1StateRunStatus[si] = 'skipped';
        this.updateE1Report();
        continue;
      }

      this.e1CurrentStateIdx = si;
      this.e1StateRunStatus[si] = 'loading';
      const st = SYSTEM_STATES[si];

      // ── Load model for this pair ──
      let model: mindSporeLite.Model;
      try {
        this.e1Status = 'Loading ' + e1ModelName + ' for ' + st.name + '...';
        model = await this.loadYoloModel(e1ModelName);
      } catch (e) {
        this.e1Status = 'Failed to load model: ' + JSON.stringify(e);
        this.e1StateRunStatus[si] = 'failed';
        this.updateE1Report();
        continue;
      }

      // ── Cooldown (skip Idle) ──
      if (si > 0) {
        let currentTemp = this.getDeviceTemp();
        if (currentTemp > cooldownTarget + 1) {
          this.e1Status = 'Cooldown before ' + st.name + '...';
          this.expStatus = 'Cooldown';
          let cooled = await this.waitForCooldown(cooldownTarget, 300);
          if (!cooled) {
            this.e1Status = 'Cooldown timeout (' + this.getDeviceTemp().toFixed(1)
              + '°C), continuing';
            await new Promise<void>(r => setTimeout(r, 2000));
          }
        }
      }

      if (!this.e1Running) break;

      // ── Prompt user to set up the state ──
      await this.promptUserForState(st);
      if (!this.e1Running) break;

      // ── Apply simulator load ──
      this.stateManager.applyState(st);
      this.e1Status = 'State ' + (si + 1) + '/5: ' + st.name;
      this.expStatus = 'Stabilizing';
      this.e1StateRunStatus[si] = 'stabilizing';

      // ── Stabilize ──
      const stabilizeSec = st.name === 'Idle' ? 10 : 30;
      await new Promise<void>(r => setTimeout(r, stabilizeSec * 1000));
      if (!this.e1Running) break;

      // ── Run inference ──
      this.expStatus = 'Running';
      this.e1StateRunStatus[si] = 'running';
      const durationMs = this.e1DurationMin * 60 * 1000;
      const startTime = Date.now();
      let inferenceCount = 0;
      let totalLatency = 0;
      let totalEnergy = 0;
      let totalCpu = 0;
      let totalFps = 0;
      let sampleCount = 0;

      await new Promise<void>((resolve) => {
        const intervalId = setInterval(async () => {
          const elapsed = Date.now() - startTime;
          if (elapsed >= durationMs || !this.e1Running) {
            clearInterval(intervalId);
            resolve();
            return;
          }

          try {
            const inputs = model.getInputs();
            inputs[0].setData(this.generateRandomInput(bs));
            const t0 = Date.now();
            await model.predict(inputs);
            const dt = Date.now() - t0;
            inferenceCount++;
            totalLatency += dt;
            this.inferCounter++;
            this.expTotalInferences = this.inferCounter;
          } catch (_) {}

          const sample = MetricsCollector.captureSample(elapsed);
          totalEnergy += sample.batteryCurrent * sample.batteryVoltage / 1000;
          totalCpu += sample.cpuUsagePercent;
          sampleCount++;
          this.expSampleCount = sampleCount;
          this.expElapsedSec = Math.floor(elapsed / 1000);
          if (this.expElapsedSec > 0) {
            totalFps = inferenceCount / this.expElapsedSec;
            this.expFps = totalFps;
            this.expThroughput = totalFps * bs;
          }
          let elapsedMin = Math.floor(elapsed / 60000);
          let elapsedSec = Math.floor((elapsed % 60000) / 1000);
          this.e1Status = 'State ' + (si + 1) + '/5: ' + st.name
            + ' — ' + elapsedMin + 'm' + (elapsedSec < 10 ? '0' : '') + elapsedSec + 's'
            + ' / ' + this.e1DurationMin + 'm';
        }, 1000) as number;
      });

      // ── Save result (only if not interrupted) ──
      if (!this.e1Running) break;
      let cell: Exp1Cell = {
        stateName: st.name,
        modelName: e1ModelName,
        avgLatencyMs: inferenceCount > 0 ? totalLatency / inferenceCount : 0,
        avgEnergyMw: sampleCount > 0 ? totalEnergy / sampleCount : 0,
        avgCpuPercent: sampleCount > 0 ? totalCpu / sampleCount : 0,
        avgFps: totalFps,
        sampleCount: sampleCount,
      };
      this.e1StateResults[si] = cell;
      this.e1StateRunStatus[si] = 'done';
      this.updateE1Report();
    }

    this.stateManager.stopAll();
    this.stopPolling();
    this.e1Running = false;
    this.expRunning = false;
    this.e1CurrentStateIdx = -1;
    this.e1Status = 'Done';
    this.expStatus = 'Done';
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Exp 2: InFi Static Baseline
  // ──────────────────────────────────────────────────────────────────────────

  private captureFullSnapshot(): string {
    // Capture every available system metric into a pipe-delimited snapshot string.
    // Format: cpuProc|cpuSys|cpuFreqs|gpuFreq|pssMb|availMemMb|totalMemMb|freeMemMb|
    //         batterySOC|batteryTemp|batteryCurrent|batteryVoltage|thermalLevel
    let parts: string[] = [];
    try { parts.push(hidebug.getCpuUsage().toFixed(4)); } catch (_) { parts.push(''); }
    try { parts.push(hidebug.getSystemCpuUsage().toFixed(4)); } catch (_) { parts.push(''); }
    try { parts.push(libentry.readCpuFreqsCsv() || ''); } catch (_) { parts.push(''); }
    try { parts.push((libentry.readGpuFreq() || 0).toString()); } catch (_) { parts.push(''); }
    try { parts.push((Number(hidebug.getPss()) / 1024).toFixed(2)); } catch (_) { parts.push(''); }
    try {
      const mem = hidebug.getSystemMemInfo();
      parts.push((Number(mem.availableMem) / 1024).toFixed(2));
      parts.push((Number(mem.totalMem) / 1024).toFixed(2));
      parts.push((Number(mem.freeMem) / 1024).toFixed(2));
    } catch (_) { parts.push(''); parts.push(''); parts.push(''); }
    try { parts.push(batteryInfo.batterySOC.toString()); } catch (_) { parts.push(''); }
    try { parts.push((batteryInfo.batteryTemperature as number / 10.0).toFixed(2)); } catch (_) { parts.push(''); }
    try { parts.push(batteryInfo.nowCurrent.toString()); } catch (_) { parts.push(''); }
    try { parts.push(batteryInfo.voltage.toString()); } catch (_) { parts.push(''); }
    try { parts.push(thermal.getThermalLevel().toString()); } catch (_) { parts.push(''); }
    return parts.join('|');
  }

  async runExp2(): Promise<void> {
    if (this.e2Running) return;
    this.e2Running = true;
    this.expRunning = true;
    this.e2Status = 'Phase 1/3: Loading InFi JSON...';
    this.expStatus = 'Loading';
    this.e2Phase = 'load_json';
    this.e2Results = '';
    this.e2CurrentImage = 0;
    this.e2CurrentImageFile = '';
    this.e2DecodeMs = 0;
    this.e2PreprocessMs = 0;
    this.e2InferMs = 0;
    this.e2GatingPass = 0;
    this.e2GatingSkip = 0;
    this.e2DeadlineMiss = 0;
    this.e2InfiSummary = '';
    this.e2JsonLoaded = false;
    this.e2ModelLoaded = false;

    const ctx = getContext(this) as common.UIAbilityContext;
    const filesDir = ctx.filesDir;
    try { fileIo.mkdirSync(filesDir + '/experiments2', true); } catch (_) {}

    // ═══════════════════════════════════════════════════════════════════
    // Phase 1: Load pre-computed InFi JSON results
    // ═══════════════════════════════════════════════════════════════════

    const infiLoader = new InfiResultLoader();
    const configFile = INFI_CONFIG_FILES[this.e2ConfigIdx];

    try {
      await infiLoader.loadFromRawfile(ctx, configFile);
      this.e2InfiSummary = infiLoader.generateReport();
      this.e2JsonLoaded = true;
      hilog.info(0x0000, TAG, 'InFi JSON loaded: %{public}d entries', infiLoader.count);
    } catch (e) {
      this.e2Status = 'Failed to load InFi JSON: ' + JSON.stringify(e);
      this.expStatus = 'Failed';
      this.e2Running = false;
      this.expRunning = false;
      return;
    }

    // ═══════════════════════════════════════════════════════════════════
    // Phase 2: Load YOLO model
    // ═══════════════════════════════════════════════════════════════════

    this.e2Phase = 'load_model';
    this.e2Status = 'Phase 2/3: Loading YOLO model...';
    const yoloModelName = YOLO_MODELS[this.e2ModelIdx];
    let yoloModel: mindSporeLite.Model;
    try {
      yoloModel = await this.loadYoloModel(yoloModelName);
      this.e2ModelLoaded = true;
    } catch (e) {
      this.e2Status = 'Failed to load YOLO model: ' + JSON.stringify(e);
      this.expStatus = 'Failed';
      this.e2Running = false;
      this.expRunning = false;
      return;
    }

    // ═══════════════════════════════════════════════════════════════════
    // Phase 3: Run YOLO inference on COCO images
    // ═══════════════════════════════════════════════════════════════════

    this.e2Phase = 'inference';
    this.e2Status = 'Phase 3/3: Running inference...';
    this.expStatus = 'Running';
    this.startPolling();

    // Prepare CSV
    const csvFile = 'exp2_infi_coco_baseline_' + Date.now() + '.csv';
    const csvPath = filesDir + '/experiments2/' + csvFile;
    let fd = -1;
    try {
      const f = await fileIo.open(csvPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fd = f.fd;
      const cols = [
        'imgId', 'file', 'origResolution', 'infiPredPerson', 'infiProbPerson',
        'gtPerson', 'infiCorrect', 'infiType',
        'yoloModel', 'latencyMs', 'prepMs', 'totalMs',
        'deadlineMiss', 'stateName',
        'snapshotCpu', 'snapshotTemp', 'snapshotFreqs',
        'preprocessMode',
      ];
      await fileIo.write(fd, cols.join(',') + '\n');
    } catch (_) {}

    const cocoLoader = new CocoImagePreprocessor(ctx, COCO_IMAGES_DIR);

    // Config file determines the dataset size — use all entries
    const imageCount = infiLoader.count;
    let allResults = infiLoader.results.slice(0, imageCount);

    // ── Apply InFi gating filter BEFORE batching (if enabled) ──
    if (this.e2EnableGating) {
      // Count skip images (pred_person=0) — they won't be processed
      for (let i = 0; i < allResults.length; i++) {
        if (allResults[i].pred_person === 0) {
          this.e2GatingSkip++;
        } else {
          this.e2GatingPass++;
        }
      }
      // Only keep pass images for inference
      allResults = allResults.filter((e: InfiResultEntry): boolean => e.pred_person === 1);
      hilog.info(0x0000, TAG, 'Gating ON: %{public}d/%{public}d images pass (skip=%{public}d)',
        allResults.length, imageCount, this.e2GatingSkip);
    }

    // Batch size from model name (e.g. yolov8l_bsz4 → bsz=4)
    const bsz = getBatchSize(yoloModelName);
    const results = allResults;
    // Round down to full batches
    const numBatches = Math.floor(results.length / bsz);

    // Statistics accumulators
    let totalLatency = 0;
    let totalDecodeMs = 0;
    let totalPreprocessMs = 0;
    let totalEndToEnd = 0;
    let successfulBatches = 0;
    let successfulInferences = 0;
    let failedBatches = 0;
    let allLatencies: number[] = [];

    this.e2Status = 'Phase 3/3: ' + imageCount + ' images, ' + bsz + '/batch, '
      + numBatches + ' batches';

    for (let bi = 0; bi < numBatches; bi++) {
      if (!this.e2Running) break;

      const batchStart = bi * bsz;
      const batchEntries = results.slice(batchStart, batchStart + bsz);
      this.e2CurrentImage = batchStart + 1;
      this.e2CurrentImageFile = 'batch ' + (bi + 1) + '/' + numBatches
        + ' (' + bsz + ' imgs)';

      // Count gating decisions (only when gating is OFF — otherwise pre-counted)
      if (!this.e2EnableGating) {
        for (let k = 0; k < batchEntries.length; k++) {
          if (batchEntries[k].pred_person === 1) {
            this.e2GatingPass++;
          } else {
            this.e2GatingSkip++;
          }
        }
      }

      // ── Step A+B fused: Decode + letterbox + CHW in one pass per image, then stack ──
      let batchFusedTotalMs = 0;
      let batchFailed = false;
      let batchChwTensors: Float32Array[] = [];

      for (let k = 0; k < batchEntries.length; k++) {
        const entry = batchEntries[k];
        try {
          // Fused: RGBA bytes → CHW[3,640,640] in ONE loop (no intermediate HWC)
          const fused = await cocoLoader.decodeAndPreprocessFused(entry.file);
          batchChwTensors.push(fused.chw);
          batchFusedTotalMs += fused.totalMs;
          // Capture timing breakdown from first image in batch for UI display
          if (k === 0 && fused.timing) {
            this.e2TimingOpen = fused.timing['1_openFile'] ?? 0;
            this.e2TimingDecode = fused.timing['2_jpegDecode'] ?? 0;
            this.e2TimingRead = fused.timing['3_readPixels'] ?? 0;
            this.e2TimingParams = fused.timing['4_params'] ?? 0;
            this.e2TimingLoop = fused.timing['5_fusedLoop'] ?? 0;
          }
        } catch (e) {
          hilog.warn(0x0000, TAG, 'Failed fused decode/pp %{public}s: %{public}s',
            entry.file, JSON.stringify(e));
          batchFailed = true;
          break;
        }
      }

      if (batchFailed || batchChwTensors.length < bsz) {
        failedBatches++;
        this.e2DecodeMs = -1;
        this.e2PreprocessMs = -1;
        continue;
      }

      // Per-image fused time
      const perImageFusedMs = batchFusedTotalMs / bsz;
      this.e2DecodeMs = perImageFusedMs;
      this.e2PreprocessMs = 0;
      totalDecodeMs += batchFusedTotalMs;
      totalPreprocessMs += 0;

      // ── Stack CHW tensors → NCHW batch tensor (bsz×3×640×640) ──
      const perSample = batchChwTensors[0].length;
      const batchTensor = new Float32Array(perSample * bsz);
      for (let k = 0; k < bsz; k++) {
        batchTensor.set(batchChwTensors[k], k * perSample);
      }

      // ── Pre-inference snapshot ──
      const snapshotCpu = this.expCpuUsage;
      const snapshotTemp = this.expTemp;
      const snapshotFreqs = this.expCpuFreqs;

      // ── Step C: Run YOLO inference (one batch predict) ──
      let batchLatencyMs = -1;
      try {
        const inputs = yoloModel.getInputs();
        inputs[0].setData(batchTensor.buffer);
        const t0 = Date.now();
        const outputs = await yoloModel.predict(inputs);
        batchLatencyMs = Date.now() - t0;
        this.e2InferMs = batchLatencyMs;

        totalLatency += batchLatencyMs;
        totalEndToEnd += batchFusedTotalMs + batchLatencyMs;
        successfulBatches++;
        successfulInferences += bsz;

        // Per-image estimated latency = batch_latency / bsz
        const perImageLatency = batchLatencyMs / bsz;
        for (let k = 0; k < bsz; k++) {
          allLatencies.push(perImageLatency);
        }

        // Deadline check (batch-level)
        if (perImageLatency > this.e2DeadlineMs) {
          this.e2DeadlineMiss += bsz;
        }
      } catch (e) {
        hilog.warn(0x0000, TAG, 'YOLO batch inference failed: %{public}s',
          JSON.stringify(e));
        failedBatches++;
        batchLatencyMs = -1;
        this.e2InferMs = -1;
      }

      // ── Step D: Write CSV row per image in this batch ──
      if (fd >= 0) {
        const perImageLat = batchLatencyMs > 0 ? batchLatencyMs / bsz : -1;
        const fusedPerImage = batchFusedTotalMs / bsz;
        for (let k = 0; k < batchEntries.length; k++) {
          const entry = batchEntries[k];
          const deadlineMiss = (perImageLat > 0 && perImageLat > this.e2DeadlineMs) ? 1 : 0;
          const row: (string | number)[] = [
            entry.img_id, entry.file, entry.orig_resolution,
            entry.pred_person, entry.prob_person.toFixed(6),
            entry.gt_person, entry.correct, entry.type,
            yoloModelName, perImageLat > 0 ? perImageLat.toFixed(2) : '-1',
            fusedPerImage.toFixed(2), '0',  // prepMs = fused, ppMs = 0 (combined)
            (perImageLat > 0 ? (fusedPerImage + perImageLat).toFixed(2) : '-1'),
            deadlineMiss, 'Idle',
            snapshotCpu.toFixed(2), snapshotTemp.toFixed(2), snapshotFreqs,
            'fused', // preprocessSteps marker
          ];
          try { await fileIo.write(fd, row.join(',') + '\n'); } catch (_) {}
        }
      }

      // Update shared counters
      this.expSampleCount = successfulInferences;
      this.expTotalInferences = successfulInferences + (failedBatches * bsz);
      this.expElapsedSec = Math.floor(successfulInferences / bsz);
      if (successfulInferences > 0) {
        this.expFps = 1000 / (totalLatency / successfulBatches) * bsz;
        this.expThroughput = successfulInferences / (totalLatency / 1000);
      }

      // Update status every batch
      this.e2Status = 'Phase 3/3: Batch ' + (bi + 1) + '/' + numBatches
        + ' · ' + successfulInferences + ' imgs done'
        + ' · batch=' + (batchLatencyMs > 0 ? batchLatencyMs.toFixed(1) + 'ms' : 'err')
        + ' · per-img=' + (batchLatencyMs > 0 ? (batchLatencyMs / bsz).toFixed(1) + 'ms' : '-');
    }

    if (fd >= 0) try { await fileIo.close(fd); } catch (_) {}

    this.stopPolling();
    this.e2Running = false;
    this.expRunning = false;
    this.e2Phase = 'done';

    // ═══════════════════════════════════════════════════════════════════
    // Build report
    // ═══════════════════════════════════════════════════════════════════

    if (successfulInferences > 0) {
      allLatencies.sort((a: number, b: number): number => a - b);
      const n = allLatencies.length;
      const avg = totalLatency / n;
      const totalProcessed = successfulInferences + (failedBatches * bsz);
      const avgPrep = totalProcessed > 0 ? totalDecodeMs / totalProcessed : 0;
      const avgE2E = totalEndToEnd / n;

      const p50Idx = Math.floor(n * 0.5);
      const p90Idx = Math.floor(n * 0.9);
      const p95Idx = Math.floor(n * 0.95);
      const p99Idx = Math.floor(n * 0.99);

      let report = '=== InFi + YOLO Static Baseline ===\n\n';
      report += this.e2InfiSummary + '\n\n';
      report += '── YOLO Model ──\n';
      report += 'Model: ' + yoloModelName + '\n';
      report += 'Batch size: ' + bsz + ' (batched inference)\n';
      report += 'Inference mode: ' + bsz + ' images/batch → ' + numBatches + ' predict calls\n';
      report += 'Deadline: ' + this.e2DeadlineMs + 'ms (per-image)\n\n';
      report += '── Run Summary ──\n';
      report += 'Images: ' + imageCount + ' (from ' + INFI_CONFIG_LABELS[this.e2ConfigIdx] + ')\n';
      report += 'Successful: ' + successfulInferences + ' images (' + successfulBatches + ' batches)\n';
      report += 'Failed batches: ' + failedBatches + '\n\n';
      report += '── Latency (per-image, = batch_latency / ' + bsz + ') ──\n';
      report += 'Avg: ' + avg.toFixed(2) + 'ms\n';
      report += 'Min: ' + allLatencies[0].toFixed(2) + 'ms\n';
      report += 'Max: ' + allLatencies[n - 1].toFixed(2) + 'ms\n';
      report += 'P50: ' + allLatencies[p50Idx].toFixed(2) + 'ms\n';
      report += 'P90: ' + allLatencies[p90Idx].toFixed(2) + 'ms\n';
      report += 'P95: ' + allLatencies[p95Idx].toFixed(2) + 'ms\n';
      report += 'P99: ' + allLatencies[p99Idx].toFixed(2) + 'ms\n\n';
      report += '── Preprocessing (fused decode+letterbox+CHW) ──\n';
      report += 'Avg prep per image: ' + avgPrep.toFixed(2) + 'ms\n';
      report += 'Avg end-to-end:     ' + avgE2E.toFixed(2) + 'ms\n\n';
      report += '── Gating ──\n';
      report += 'Pass (InFi→run heavy): ' + this.e2GatingPass + '\n';
      report += 'Skip (InFi→gated):     ' + this.e2GatingSkip + '\n';
      report += 'Deadline misses:        ' + this.e2DeadlineMiss
        + ' (' + (this.e2DeadlineMiss / n * 100).toFixed(1) + '%)\n\n';
      report += 'CSV: ' + csvPath;
      this.e2Results = report;
    } else {
      this.e2Results = 'No successful batches. Check:\n'
        + '  • COCO_val/ directory in app sandbox?\n'
        + '  • Model bsz matches input shape?\n'
        + 'InFi data: ' + (this.e2JsonLoaded ? 'loaded OK' : 'FAILED');
    }

    this.expCsvPath = csvPath;
    this.e2Status = 'Done (' + successfulInferences + ' imgs in '
      + successfulBatches + ' batches)';
    this.expStatus = 'Done';
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Exp 3: Gain Predictability
  // ──────────────────────────────────────────────────────────────────────────

  async runExp3(): Promise<void> {
    if (this.e3Running) return;
    this.e3Running = true;
    this.expRunning = true;
    this.e3Status = 'Loading models...';
    this.expStatus = 'Loading';
    this.e3Results = '';

    const filesDir = (getContext(this) as common.UIAbilityContext).filesDir;
    try { fileIo.mkdirSync(filesDir + '/experiments2', true); } catch (_) {}
    const csvFile = 'exp3_gain_features_' + Date.now() + '.csv';

    try {
      const modelN = await this.loadYoloModel(YOLO_MODELS[0]);
      const modelL = await this.loadYoloModel(YOLO_MODELS[3]);
      const predictor = new GainPredictor();
      predictor.load();
      this.startPolling();

      this.e3Status = 'Running...';
      this.expStatus = 'Running';

      let fd = -1;
      const csvPath = filesDir + '/experiments2/' + csvFile;
      try {
        const f = await fileIo.open(csvPath,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        fd = f.fd;
        const cols = 'imageIndex,difficulty,brightness,contrast,entropy,edgeDensity,numObjects,avgConfidence,maxConfidence,gainNtoL,predictedGain\n';
        await fileIo.write(fd, cols);
      } catch (_) {}

      const difficulties: DifficultyLevel[] = [DifficultyLevel.Easy, DifficultyLevel.Medium, DifficultyLevel.Hard];

      for (let i = 0; i < this.e3ImageCount; i++) {
        if (!this.e3Running) break;
        const diff = difficulties[i % difficulties.length];
        // Generate preprocessed NCHW input (shared across nano and large models)
        const inputBufferNCHW = SyntheticImageGenerator.getInputForInferenceNCHW({
          width: 640, height: 640, channels: 3, difficulty: diff, seed: 2000 + i,
        } as SynthImageConfig, 1);

        // Run nano model and score
        const modelNInputs = modelN.getInputs();
        modelNInputs[0].setData(inputBufferNCHW);
        const outputsN = await modelN.predict(modelNInputs);
        const qNano = QualityScorer.scoreFromOutputs(outputsN);

        // Extract image features (needs HWC layout — regenerate raw HWC data)
        const hwcForFeatures = SyntheticImageGenerator.generate(diff, 2000 + i);
        const features = ImageFeatureExtractor.extractFeatures(hwcForFeatures, qNano);

        // Run large model and score (reuse same NCHW-preprocessed input)
        const modelLInputs = modelL.getInputs();
        modelLInputs[0].setData(inputBufferNCHW);
        const outputsL = await modelL.predict(modelLInputs);
        const qLarge = QualityScorer.scoreFromOutputs(outputsL);

        // Compute gain
        const gainNtoL = QualityScorer.computeGain(qNano, qLarge);
        const predictedGain = predictor.predictGain(features);

        this.expSampleCount = i + 1;
        this.expElapsedSec = i + 1;
        this.e3Status = 'Image ' + (i + 1) + '/' + this.e3ImageCount;

        if (fd >= 0) {
          let diffLabel = diff === DifficultyLevel.Easy ? 'Easy'
            : (diff === DifficultyLevel.Medium ? 'Medium' : 'Hard');
          let row: (string | number)[] = [
            i, diffLabel,
            features.brightness.toFixed(4), features.contrast.toFixed(4),
            features.entropy.toFixed(4), features.edgeDensity.toFixed(4),
            features.numObjects, features.avgConfidence.toFixed(6),
            features.maxConfidence.toFixed(6),
            gainNtoL.toFixed(6), predictedGain.toFixed(6),
          ];
          try { await fileIo.write(fd, row.join(',') + '\n'); } catch (_) {}
        }
      }

      if (fd >= 0) try { await fileIo.close(fd); } catch (_) {}

      this.e3Results = 'Samples collected: ' + this.e3ImageCount + ' → ' + csvPath;
      this.expCsvPath = csvPath;
    } catch (e) {
      this.e3Status = 'Failed: ' + JSON.stringify(e);
      this.expStatus = 'Failed';
    }

    this.e3Running = false;
    this.expRunning = false;
    this.stopPolling();
    this.e3Status = 'Done (data collected for offline analysis)';
    this.expStatus = 'Done';
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Exp 4: Gain-aware Scheduler vs Baselines
  // ──────────────────────────────────────────────────────────────────────────

  async runExp4(): Promise<void> {
    if (this.e4Running) return;
    this.e4Running = true;
    this.expRunning = true;
    this.e4Status = 'Running...';
    this.expStatus = 'Running';
    this.e4Results = '';

    const st = SYSTEM_STATES[this.e4StateIdx];
    const filesDir = (getContext(this) as common.UIAbilityContext).filesDir;
    this.stateManager.applyState(st);
    this.startPolling();

    // Brief stabilization
    await new Promise<void>(r => setTimeout(r, 10000));

    try {
      const models = await this.loadAllModels();
      const predictor = new GainPredictor();
      predictor.load();

      let results: Exp4BaselineResult[] = [];
      const difficulties: DifficultyLevel[] = [DifficultyLevel.Easy, DifficultyLevel.Medium, DifficultyLevel.Hard];

      for (let bi = 0; bi < ALL_BASELINES.length; bi++) {
        if (!this.e4Running) break;
        const method = ALL_BASELINES[bi];
        this.e4Status = 'Testing: ' + baselineLabel(method);

        let totalQuality = 0;
        let totalEnergy = 0;
        let totalLatency = 0;
        let latencyCount = 0;
        let modelDist: number[] = [0, 0, 0, 0];

        for (let i = 0; i < this.e4ImageCount; i++) {
          if (!this.e4Running) break;
          const diff = difficulties[i % difficulties.length];
          // Generate preprocessed NCHW input (shared across models)
          const inputBufferNCHW = SyntheticImageGenerator.getInputForInferenceNCHW({
            width: 640, height: 640, channels: 3, difficulty: diff, seed: 3000 + i,
          } as SynthImageConfig, 1);

          // Run nano first to get features for decision
          let chosenMi = 0;
          if (models[0]) {
            try {
              let inputsNano = models[0]!.getInputs();
              inputsNano[0].setData(inputBufferNCHW);
              let outputsNano = await models[0]!.predict(inputsNano);
              const qNano = QualityScorer.scoreFromOutputs(outputsNano);

              // Decision based on method
              if (method === BaselineMethod.AlwaysN) {
                chosenMi = 0;
              } else if (method === BaselineMethod.AlwaysL) {
                chosenMi = 3;
              } else if (method === BaselineMethod.ConfidenceThreshold) {
                chosenMi = qNano.avgConfidence < 0.3 ? 3 : 0;
              } else if (method === BaselineMethod.DifficultyBased) {
                const features = ImageFeatureExtractor.extractFeatures(
                  SyntheticImageGenerator.generate(diff, 3000 + i), qNano);
                chosenMi = features.entropy > 4.5 ? 3 : (features.entropy > 4.0 ? 2 : 0);
              } else if (method === BaselineMethod.GainStateAware) {
                const features = ImageFeatureExtractor.extractFeatures(
                  SyntheticImageGenerator.generate(diff, 3000 + i), qNano);
                const gain = predictor.predictGain(features);
                const headroom = 1.0 - this.expCpuUsage / 100;
                const score = gain * Math.max(0.1, headroom);
                if (score > 0.6) chosenMi = 3;
                else if (score > 0.4) chosenMi = 2;
                else if (score > 0.2) chosenMi = 1;
                else chosenMi = 0;
              }

              totalQuality += qNano.qualityScore;
            } catch (_) {}
          }

          modelDist[chosenMi]++;

          // Run chosen model (if not nano, which was already run)
          if (chosenMi > 0 && models[chosenMi]) {
            try {
              const t0 = Date.now();
              let chosenInputs = models[chosenMi]!.getInputs();
              chosenInputs[0].setData(inputBufferNCHW);
              await models[chosenMi]!.predict(chosenInputs);
              totalLatency += Date.now() - t0;
              latencyCount++;

              const sample = MetricsCollector.captureSample(0);
              totalEnergy += sample.batteryCurrent * sample.batteryVoltage / 1000;
            } catch (_) {}
          }
        }

        let entry: Exp4BaselineResult = {
          method: baselineLabel(method),
          totalQuality: totalQuality,
          totalEnergyMw: totalEnergy,
          avgLatencyMs: latencyCount > 0 ? totalLatency / latencyCount : 0,
          avgFps: latencyCount > 0 ? 1000 / (totalLatency / latencyCount) : 0,
          modelDist: modelDist.join('/'),
        };
        results.push(entry);
      }

      let report = '=== Scheduler Comparison ===\n\n';
      report += 'Method | Quality | Energy(mW) | AvgLat(ms) | FPS | Dist(n/s/m/l)\n';
      report += '-------|---------|------------|------------|-----|---------------\n';
      for (let ri = 0; ri < results.length; ri++) {
        const r = results[ri];
        report += r.method + ' | ' + r.totalQuality.toFixed(2) + ' | '
          + r.totalEnergyMw.toFixed(1) + ' | ' + r.avgLatencyMs.toFixed(2) + ' | '
          + r.avgFps.toFixed(2) + ' | ' + r.modelDist + '\n';
      }
      this.e4Results = report;
    } catch (e) {
      this.e4Status = 'Failed: ' + JSON.stringify(e);
      this.expStatus = 'Failed';
    }

    this.stateManager.stopAll();
    this.stopPolling();
    this.e4Running = false;
    this.expRunning = false;
    this.e4Status = 'Done';
    this.expStatus = 'Done';
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Exp 5: Dynamic System Interference
  // ──────────────────────────────────────────────────────────────────────────

  async runExp5(): Promise<void> {
    if (this.e5Running) return;
    this.e5Running = true;
    this.expRunning = true;
    this.e5Status = 'Running...';
    this.expStatus = 'Running';
    this.e5Results = '';

    const scenario = this.selectedScenario;
    const filesDir = (getContext(this) as common.UIAbilityContext).filesDir;
    this.startPolling();

    try {
      const models = await this.loadAllModels();
      const predictor = new GainPredictor();
      predictor.load();

      const methods: BaselineMethod[] = [
        BaselineMethod.AlwaysN,
        BaselineMethod.AlwaysL,
        BaselineMethod.ConfidenceThreshold,
        BaselineMethod.GainStateAware,
      ];

      let allResults: Exp5ScenarioResult[] = [];

      for (let mi = 0; mi < methods.length; mi++) {
        if (!this.e5Running) break;
        const method = methods[mi];
        this.e5Status = 'Scenario: ' + scenario.name + ' | Method: ' + baselineLabel(method);

        let totalQuality = 0;
        let totalEnergy = 0;
        let totalLatency = 0;
        let latencyCount = 0;
        let failures = 0;

        for (let ti = 0; ti < scenario.transitions.length; ti++) {
          if (!this.e5Running) break;
          const trans = scenario.transitions[ti];
          const state = SYSTEM_STATES[trans.stateIndex];
          this.stateManager.applyState(state);

          // Run for transition duration
          const tEnd = Date.now() + trans.durationMs;
          while (Date.now() < tEnd && this.e5Running) {
            // Generate preprocessed NCHW input
            const inputBufferNCHW = SyntheticImageGenerator.getInputForInferenceNCHW({
              width: 640, height: 640, channels: 3, difficulty: DifficultyLevel.Medium, seed: 4000 + latencyCount,
            } as SynthImageConfig, 1);

            try {
              if (method === BaselineMethod.AlwaysN && models[0]) {
                const t0 = Date.now();
                let inputs = models[0]!.getInputs();
                inputs[0].setData(inputBufferNCHW);
                await models[0]!.predict(inputs);
                totalLatency += Date.now() - t0;
              } else if (method === BaselineMethod.AlwaysL && models[3]) {
                const t0 = Date.now();
                let inputs = models[3]!.getInputs();
                inputs[0].setData(inputBufferNCHW);
                await models[3]!.predict(inputs);
                totalLatency += Date.now() - t0;
              } else if (method === BaselineMethod.ConfidenceThreshold) {
                // Run nano, decide
                if (models[0]) {
                  let inputs0 = models[0]!.getInputs();
                  inputs0[0].setData(inputBufferNCHW);
                  let outputs0 = await models[0]!.predict(inputs0);
                  const q = QualityScorer.scoreFromOutputs(outputs0);
                  const t0 = Date.now();
                  if (q.avgConfidence < 0.3 && models[2]) {
                    let inputsM = models[2]!.getInputs();
                    inputsM[0].setData(inputBufferNCHW);
                    await models[2]!.predict(inputsM);
                  }
                  totalLatency += Date.now() - t0;
                }
              } else if (method === BaselineMethod.GainStateAware) {
                // Run nano, extract features, decide
                if (models[0]) {
                  let inputs0 = models[0]!.getInputs();
                  inputs0[0].setData(inputBufferNCHW);
                  let outputs0 = await models[0]!.predict(inputs0);
                  const q = QualityScorer.scoreFromOutputs(outputs0);
                  // Regenerate HWC data for feature extraction
                  const hwcForFeatures = SyntheticImageGenerator.generate(DifficultyLevel.Medium, 4000 + latencyCount);
                  const features = ImageFeatureExtractor.extractFeatures(hwcForFeatures, q);
                  const gain = predictor.predictGain(features);
                  const headroom = 1.0 - this.expCpuUsage / 100;
                  const score = gain * Math.max(0.1, headroom);
                  let chosenMi = score > 0.5 ? 3 : (score > 0.3 ? 2 : 0);
                  if (chosenMi > 0 && models[chosenMi]) {
                    let inputsChosen = models[chosenMi]!.getInputs();
                    inputsChosen[0].setData(inputBufferNCHW);
                    await models[chosenMi]!.predict(inputsChosen);
                  }
                }
              }

              latencyCount++;
              const sample = MetricsCollector.captureSample(0);
              totalEnergy += sample.batteryCurrent * sample.batteryVoltage / 1000;
            } catch (_) {
              failures++;
            }

            await new Promise<void>(r => setTimeout(r, 100));
          }
        }

        let r: Exp5ScenarioResult = {
          scenario: scenario.name,
          method: baselineLabel(method),
          totalQuality: totalQuality,
          totalEnergyMw: totalEnergy,
          avgLatencyMs: latencyCount > 0 ? totalLatency / latencyCount : 0,
          failures: failures,
        };
        allResults.push(r);
      }

      let report = '=== Dynamic Interference ===\n\n';
      report += 'Scenario: ' + scenario.name + '\n\n';
      report += 'Method | AvgLat(ms) | Energy(mW) | Failures\n';
      report += '-------|------------|------------|---------\n';
      for (let ri = 0; ri < allResults.length; ri++) {
        const r = allResults[ri];
        report += r.method + ' | ' + r.avgLatencyMs.toFixed(2) + ' | '
          + r.totalEnergyMw.toFixed(1) + ' | ' + r.failures + '\n';
      }
      this.e5Results = report;
    } catch (e) {
      this.e5Status = 'Failed: ' + JSON.stringify(e);
      this.expStatus = 'Failed';
    }

    this.stateManager.stopAll();
    this.stopPolling();
    this.e5Running = false;
    this.expRunning = false;
    this.e5Status = 'Done';
    this.expStatus = 'Done';
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Exp 6: Budget-constrained Video
  // ──────────────────────────────────────────────────────────────────────────

  async runExp6(): Promise<void> {
    if (this.e6Running) return;
    this.e6Running = true;
    this.expRunning = true;
    this.e6Status = 'Running...';
    this.expStatus = 'Running';
    this.e6Results = '';

    this.startPolling();

    try {
      const models = await this.loadAllModels();
      const predictor = new GainPredictor();
      predictor.load();

      let results: Exp6StrategyResult[] = [];

      for (let si = 0; si < ALL_STRATEGIES.length; si++) {
        if (!this.e6Running) break;
        const strategy = ALL_STRATEGIES[si];
        this.e6Status = 'Strategy: ' + strategyLabel(strategy);

        let totalQuality = 0;
        let totalEnergy = 0;
        let framesDone = 0;
        let modelDist: number[] = [0, 0, 0, 0];

        const difficulties: DifficultyLevel[] = [DifficultyLevel.Easy, DifficultyLevel.Medium, DifficultyLevel.Hard];

        for (let i = 0; i < this.e6FrameCount; i++) {
          if (!this.e6Running) break;
          if (totalEnergy >= this.e6BudgetMw) break;

          const diff = difficulties[i % difficulties.length];
          // Generate preprocessed NCHW input (shared across models)
          const inputBufferNCHW = SyntheticImageGenerator.getInputForInferenceNCHW({
            width: 640, height: 640, channels: 3, difficulty: diff, seed: 5000 + i,
          } as SynthImageConfig, 1);

          let chosenMi = 0;
          const energyPerSample = 150; // heuristic mW per inference

          if (totalEnergy + energyPerSample * 4 > this.e6BudgetMw) {
            chosenMi = 0; // force nano if budget low
          } else if (strategy === AllocationStrategy.Uniform) {
            chosenMi = 1; // always small
          } else if (strategy === AllocationStrategy.RandomAlloc) {
            chosenMi = Math.floor(Math.random() * 4);
          } else if (strategy === AllocationStrategy.ConfidenceBased) {
            if (models[0]) {
              try {
                let inputs0 = models[0]!.getInputs();
                inputs0[0].setData(inputBufferNCHW);
                let outputs0 = await models[0]!.predict(inputs0);
                const qConf = QualityScorer.scoreFromOutputs(outputs0);
                chosenMi = qConf.avgConfidence < 0.3 ? 3 : 0;
              } catch (_) {}
            }
          } else if (strategy === AllocationStrategy.GainBased) {
            if (models[0]) {
              try {
                let inputs0 = models[0]!.getInputs();
                inputs0[0].setData(inputBufferNCHW);
                let outputs0 = await models[0]!.predict(inputs0);
                const q = QualityScorer.scoreFromOutputs(outputs0);
                const hwcForFeatures = SyntheticImageGenerator.generate(diff, 5000 + i);
                const features = ImageFeatureExtractor.extractFeatures(hwcForFeatures, q);
                const gain = predictor.predictGain(features);
                const headroom = 1.0 - this.expCpuUsage / 100;
                const score = gain * Math.max(0.1, headroom);
                if (score > 0.6) chosenMi = 3;
                else if (score > 0.4) chosenMi = 2;
                else if (score > 0.2) chosenMi = 1;
              } catch (_) {}
            }
          }

          modelDist[chosenMi]++;

          if (chosenMi > 0 && models[chosenMi]) {
            try {
              let inputsChosen = models[chosenMi]!.getInputs();
              inputsChosen[0].setData(inputBufferNCHW);
              let outputsChosen = await models[chosenMi]!.predict(inputsChosen);
              const q = QualityScorer.scoreFromOutputs(outputsChosen);
              totalQuality += q.qualityScore;
            } catch (_) {}
          } else if (models[0]) {
            try {
              let inputs0 = models[0]!.getInputs();
              inputs0[0].setData(inputBufferNCHW);
              let outputs0 = await models[0]!.predict(inputs0);
              const q = QualityScorer.scoreFromOutputs(outputs0);
              totalQuality += q.qualityScore;
            } catch (_) {}
          }

          totalEnergy += energyPerSample * (chosenMi + 1);
          framesDone++;

          this.expSampleCount = framesDone;
          this.expElapsedSec = framesDone;
          this.e6Status = 'Strategy: ' + strategyLabel(strategy) + ' | Frame: ' + framesDone;
        }

        let entry: Exp6StrategyResult = {
          strategy: strategyLabel(strategy),
          totalQuality: totalQuality,
          totalEnergyMw: totalEnergy,
          framesProcessed: framesDone,
          efficiency: totalEnergy > 0 ? totalQuality / totalEnergy : 0,
          modelDist: modelDist.join('/'),
        };
        results.push(entry);
      }

      let report = '=== Budget-Constrained Video ===\n\n';
      report += 'Budget: ' + this.e6BudgetMw.toFixed(0) + ' mW\n\n';
      report += 'Strategy | Quality | Energy | Frames | Eff(Q/E) | Dist(n/s/m/l)\n';
      report += '---------|---------|--------|--------|----------|---------------\n';
      for (let ri = 0; ri < results.length; ri++) {
        const r = results[ri];
        report += r.strategy + ' | ' + r.totalQuality.toFixed(2) + ' | '
          + r.totalEnergyMw.toFixed(1) + ' | ' + r.framesProcessed + ' | '
          + r.efficiency.toFixed(4) + ' | ' + r.modelDist + '\n';
      }
      this.e6Results = report;
    } catch (e) {
      this.e6Status = 'Failed: ' + JSON.stringify(e);
      this.expStatus = 'Failed';
    }

    this.stopPolling();
    this.e6Running = false;
    this.expRunning = false;
    this.e6Status = 'Done';
    this.expStatus = 'Done';
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Utility
  // ──────────────────────────────────────────────────────────────────────────

  // Pre-allocated reusable input buffers to avoid GC pressure
  private reusableInput: Float32Array | null = null;
  private reusableChw: Float32Array | null = null;

  /**
   * Generate random input for YOLO inference in NCHW format.
   *
   * YOLO Preprocessing applied:
   *   1. Generate random HWC float32 [0,1] data (640×640×3)
   *   2. HWC → CHW transpose
   *   3. Add batch dimension → NCHW (N×3×640×640)
   *
   * @param batchSize  Batch dimension (e.g. 1 for bs1, 4 for bs4 models)
   * @returns          ArrayBuffer containing N×3×640×640 float32 tensor (NCHW)
   */
  generateRandomInput(batchSize: number): ArrayBuffer {
    const hwcLen = 640 * 640 * 3;
    const pixels = 640 * 640;

    // Step 1: Generate random HWC data [0, 1]
    if (!this.reusableInput || this.reusableInput.length !== hwcLen) {
      this.reusableInput = new Float32Array(hwcLen);
    }
    for (let i = 0; i < hwcLen; i++) {
      this.reusableInput[i] = Math.random();
    }

    // Step 5: HWC → CHW transpose
    if (!this.reusableChw || this.reusableChw.length !== hwcLen) {
      this.reusableChw = new Float32Array(hwcLen);
    }
    for (let ch = 0; ch < 3; ch++) {
      const chOffset = ch * pixels;
      for (let i = 0; i < pixels; i++) {
        this.reusableChw[chOffset + i] = this.reusableInput[i * 3 + ch];
      }
    }

    // Step 6: Add batch dimension → NCHW
    if (batchSize <= 1) {
      return this.reusableChw.buffer;
    }
    const totalFloats = hwcLen * batchSize;
    const nchw = new Float32Array(totalFloats);
    for (let b = 0; b < batchSize; b++) {
      nchw.set(this.reusableChw, b * hwcLen);
    }
    return nchw.buffer;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────────────

  aboutToAppear(): void {
    this.startPolling();
  }

  aboutToDisappear(): void {
    this.expRunning = false;
    this.e1Running = false;
    this.e2Running = false;
    this.e3Running = false;
    this.e4Running = false;
    this.e5Running = false;
    this.e6Running = false;
    this.stopPolling();
    this.stateManager.stopAll();
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
      Row() {
        Text('Status: ' + this.expStatus)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.expRunning ? '#007DFF' : '#333')
          .layoutWeight(1)
        Text('Infers: ' + this.expTotalInferences)
          .fontSize(12)
          .fontColor('#666')
          .layoutWeight(1)
        Text('FPS: ' + this.expFps.toFixed(2))
          .fontSize(12)
          .fontColor(this.expFps > 0 ? '#007DFF' : '#666')
          .layoutWeight(1)
        Text('Thru: ' + this.expThroughput.toFixed(1) + ' img/s')
          .fontSize(12)
          .fontColor('#666')
          .layoutWeight(1)
      }.width('100%')

      Row() {
        Text('Samples: ' + this.expSampleCount)
          .fontSize(12)
          .fontColor('#666')
          .layoutWeight(1)
        Text('Time: ' + this.expElapsedSec + 's')
          .fontSize(12)
          .fontColor('#666')
          .layoutWeight(1)
        Text('CPU: ' + this.expCpuUsage.toFixed(1) + '%')
          .fontSize(12)
          .layoutWeight(1)
        Text('Temp: ' + this.expTemp.toFixed(1) + '°C')
          .fontSize(12)
          .fontColor(this.expTemp > 40 ? '#C62828' : '#333')
          .layoutWeight(1)
      }.width('100%')

      Row() {
        Text('PSS: ' + this.expPssMb)
          .fontSize(12)
          .layoutWeight(1)
        Text('Avail: ' + this.expAvailMemMb)
          .fontSize(12)
          .layoutWeight(1)
        Text('Bat: ' + this.expBatterySOC + '%')
          .fontSize(12)
          .layoutWeight(1)
        Text('Energy: ' + this.expEnergyMw.toFixed(0) + 'mW')
          .fontSize(12)
          .layoutWeight(1)
      }.width('100%')

      if (this.expCpuFreqs.length > 0) {
        Text('Freqs: ' + this.expCpuFreqs)
          .fontSize(10)
          .fontColor('#888')
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (this.expCsvPath.length > 0) {
        Text('CSV: ' + this.expCsvPath)
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

  // ── Tab 1: Cost vs State ──

  @Builder
  tab1CostVsState(): void {
    Column({ space: 12 }) {
      this.sectionTitle('Exp 1: Model Cost vs System State')
      Text('Purpose: Prove that the SAME model has different cost under different system states.\n'
        + 'Each model-state pair runs independently — results are saved after each pair completes.')
        .fontSize(11)
        .fontColor('#666')
        .width('100%')

      // State list with checkboxes and per-pair status
      Column({ space: 4 }) {
        Text('5 System States (select which to run):').fontSize(12).fontWeight(FontWeight.Medium).width('100%')
        ForEach(SYSTEM_STATES, (st: SystemStateDef, idx: number) => {
          Row() {
            Checkbox()
              .select(this.e1StateSelections[idx])
              .selectedColor('#4CAF50')
              .onChange((checked: boolean) => {
                this.e1StateSelections[idx] = checked;
                this.e1StateSelections = [...this.e1StateSelections]; // trigger @State update
              })
            Column() {
              Text((idx + 1) + '. ' + st.name)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor('#333')
              Text('   ' + st.description)
                .fontSize(10)
                .fontColor('#888')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // Per-pair status badge
            if (this.e1StateRunStatus[idx].length > 0) {
              Text(this.e1StateRunStatus[idx])
                .fontSize(10)
                .fontColor(this.e1StateRunStatus[idx] === 'done' ? '#4CAF50'
                  : (this.e1StateRunStatus[idx] === 'failed' ? '#C62828'
                  : (this.e1StateRunStatus[idx] === 'running' ? '#007DFF' : '#888')))
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor(this.e1StateRunStatus[idx] === 'done' ? '#E8F5E9'
                  : (this.e1StateRunStatus[idx] === 'failed' ? '#FFEBEE'
                  : (this.e1StateRunStatus[idx] === 'running' ? '#E3F2FD' : '#F5F5F5')))
                .borderRadius(4)
            }
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
        })
      }
      .width('100%')
      .padding(8)
      .backgroundColor('#FFF8E1')
      .borderRadius(6)

      Column({ space: 4 }) {
        Text('Model').fontSize(12).fontWeight(FontWeight.Medium).width('100%')
        Select(MODEL_OPTIONS)
          .width('100%')
          .height(36)
          .selected(this.e1ModelIdx)
          .onSelect((idx: number) => { this.e1ModelIdx = idx; })
      }.width('100%')

      Column({ space: 4 }) {
        Text('Duration per state: ' + this.e1DurationMin + ' min').fontSize(12).fontWeight(FontWeight.Medium).width('100%')
        Slider({
          value: this.e1DurationMin,
          min: 1, max: 20, step: 1,
          style: SliderStyle.InSet,
        })
          .width('100%')
          .onChange((v: number) => { this.e1DurationMin = v; })
      }.width('100%')

      Column({ space: 4 }) {
        Text('Cooldown target: ' + this.e1TargetTemp.toFixed(0) + '°C').fontSize(12).fontWeight(FontWeight.Medium).width('100%')
        Slider({
          value: this.e1TargetTemp,
          min: 30, max: 45, step: 1,
          style: SliderStyle.InSet,
        })
          .width('100%')
          .onChange((v: number) => { this.e1TargetTemp = v; })
      }.width('100%')

      // ── User prompt for manual-app states ──
      if (this.e1WaitingForUser && this.e1CurrentPrompt.length > 0) {
        Column({ space: 8 }) {
          Text('=== ACTION REQUIRED ===')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#C62828')
            .width('100%')
            .textAlign(TextAlign.Center)
          Text(this.e1CurrentPrompt)
            .fontSize(12)
            .fontColor('#333')
            .width('100%')
          Button('✓ Ready — Continue')
            .width('100%')
            .fontWeight(FontWeight.Bold)
            .fontSize(15)
            .backgroundColor('#C62828')
            .onClick(() => { this.e1UserContinue(); })
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#FFEBEE')
        .borderRadius(8)
        .border({ width: 2, color: '#C62828' })
      }

      Row({ space: 8 }) {
        Button(this.e1Running ? 'Running...' : 'Start Exp 1')
          .layoutWeight(1)
          .fontWeight(500)
          .fontSize(14)
          .enabled(!this.e1Running)
          .backgroundColor('#4CAF50')
          .onClick(() => { this.runExp1(); })
        Button('Stop')
          .layoutWeight(1)
          .fontWeight(500)
          .fontSize(14)
          .enabled(this.e1Running)
          .backgroundColor('#C62828')
          .onClick(() => {
            this.e1Running = false;
            this.expRunning = false;
            this.stopPolling();
            this.stateManager.stopAll();
            // Mark current pair as interrupted
            if (this.e1CurrentStateIdx >= 0 && this.e1StateRunStatus[this.e1CurrentStateIdx] === 'running') {
              this.e1StateRunStatus[this.e1CurrentStateIdx] = 'interrupted';
            }
            if (this.e1UserResolve) {
              this.e1UserResolve();
            }
          })
      }.width('100%')

      Text('Status: ' + this.e1Status)
        .fontSize(12)
        .fontColor(this.e1Status.startsWith('Done') ? '#4CAF50' : '#333')
        .width('100%')

      if (this.e1Results.length > 0) {
        Text(this.e1Results)
          .fontSize(11)
          .fontColor('#333')
          .width('100%')
          .padding(8)
          .backgroundColor('#F5F5F5')
          .borderRadius(4)
          .fontFamily('monospace')
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FAFAFA')
    .borderRadius(8)
  }

  // ── Tab 2: InFi Static Baseline ──

  @Builder
  tab2GainDistribution(): void {
    Column({ space: 12 }) {
      this.sectionTitle('Exp 2: InFi Static Baseline')
      Text('Purpose: Establish YOLO inference baseline on real COCO images,\n'
        + 'using pre-computed InFi gating decisions as the reference.\n'
        + 'No InFi model inference is run — results are loaded from JSON.')
        .fontSize(11)
        .fontColor('#666')
        .width('100%')

      // Data source info
      Column({ space: 3 }) {
        Text('Data Sources:').fontSize(12).fontWeight(FontWeight.Medium).width('100%')
        Text('  • InFi results: rawfile/data_config/ (config determines image count)')
          .fontSize(10).fontColor('#888').width('100%')
        Text('  • COCO images: app sandbox COCO_val/ (5000 JPEG files)')
          .fontSize(10).fontColor('#888').width('100%')
        Text('  • YOLO models: rawfile yolov8{n,s,m,l}_bsz4.ms (bsz=4, batched inference)')
          .fontSize(10).fontColor('#888').width('100%')
      }
      .width('100%')
      .padding(8)
      .backgroundColor('#E8F5E9')
      .borderRadius(6)

      // InFi config file picker (config determines dataset size)
      Column({ space: 4 }) {
        Text('InFi Config:').fontSize(12).fontWeight(FontWeight.Medium).width('100%')
        Select(INFI_CONFIG_LABELS.map((s: string): SelectOption => ({ value: s } as SelectOption)))
          .width('100%')
          .height(36)
          .selected(this.e2ConfigIdx)
          .onSelect((idx: number) => { this.e2ConfigIdx = idx; })
      }.width('100%')

      // InFi summary (shown after JSON is loaded)
      if (this.e2InfiSummary.length > 0) {
        Text(this.e2InfiSummary)
          .fontSize(10)
          .fontColor('#333')
          .fontFamily('monospace')
          .width('100%')
          .padding(6)
          .backgroundColor('#FFF8E1')
          .borderRadius(4)
          .maxLines(12)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      // YOLO model picker
      Column({ space: 4 }) {
        Text('YOLO Model to benchmark:').fontSize(12).fontWeight(FontWeight.Medium).width('100%')
        Select(YOLO_MODELS.map((s: string): SelectOption => ({ value: s } as SelectOption)))
          .width('100%')
          .height(36)
          .selected(this.e2ModelIdx)
          .onSelect((idx: number) => { this.e2ModelIdx = idx; })
      }.width('100%')

      // System state snapshot display (real-time)
      Column({ space: 2 }) {
        Text('Current System State:').fontSize(11).fontWeight(FontWeight.Medium).width('100%')
        Row() {
          Text('CPU: ' + this.expCpuUsage.toFixed(1) + '%')
            .fontSize(10).fontColor('#555').layoutWeight(1)
          Text('SysCPU: ' + this.expSystemCpu.toFixed(1) + '%')
            .fontSize(10).fontColor('#555').layoutWeight(1)
          Text('Temp: ' + this.expTemp.toFixed(1) + '°C')
            .fontSize(10).fontColor(this.expTemp > 38 ? '#C62828' : '#555').layoutWeight(1)
        }.width('100%')
        Row() {
          Text('PSS: ' + this.expPssMb)
            .fontSize(10).fontColor('#555').layoutWeight(1)
          Text('Avail: ' + this.expAvailMemMb)
            .fontSize(10).fontColor('#555').layoutWeight(1)
          Text('Thermal: Lv' + this.expThermal)
            .fontSize(10).fontColor('#555').layoutWeight(1)
        }.width('100%')
      }
      .width('100%')
      .padding(6)
      .backgroundColor('#F5F5F5')
      .borderRadius(4)

      // Deadline slider
      Column({ space: 4 }) {
        Text('Deadline: ' + this.e2DeadlineMs + 'ms').fontSize(12).fontWeight(FontWeight.Medium).width('100%')
        Slider({
          value: this.e2DeadlineMs,
          min: 30, max: 500, step: 10,
          style: SliderStyle.InSet,
        })
          .width('100%')
          .onChange((v: number) => { this.e2DeadlineMs = v; })
      }.width('100%')

      // Live progress during run
      if (this.e2Running) {
        Column({ space: 3 }) {
          Text('Phase: ' + this.e2Phase)
            .fontSize(11).fontWeight(FontWeight.Medium).fontColor('#007DFF').width('100%')
          Text(this.e2CurrentImageFile)
            .fontSize(11).fontColor('#333').width('100%')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Row() {
            Text('Prep: ' + (this.e2DecodeMs > 0 ? this.e2DecodeMs.toFixed(0) + 'ms' : '-'))
              .fontSize(10).fontColor('#555').layoutWeight(1)
            Text('Infer: ' + (this.e2InferMs > 0 ? this.e2InferMs.toFixed(1) + 'ms' : '-'))
              .fontSize(10).fontColor(this.e2InferMs > this.e2DeadlineMs ? '#C62828' : '#555').layoutWeight(1)
            Text('Total: ' + (this.e2DecodeMs > 0 && this.e2InferMs > 0
              ? (this.e2DecodeMs + this.e2InferMs).toFixed(0) + 'ms' : '-'))
              .fontSize(10).fontColor('#333').layoutWeight(1)
          }.width('100%')
          // Per-step timing breakdown (from 1st image in batch)
          if (this.e2TimingDecode > 0) {
            Row() {
              Text('open=' + this.e2TimingOpen + 'ms')
                .fontSize(9).fontColor('#999').layoutWeight(1)
              Text('jpeg=' + this.e2TimingDecode + 'ms')
                .fontSize(9).fontColor('#999').layoutWeight(1)
              Text('read=' + this.e2TimingRead + 'ms')
                .fontSize(9).fontColor(this.e2TimingRead > 50 ? '#E65100' : '#999').layoutWeight(1)
              Text('loop=' + this.e2TimingLoop + 'ms')
                .fontSize(9).fontColor(this.e2TimingLoop > 100 ? '#E65100' : '#999').layoutWeight(1)
            }.width('100%')
          }
          Row() {
            Text('Pass: ' + this.e2GatingPass + ' | Skip: ' + this.e2GatingSkip
              + ' | Miss: ' + this.e2DeadlineMiss)
              .fontSize(10).fontColor('#888').layoutWeight(1)
            Text('JSON: ' + (this.e2JsonLoaded ? '✓' : '✗')
              + '  Model: ' + (this.e2ModelLoaded ? '✓' : '✗'))
              .fontSize(10).fontColor(this.e2JsonLoaded && this.e2ModelLoaded ? '#4CAF50' : '#C62828')
              .layoutWeight(1)
          }.width('100%')
        }
        .width('100%')
        .padding(8)
        .backgroundColor('#E3F2FD')
        .borderRadius(6)
      }

      // Gating toggle
      Row({ space: 8 }) {
        Text('Gate (skip pred=0):').fontSize(12).fontColor('#333')
        Toggle({ type: ToggleType.Switch, isOn: this.e2EnableGating })
          .onChange((checked: boolean) => { this.e2EnableGating = checked; })
        Text(this.e2EnableGating ? 'ON — skip non-person images' : 'OFF — process all images')
          .fontSize(10).fontColor('#888')
      }.width('100%')

      Row({ space: 8 }) {
        Button(this.e2Running ? 'Running...' : 'Start Exp 2')
          .layoutWeight(1)
          .fontWeight(500)
          .fontSize(14)
          .enabled(!this.e2Running && !this.expRunning)
          .backgroundColor('#2196F3')
          .onClick(() => { this.runExp2(); })
        Button('Stop')
          .layoutWeight(1)
          .fontWeight(500)
          .fontSize(14)
          .enabled(this.e2Running)
          .backgroundColor('#C62828')
          .onClick(() => { this.e2Running = false; this.expRunning = false; })
      }.width('100%')

      Text('Status: ' + this.e2Status)
        .fontSize(12)
        .fontColor(this.e2Status.startsWith('Done') ? '#4CAF50'
          : (this.e2Status.startsWith('Failed') ? '#C62828' : '#333'))
        .width('100%')

      if (this.e2Results.length > 0) {
        Text(this.e2Results)
          .fontSize(11)
          .fontColor('#333')
          .width('100%')
          .padding(8)
          .backgroundColor('#E3F2FD')
          .borderRadius(4)
          .fontFamily('monospace')
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FAFAFA')
    .borderRadius(8)
  }

  // ── Tab 3: Gain Predictability ──

  @Builder
  tab3GainPredictability(): void {
    Column({ space: 12 }) {
      this.sectionTitle('Exp 3: Gain Predictability')
      Text('暂无实现')
        .fontSize(14)
        .fontColor('#999')
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding(40)
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FAFAFA')
    .borderRadius(8)
  }

  // ── Tab 4: Gain-aware Scheduler ──

  @Builder
  tab4Scheduler(): void {
    Column({ space: 12 }) {
      this.sectionTitle('Exp 4: Gain-aware Scheduler vs Baselines')
      Text('暂无实现')
        .fontSize(14)
        .fontColor('#999')
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding(40)
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FAFAFA')
    .borderRadius(8)
  }

  // ── Tab 5: Dynamic Interference ──

  @Builder
  tab5Dynamic(): void {
    Column({ space: 12 }) {
      this.sectionTitle('Exp 5: Dynamic System Interference')
      Text('暂无实现')
        .fontSize(14)
        .fontColor('#999')
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding(40)
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FAFAFA')
    .borderRadius(8)
  }

  // ── Tab 6: Budget Video ──

  @Builder
  tab6Budget(): void {
    Column({ space: 12 }) {
      this.sectionTitle('Exp 6: Budget-Constrained Video')
      Text('暂无实现')
        .fontSize(14)
        .fontColor('#999')
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding(40)
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
              Column() { this.tab1CostVsState() }
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 16 })
            }
            .scrollable(ScrollDirection.Vertical)
            .scrollBar(BarState.Auto)
          }
          .tabBar(this.tabTitles[0])

          TabContent() {
            Scroll() {
              Column() { this.tab2GainDistribution() }
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 16 })
            }
            .scrollable(ScrollDirection.Vertical)
            .scrollBar(BarState.Auto)
          }
          .tabBar(this.tabTitles[1])

          TabContent() {
            Scroll() {
              Column() { this.tab3GainPredictability() }
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 16 })
            }
            .scrollable(ScrollDirection.Vertical)
            .scrollBar(BarState.Auto)
          }
          .tabBar(this.tabTitles[2])

          TabContent() {
            Scroll() {
              Column() { this.tab4Scheduler() }
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 16 })
            }
            .scrollable(ScrollDirection.Vertical)
            .scrollBar(BarState.Auto)
          }
          .tabBar(this.tabTitles[3])

          TabContent() {
            Scroll() {
              Column() { this.tab5Dynamic() }
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 16 })
            }
            .scrollable(ScrollDirection.Vertical)
            .scrollBar(BarState.Auto)
          }
          .tabBar(this.tabTitles[4])

          TabContent() {
            Scroll() {
              Column() { this.tab6Budget() }
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 16 })
            }
            .scrollable(ScrollDirection.Vertical)
            .scrollBar(BarState.Auto)
          }
          .tabBar(this.tabTitles[5])
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
    .title(TitleComponent('Experiment Dashboard 2', 'Gain Prediction · System-Aware Scheduling'))
  }
}
