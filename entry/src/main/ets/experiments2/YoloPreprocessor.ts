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

import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'YoloPreprocessor';

/**
 * YOLO Inference Preprocessor
 *
 * Implements the standard YOLO (v5/v8/v11) preprocessing pipeline.
 *
 * ── Pipeline Overview ──────────────────────────────────────────────────
 *
 *   Input:  Raw image  H×W×3, BGR, uint8 (or float32 [0, 255])
 *
 *   Step 1  Read image          → H×W×3, BGR, uint8
 *   Step 2  BGR → RGB           → H×W×3, RGB, uint8
 *   Step 3  Letterbox           → 640×640×3, RGB, uint8/float32
 *   Step 4  Normalize (/255.0)  → 640×640×3, RGB, float32, [0, 1]
 *   Step 5  HWC → CHW           → 3×640×640, float32 (CHW)
 *   Step 6  Add batch dim        → 1×3×640×640, float32 (NCHW)
 *
 *   Output: 1×3×640×640 float32 tensor (NCHW)
 *
 * ── Letterbox Detail ───────────────────────────────────────────────────
 *
 *   a) 缩放比:      r   = 640 / max(H, W)
 *   b) 等比缩放:    new_w = round(W × r), new_h = round(H × r)
 *   c) 灰边填充:    pad_w = 640 - new_w,  pad_h = 640 - new_h
 *                   top    = pad_h // 2,  bottom = pad_h - top
 *                   left   = pad_w // 2,  right  = pad_w - left
 *                   fill value = 114 (gray, → 114/255 ≈ 0.447 after norm)
 *
 * ── Memory Layout ──────────────────────────────────────────────────────
 *
 *   HWC (input):   [R00 G00 B00 | R01 G01 B01 | ... | R_wh G_wh B_wh]
 *                   stride: channels=3, contiguous per pixel
 *
 *   NCHW (output): [R plane (640×640) | G plane (640×640) | B plane (640×640)]
 *                   stride: H×W per channel, contiguous per plane
 *
 * ── Usage ──────────────────────────────────────────────────────────────
 *
 *   // Full pipeline (real image from file/camera):
 *   const tensor = YoloPreprocessor.preprocessFull(rawPixels, imgH, imgW, channels);
 *
 *   // Fast path (pre-resized 640×640 float32 [0,1] HWC data):
 *   const tensor = YoloPreprocessor.preprocessFast(synthetic640Data, batchSize);
 *
 *   // Get metadata about what was done:
 *   const meta = YoloPreprocessor.getLastMetadata();
 */

// ── Constants ──

/** Target input size for YOLO models */
const MODEL_SIZE = 640;

/** Pad fill value (gray in uint8, normalizes to ~0.447) */
const PAD_VALUE_U8 = 114;
const PAD_VALUE_NORM = 114.0 / 255.0; // ≈ 0.447

// ── Metadata type ──

export interface PreprocessMetadata {
  /** Steps executed in this preprocessing call */
  steps: string[];
  /** Original image dimensions [H, W, C] */
  originalShape: number[];
  /** Output tensor shape [N, C, H, W] */
  outputShape: number[];
  /** Whether letterbox padding was applied */
  letterboxApplied: boolean;
  /** Pad amounts [top, bottom, left, right] if letterbox was applied */
  padAmounts: number[];
  /** Scale ratio used for resize */
  scaleRatio: number;
  /** Whether BGR→RGB conversion was performed */
  bgrToRgb: boolean;
  /** Whether normalization was applied */
  normalized: boolean;
  /** Total preprocessing time in ms */
  elapsedMs: number;
}

// ── Main class ──

export class YoloPreprocessor {
  private static lastMetadata: PreprocessMetadata | null = null;

  /**
   * Get metadata about the most recent preprocessing call.
   */
  static getLastMetadata(): PreprocessMetadata | null {
    return this.lastMetadata;
  }

  // ═══════════════════════════════════════════════════════════════════
  // FULL PIPELINE: raw image → NCHW tensor
  // ═══════════════════════════════════════════════════════════════════

