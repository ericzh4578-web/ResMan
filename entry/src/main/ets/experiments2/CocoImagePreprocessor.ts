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

import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { YoloPreprocessor, PreprocessMetadata } from './YoloPreprocessor';

const TAG = 'CocoImagePreprocessor';

/**
 * Preprocessing result with metadata.
 */
export interface CocoPreprocessResult {
  /** NCHW float32 tensor ready for model.predict() */
  tensor: ArrayBuffer;
  /** Preprocessing metadata (steps executed, letterbox params, timing) */
  metadata: PreprocessMetadata | null;
  /** Original image dimensions [H, W] */
  originalSize: number[];
  /** Total time for load + decode + preprocess (ms) */
  totalMs: number;
}

/**
 * Loader for COCO val2017 JPEG images with YOLO preprocessing.
 *
 * Reads JPEG files from the app sandbox directory `COCO_val/`,
 * decodes them via @kit.ImageKit, and applies the full YOLO
 * preprocessing pipeline (letterbox → normalize → CHW → NCHW).
 *
 * ── Usage ────────────────────────────────────────────────────────────
 *
 *   const loader = new CocoImagePreprocessor(context);
 *   const result = await loader.loadAndPreprocess('000000140640.jpg');
 *   modelInputs[0].setData(result.tensor);   // NCHW ready
 *   const outputs = await model.predict(modelInputs);
 *
 * ── Pipeline (full path) ─────────────────────────────────────────────
 *
 *   JPEG file (sandbox: COCO_val/{filename})
 *     ↓ ImageSource + createPixelMap
 *   RGBA PixelMap (original resolution)
 *     ↓ readPixelsToBuffer + strip alpha
 *   HWC Float32Array [0,1], RGB (original W×H)
 *     ↓ YoloPreprocessor.preprocessFull()
 *       - BGR→RGB:      skip (decoder outputs RGB)
 *       - Letterbox:    resize + pad to 640×640
 *       - Normalize:    skip (already [0,1])
 *       - HWC→CHW:      channel transpose
 *       - Batch dim:    expand to NCHW
 *   NCHW Float32Array [1, 3, 640, 640]
 */
export class CocoImagePreprocessor {
  private context: common.UIAbilityContext;
  private cocoDir: string;

  /**
   * @param context   UIAbilityContext (for filesDir path resolution)
   * @param cocoDir   COCO images directory name under filesDir (default: "COCO_val")
   */
  constructor(context: common.UIAbilityContext, cocoDir: string = 'COCO_val') {
    this.context = context;
    this.cocoDir = cocoDir;
  }

  /**
   * Build the full sandbox path to a COCO image file.
   */
  getImagePath(filename: string): string {
    return this.context.filesDir + '/' + this.cocoDir + '/' + filename;
  }

  /**
   * Check if a COCO image file exists in the sandbox.
   */
  async fileExists(filename: string): Promise<boolean> {
    try {
      const filePath = this.getImagePath(filename);
      // Try to open for read — throws if not found
      const imageSource = image.createImageSource(filePath);
      const info = await imageSource.getImageInfo();
      return info !== null;
    } catch (_) {
      return false;
    }
  }

  /**
   * Load a JPEG image from COCO_val sandbox, decode to PixelMap,
   * read RGBA pixels, convert to HWC Float32Array [0,1].
   *
   * This is the "raw decode" step before YOLO preprocessing.
   *
   * @param filename  e.g. "000000140640.jpg"
   * @returns         { pixels: HWC Float32Array [0,1], width, height, channels }
   */
  async decodeToHwc(filename: string): Promise<{
    pixels: Float32Array;
    width: number;
    height: number;
    channels: number;
  }> {
    const filePath = this.getImagePath(filename);

    // Step A: Create ImageSource from file
    const imageSource = image.createImageSource(filePath);

    // Step B: Decode to PixelMap at original resolution
    const decodingOptions: image.DecodingOptions = {
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
    };
    const pixelMap = await imageSource.createPixelMap(decodingOptions);
    const info = await pixelMap.getImageInfo();
    const w = info.size.width;
    const h = info.size.height;

    // Step C: Read RGBA pixel buffer
    const bufferSize = w * h * 4;
    let readBuffer = new ArrayBuffer(bufferSize);
    await pixelMap.readPixelsToBuffer(readBuffer);
    const rgba = new Uint8Array(readBuffer);

    // Step D: Convert RGBA → RGB Float32Array [0,1]
    //   RGBA_8888 layout: [R, G, B, A, R, G, B, A, ...]
    //   Output HWC:       [R, G, B, R, G, B, ...]  (3 channels, no alpha)
    const rgbLen = w * h * 3;
    const rgb = new Float32Array(rgbLen);
    let outIdx = 0;
    for (let i = 0; i < rgba.length; i += 4) {
      rgb[outIdx]     = rgba[i]     / 255.0;   // R
      rgb[outIdx + 1] = rgba[i + 1] / 255.0;   // G
      rgb[outIdx + 2] = rgba[i + 2] / 255.0;   // B (skip alpha at i+3)
      outIdx += 3;
    }

    // Release PixelMap to free native memory
    pixelMap.release();

    return { pixels: rgb, width: w, height: h, channels: 3 };
  }

