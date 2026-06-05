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

import libentry from 'libentry.so';
import { SystemStateDef } from './ExperimentTypes';

export class SystemStateManager {
  private currentState: SystemStateDef | null = null;
  private filesDir: string = '';

  setFilesDir(dir: string): void {
    this.filesDir = dir;
  }

  stopAll(): void {
    try { libentry.stopCpuLoad(); } catch (_) {}
    try { libentry.stopMemoryLoad(); } catch (_) {}
    try { libentry.stopIoLoad(); } catch (_) {}
    this.currentState = null;
  }

  /**
   * Apply a system state.
   *
   * Idle:         nothing — all simulators off.
   * Light/Mid/Heavy: user manually launches apps; simulators at level 0 (sleep-only thread)
   *                   act as negligible fallback if apps aren't started.
   * Extreme:      user launches apps + code adds CPU/Mem/IO load automatically.
   */
  applyState(state: SystemStateDef): void {
    this.stopAll();

    // Start CPU if level >= 0 (level 0 = sleep-only, negligible)
    if (state.cpuLevel >= 0) {
      try { libentry.startCpuLoad(state.cpuLevel); } catch (_) {}
    }

    // Start Memory load if level >= 0
    if (state.memLevel >= 0) {
      try { libentry.startMemoryLoad(state.memLevel); } catch (_) {}
    }

    // Start IO load if level >= 0 AND filesDir is set
    if (state.ioLevel >= 0 && this.filesDir.length > 0) {
      try { libentry.startIoLoad(state.ioLevel, this.filesDir); } catch (_) {}
    }

    this.currentState = state;
  }

  async stabilize(durationMs: number, onTick?: (remainingS: number) => void): Promise<void> {
    const start = Date.now();
    while (Date.now() - start < durationMs) {
      if (onTick) {
        const remaining = Math.ceil((durationMs - (Date.now() - start)) / 1000);
        onTick(remaining);
      }
      await new Promise<void>(r => setTimeout(r, 1000));
    }
  }

  getCurrentState(): SystemStateDef | null {
    return this.currentState;
  }

  isActive(): boolean {
    return this.currentState !== null;
  }

  /** Whether this state uses real app load (user manually launched). */
  isManualState(state: SystemStateDef): boolean {
    return state.name !== 'Idle';
  }

  /** Whether this state adds ResourceSimulator on top of apps. */
  hasSimulatorLoad(state: SystemStateDef): boolean {
    return state.cpuLevel > 0 || state.memLevel >= 0 || state.ioLevel > 0;
  }
}
