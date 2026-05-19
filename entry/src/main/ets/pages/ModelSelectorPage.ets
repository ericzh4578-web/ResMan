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

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { mindSporeLite } from '@kit.MindSporeLiteKit';
import { TitleComponent } from '../view/TitleComponent';

const TAG = 'ModelSelectorPage';

// ── Available model files in rawfile ──
const AVAILABLE_INFI_MODELS: string[] = ['infi_coco_full_bsz1.ms'];
const AVAILABLE_YOLO_MODELS: string[] = [
  'yolov8n_bsz4.ms',
  'yolov8s_bsz4.ms',
  'yolov8m_bsz4.ms',
  'yolov8l_bsz4.ms',
  'yolov8x_bsz4.ms',
];

type YoloVariant = 'n' | 's' | 'm' | 'l' | 'x';

interface ModelInfo {
  fileName: string;
  displayName: string;
  size: string;
  type: string;
}

interface SelectOption {
  value: string;
}

function getModelInfo(fileName: string): ModelInfo {
  let displayName = fileName;
  let type = 'Unknown';
  let size = 'Unknown';

  if (fileName.indexOf('yolov8') >= 0) {
    type = 'YOLOv8 Object Detection';
    const variant = fileName.charAt(6) as YoloVariant;
    const variantNames: Record<YoloVariant, string> = {
      'n': 'nano',
      's': 'small',
      'm': 'medium',
      'l': 'large',
      'x': 'xlarge'
    };
    displayName = `YOLOv8 ${variantNames[variant] || variant}`;
    const sizeMap: Record<string, string> = {
      'n': '~6 MB',
      's': '~22 MB',
      'm': '~52 MB',
      'l': '~87 MB',
      'x': '~136 MB',
    };
    size = sizeMap[variant] || 'Unknown';
  } else if (fileName.indexOf('infi') >= 0) {
    type = 'InFi Image Classifier';
    displayName = 'InFi Coco Full';
    size = '~95 MB';
  }

  return { fileName, displayName, size, type };
}

function buildSelectOptions(models: string[]): SelectOption[] {
  return models.map((name: string): SelectOption => {
    return { value: name };
  });
}

@Component
export struct ModelSelectorPage {
  @Consume('pageInfos') pageInfos: NavPathStack;

  @State selectedInfiModel: string = AVAILABLE_INFI_MODELS[0];
  @State selectedYoloModel: string = AVAILABLE_YOLO_MODELS[3]; // yolov8l default
  @State status: string = 'Idle';
  @State isTesting: boolean = false;
  @State testResult: string = '';

  private infiSelectOptions: SelectOption[] = buildSelectOptions(AVAILABLE_INFI_MODELS);
  private yoloSelectOptions: SelectOption[] = buildSelectOptions(AVAILABLE_YOLO_MODELS);

  private get infiModelIndex(): number {
    const idx = AVAILABLE_INFI_MODELS.indexOf(this.selectedInfiModel);
    return idx >= 0 ? idx : 0;
  }
  private get yoloModelIndex(): number {
    const idx = AVAILABLE_YOLO_MODELS.indexOf(this.selectedYoloModel);
    return idx >= 0 ? idx : 0;
  }
  private get selectedInfiInfo(): ModelInfo {
    return getModelInfo(this.selectedInfiModel);
  }
  private get selectedYoloInfo(): ModelInfo {
    return getModelInfo(this.selectedYoloModel);
  }

  // ── Test-load the selected models ──────────────────────────────────────────