  /**
   * Full YOLO preprocessing pipeline for raw image data.
   *
   * @param rawData    Raw pixel data — Float32Array, layout depends on `layout`
   * @param origH      Original image height in pixels
   * @param origW      Original image width in pixels
   * @param origC      Original image channels (typically 3 for RGB)
   * @param layout     Input channel layout: 'bgr' | 'rgb'
   * @param valueRange Input value range: 'uint8' (0-255) | 'float01' ([0,1])
   * @param batchSize  Batch dimension size (default 1)
   * @returns          ArrayBuffer containing N×C×640×640 float32 tensor
   *
   * Pipeline applied:
   *   1. BGR→RGB (if layout='bgr')
   *   2. Letterbox resize + pad to 640×640
   *   3. Normalize to [0, 1] (if valueRange='uint8')
   *   4. HWC → CHW transpose
   *   5. Add batch dimension
   */
  static preprocessFull(
    rawData: Float32Array,
    origH: number,
    origW: number,
    origC: number,
    layout: 'bgr' | 'rgb',
    valueRange: 'uint8' | 'float01',
    batchSize: number = 1,
  ): ArrayBuffer {
    const t0 = Date.now();
    const steps: string[] = [];

    let data = rawData;
    let h = origH;
    let w = origW;
    let c = origC;
    let bgrToRgb = false;
    let normalized = false;
    let letterboxApplied = false;
    let padAmounts: number[] = [0, 0, 0, 0];
    let scaleRatio = 1.0;

    // ── Step 1 & 2: BGR → RGB ──
    if (layout === 'bgr') {
      steps.push('BGR→RGB');
      data = this.swapBgrToRgb(data, h, w, c);
      bgrToRgb = true;
    } else {
      steps.push('RGB (skip BGR→RGB)');
    }

    // ── Step 3: Letterbox ──
    if (h !== MODEL_SIZE || w !== MODEL_SIZE) {
      steps.push('Letterbox ' + h + '×' + w + ' → ' + MODEL_SIZE + '×' + MODEL_SIZE);
      const lb = this.letterbox(data, h, w, c, valueRange);
      data = lb.data;
      h = MODEL_SIZE;
      w = MODEL_SIZE;
      padAmounts = lb.padAmounts;
      scaleRatio = lb.scaleRatio;
      letterboxApplied = true;
    } else {
      steps.push('Letterbox (skip — already 640×640)');
    }

    // ── Step 4: Normalize [0,255] → [0,1] ──
    if (valueRange === 'uint8') {
      steps.push('Normalize /255.0');
      data = this.normalize(data);
      normalized = true;
    } else {
      steps.push('Normalize (skip — already [0,1])');
    }

    // ── Step 5: HWC → CHW ──
    steps.push('HWC→CHW transpose');
    const chw = this.hwcToChw(data, h, w, c);

    // ── Step 6: Add batch dimension ──
    const outputShape = [batchSize, c, h, w];
    let result: ArrayBuffer;
    if (batchSize === 1) {
      steps.push('NCHW (batch=1)');
      result = chw.buffer;
    } else {
      steps.push('NCHW (batch=' + batchSize + ')');
      result = this.addBatchDim(chw, batchSize);
    }

    const elapsed = Date.now() - t0;

    // Save metadata
    this.lastMetadata = {
      steps: steps,
      originalShape: [origH, origW, origC],
      outputShape: outputShape,
      letterboxApplied: letterboxApplied,
      padAmounts: padAmounts,
      scaleRatio: scaleRatio,
      bgrToRgb: bgrToRgb,
      normalized: normalized,
      elapsedMs: elapsed,
    };

    hilog.info(0x0000, TAG,
      'preprocessFull: %{public}s → NCHW %{public}d×%{public}d×%{public}d×%{public}d (%{public}dms)',
      steps.join(' → '), batchSize, c, h, w, elapsed);

    return result;
  }

  // ═══════════════════════════════════════════════════════════════════
  // FAST PATH: pre-resized 640×640 float32 [0,1] HWC → NCHW
  // ═══════════════════════════════════════════════════════════════════

