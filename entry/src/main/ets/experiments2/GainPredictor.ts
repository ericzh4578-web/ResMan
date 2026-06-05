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

export class GainPredictor {
  private readonly weights: number[] = [
    0.05,
    -0.03,
    0.12,
    0.08,
    0.15,
    0.20,
    0.10,
    -0.05,
    0.02,
    0.18,
  ];
  private readonly bias: number = -0.5;
  private modelLoaded: boolean = false;

  ready(): boolean {
    return this.modelLoaded;
  }

  load(): void {
    this.modelLoaded = true;
  }

  predictGain(features: ImageFeatures): number {
    const featArray: number[] = [
      features.brightness,
      features.contrast,
      features.entropy,
      features.edgeDensity,
      features.numObjects / 100,
      features.avgConfidence,
      features.maxConfidence,
      features.bboxSizeMean / 100,
      features.bboxSizeStd / 50,
      features.smallObjectRatio,
    ];

    let score: number = this.bias;
    for (let i = 0; i < featArray.length; i++) {
      score += this.weights[i] * featArray[i];
    }

    return 1.0 / (1.0 + Math.exp(-score));
  }

  release(): void {
    this.modelLoaded = false;
  }
}
