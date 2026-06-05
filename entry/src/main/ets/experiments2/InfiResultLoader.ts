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
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  InfiResultEntry, InfiSummary, InfiDataset, InfiConfusionMatrix,
  INFI_CONFIG_FILES,
} from './ExperimentTypes';

const TAG = 'InfiResultLoader';

/**
 * Loader for pre-computed InFi inference results.
 *
 * The InFi model (224×224 binary person classifier) has already been run
 * on COCO val2017 images. Results are stored as JSON in rawfile/data_config/.
 *
 * This loader reads the JSON, parses it into typed objects, and provides
 * fast lookup by image filename for use in experiments.
 *
 * ── Usage ────────────────────────────────────────────────────────────
 *
 *   const loader = new InfiResultLoader();
 *   await loader.loadFromRawfile(context, INFI_CONFIG_FILES[0]);
 *   const entry = loader.getByFile('000000140640.jpg');
 *   // entry.pred_person === 1 → run heavy model
 *   // entry.pred_person === 0 → skip (gated)
 */
export class InfiResultLoader {
  private dataset: InfiDataset | null = null;
  private fileIndex: Map<string, InfiResultEntry> = new Map();
  private imgIdIndex: Map<number, InfiResultEntry> = new Map();

  // ── Properties ──

  get summary(): InfiSummary | null {
    return this.dataset?.summary ?? null;
  }

  get results(): InfiResultEntry[] {
    return this.dataset?.results ?? [];
  }

  get count(): number {
    return this.dataset?.results.length ?? 0;
  }

  get isLoaded(): boolean {
    return this.dataset !== null;
  }

  // ── Statistics ──

  get gatingPassCount(): number {
    // pred_person === 1 means InFi decided to run heavy model
    return this.results.filter((e: InfiResultEntry): boolean => e.pred_person === 1).length;
  }

  get gatingSkipCount(): number {
    return this.results.filter((e: InfiResultEntry): boolean => e.pred_person === 0).length;
  }

  get correctCount(): number {
    return this.results.filter((e: InfiResultEntry): boolean => e.correct === 1).length;
  }

  get tpCount(): number {
    return this.results.filter((e: InfiResultEntry): boolean => e.type === 'TP').length;
  }

  get tnCount(): number {
    return this.results.filter((e: InfiResultEntry): boolean => e.type === 'TN').length;
  }

  get fpCount(): number {
    return this.results.filter((e: InfiResultEntry): boolean => e.type === 'FP').length;
  }

  get fnCount(): number {
    return this.results.filter((e: InfiResultEntry): boolean => e.type === 'FN').length;
  }

  // ── Loading ──

  /**
   * Load InFi results from a rawfile JSON config.
   *
   * @param context     UIAbilityContext for resource manager access
   * @param rawfilePath Path relative to rawfile/, e.g. "data_config/onnx_person_val2017_100.json"
   */
  async loadFromRawfile(context: common.UIAbilityContext, rawfilePath: string): Promise<void> {
    const t0 = Date.now();

    // Read raw JSON bytes
    let rawBytes: Uint8Array;
    try {
      rawBytes = await context.resourceManager.getRawFileContent(rawfilePath);
      hilog.info(0x0000, TAG, 'Read %{public}s: %{public}d bytes',
        rawfilePath, rawBytes.length);
    } catch (e) {
      throw new Error('Failed to read InFi JSON: ' + rawfilePath + ' — ' + JSON.stringify(e));
    }

    // Decode Uint8Array to string (JSON is ASCII/UCS-2 compatible)
    let jsonStr = '';
    for (let i = 0; i < rawBytes.length; i++) {
      jsonStr += String.fromCharCode(rawBytes[i]);
    }

    // Parse JSON
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(jsonStr) as Record<string, Object>;
    } catch (e) {
      throw new Error('Failed to parse InFi JSON: ' + JSON.stringify(e));
    }

    // Extract summary
    const summaryObj = parsed['summary'] as Record<string, Object>;
    const cm = summaryObj['confusion_matrix'] as Record<string, Object>;
    let summary: InfiSummary = {
      model: (summaryObj['model'] as string) ?? '',
      test_data: (summaryObj['test_data'] as string) ?? '',
      total_images: (summaryObj['total_images'] as number) ?? 0,
      input_size: (summaryObj['input_size'] as string) ?? '',
      threshold: (summaryObj['threshold'] as number) ?? 0.5,
      accuracy: (summaryObj['accuracy'] as number) ?? 0,
      precision: (summaryObj['precision'] as number) ?? 0,
      recall: (summaryObj['recall'] as number) ?? 0,
      confusion_matrix: {
        TP: (cm['TP'] as number) ?? 0,
        TN: (cm['TN'] as number) ?? 0,
        FP: (cm['FP'] as number) ?? 0,
        FN: (cm['FN'] as number) ?? 0,
      } as InfiConfusionMatrix,
    };

