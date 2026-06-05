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

export enum DifficultyLevel {
  Easy = 0,
  Medium = 1,
  Hard = 2,
}

export interface SynthImageConfig {
  width: number;
  height: number;
  channels: number;
  difficulty: DifficultyLevel;
  seed: number;
}

export class SyntheticImageGenerator {
  static readonly WIDTH: number = 640;
  static readonly HEIGHT: number = 640;
  static readonly CHANNELS: number = 3;
  static readonly PIXELS: number = SyntheticImageGenerator.WIDTH * SyntheticImageGenerator.HEIGHT;
  static readonly TOTAL_FLOATS: number = SyntheticImageGenerator.PIXELS * SyntheticImageGenerator.CHANNELS;

  static generate(difficulty: DifficultyLevel, seed: number): Float32Array {
    const total = this.TOTAL_FLOATS;
    const buf = new Float32Array(total);

    let s = seed;
    const nextRand = (): number => {
      s = (s * 1664525 + 1013904223) & 0x7fffffff;
      return s / 0x7fffffff;
    };

    switch (difficulty) {
      case DifficultyLevel.Easy:
        for (let i = 0; i < total; i++) {
          buf[i] = 0.5 + (nextRand() - 0.5) * 0.1;
        }
        break;

      case DifficultyLevel.Medium:
        for (let y = 0; y < this.HEIGHT; y++) {
          for (let x = 0; x < this.WIDTH; x++) {
            const idx = (y * this.WIDTH + x) * this.CHANNELS;
            const freq = 0.02 + nextRand() * 0.05;
            const phase = nextRand() * Math.PI * 2;
            buf[idx]     = Math.sin(x * freq + phase) * 0.4 + 0.5;
            buf[idx + 1] = Math.cos(y * freq + phase) * 0.4 + 0.5;
            buf[idx + 2] = Math.sin((x + y) * freq * 0.5 + phase) * 0.4 + 0.5;
          }
        }
        break;

      case DifficultyLevel.Hard:
        for (let i = 0; i < total; i++) {
          buf[i] = nextRand();
        }
        break;
    }

    return buf;
  }

  static generateArrayBuffer(config: SynthImageConfig): ArrayBuffer {
    return this.generate(config.difficulty, config.seed).buffer;
  }

  static generateDataset(
    count: number,
    seedBase: number,
    difficulties: DifficultyLevel[]
  ): { data: Float32Array; configs: SynthImageConfig[] } {
    const totalFloats = count * this.TOTAL_FLOATS;
    const data = new Float32Array(totalFloats);
    const configs: SynthImageConfig[] = [];

    for (let i = 0; i < count; i++) {
      const diff = difficulties[i % difficulties.length];
      const singleImage = this.generate(diff, seedBase + i);
      const offset = i * this.TOTAL_FLOATS;
      data.set(singleImage, offset);
      let config: SynthImageConfig = {
        width: this.WIDTH,
        height: this.HEIGHT,
        channels: this.CHANNELS,
        difficulty: diff,
        seed: seedBase + i,
      };
      configs.push(config);
    }

    return { data, configs };
  }

  /**
   * Generate raw HWC float32 data [0,1] for inference.
   *
   * Output layout: HWC (channel-last, interleaved) — RGBRGBRGB...
   * Shape: 640×640×3 = 1,228,800 floats
   *
   * NOTE: This returns RAW HWC data. Most YOLO .ms models expect NCHW format.
   * Use YoloPreprocessor.preprocessFast() to convert HWC → NCHW before model.predict().
   *
   * @see YoloPreprocessor.preprocessFast
   * @see getInputForInferenceNCHW
   */
  static getInputForInference(config: SynthImageConfig): ArrayBuffer {
    const single = this.generate(config.difficulty, config.seed);
    return single.buffer;
  }

  /**
   * Generate preprocessed NCHW float32 tensor [0,1] ready for model.predict().
   *
   * Applies the full YOLO preprocessing pipeline:
   *   1. Generate synthetic HWC data (already 640×640, [0,1], RGB)
   *   2. HWC → CHW transpose
   *   3. Add batch dimension → NCHW
   *
   * Output layout: NCHW (channel-first, planar) — RRR...GGG...BBB...
   * Shape: N×3×640×640
   *
   * @param config     Image generation config (difficulty, seed, etc.)
   * @param batchSize  Batch dimension (default 1)
   * @returns          ArrayBuffer containing N×3×640×640 float32 tensor (NCHW)
   */
  static getInputForInferenceNCHW(config: SynthImageConfig, batchSize: number = 1): ArrayBuffer {
    // Step 1: Generate synthetic HWC data (Step 1-4 of YOLO pipeline are N/A for synthetic)
    //   - Already 640×640 → skip letterbox
    //   - Already [0,1] float32 → skip normalize
    //   - Already RGB → skip BGR→RGB
    const hwc = this.generate(config.difficulty, config.seed);

    // Step 5: HWC → CHW transpose
    const pixels = this.WIDTH * this.HEIGHT;
    const chw = new Float32Array(pixels * this.CHANNELS);
    for (let ch = 0; ch < this.CHANNELS; ch++) {
      const chOffset = ch * pixels;
      for (let i = 0; i < pixels; i++) {
        chw[chOffset + i] = hwc[i * this.CHANNELS + ch];
      }
    }

    // Step 6: Add batch dimension → NCHW
    if (batchSize <= 1) {
      return chw.buffer;
    }
    const total = chw.length * batchSize;
    const nchw = new Float32Array(total);
    for (let b = 0; b < batchSize; b++) {
      nchw.set(chw, b * chw.length);
    }
    return nchw.buffer;
  }
}
