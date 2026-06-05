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
import { QualityResult } from './ExperimentTypes';

export class QualityScorer {
  private static readonly CONF_THRESHOLD: number = 0.01;

  static scoreFromOutputs(outputs: mindSporeLite.MSTensor[]): QualityResult {
    let qualityScore: number = 0;
    let avgConfidence: number = 0;
    let maxConfidence: number = 0;
    let detectionCount: number = 0;

    if (outputs.length === 0) {
      return {
        qualityScore: 0,
        avgConfidence: 0,
        maxConfidence: 0,
        detectionCount: 0,
      } as QualityResult;
    }

    const outputTensor = outputs[0];
    const data: Float32Array = outputTensor.getData() as Float32Array;

    if (!data || data.length === 0) {
      return {
        qualityScore: 0,
        avgConfidence: 0,
        maxConfidence: 0,
        detectionCount: 0,
      } as QualityResult;
    }

    let sum: number = 0;
    let maxVal: number = 0;
    let countAbove: number = 0;

    for (let i = 0; i < data.length; i++) {
      const prob = 1.0 / (1.0 + Math.exp(-data[i]));
      sum += prob;
      if (prob > maxVal) maxVal = prob;
      if (prob > QualityScorer.CONF_THRESHOLD) countAbove++;
    }

    avgConfidence = sum / data.length;
    maxConfidence = maxVal;
    detectionCount = countAbove;
    qualityScore = avgConfidence * Math.log(countAbove + 1);

    let result: QualityResult = {
      qualityScore: qualityScore,
      avgConfidence: avgConfidence,
      maxConfidence: maxConfidence,
      detectionCount: detectionCount,
    };
    return result;
  }

  static scoreModelOutput(model: mindSporeLite.Model): QualityResult {
    // Fallback: cannot call getOutputs directly; use the async predict path instead.
    let result: QualityResult = {
      qualityScore: 0,
      avgConfidence: 0,
      maxConfidence: 0,
      detectionCount: 0,
    };
    return result;
  }

  static computeGain(qualityA: QualityResult, qualityB: QualityResult): number {
    if (qualityA.qualityScore <= 0) {
      return qualityB.qualityScore;
    }
    return (qualityB.qualityScore - qualityA.qualityScore) / qualityA.qualityScore;
  }
}