  /**
   * Full pipeline: load JPEG → decode → YOLO preprocessing → NCHW tensor.
   *
   * Applies the complete YOLO preprocessing:
   *   1. Decode JPEG to HWC Float32Array [0,1] (RGB, original size)
   *   2. Letterbox to 640×640 (keep aspect ratio, pad with gray 114)
   *   3. HWC → CHW transpose
   *   4. Add batch dimension → NCHW (1×3×640×640)
   *
   * @param filename    COCO image filename (e.g. "000000140640.jpg")
   * @param batchSize   Batch dimension (default 1)
   * @returns           Preprocessed tensor + metadata
   */
  async loadAndPreprocess(filename: string, batchSize: number = 1): Promise<CocoPreprocessResult> {
    const tTotal0 = Date.now();

    // ── Phase 1: Decode JPEG to HWC Float32Array ──
    const tDecode0 = Date.now();
    const decoded = await this.decodeToHwc(filename);
    const decodeMs = Date.now() - tDecode0;

    // ── Phase 2: YOLO preprocessing ──
    //   layout='rgb' — decoder outputs RGB (not BGR)
    //   valueRange='float01' — already [0,1] after /255
    const preprocessTensor = YoloPreprocessor.preprocessFull(
      decoded.pixels,
      decoded.height,
      decoded.width,
      decoded.channels,
      'rgb',       // decoder output is RGB
      'float01',   // already in [0,1]
      batchSize,
    );
    const preprocessMeta = YoloPreprocessor.getLastMetadata();

    const totalMs = Date.now() - tTotal0;

    hilog.info(0x0000, TAG,
      'Preprocessed %{public}s: %{public}d×%{public}d → NCHW (decode=%{public}dms, pp=%{public}dms, total=%{public}dms)',
      filename, decoded.width, decoded.height,
      decodeMs, preprocessMeta?.elapsedMs ?? 0, totalMs);

    return {
      tensor: preprocessTensor,
      metadata: preprocessMeta,
      originalSize: [decoded.height, decoded.width],
      totalMs: totalMs,
    };
  }

