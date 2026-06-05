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

// ── Model definitions ──

export const YOLO_MODELS: string[] = [
  'yolov8n_bsz4.ms',
  'yolov8s_bsz4.ms',
  'yolov8m_bsz4.ms',
  'yolov8l_bsz4.ms',
];

export const MODEL_SHORT_NAMES: string[] = ['n', 's', 'm', 'l'];

export const CPU_LEVELS: string[] = ['0%', '25%', '50%', '75%', '100%'];
export const MEM_LEVELS: string[] = ['10%', '15%', '20%', '25%'];
export const IO_LEVELS: string[] = ['Weak', 'Medium', 'Strong'];

// ── Select option (for Select components) ──

export interface SelectOption {
  value: string;
}

export function toSelectOptions(arr: string[]): SelectOption[] {
  let result: SelectOption[] = [];
  for (let i = 0; i < arr.length; i++) {
    result.push({ value: arr[i] } as SelectOption);
  }
  return result;
}

export function getBatchSize(modelName: string): number {
  const m = modelName.match(/_bsz(\d+)/);
  return m ? parseInt(m[1]) : 1;
}

export function modelIndexFromName(modelName: string): number {
  for (let i = 0; i < YOLO_MODELS.length; i++) {
    if (YOLO_MODELS[i] === modelName) return i;
  }
  return 0;
}

// ── System state definitions (Exp 1, 4, 5) ──

export interface SystemStateDef {
  name: string;
  description: string;   // what the user should manually do
  cpuLevel: number;       // ResourceSimulator CPU: 0-4, -1 = no change
  memLevel: number;       // ResourceSimulator Mem: 0-3, -1 = no change
  ioLevel: number;        // ResourceSimulator IO:  0-2, -1 = no change
}

// Hybrid model: states 1-4 rely on user launching real apps manually.
// Extreme adds ResourceSimulator on top of the real-app load.
// Each state also carries ResourceSimulator fallback levels for automated runs.

export const SYSTEM_STATES: SystemStateDef[] = [
  {
    name: 'Idle',
    description: 'Clear all background apps. Only YOLO running.',
    cpuLevel: -1, memLevel: -1, ioLevel: -1,
  },
  {
    name: 'Light (Music + Nav)',
    description: 'Manually start: Music app + Map Navigation. Then return to this app.',
    cpuLevel: 0, memLevel: -1, ioLevel: 0,
  },
  {
    name: 'Mid (Meeting)',
    description: 'Manually start: Video call app (WeChat/Meeting). Then return to this app.',
    cpuLevel: 0, memLevel: -1, ioLevel: 0,
  },
  {
    name: 'Heavy (Music + Nav + Meeting)',
    description: 'Manually start: Music + Navigation + Video call. Then return to this app.',
    cpuLevel: 0, memLevel: -1, ioLevel: 0,
  },
  {
    name: 'Extreme (All apps + CPU/Mem load)',
    description: 'Manually start: Music + Nav + Meeting. Code adds CPU+Mem+IO load automatically.',
    cpuLevel: 2, memLevel: 1, ioLevel: 1,
  },
];

// ── Quality / Gain types (Exp 2, 3) ──

export interface QualityResult {
  qualityScore: number;
  avgConfidence: number;
  maxConfidence: number;
  detectionCount: number;
}

export interface PerImageQuality {
  imageIndex: number;
  difficulty: string;
  scores: number[];
  gains: number[];
}

export interface GainDistribution {
  imagesTested: number;
  meanGainNtoS: number;
  meanGainNtoM: number;
  meanGainNtoL: number;
  fractionNearZeroNtoL: number;
  p80GainNtoL: number;
  p90GainNtoL: number;
  avgQualityNano: number;
  avgQualityLarge: number;
}

// ── Image feature types (Exp 3) ──

export interface ImageFeatures {
  brightness: number;
  contrast: number;
  entropy: number;
  edgeDensity: number;
  numObjects: number;
  avgConfidence: number;
  maxConfidence: number;
  bboxSizeMean: number;
  bboxSizeStd: number;
  smallObjectRatio: number;
}

export interface FeatureSample {
  imageIndex: number;
  difficulty: string;
  features: ImageFeatures;
  gainNtoL: number;
  qualityNano: number;
  qualityLarge: number;
}

// ── Scheduler / decision types (Exp 4, 5, 6) ──

export interface ModelDecision {
  imageIndex: number;
  modelIndex: number;
  modelName: string;
  predictedGain: number;
  systemState: string;
  qualityScore: number;
  energyMw: number;
  latencyMs: number;
}

export interface DecisionMetrics {
  method: string;
  totalQualityScore: number;
  totalEnergyMw: number;
  avgLatencyMs: number;
  avgFps: number;
  decisionCount: number;
  modelDistribution: number[];
}

export enum BaselineMethod {
  AlwaysN = 'Always-n',
  AlwaysL = 'Always-l',
  ConfidenceThreshold = 'Confidence-threshold',
  DifficultyBased = 'Difficulty-based',
  GainStateAware = 'Gain+State-aware',
}

