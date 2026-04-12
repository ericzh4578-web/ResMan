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
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';

const TAG = 'VideoDecoderPage';

@Entry
@Component
export struct VideoDecoderPage {
  // ── State ──────────────────────────────────────────────────────────────
  @State status: string = 'Idle';
  @State frameCount: number = 0;
  @State frameWidth: number = 0;
  @State frameHeight: number = 0;
  @State isDecoding: boolean = false;

  // Latest RGBA frame rendered via PixelMap (optional display)
  @State latestFramePixelMap: PixelMap | undefined = undefined;

  // ── Pick video from device gallery ────────────────────────────────────
  private async pickVideo(): Promise<string | null> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE,
        maxSelectNumber: 1,
      });
      if (result.photoUris && result.photoUris.length > 0) {
        // Convert content URI to a real file path accessible by native code.
        // On HarmonyOS the URI is already a file:// or /data/... path for local media.
        const uri = result.photoUris[0];
        hilog.info(0x0000, TAG, 'Selected video URI: %{public}s', uri);
        return uri;
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'pickVideo error: %{public}s', JSON.stringify(e));
    }
    return null;
  }

  // ── Start decoding ─────────────────────────────────────────────────────
  private startDecode(filePath: string): void {
    this.frameCount = 0;
    this.isDecoding = true;
    this.status = 'Decoding…';

    libentry.decodeVideoFrames(
      filePath,
      (frame: ArrayBuffer | null, width: number, height: number, isEos: number) => {
        if (isEos === 1 || frame === null) {
          this.status = `Done — ${this.frameCount} frames decoded`;
          this.isDecoding = false;
          hilog.info(0x0000, TAG, 'Decoding finished, total frames: %{public}d', this.frameCount);
          return;
        }

        this.frameCount += 1;
        this.frameWidth = width;
        this.frameHeight = height;

        // ── Optional: render the latest frame ──────────────────────────
        // Convert the RGBA ArrayBuffer to a PixelMap for display.
        // This is done asynchronously to avoid blocking the callback.
        this.renderFrame(frame, width, height);

        hilog.debug(0x0000, TAG, 'Frame #%{public}d  %{public}dx%{public}d  bytes=%{public}d',
          this.frameCount, width, height, frame.byteLength);
      }
    );
  }

  // ── Render one RGBA frame into a PixelMap ──────────────────────────────
  private renderFrame(rgba: ArrayBuffer, width: number, height: number): void {
    if (this.frameCount % 10 !== 0) return;

    const opts: image.InitializationOptions = {
      size: { width: width, height: height },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: false,
    };
    image.createPixelMap(rgba, opts).then((pm: PixelMap) => {
      this.latestFramePixelMap = pm;
    }).catch((e: Error) => {
      hilog.warn(0x0000, TAG, 'createPixelMap failed: %{public}s', e.message);
    });
  }

  // ── UI ─────────────────────────────────────────────────────────────────
  build() {
    NavDestination() {
      Column({ space: 16 }) {

        // Preview area
        if (this.latestFramePixelMap !== undefined) {
          Image(this.latestFramePixelMap)
            .width('100%')
            .aspectRatio(this.frameWidth > 0 ? this.frameWidth / this.frameHeight : 1.78)
            .objectFit(ImageFit.Contain)
            .borderRadius(8)
        } else {
          Row() {
            Text('No frame yet')
              .fontSize(14)
              .fontColor('#888888')
          }
          .width('100%')
          .height(200)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#1A000000')
          .borderRadius(8)
        }

        // Stats
        Column({ space: 4 }) {
          Text(`Status: ${this.status}`)
            .fontSize(14)
            .fontColor(this.isDecoding ? '#007DFF' : '#333333')
          Text(`Frames decoded: ${this.frameCount}`)
            .fontSize(14)
          if (this.frameWidth > 0) {
            Text(`Resolution: ${this.frameWidth} × ${this.frameHeight}`)
              .fontSize(14)
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#F5F5F5')
        .borderRadius(8)

        // Action button
        Button(this.isDecoding ? 'Decoding…' : 'Pick Video & Decode')
          .width('100%')
          .enabled(!this.isDecoding)
          .fontWeight(500)
          .fontSize(16)
          .onClick(async () => {
            const path = await this.pickVideo();
            if (path) {
              this.startDecode(path);
            } else {
              this.status = 'No video selected';
            }
          })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    }
    .title('Video Decoder (Buffer Mode)')
    .backgroundColor($r('app.color.background_color'))
  }
}
