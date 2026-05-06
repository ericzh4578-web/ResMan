/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
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

#ifndef NATIVE_CASE_YOLO_INFERENCE_H
#define NATIVE_CASE_YOLO_INFERENCE_H

#include "napi/native_api.h"
#include <vector>
#include <memory>
#include <chrono>

namespace YoloInference {

struct InferenceResult {
    double preprocessTime;  // 预处理时间（毫秒）
    double inferenceTime;   // 推理时间（毫秒）
    std::vector<float> outputs;  // 推理输出
};

/**
 * NAPI entry point: yoloInference(modelPath: string, inputData: ArrayBuffer,
 *                                  batchSize: number,
 *                                  callback: (result: object) => void): void
 *
 * Performs YOLO model inference with preprocessing and timing information.
 * Uses NPU for inference with specified batch size.
 *
 * @param modelPath Path to the YOLO model file
 * @param inputData Input image data as ArrayBuffer
 * @param batchSize Batch size for inference (default: 4)
 * @param callback Called with inference results including timing information
 */
napi_value YoloInference(napi_env env, napi_callback_info info);

} // namespace YoloInference

#endif // NATIVE_CASE_YOLO_INFERENCE_H