export const ALL_BASELINES: BaselineMethod[] = [
  BaselineMethod.AlwaysN,
  BaselineMethod.AlwaysL,
  BaselineMethod.ConfidenceThreshold,
  BaselineMethod.DifficultyBased,
  BaselineMethod.GainStateAware,
];

// ── Scenario types (Exp 5) ──

export interface ScenarioTransition {
  stateIndex: number;
  durationMs: number;
}

export interface ScenarioDef {
  name: string;
  transitions: ScenarioTransition[];
}

export const SCENARIOS: ScenarioDef[] = [
  {
    name: 'Idle → Music → Idle',
    transitions: [
      { stateIndex: 0, durationMs: 30000 },
      { stateIndex: 1, durationMs: 30000 },
      { stateIndex: 0, durationMs: 30000 },
    ],
  },
  {
    name: 'Idle → VideoCall → Idle',
    transitions: [
      { stateIndex: 0, durationMs: 30000 },
      { stateIndex: 4, durationMs: 30000 },
      { stateIndex: 0, durationMs: 30000 },
    ],
  },
  {
    name: 'Idle → Chrome → Video',
    transitions: [
      { stateIndex: 0, durationMs: 30000 },
      { stateIndex: 2, durationMs: 30000 },
      { stateIndex: 3, durationMs: 30000 },
    ],
  },
];

export interface ScenarioResult {
  scenario: string;
  methodResults: DecisionMetrics[];
}

// ── Budget types (Exp 6) ──

export enum AllocationStrategy {
  Uniform = 'Uniform',
  RandomAlloc = 'Random',
  ConfidenceBased = 'Confidence-based',
  GainBased = 'Gain-based',
}

export const ALL_STRATEGIES: AllocationStrategy[] = [
  AllocationStrategy.Uniform,
  AllocationStrategy.RandomAlloc,
  AllocationStrategy.ConfidenceBased,
  AllocationStrategy.GainBased,
];

export interface BudgetResult {
  strategy: string;
  totalQualityScore: number;
  totalEnergyMw: number;
  framesProcessed: number;
  efficiency: number;
  modelDistribution: number[];
}

// ── InFi pre-computed result types (Exp 2) ──

/** A single InFi inference result entry from JSON */
export interface InfiResultEntry {
  rank: number;
  img_id: number;
  file: string;               // e.g. "000000140640.jpg"
  orig_resolution: string;    // e.g. "640x426"
  gt_person: number;          // 0 or 1
  prob_person: number;        // [0, 1] confidence
  pred_person: number;        // 0 or 1 (threshold 0.5)
  correct: number;            // 0 or 1
  type: string;               // "TP" | "TN" | "FP" | "FN"
}

/** Summary section of InFi JSON */
export interface InfiSummary {
  model: string;
  test_data: string;
  total_images: number;
  input_size: string;
  threshold: number;
  accuracy: number;
  precision: number;
  recall: number;
  confusion_matrix: InfiConfusionMatrix;
}

export interface InfiConfusionMatrix {
  TP: number;
  TN: number;
  FP: number;
  FN: number;
}

/** Parsed InFi dataset */
export interface InfiDataset {
  summary: InfiSummary;
  results: InfiResultEntry[];
}

/** Available InFi JSON config files (rawfile paths) */
export const INFI_CONFIG_FILES: string[] = [
  'data_config/onnx_person_val2017_sorted.json',
  'data_config/onnx_person_val2017_100.json',
  'data_config/onnx_person_val2017_200.json',
  'data_config/onnx_person_val2017_500.json',
  'data_config/onnx_person_val2017_1000.json',
  'data_config/onnx_person_val2017_2000.json',
];

/** Short display labels for INFI_CONFIG_FILES (same order, for Select UI) */
export const INFI_CONFIG_LABELS: string[] = [
  'Sorted (5000)',
  '100 samples',
  '200 samples',
  '500 samples',
  '1000 samples',
  '2000 samples',
];

/** COCO images root directory in app sandbox */
export const COCO_IMAGES_DIR = 'COCO_val';

/** Exp 2 per-image measurement record */
export interface Exp2ImageRecord {
  imgId: number;
  file: string;
  origResolution: string;
  infiPredPerson: number;     // InFi gating decision
  infiProbPerson: number;     // InFi confidence
  gtPerson: number;           // ground truth
  yoloModel: string;          // which YOLO model was used
  latencyMs: number;          // YOLO inference latency
  preprocessMs: number;       // image load + preprocess time
  totalMs: number;            // end-to-end time
  stateName: string;          // system state during measurement
  snapshotCpu: number;
  snapshotTemp: number;
  snapshotFreqs: string;
}

// ── Progress type ──

export interface ExpProgress {
  status: string;
  phase: string;
  elapsedMs: number;
  sampleCount: number;
  currentFps: number;
  currentTemp: number;
  currentCpu: number;
  currentEnergyMw: number;
  message: string;
  csvPath: string;
}
