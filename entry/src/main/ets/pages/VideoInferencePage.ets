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
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { hidebug } from '@kit.PerformanceAnalysisKit';
import { thermal, batteryInfo } from '@kit.BasicServicesKit';
import { mindSporeLite } from '@kit.MindSporeLiteKit';
import { common } from '@kit.AbilityKit';

const TAG = 'VideoInferencePage';
const YOLO_INPUT_SIZE = 640;
const YOLO_BATCH_SIZE = 4;

// ─────────────────────────────────────────────────────────────────────────────
// Infi Model Inference Utilities
// ─────────────────────────────────────────────────────────────────────────────

function getLiteContext(): mindSporeLite.Context {
  let context: mindSporeLite.Context = {};
  context.target = ['cpu'];
  context.cpu = {
    threadNum: 4,
    threadAffinityMode: 1,
    threadAffinityCoreList: [0, 1, 2],
    precisionMode: 'enforce_fp32'
  };
  return context;
}

// ─────────────────────────────────────────────────────────────────────────────
// YOLO Model Inference Utilities
// ─────────────────────────────────────────────────────────────────────────────

function getYoloContext(): mindSporeLite.Context {
  let context: mindSporeLite.Context = {};
  context.target = ['nnrt'];
  context.nnrt = {};
  context.nnrt.performanceMode = 3;
  return context;
}

async function preprocessYolo(pixelMap: image.PixelMap): Promise<ArrayBuffer> {
  const TARGET_SIZE = 640;
  const startTime = Date.now();

  let info = await pixelMap.getImageInfo();
  if (info.size.width !== TARGET_SIZE || info.size.height !== TARGET_SIZE) {
    await pixelMap.scale(TARGET_SIZE / info.size.width, TARGET_SIZE / info.size.height);
  }

  const bufferSize = TARGET_SIZE * TARGET_SIZE * 4;
  let readBuffer = new ArrayBuffer(bufferSize);
  await pixelMap.readPixelsToBuffer(readBuffer);
  const imageArr = new Uint8Array(readBuffer);

  let float32View = new Float32Array(TARGET_SIZE * TARGET_SIZE * 3);
  let index = 0;

  for (let i = 0; i < imageArr.length; i += 4) {
    float32View[index] = imageArr[i] / 255.0;
    float32View[index + 1] = imageArr[i + 1] / 255.0;
    float32View[index + 2] = imageArr[i + 2] / 255.0;
    index += 3;
  }

  const duration = Date.now() - startTime;
  hilog.info(0x0000, TAG, '[YOLO_PREPROCESS] YOLO preprocessing completed | Duration: %{public}dms | Size: 640×640×3 | Batch size: %{public}d', duration, YOLO_BATCH_SIZE);

  return float32View.buffer;
}

async function predictYoloModel(model: mindSporeLite.Model, inputBuffer: ArrayBuffer): Promise<mindSporeLite.MSTensor[]> {
  const startTime = Date.now();

  let modelInputs: mindSporeLite.MSTensor[] = model.getInputs();
  modelInputs[0].setData(inputBuffer);

  let modelOutputs: mindSporeLite.MSTensor[] = await model.predict(modelInputs);

  const duration = Date.now() - startTime;
  hilog.info(0x0000, TAG, '[YOLO_INFERENCE] YOLO inference completed | Duration: %{public}dms | Output tensors: %{public}d | Batch size: %{public}d', duration, modelOutputs.length, YOLO_BATCH_SIZE);

  return modelOutputs;
}

function parseYoloOutput(outputs: mindSporeLite.MSTensor[]): string {
  if (!outputs || outputs.length === 0) {
    return 'No output';
  }

  const output = outputs[0];
  const data = new Float32Array(output.getData());

  if (!data || data.byteLength === 0) {
    return 'Empty output data';
  }

  const resultStr = data.toString();
  hilog.info(0x0000, TAG, '[YOLO_OUTPUT] YOLO predictions: %{public}s', resultStr);

  return resultStr;
}