  /**
   * Fast preprocessing for data that is already:
   *   - 640×640×3
   *   - float32 in [0, 1] range
   *   - HWC layout (interleaved channels)
   *
   * Only performs HWC→CHW transpose + batch dimension.
   * This is the typical path for synthetic/generated images.
   *
   * @param hwcData   Float32Array of size 640×640×3 = 1,228,800 (HWC layout)
   * @param batchSize Batch dimension size (default 1)
   * @returns         ArrayBuffer containing N×3×640×640 float32 tensor
   */
  static preprocessFast(hwcData: Float32Array, batchSize: number = 1): ArrayBuffer {
    const t0 = Date.now();
    const steps: string[] = [
      'RGB (already 640×640 [0,1] HWC)',
      'Letterbox (skip)',
      'Normalize (skip)',
      'HWC→CHW transpose',
    ];

    const chw = this.hwcToChw(hwcData, MODEL_SIZE, MODEL_SIZE, 3);

    let result: ArrayBuffer;
    if (batchSize === 1) {
      steps.push('NCHW (batch=1)');
      result = chw.buffer;
    } else {
      steps.push('NCHW (batch=' + batchSize + ')');
      result = this.addBatchDim(chw, batchSize);
    }

    const elapsed = Date.now() - t0;

    this.lastMetadata = {
      steps: steps,
      originalShape: [MODEL_SIZE, MODEL_SIZE, 3],
      outputShape: [batchSize, 3, MODEL_SIZE, MODEL_SIZE],
      letterboxApplied: false,
      padAmounts: [0, 0, 0, 0],
      scaleRatio: 1.0,
      bgrToRgb: false,
      normalized: false,
      elapsedMs: elapsed,
    };

    return result;
  }

