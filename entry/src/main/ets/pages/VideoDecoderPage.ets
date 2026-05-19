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

import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { VideoDecoderSession, VideoDecoderSnapshot } from './VideoDecoderSession';

const TAG = 'VideoDecoderPage';

@Entry
@Component
export struct VideoDecoderPage {
  private readonly session: VideoDecoderSession = VideoDecoderSession.getInstance();
  private readonly sessionListener: (snapshot: VideoDecoderSnapshot) => void = (snapshot: VideoDecoderSnapshot): void => {
    this.status = snapshot.status;
    this.frameCount = snapshot.frameCount;
    this.frameWidth = snapshot.frameWidth;
    this.frameHeight = snapshot.frameHeight;
    this.isDecoding = snapshot.isDecoding;
    this.latestFramePixelMap = snapshot.latestFramePixelMap;
  };

  @State status: string = 'Idle';
  @State frameCount: number = 0;
  @State frameWidth: number = 0;
  @State frameHeight: number = 0;
  @State isDecoding: boolean = false;
  @State latestFramePixelMap: PixelMap | undefined = undefined;

  private async pickVideo(): Promise<string | null> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE,
        maxSelectNumber: 1,
      });
      if (result.photoUris && result.photoUris.length > 0) {
        const uri = result.photoUris[0];
        hilog.info(0x0000, TAG, 'Selected video URI: %{public}s', uri);
        return uri;
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'pickVideo error: %{public}s', JSON.stringify(e));
    }
    return null;
  }

  aboutToAppear(): void {
    this.session.subscribe(this.sessionListener);
  }

  aboutToDisappear(): void {
    this.session.unsubscribe(this.sessionListener);
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 16 }) {
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

          Column({ space: 4 }) {
            Text(`Status: ${this.status}`)
              .fontSize(14)
              .fontColor(this.isDecoding ? '#007DFF' : '#333333')
            Text(`Frames decoded: ${this.frameCount}`)
              .fontSize(14)
            if (this.frameWidth > 0) {
              Text(`Resolution: ${this.frameWidth} x ${this.frameHeight}`)
                .fontSize(14)
            }
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)

          Button(this.isDecoding ? 'Decoding...' : 'Pick Video & Decode')
            .width('100%')
            .enabled(!this.isDecoding)
            .fontWeight(500)
            .fontSize(16)
            .onClick(async () => {
              const path = await this.pickVideo();
              if (path) {
                await this.session.startDecode(path, getContext(this).filesDir);
              } else {
                this.status = 'No video selected';
              }
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
    }
    .title('Video Decoder (Buffer Mode)')
    .backgroundColor($r('app.color.background_color'))
  }
}