    // Extract results array
    const resultsRaw = parsed['results'] as Record<string, Object>[];
    let results: InfiResultEntry[] = [];
    for (let i = 0; i < resultsRaw.length; i++) {
      const r = resultsRaw[i];
      let entry: InfiResultEntry = {
        rank: (r['rank'] as number) ?? i,
        img_id: (r['img_id'] as number) ?? 0,
        file: (r['file'] as string) ?? '',
        orig_resolution: (r['orig_resolution'] as string) ?? '',
        gt_person: (r['gt_person'] as number) ?? 0,
        prob_person: (r['prob_person'] as number) ?? 0,
        pred_person: (r['pred_person'] as number) ?? 0,
        correct: (r['correct'] as number) ?? 0,
        type: (r['type'] as string) ?? '',
      };
      results.push(entry);
    }

    // Build indices
    let fileIndex = new Map<string, InfiResultEntry>();
    let imgIdIndex = new Map<number, InfiResultEntry>();
    for (let i = 0; i < results.length; i++) {
      const e = results[i];
      if (e.file) {
        fileIndex.set(e.file, e);
      }
      if (e.img_id) {
        imgIdIndex.set(e.img_id, e);
      }
    }

    this.dataset = { summary, results };
    this.fileIndex = fileIndex;
    this.imgIdIndex = imgIdIndex;

    const elapsed = Date.now() - t0;
    hilog.info(0x0000, TAG,
      'Loaded %{public}d InFi results from %{public}s (%{public}dms)',
      results.length, rawfilePath, elapsed);
  }

  // ── Lookup ──

  /** Get InFi result by image filename (e.g. "000000140640.jpg") */
  getByFile(file: string): InfiResultEntry | null {
    return this.fileIndex.get(file) ?? null;
  }

  /** Get InFi result by COCO image ID */
  getByImgId(imgId: number): InfiResultEntry | null {
    return this.imgIdIndex.get(imgId) ?? null;
  }

  /**
   * Get a subset of results filtered by gating decision.
   * @param passOnly  true → only images where InFi says "run heavy" (pred_person=1)
   */
  getFiltered(passOnly: boolean): InfiResultEntry[] {
    if (passOnly) {
      return this.results.filter((e: InfiResultEntry): boolean => e.pred_person === 1);
    }
    return this.results.filter((e: InfiResultEntry): boolean => e.pred_person === 0);
  }

  /**
   * Get a balanced subset: N pass + N skip images.
   * Useful for controlled experiments.
   */
  getBalancedSubset(nPerClass: number): InfiResultEntry[] {
    const pass = this.getFiltered(true).slice(0, nPerClass);
    const skip = this.getFiltered(false).slice(0, nPerClass);
    return pass.concat(skip);
  }

  // ── Report ──

  /**
   * Generate a human-readable summary string for display / CSV header.
   */
  generateReport(): string {
    const s = this.summary;
    if (!s) return 'No InFi data loaded.';

    const cm = s.confusion_matrix;
    const total = this.count;
    const passPct = total > 0 ? (this.gatingPassCount / total * 100).toFixed(1) : '0';
    const skipPct = total > 0 ? (this.gatingSkipCount / total * 100).toFixed(1) : '0';

    return [
      '=== InFi Results Summary ===',
      'Model: ' + s.model,
      'Input: ' + s.input_size + ' | Threshold: ' + s.threshold,
      'Total images: ' + total,
      'Accuracy: ' + (s.accuracy * 100).toFixed(2) + '%',
      'Precision: ' + (s.precision * 100).toFixed(2) + '%',
      'Recall: ' + (s.recall * 100).toFixed(2) + '%',
      '── Gating ──',
      'Pass (run heavy): ' + this.gatingPassCount + ' (' + passPct + '%)',
      'Skip (gated):    ' + this.gatingSkipCount + ' (' + skipPct + '%)',
      '── Confusion Matrix ──',
      'TP=' + cm.TP + ' TN=' + cm.TN + ' FP=' + cm.FP + ' FN=' + cm.FN,
    ].join('\n');
  }
}