  /**
   * FUSED pipeline: decode + letterbox + CHW in a single pass.
   *
   * Instead of three separate loops (RGBA→RGB, letterbox fill+resize, HWC→CHW),
   * this does everything in ONE pass over the 3×640×640 output buffer.
   *
   * Per-pixel logic:
   *   For each (c, y, x) in CHW output:
   *     1. Map (y, x) back to source coordinates via letterbox params
   *     2. If inside source: read RGBA byte → normalize /255 → write to CHW[c]
   *     3. If in pad region: write 114/255 ≈ 0.447
   *
   * Expected speedup: 3-5× vs the unfused pipeline.
   *
   * @param filename  COCO image filename
   * @returns         CHW Float32Array (3×640×640) + metadata
   */
  async decodeAndPreprocessFused(filename: string): Promise<{
    chw: Float32Array;
    origW: number;
    origH: number;
    totalMs: number;
    /** Detailed timing breakdown (ms) */
    timing: Record<string, number>;
  }> {
    const TARGET = 640;
    const PAD_VAL = 114.0 / 255.0;
    const t0 = Date.now();
    let timing: Record<string, number> = {};

    // ── [1] file open: createImageSource ──
    let t = Date.now();
    const filePath = this.getImagePath(filename);
    const imageSource = image.createImageSource(filePath);
    timing['1_openFile'] = Date.now() - t;

    // ── [2] JPEG decode: createPixelMap (native) ──
    t = Date.now();
    const decodingOptions: image.DecodingOptions = {
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
    };
    const pixelMap = await imageSource.createPixelMap(decodingOptions);
    const info = await pixelMap.getImageInfo();
    timing['2_jpegDecode'] = Date.now() - t;

    const srcW = info.size.width;
    const srcH = info.size.height;
    const srcPixels = srcW * srcH;
    const bufferSize = srcPixels * 4;

    // ── [3] GPU→CPU: readPixelsToBuffer ──
    t = Date.now();
    let readBuffer = new ArrayBuffer(bufferSize);
    await pixelMap.readPixelsToBuffer(readBuffer);
    const rgba = new Uint8Array(readBuffer);
    pixelMap.release();
    timing['3_readPixels'] = Date.now() - t;

    // ── [4] compute letterbox params ──
    t = Date.now();
    const maxDim = Math.max(srcW, srcH);
    const r = TARGET / maxDim;
    const newW = Math.round(srcW * r);
    const newH = Math.round(srcH * r);
    const padTop = Math.floor((TARGET - newH) / 2);
    const padLeft = Math.floor((TARGET - newW) / 2);
    // invR = 1/r.  When maxDim == 640, invR == 1.0 — use fast path.
    const invR = maxDim / TARGET;
    const isIdentity = (maxDim === TARGET); // invR == 1.0, no scaling needed
    timing['4_params'] = Date.now() - t;

    // ── [5] fused fill + resize + CHW write ──
    t = Date.now();
    const pixels = TARGET * TARGET;
    const chw = new Float32Array(pixels * 3);

    // Fill all 3 planes with PAD_VAL in 3 fast native calls,
    // then overwrite the image region. Fewer calls > fewer bytes.
    for (let c = 0; c < 3; c++) {
      chw.fill(PAD_VAL, c * pixels, (c + 1) * pixels);
    }

    // Write image region: (newH × newW) pixels, with fast path if no scaling
    const outRowStride = TARGET;
    const srcRowStride = srcW;

    // Cache plane bases + norm factor for inner loop
    const planeR = 0;
    const planeG = pixels;
    const planeB = 2 * pixels;
    const norm = 1.0 / 255.0;

    if (isIdentity) {
      // ── FAST PATH: maxDim==640, identity mapping (most COCO images) ──
      for (let dy = 0; dy < newH; dy++) {
        if (dy >= srcH) continue;
        const outRowStart = (padTop + dy) * outRowStride + padLeft;
        const srcRowStart = dy * srcRowStride;

        for (let dx = 0; dx < newW; dx++) {
          if (dx >= srcW) continue;
          const oi = outRowStart + dx;
          const si = (srcRowStart + dx) * 4;

          chw[planeR + oi] = rgba[si]     * norm;
          chw[planeG + oi] = rgba[si + 1] * norm;
          chw[planeB + oi] = rgba[si + 2] * norm;
        }
      }
    } else {
      // ── SLOW PATH: nearest-neighbor scaling ──
      for (let dy = 0; dy < newH; dy++) {
        const sy = Math.floor(dy * invR);
        if (sy >= srcH) continue;
        const outRowStart = (padTop + dy) * outRowStride + padLeft;
        const srcRowStart = sy * srcRowStride;

        for (let dx = 0; dx < newW; dx++) {
          const sx = Math.floor(dx * invR);
          if (sx >= srcW) continue;
          const oi = outRowStart + dx;
          const si = (srcRowStart + sx) * 4;

          chw[planeR + oi] = rgba[si]     * norm;
          chw[planeG + oi] = rgba[si + 1] * norm;
          chw[planeB + oi] = rgba[si + 2] * norm;
        }
      }
    }
    timing['5_fusedLoop'] = Date.now() - t;

    timing['total'] = Date.now() - t0;
    return { chw, origW: srcW, origH: srcH, totalMs: timing['total'], timing };
  }

  /**
   * Fused batch preprocess: decode + preprocess bsz images → stacked NCHW tensor.
   *
   * @param filenames  Array of bsz COCO image filenames
   * @param bsz        Batch size (should match model _bszN)
   * @returns          NCHW ArrayBuffer (bsz×3×640×640) + per-image timings
   */
  async decodeAndPreprocessBatch(filenames: string[], bsz: number): Promise<{
    nchwTensor: ArrayBuffer;
    totalMs: number;
    perImageMs: number[];
    allTimings: Record<string, number>[];
  }> {
    const t0 = Date.now();
    const pixels = 640 * 640 * 3;
    const batchTensor = new Float32Array(pixels * bsz);
    const perImageMs: number[] = [];
    const allTimings: Record<string, number>[] = [];

    for (let i = 0; i < filenames.length; i++) {
      const tImg0 = Date.now();
      const fused = await this.decodeAndPreprocessFused(filenames[i]);
      batchTensor.set(fused.chw, i * pixels);
      perImageMs.push(Date.now() - tImg0);
      allTimings.push(fused.timing);
    }

    const totalMs = Date.now() - t0;
    return { nchwTensor: batchTensor.buffer, totalMs, perImageMs, allTimings };
  }
}
