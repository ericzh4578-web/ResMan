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

import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'CsvLogger';

export class CsvLogger {
  private fd: number = -1;
  private path: string = '';
  private headerWritten: boolean = false;
  private rowCount: number = 0;

  constructor(
    private readonly dir: string,
    private readonly fileName: string,
    private readonly columns: string[]
  ) {
    this.path = `${dir}/${fileName}`;
  }

  async open(): Promise<void> {
    try {
      const file = await fileIo.open(this.path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      this.fd = file.fd;
      hilog.info(0x0000, TAG, 'Opened %{public}s', this.fileName);
    } catch (e) {
      hilog.error(0x0000, TAG, 'Failed to open %{public}s: %{public}s', this.fileName, JSON.stringify(e));
    }
  }

  async writeHeader(): Promise<void> {
    if (this.headerWritten || this.fd < 0) return;
    try {
      await fileIo.write(this.fd, this.columns.join(',') + '\n');
      this.headerWritten = true;
    } catch (e) {
      hilog.error(0x0000, TAG, 'writeHeader failed: %{public}s', JSON.stringify(e));
    }
  }

  async writeRow(values: (string | number)[]): Promise<void> {
    if (this.fd < 0) return;
    if (!this.headerWritten) {
      await this.writeHeader();
    }
    try {
      const line = values.map(v => String(v)).join(',') + '\n';
      await fileIo.write(this.fd, line);
      this.rowCount++;
    } catch (e) {
      hilog.error(0x0000, TAG, 'writeRow failed: %{public}s', JSON.stringify(e));
    }
  }

  async close(): Promise<void> {
    if (this.fd < 0) return;
    try {
      await fileIo.close(this.fd);
      hilog.info(0x0000, TAG, 'Closed %{public}s (%{public}d rows)', this.fileName, this.rowCount);
    } catch (e) {
      hilog.error(0x0000, TAG, 'close failed: %{public}s', JSON.stringify(e));
    }
    this.fd = -1;
  }

  getFilePath(): string {
    return this.path;
  }

  getRowCount(): number {
    return this.rowCount;
  }
}