  /**
   * Preprocess for batch inference: tile one CHW tensor into batchN.
   * Input: 3×640×640 CHW → Output: N×3×640×640 NCHW
   *
   * @param chwData   Float32Array of size 3×640×640 (CHW layout)
   * @param batchSize Number of copies in the batch dimension
   * @returns         ArrayBuffer containing N×3×640×640 float32 tensor
   */
  static preprocessBatch(chwData: Float32Array, batchSize: number): ArrayBuffer {
    return this.addBatchDim(chwData, batchSize);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Low-level operations (exposed for testing / custom pipelines)
  // ═══════════════════════════════════════════════════════════════════

  /** Step 2: Swap B and R channels in-place. Returns new Float32Array. */
  static swapBgrToRgb(data: Float32Array, h: number, w: number, c: number): Float32Array {
    if (c !== 3) return data; // only meaningful for 3-channel
    const total = h * w * c;
    const out = new Float32Array(total);
    for (let i = 0; i < total; i += 3) {
      out[i]     = data[i + 2]; // B → R
      out[i + 1] = data[i + 1]; // G → G
      out[i + 2] = data[i];     // R → B
    }
    return out;
  }

  /** Step 3: Letterbox resize + pad to 640×640. */
  static letterbox(
    data: Float32Array,
    origH: number,
    origW: number,
    channels: number,
    valueRange: 'uint8' | 'float01',
  ): { data: Float32Array; padAmounts: number[]; scaleRatio: number } {
    const target = MODEL_SIZE;
    const r = target / Math.max(origH, origW);
    const newH = Math.round(origH * r);
    const newW = Math.round(origW * r);

    const padH = target - newH;
    const padW = target - newW;
    const top = Math.floor(padH / 2);
    const bottom = padH - top;
    const left = Math.floor(padW / 2);
    const right = padW - left;

    const fillValue = valueRange === 'uint8' ? PAD_VALUE_U8 : PAD_VALUE_NORM;
    const totalOut = target * target * channels;
    const out = new Float32Array(totalOut);

    // Fill entire output with pad value first
    out.fill(fillValue);

    // Nearest-neighbor resize into the center region
    for (let y = 0; y < newH; y++) {
      const srcY = Math.floor(y / r);
      for (let x = 0; x < newW; x++) {
        const srcX = Math.floor(x / r);
        const dstIdx = ((top + y) * target + (left + x)) * channels;
        const srcIdx = (srcY * origW + srcX) * channels;
        for (let ch = 0; ch < channels; ch++) {
          out[dstIdx + ch] = data[srcIdx + ch];
        }
      }
    }

    let result: { data: Float32Array; padAmounts: number[]; scaleRatio: number } = {
      data: out,
      padAmounts: [top, bottom, left, right],
      scaleRatio: r,
    };
    return result;
  }

  /** Step 4: Normalize uint8 [0,255] → float32 [0,1] in-place (returns new array). */
  static normalize(data: Float32Array): Float32Array {
    const out = new Float32Array(data.length);
    for (let i = 0; i < data.length; i++) {
      out[i] = data[i] / 255.0;
    }
    return out;
  }

  /**
   * Step 5: HWC → CHW transpose.
   *
   * HWC layout: pixel-major — [R00 G00 B00 R01 G01 B01 ...]
   *   index = (y * W + x) * C + channel
   *
   * CHW layout: channel-major — [R00 R01 ... R_wh | G00 G01 ... G_wh | B00 B01 ... B_wh]
   *   index = channel * H * W + y * W + x
   */
  static hwcToChw(data: Float32Array, h: number, w: number, c: number): Float32Array {
    const pixels = h * w;
    const out = new Float32Array(pixels * c);

    // For each channel, extract the plane
    for (let ch = 0; ch < c; ch++) {
      const chOffset = ch * pixels;
      for (let i = 0; i < pixels; i++) {
        out[chOffset + i] = data[i * c + ch];
      }
    }

    return out;
  }

  /**
   * Step 6: Add batch dimension by tiling CHW data.
   *
   * Input:  float32[C*H*W] — single sample CHW
   * Output: float32[N*C*H*W] — N copies concatenated
   */
  static addBatchDim(chwData: Float32Array, batchSize: number): ArrayBuffer {
    if (batchSize <= 1) {
      return chwData.buffer.slice(0);
    }
    const totalPerSample = chwData.length;
    const total = totalPerSample * batchSize;
    const out = new Float32Array(total);
    for (let b = 0; b < batchSize; b++) {
      out.set(chwData, b * totalPerSample);
    }
    return out.buffer;
  }

  // ═══════════════════════════════════════════════════════════════════
  // Convenience / debugging
  // ═══════════════════════════════════════════════════════════════════

  /**
   * Return a human-readable summary of the preprocessing pipeline steps.
   */
  static describePipeline(): string {
    return [
      'YOLO Preprocessing Pipeline (6 steps):',
      '  1. Read image    → H×W×3, BGR, uint8',
      '  2. BGR→RGB       → H×W×3, RGB, uint8  [cv2.cvtColor(BGR2RGB)]',
      '  3. Letterbox     → 640×640×3, RGB, uint8',
      '     a) r = 640 / max(H, W)',
      '     b) new_w = round(W×r), new_h = round(H×r)',
      '     c) pad with gray (114) to 640×640',
      '  4. Normalize     → float32, [0, 1]     [/255.0]',
      '  5. HWC→CHW       → 3×640×640           [np.transpose(2,0,1)]',
      '  6. Batch dim     → 1×3×640×640         [np.expand_dims(0)]',
      '',
      'Output: NCHW float32 tensor for MindSpore Lite / ONNX inference',
    ].join('\n');
  }

  /**
   * Format preprocessing metadata as a pipe-delimited string for CSV logging.
   */
  static metadataToCsvFragment(meta: PreprocessMetadata): string {
    return [
      meta.steps.join('→'),
      meta.originalShape.join('x'),
      meta.outputShape.join('x'),
      meta.letterboxApplied ? '1' : '0',
      meta.padAmounts.join(';'),
      meta.scaleRatio.toFixed(4),
      meta.bgrToRgb ? '1' : '0',
      meta.normalized ? '1' : '0',
      meta.elapsedMs.toString(),
    ].join('|');
  }
}