  private async testLoadModels(): Promise<void> {
    this.isTesting = true;
    this.status = 'Loading models…';
    this.testResult = '';

    try {
      const context = getContext(this) as common.UIAbilityContext;
      const resMgr = context.resourceManager;

      // Load InFi model
      const infiStart = Date.now();
      const infiBuffer = await resMgr.getRawFileContent(this.selectedInfiModel);
      const infiCtx: mindSporeLite.Context = {
        target: ['cpu'],
        cpu: { threadNum: 4, threadAffinityMode: 1, threadAffinityCoreList: [0, 1, 2], precisionMode: 'enforce_fp32' }
      };
      const infiModel = await mindSporeLite.loadModelFromBuffer(infiBuffer.buffer.slice(0), infiCtx);
      const infiTime = Date.now() - infiStart;
      hilog.info(0x0000, TAG, 'InFi model loaded: %{public}s (%{public}dms)', this.selectedInfiModel, infiTime);

      // Load YOLO model
      const yoloStart = Date.now();
      const yoloBuffer = await resMgr.getRawFileContent(this.selectedYoloModel);
      const yoloCtx: mindSporeLite.Context = {
        target: ['nnrt'],
        nnrt: { performanceMode: 3 }
      };
      const yoloModel = await mindSporeLite.loadModelFromBuffer(yoloBuffer.buffer.slice(0), yoloCtx);
      const yoloTime = Date.now() - yoloStart;
      hilog.info(0x0000, TAG, 'YOLO model loaded: %{public}s (%{public}dms)', this.selectedYoloModel, yoloTime);

      this.status = 'Both models loaded successfully';
      this.testResult = `InFi (${this.selectedInfiModel}): ${infiTime}ms\n`
        + `YOLO (${this.selectedYoloModel}): ${yoloTime}ms\n`
        + `Total: ${infiTime + yoloTime}ms`;

    } catch (e) {
      this.status = 'Load failed';
      this.testResult = `Error: ${JSON.stringify(e)}`;
      hilog.error(0x0000, TAG, 'testLoadModels failed: %{public}s', JSON.stringify(e));
    } finally {
      this.isTesting = false;
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 16 }) {

          // ── Description ──
          Column({ space: 4 }) {
            Text('Select AI model files for video inference.')
              .fontSize(13)
              .fontColor('#666666')
              .width('100%')
            Text('Models are loaded from the rawfile directory. Different YOLO variants offer speed/accuracy trade-offs.')
              .fontSize(12)
              .fontColor('#888888')
              .width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)

          // ── InFi Model Selection ──
          Column({ space: 8 }) {
            Text('InFi Model (Classifier)')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .width('100%')

            Select(this.infiSelectOptions)
              .width('100%')
              .height(40)
              .selected(this.infiModelIndex)
              .enabled(!this.isTesting)
              .onSelect((index: number) => {
                this.selectedInfiModel = AVAILABLE_INFI_MODELS[index];
              })

            Column({ space: 4 }) {
              Text(`File: ${this.selectedInfiInfo.fileName}`)
                .fontSize(12)
                .fontColor('#333333')
                .width('100%')
              Text(`Type: ${this.selectedInfiInfo.type}  |  Est. size: ${this.selectedInfiInfo.size}`)
                .fontSize(12)
                .fontColor('#666666')
                .width('100%')
            }
            .width('100%')
            .padding(8)
            .backgroundColor('#F0F8FF')
            .borderRadius(4)
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#FAFAFA')
          .borderRadius(8)

          // ── YOLO Model Selection ──
          Column({ space: 8 }) {
            Text('YOLO Model (Object Detection)')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .width('100%')

            Select(this.yoloSelectOptions)
              .width('100%')
              .height(40)
              .selected(this.yoloModelIndex)
              .enabled(!this.isTesting)
              .onSelect((index: number) => {
                this.selectedYoloModel = AVAILABLE_YOLO_MODELS[index];
              })

            Column({ space: 4 }) {
              Text(`File: ${this.selectedYoloInfo.fileName}`)
                .fontSize(12)
                .fontColor('#333333')
                .width('100%')
              Text(`Type: ${this.selectedYoloInfo.type}  |  Est. size: ${this.selectedYoloInfo.size}`)
                .fontSize(12)
                .fontColor('#666666')
                .width('100%')
            }
            .width('100%')
            .padding(8)
            .backgroundColor('#FFF3E0')
            .borderRadius(4)
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#FAFAFA')
          .borderRadius(8)

          // ── Test Load ──
          Column({ space: 8 }) {
            Button(this.isTesting ? 'Loading…' : 'Test Load Selected Models')
              .width('100%')
              .fontWeight(500)
              .fontSize(16)
              .enabled(!this.isTesting)
              .onClick(() => { this.testLoadModels(); })

            Text(`Status: ${this.status}`)
              .fontSize(13)
              .fontColor(this.status.indexOf('success') >= 0 ? '#4CAF50' :
                this.status.indexOf('failed') >= 0 ? '#C62828' : '#333333')
              .width('100%')

            if (this.testResult.length > 0) {
              Text(this.testResult)
                .fontSize(12)
                .fontColor('#333333')
                .width('100%')
                .padding(10)
                .backgroundColor('#F5F5F5')
                .borderRadius(4)
            }
          }
          .width('100%')

          // ── Model Comparison ──
          Column({ space: 8 }) {
            Text('YOLO Variant Comparison')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .width('100%')

            Column() {
              Row() {
                Text('Variant')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)
                Text('Speed')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)
                Text('Accuracy')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)
                Text('Size')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ top: 4, bottom: 4 })
              .border({ width: { bottom: 1 }, color: '#E0E0E0' })

              Row() {
                Text('n (nano)').fontSize(12).layoutWeight(1)
                Text('Fastest').fontSize(12).layoutWeight(1)
                Text('Lowest').fontSize(12).layoutWeight(1)
                Text('~6 MB').fontSize(12).layoutWeight(1)
              }
              .width('100%').padding({ top: 4, bottom: 4 })

              Row() {
                Text('s (small)').fontSize(12).layoutWeight(1)
                Text('Fast').fontSize(12).layoutWeight(1)
                Text('Low').fontSize(12).layoutWeight(1)
                Text('~22 MB').fontSize(12).layoutWeight(1)
              }
              .width('100%').padding({ top: 4, bottom: 4 })

              Row() {
                Text('m (medium)').fontSize(12).layoutWeight(1)
                Text('Moderate').fontSize(12).layoutWeight(1)
                Text('Moderate').fontSize(12).layoutWeight(1)
                Text('~52 MB').fontSize(12).layoutWeight(1)
              }
              .width('100%').padding({ top: 4, bottom: 4 })

              Row() {
                Text('l (large)').fontSize(12).layoutWeight(1)
                Text('Slow').fontSize(12).layoutWeight(1)
                Text('High').fontSize(12).layoutWeight(1)
                Text('~87 MB').fontSize(12).layoutWeight(1)
              }
              .width('100%').padding({ top: 4, bottom: 4 })

              Row() {
                Text('x (xlarge)').fontSize(12).layoutWeight(1)
                Text('Slowest').fontSize(12).layoutWeight(1)
                Text('Highest').fontSize(12).layoutWeight(1)
                Text('~136 MB').fontSize(12).layoutWeight(1)
              }
              .width('100%').padding({ top: 4, bottom: 4 })
            }
            .width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
    }
    .backgroundColor($r('app.color.background_color'))
    .title(TitleComponent('Model Selector', 'Browse and select AI model files'))
  }
}
