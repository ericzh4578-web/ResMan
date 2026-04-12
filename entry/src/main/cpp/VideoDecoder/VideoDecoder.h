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

#ifndef NATIVE_CASE_VIDEO_DECODER_H
#define NATIVE_CASE_VIDEO_DECODER_H

#include "napi/native_api.h"

namespace VideoDecoder {

/**
 * NAPI entry point: decodeVideoFrames(filePath: string, callback: (frame: ArrayBuffer, width: number, height: number,
 * isEos: boolean) => void): void
 *
 * Reads an H.264/H.265 video file from the given absolute path, decodes it in Buffer mode using
 * OH_VideoDecoder, converts each NV12 frame to RGBA8888, and delivers the result to the JS
 * callback as an ArrayBuffer on the main thread via a thread-safe function.
 */
napi_value DecodeVideoFrames(napi_env env, napi_callback_info info);

} // namespace VideoDecoder

#endif // NATIVE_CASE_VIDEO_DECODER_H
