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

import { ImageFeatures } from './ExperimentTypes';
import { QualityResult } from './ExperimentTypes';

export class ImageFeatureExtractor {
  static readonly WIDTH: number = 640;
  static readonly HEIGHT: number = 640;
  static readonly CHANNELS: number = 3;

  static extractFeatures(inputData: Float32Array, quality: QualityResult): ImageFeatures {
    const brightness = this.computeBrightness(inputData);
    const contrast = this.computeContrast(inputData, brightness);
    const entropy = this.computeEntropy(inputData);
    const edgeDensity = this.computeEdgeDensity(inputData);

    const numObjects = quality.detectionCount;
    const avgConfidence = quality.avgConfidence;
    const maxConfidence = quality.maxConfidence;
    const bboxSizeMean = 0;
    const bboxSizeStd = 0;
    const smallObjectRatio = 0;

    let features: ImageFeatures = {
      brightness: brightness,
      contrast: contrast,
      entropy: entropy,
      edgeDensity: edgeDensity,
      numObjects: numObjects,
      avgConfidence: avgConfidence,
      maxConfidence: maxConfidence,
      bboxSizeMean: bboxSizeMean,
      bboxSizeStd: bboxSizeStd,
      smallObjectRatio: smallObjectRatio,
    };
    return features;
  }

  private static computeBrightness(data: Float32Array): number {
    let sum: number = 0;
    for (let i = 0; i < data.length; i++) {
      sum += data[i];
    }
    return sum / data.length;
  }

  private static computeContrast(data: Float32Array, mean: number): number {
    let sumSqDiff: number = 0;
    for (let i = 0; i < data.length; i++) {
      const diff = data[i] - mean;
      sumSqDiff += diff * diff;
    }
    return Math.sqrt(sumSqDiff / data.length);
  }

  private static computeEntropy(data: Float32Array): number {
    const bins: number = 32;
    const hist = new Float32Array(bins);
    for (let i = 0; i < bins; i++) hist[i] = 0;

    for (let i = 0; i < data.length; i++) {
      const bin = Math.min(bins - 1, Math.floor(data[i] * bins));
      hist[bin]++;
    }

    const total = data.length;
    let entropyVal: number = 0;
    for (let i = 0; i < bins; i++) {
      if (hist[i] > 0) {
        const p = hist[i] / total;
        entropyVal -= p * Math.log2(p);
      }
    }
    return entropyVal;
  }

  private static computeEdgeDensity(data: Float32Array): number {
    const h = this.HEIGHT;
    const w = this.WIDTH;
    const c = this.CHANNELS;
    let edgeSum: number = 0;
    let count: number = 0;

    for (let y = 0; y < h - 1; y++) {
      for (let x = 0; x < w - 1; x++) {
        const idx = (y * w + x) * c;
        edgeSum += Math.abs(data[idx] - data[idx + c]);
        edgeSum += Math.abs(data[idx] - data[idx + w * c]);
        count += 2;
      }
    }
    return count > 0 ? edgeSum / count : 0;
  }
}