async function preprocessInFi(pixelMap: image.PixelMap): Promise<ArrayBuffer> {
  const TARGET_SIZE = 224;
  const startTime = Date.now();

  let info = await pixelMap.getImageInfo();
  if (info.size.width !== TARGET_SIZE || info.size.height !== TARGET_SIZE) {
    await pixelMap.scale(TARGET_SIZE / info.size.width, TARGET_SIZE / info.size.height);
  }

  const bufferSize = TARGET_SIZE * TARGET_SIZE * 4;
  let readBuffer = new ArrayBuffer(bufferSize);
  await pixelMap.readPixelsToBuffer(readBuffer);
  const imageArr = new Uint8Array(readBuffer);

  let float32View = new Float32Array(TARGET_SIZE * TARGET_SIZE * 3);
  let index = 0;

  for (let i = 0; i < imageArr.length; i += 4) {
    float32View[index] = imageArr[i] / 255.0;
    float32View[index + 1] = imageArr[i + 1] / 255.0;
    float32View[index + 2] = imageArr[i + 2] / 255.0;
    index += 3;
  }

  const duration = Date.now() - startTime;
  hilog.info(0x0000, TAG, '[PREPROCESS] InFi preprocessing completed | Duration: %{public}dms | Size: 224×224×3', duration);

  return float32View.buffer;
}

async function predictInFiModel(model: mindSporeLite.Model, inputBuffer: ArrayBuffer): Promise<mindSporeLite.MSTensor[]> {
  const startTime = Date.now();

  let modelInputs: mindSporeLite.MSTensor[] = model.getInputs();
  modelInputs[0].setData(inputBuffer);

  let modelOutputs: mindSporeLite.MSTensor[] = await model.predict(modelInputs);

  const duration = Date.now() - startTime;
  hilog.info(0x0000, TAG, '[INFERENCE] InFi inference completed | Duration: %{public}dms | Output tensors: %{public}d', duration, modelOutputs.length);

  return modelOutputs;
}

