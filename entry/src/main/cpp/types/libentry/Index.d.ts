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

import { resourceManager } from '@kit.LocalizationKit'

export const syncCallbackRead: (fileName: string, resMgr: resourceManager.ResourceManager, callback: object) => void;

export const asyncCallbackRead: (fileName: string, resMgr: resourceManager.ResourceManager, callback: object) => void;

export const asyncPromiseRead: (fileName: string, resMgr: resourceManager.ResourceManager) => Promise<string>;

export const threadSafeCaseFun: (work: object) => void;

export const libUvCaseFun: (work: object) => void;

export const destroy: () => void;

/**
 * Decode a local video file (H.264 or H.265) in Buffer mode.
 *
 * @param filePath  Absolute path to the video file on device storage.
 * @param callback  Called once per decoded frame (and once at end-of-stream).
 *                  - frame:   RGBA8888 pixel data as ArrayBuffer, or null on EOS.
 *                  - width:   Frame width in pixels.
 *                  - height:  Frame height in pixels.
 *                  - isEos:   1 when the stream has ended, 0 otherwise.
 */
export const decodeVideoFrames: (
  filePath: string,
  callback: (frame: ArrayBuffer | null, width: number, height: number, isEos: number) => void
) => void;