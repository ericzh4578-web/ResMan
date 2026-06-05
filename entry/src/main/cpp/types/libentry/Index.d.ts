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
 * Resource Simulator — control CPU / Memory / I/O load on the device.
 */

/** Start CPU load at 0 (idle), 1 (25%), 2 (50%), 3 (75%), or 4 (100%). */
export const startCpuLoad: (level: number) => void;

/** Stop the active CPU load. */
export const stopCpuLoad: () => void;

/** Start memory load at 0 (10%), 1 (15%), 2 (20%), or 3 (25%) of physical RAM. */
export const startMemoryLoad: (level: number) => void;

/** Free the allocated memory load buffer. */
export const stopMemoryLoad: () => void;

/** Start I/O random read/write load.
 *  level: 0 = weak, 1 = medium, 2 = strong.
 *  filesDir: app sandbox directory for the temporary test file. */
export const startIoLoad: (level: number, filesDir: string) => void;

/** Stop the active I/O load and delete the test file. */
export const stopIoLoad: () => void;

export interface SimulatorStatus {
  cpuActive: boolean;
  cpuLevel: number;
  memActive: boolean;
  memLevel: number;
  ioActive: boolean;
  ioLevel: number;
}

/** Return the current simulator state. */
export const getSimulatorStatus: () => SimulatorStatus;

/**
 * Decode a local video file (H.264 or H.265) in Buffer mode.
 *
 * @param fd        File descriptor of the video file (opened via fileIo.open).
 * @param fileSize  Total size of the file in bytes.
 * @param callback  Called once per decoded frame (and once at end-of-stream).
 *                  - frame:   RGBA8888 pixel data as ArrayBuffer, or null on EOS.
 *                  - width:   Frame width in pixels.
 *                  - height:  Frame height in pixels.
 *                  - isEos:   1 when the stream has ended, 0 otherwise.
 */
export const decodeVideoFrames: (
  fd: number,
  fileSize: number,
  callback: (frame: ArrayBuffer | null, width: number, height: number, isEos: number) => void,
  filesDir?: string
) => void;

/**
 * SysfsReader — read CPU / GPU frequencies from sysfs.
 */

/** Read a single CPU core frequency (kHz). coreIndex: 0-based. */
export const readCpuFreq: (coreIndex: number) => number;

/** Read all CPU core frequencies as a CSV string (core0,core1,... in kHz). */
export const readCpuFreqsCsv: () => string;

/** Read GPU frequency (kHz). Returns 0 on failure. */
export const readGpuFreq: () => number;