function parseInFiOutput(outputs: mindSporeLite.MSTensor[]): string {
  if (!outputs || outputs.length === 0) {
    return 'No output';
  }

  try {
    const output = outputs[0];
    const data = new Float32Array(output.getData());

    if (!data || data.byteLength === 0) {
      return 'Empty output data';
    }

    const resultStr = data.toString()

    hilog.info(0x0000, TAG, '[OUTPUT] InFi predictions: %{public}s', resultStr);

    return resultStr;
  } catch (e) {
    hilog.error(0x0000, TAG, '[OUTPUT] Failed to parse output: %{public}s', JSON.stringify(e));
    return 'Parse error';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pipeline queue item types
// ─────────────────────────────────────────────────────────────────────────────

interface FrameItem {
  rgba: ArrayBuffer;
  width: number;
  height: number;
  frameIndex: number;
}

@Entry
@Component
export struct VideoInferencePage {
  // ── State ──────────────────────────────────────────────────────────────
  @State status: string = 'Idle';
  @State frameCount: number = 0;
  @State frameWidth: number = 0;
  @State frameHeight: number = 0;
  @State isProcessing: boolean = false;
  @State inferenceResults: string = '';
  @State inferenceSpeed: string = '';
  @State totalInferences: number = 0;

  // YOLO inference states
  @State yoloInferenceResults: string = '';
  @State yoloInferenceSpeed: string = '';
  @State yoloPreprocessTime: number = 0;
  @State yoloInferenceTime: number = 0;
  @State totalYoloInferences: number = 0;

  // Latest RGBA frame rendered via PixelMap
  @State latestFramePixelMap: PixelMap | undefined = undefined;

  // Resource monitoring
  @State cpuUsage: number = 0;
  @State systemCpuUsage: number = 0;
  @State memoryInfo: string = '';
  @State systemMemoryInfo: string = '';
  @State thermalLevel: number = 0;
  @State batterySOC: number = 0;
  @State batteryTemp: number = 0;
  @State batteryCurrent: number = 0;
  @State batteryVoltage: number = 0;
  @State isMonitoring: boolean = false;

  // Decoding speed
  @State decodingSpeed: string = '';
  @State lastDecodingTime: number = 0;

  private monitoringTimer: number = -1;
  private infiModel: mindSporeLite.Model | null = null;
  private yoloModel: mindSporeLite.Model | null = null;
  private startTime: number = 0;
  private decodingStartTime: number = 0;

  // ── Pipeline queues ────────────────────────────────────────────────────
  // decodeQueue: frames waiting for InFi inference
  // yoloQueue:   frames that passed InFi threshold (output[0] > 0.5)
  private decodeQueue: FrameItem[] = [];
  private yoloQueue: FrameItem[] = [];
  private readonly QUEUE_MAX = 8; // back-pressure cap per queue
  private isDecodeDone: boolean = false;
  private infiWorkerRunning: boolean = false;
  private yoloWorkerRunning: boolean = false;

  // ── Pick video from device gallery ────────────────────────────────────
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

  // ── Load Infi model ───────────────────────────────────────────────
  private async loadInfiModel(): Promise<boolean> {
    try {
      hilog.info(0x0000, TAG, '[INIT] Loading InFi model...');
      const context = getContext(this) as common.UIAbilityContext;
      const resMgr = context.resourceManager;
      const modelBuffer = await resMgr.getRawFileContent('infi_coco_full_bsz1.ms');
      const msContext = getLiteContext();
      this.infiModel = await mindSporeLite.loadModelFromBuffer(modelBuffer.buffer.slice(0), msContext);
      hilog.info(0x0000, TAG, '[INIT] InFi model loaded successfully');
      return true;
    } catch (e) {
      hilog.error(0x0000, TAG, '[INIT] Failed to load model: %{public}s', JSON.stringify(e));
      this.status = `Model load error: ${JSON.stringify(e)}`;
      return false;
    }
  }

  // ── Load YOLO model ───────────────────────────────────────────────
  private async loadYoloModel(): Promise<boolean> {
    try {
      hilog.info(0x0000, TAG, '[INIT] Loading YOLO model with batch size: %{public}d', YOLO_BATCH_SIZE);
      const context = getContext(this) as common.UIAbilityContext;
      const resMgr = context.resourceManager;
      const modelBuffer = await resMgr.getRawFileContent('yolov8l_bsz4.ms');
      const msContext = getYoloContext();
      this.yoloModel = await mindSporeLite.loadModelFromBuffer(modelBuffer.buffer.slice(0), msContext);
      hilog.info(0x0000, TAG, '[INIT] YOLO model loaded successfully | NPU enabled | Batch size: %{public}d', YOLO_BATCH_SIZE);
      return true;
    } catch (e) {
      hilog.error(0x0000, TAG, '[INIT] Failed to load YOLO model: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  // ── InFi worker loop: consumes decodeQueue ────────────────────────────
  // Runs continuously until decoding is done and queue is empty.
  // If InFi output[0] > 0.5, pushes frame to yoloQueue.
  private async infiWorkerLoop(): Promise<void> {
    if (this.infiWorkerRunning) return;
    this.infiWorkerRunning = true;

    while (true) {
      if (this.decodeQueue.length === 0) {
        if (this.isDecodeDone) break;
        // Yield to event loop and retry
        await new Promise<void>(resolve => setTimeout(resolve, 4));
        continue;
      }

      const item = this.decodeQueue.shift()!;

      if (!this.infiModel) {
        continue;
      }

      try {
        const opts: image.InitializationOptions = {
          size: { width: item.width, height: item.height },
          pixelFormat: image.PixelMapFormat.RGBA_8888,
          editable: false,
        };
        const pixelMap = await image.createPixelMap(item.rgba, opts);

        const preprocessStart = Date.now();
        const inputBuffer = await preprocessInFi(pixelMap);
        const preprocessDuration = Date.now() - preprocessStart;

        const inferenceStart = Date.now();
        const outputs = await predictInFiModel(this.infiModel, inputBuffer);
        const inferenceDuration = Date.now() - inferenceStart;

        pixelMap.release();

        const resultStr = parseInFiOutput(outputs);
        this.inferenceResults = resultStr;
        this.totalInferences++;

        const elapsed = Date.now() - this.startTime;
        const fps = (this.totalInferences / elapsed) * 1000;
        this.inferenceSpeed = `Frame #${item.frameIndex} | Pre: ${preprocessDuration}ms | Inf: ${inferenceDuration}ms | FPS: ${fps.toFixed(2)}`;

        hilog.info(0x0000, TAG, '[INFI_WORKER] Frame #%{public}d | Pre: %{public}dms | Inf: %{public}dms | FPS: %{public}.2f',
          item.frameIndex, preprocessDuration, inferenceDuration, fps);

        // Gate: only forward to YOLO if first output > 0.5
        if (this.yoloModel && outputs.length > 0) {
          const firstVal = new Float32Array(outputs[0].getData())[0];
          if (firstVal > 0.5 && this.yoloQueue.length < this.QUEUE_MAX) {
            this.yoloQueue.push(item);
            hilog.info(0x0000, TAG, '[INFI_WORKER] Frame #%{public}d forwarded to YOLO (score: %{public}.3f)',
              item.frameIndex, firstVal);
          }
        }
      } catch (e) {
        hilog.error(0x0000, TAG, '[INFI_WORKER] Error on frame #%{public}d: %{public}s', item.frameIndex, JSON.stringify(e));
      }
    }

    this.infiWorkerRunning = false;
    hilog.info(0x0000, TAG, '[INFI_WORKER] Worker loop finished');
  }

  // ── YOLO worker loop: consumes yoloQueue ──────────────────────────────
  private async yoloWorkerLoop(): Promise<void> {
    if (this.yoloWorkerRunning) return;
    this.yoloWorkerRunning = true;

    while (true) {
      if (this.yoloQueue.length === 0) {
        // Stop when InFi is also done (no more frames will arrive)
        if (this.isDecodeDone && !this.infiWorkerRunning) break;
        await new Promise<void>(resolve => setTimeout(resolve, 4));
        continue;
      }

      const item = this.yoloQueue.shift()!;

      if (!this.yoloModel) {
        continue;
      }

      try {
        const opts: image.InitializationOptions = {
          size: { width: item.width, height: item.height },
          pixelFormat: image.PixelMapFormat.RGBA_8888,
          editable: false,
        };
        const pixelMap = await image.createPixelMap(item.rgba, opts);

        const preprocessStart = Date.now();
        const inputBuffer = await preprocessYolo(pixelMap);
        const preprocessDuration = Date.now() - preprocessStart;

        const inferenceStart = Date.now();
        const outputs = await predictYoloModel(this.yoloModel, inputBuffer);
        const inferenceDuration = Date.now() - inferenceStart;

        pixelMap.release();

        this.yoloInferenceResults = 'Yolo Results Too Long';
        this.yoloPreprocessTime = preprocessDuration;
        this.yoloInferenceTime = inferenceDuration;
        this.totalYoloInferences++;

        const elapsed = Date.now() - this.startTime;
        const fps = (this.totalYoloInferences / elapsed) * 1000;
        this.yoloInferenceSpeed = `Frame #${item.frameIndex} | Pre: ${preprocessDuration}ms | Inf: ${inferenceDuration}ms | FPS: ${fps.toFixed(2)}`;

        hilog.info(0x0000, TAG, '[YOLO_WORKER] Frame #%{public}d | Pre: %{public}dms | Inf: %{public}dms | FPS: %{public}.2f | Batch: %{public}d',
          item.frameIndex, preprocessDuration, inferenceDuration, fps, YOLO_BATCH_SIZE);
      } catch (e) {
        hilog.error(0x0000, TAG, '[YOLO_WORKER] Error on frame #%{public}d: %{public}s', item.frameIndex, JSON.stringify(e));
      }
    }

    this.yoloWorkerRunning = false;
    hilog.info(0x0000, TAG, '[YOLO_WORKER] Worker loop finished');

    // Both workers done — finalize status
    this.status = `Done — ${this.frameCount} frames | InFi: ${this.totalInferences} | YOLO: ${this.totalYoloInferences}`;
    this.isProcessing = false;
  }

  private async startProcessing(uri: string): Promise<void> {
    // Reset state
    this.frameCount = 0;
    this.totalInferences = 0;
    this.totalYoloInferences = 0;
    this.isProcessing = true;
    this.isDecodeDone = false;
    this.decodeQueue = [];
    this.yoloQueue = [];
    this.status = 'Loading models…';
    this.inferenceResults = '';
    this.inferenceSpeed = '';
    this.yoloInferenceResults = '';
    this.yoloInferenceSpeed = '';
    this.decodingSpeed = '';
    this.startTime = Date.now();
    this.decodingStartTime = Date.now();

    try {
      const infiModelLoaded = await this.loadInfiModel();
      if (!infiModelLoaded) {
        this.isProcessing = false;
        return;
      }

      const yoloModelLoaded = await this.loadYoloModel();
      if (!yoloModelLoaded) {
        hilog.warn(0x0000, TAG, '[INIT] YOLO model load failed, continuing with InFi only');
      }

      this.status = 'Processing…';

      // Start worker loops concurrently (they self-terminate when queues drain)
      this.infiWorkerLoop();
      this.yoloWorkerLoop();

      let file: fileIo.File | null = null;
      file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(file.fd);
      const fileSize = stat.size;

      const context = getContext(this) as common.UIAbilityContext;

      // Stage 1 — Decode: push every 5th frame into decodeQueue (back-pressure aware)
      libentry.decodeVideoFrames(
        file.fd,
        fileSize,
        (frame: ArrayBuffer | null, width: number, height: number, isEos: number) => {
          if (isEos === 1 || frame === null) {
            this.isDecodeDone = true;
            if (file !== null) {
              fileIo.close(file.fd).catch((e: Error) => {
                hilog.warn(0x0000, TAG, 'close fd failed: %{public}s', e.message);
              });
              file = null;
            }
            hilog.info(0x0000, TAG, '[DECODE] EOS reached | Total frames decoded: %{public}d', this.frameCount);
            return;
          }

          this.frameCount += 1;
          this.frameWidth = width;
          this.frameHeight = height;
          this.renderFrame(frame, width, height);

          const elapsed = Date.now() - this.decodingStartTime;
          const decodingFps = (this.frameCount / elapsed) * 1000;
          this.decodingSpeed = `Decoding: ${this.frameCount} frames | FPS: ${decodingFps.toFixed(2)}`;

          // Sample every 5th frame; drop if queue is full (back-pressure)
          if (this.frameCount % 5 === 0 && this.decodeQueue.length < this.QUEUE_MAX) {
            this.decodeQueue.push({ rgba: frame, width, height, frameIndex: this.frameCount });
          }
        },
        context.filesDir
      );
    } catch (e) {
      hilog.error(0x0000, TAG, '[ERROR] startProcessing failed: %{public}s', JSON.stringify(e));
      this.status = `Error: ${JSON.stringify(e)}`;
      this.isProcessing = false;
    }
  }

  // ── Resource monitoring ────────────────────────────────────────────────
  private startMonitoring(): void {
    if (this.isMonitoring) return;
    this.isMonitoring = true;
    this.monitoringTimer = setInterval(() => {
      this.cpuUsage = Math.max(0, hidebug.getCpuUsage()) * 100;
      this.systemCpuUsage = hidebug.getSystemCpuUsage() * 100;
      this.thermalLevel = thermal.getThermalLevel();
      this.batterySOC = batteryInfo.batterySOC;
      this.batteryTemp = batteryInfo.batteryTemperature / 10;
      this.batteryCurrent = batteryInfo.nowCurrent;
      this.batteryVoltage = batteryInfo.voltage;

      let pss = hidebug.getPss();
      this.memoryInfo = (Number(pss) / 1024).toFixed(2) + ' MB';

      let systemMemInfo = hidebug.getSystemMemInfo();
      let totalMemMB = (Number(systemMemInfo.totalMem) / 1024).toFixed(2);
      let freeMemMB = (Number(systemMemInfo.freeMem) / 1024).toFixed(2);
      let availableMemMB = (Number(systemMemInfo.availableMem) / 1024).toFixed(2);
      this.systemMemoryInfo = `总: ${totalMemMB}MB | 空闲: ${freeMemMB}MB | 可用: ${availableMemMB}MB`;
    }, 2000) as number;
  }

  private stopMonitoring(): void {
    if (this.monitoringTimer !== -1) {
      clearInterval(this.monitoringTimer);
      this.monitoringTimer = -1;}
    this.isMonitoring = false;
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
  aboutToAppear(): void {
    this.startMonitoring();
  }

  aboutToDisappear(): void {
    this.stopMonitoring();
  }

  build() {
    NavDestination() {
      Scroll() {
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
              .fontColor(this.isProcessing ? '#007DFF' : '#333333')
            Text(`Frames processed: ${this.frameCount}`)
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

          // Inference results
          if (this.inferenceResults.length > 0) {
            Column({ space: 4 }) {
              Text('Inference Results')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
              Text(this.inferenceResults)
                .fontSize(12)
                .fontColor('#666666')
                .maxLines(3)
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#F0F8FF')
            .borderRadius(8)
          }

          // Inference speed
          if (this.inferenceSpeed.length > 0) {
            Column({ space: 4 }) {
              Text('Performance')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
              Text(this.inferenceSpeed)
                .fontSize(12)
                .fontColor('#FF6B35')
                .maxLines(2)
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#FFF3E0')
            .borderRadius(8)
          }

          // Decoding speed
          if (this.decodingSpeed.length > 0) {
            Column({ space: 4 }) {
              Text('Decoding Speed')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
              Text(this.decodingSpeed)
                .fontSize(12)
                .fontColor('#4CAF50')
                .maxLines(2)
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#E8F5E9')
            .borderRadius(8)
          }

          // YOLO Inference results
          if (this.yoloInferenceResults.length > 0) {
            Column({ space: 4 }) {
              Text('YOLO Inference Results')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
              Text(this.yoloInferenceResults)
                .fontSize(12)
                .fontColor('#666666')
                .maxLines(3)
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#F3E5F5')
            .borderRadius(8)
          }

          // YOLO Inference speed
          if (this.yoloInferenceSpeed.length > 0) {
            Column({ space: 4 }) {
              Text('YOLO Performance')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
              Text(this.yoloInferenceSpeed)
                .fontSize(12)
                .fontColor('#9C27B0')
                .maxLines(2)
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#F3E5F5')
            .borderRadius(8)
          }

          // YOLO Timing details
          if (this.yoloPreprocessTime > 0 || this.yoloInferenceTime > 0) {
            Column({ space: 4 }) {
              Text('YOLO Timing Details')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
              if (this.yoloPreprocessTime > 0) {
                Text(`Preprocess: ${this.yoloPreprocessTime}ms`)
                  .fontSize(12)
                  .fontColor('#FF9800')
              }
              if (this.yoloInferenceTime > 0) {
                Text(`Inference: ${this.yoloInferenceTime}ms`)
                  .fontSize(12)
                  .fontColor('#FF6B35')
              }
              Text(`Total YOLO Inferences: ${this.totalYoloInferences}`)
                .fontSize(12)
                .fontColor('#9C27B0')
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#F3E5F5')
            .borderRadius(8)
          }

          // Resource monitoring panel (always visible)
          Column({ space: 8 }) {
            Text('System Resources')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')

            Row() {
              Text(`CPU: ${this.cpuUsage.toFixed(1)}%`)
                .fontSize(12)
                .layoutWeight(1)
              Text(`Sys CPU: ${this.systemCpuUsage.toFixed(1)}%`)
                .fontSize(12)
                .layoutWeight(1)
            }
            .width('100%')

            Text(`Memory: ${this.memoryInfo}`)
              .fontSize(12)
              .width('100%')

            Text(`System: ${this.systemMemoryInfo}`)
              .fontSize(12)
              .width('100%')

            Row() {
              Text(`Battery: ${this.batterySOC}%`)
                .fontSize(12)
                .layoutWeight(1)
                Text(`Temp: ${this.thermalLevel}`)
                  .fontSize(12)
                  .layoutWeight(1)
              }
              .width('100%')

              Row() {
                Text(`Current: ${this.batteryCurrent}mA`)
                  .fontSize(12)
                  .layoutWeight(1)
                Text(`Voltage: ${(this.batteryVoltage / 1000).toFixed(2)}V`)
                  .fontSize(12)
                  .layoutWeight(1)
              }
              .width('100%')
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#F5F5F5')
            .borderRadius(8)

          // Action button
          Button(this.isProcessing ? 'Processing…' : 'Pick Video & Process')
            .width('100%')
            .enabled(!this.isProcessing)
            .fontWeight(500)
            .fontSize(16)
            .onClick(async () => {
              const path = await this.pickVideo();
              if (path) {
                await this.startProcessing(path);
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
    .title('Video Inference')
    .backgroundColor($r('app.color.background_color'))
  }
}
