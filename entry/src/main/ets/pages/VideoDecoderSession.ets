import libentry from 'libentry.so';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';

const TAG = 'VideoDecoderSession';

export interface VideoDecoderSnapshot {
  status: string;
  frameCount: number;
  frameWidth: number;
  frameHeight: number;
  isDecoding: boolean;
  latestFramePixelMap: PixelMap | undefined;
}

export type VideoDecoderListener = (snapshot: VideoDecoderSnapshot) => void;

export class VideoDecoderSession {
  private static instance: VideoDecoderSession = new VideoDecoderSession();

  static getInstance(): VideoDecoderSession {
    return VideoDecoderSession.instance;
  }

  private listeners: VideoDecoderListener[] = [];
  private file: fileIo.File | null = null;
  private decodeToken: number = 0;

  private status: string = 'Idle';
  private frameCount: number = 0;
  private frameWidth: number = 0;
  private frameHeight: number = 0;
  private isDecoding: boolean = false;
  private latestFramePixelMap: PixelMap | undefined = undefined;

  private constructor() {}

  subscribe(listener: VideoDecoderListener): void {
    if (this.listeners.indexOf(listener) === -1) {
      this.listeners.push(listener);
    }
    listener(this.getSnapshot());
  }

  unsubscribe(listener: VideoDecoderListener): void {
    this.listeners = this.listeners.filter((item: VideoDecoderListener) => item !== listener);
  }

  getSnapshot(): VideoDecoderSnapshot {
    return {
      status: this.status,
      frameCount: this.frameCount,
      frameWidth: this.frameWidth,
      frameHeight: this.frameHeight,
      isDecoding: this.isDecoding,
      latestFramePixelMap: this.latestFramePixelMap,
    };
  }

  async startDecode(uri: string, filesDir: string): Promise<boolean> {
    if (this.isDecoding) {
      return false;
    }

    this.decodeToken += 1;
    const currentToken = this.decodeToken;
    this.frameCount = 0;
    this.frameWidth = 0;
    this.frameHeight = 0;
    this.latestFramePixelMap = undefined;
    this.isDecoding = true;
    this.status = 'Decoding...';
    this.notify();

    try {
      this.file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(this.file.fd);
      const fileSize = stat.size;

      libentry.decodeVideoFrames(
        this.file.fd,
        fileSize,
        (frame: ArrayBuffer | null, width: number, height: number, isEos: number) => {
          if (currentToken !== this.decodeToken) {
            return;
          }

          if (isEos === 1 || frame === null) {
            this.status = `Done - ${this.frameCount} frames decoded`;
            this.isDecoding = false;
            this.notify();
            this.closeFile();
            hilog.info(0x0000, TAG, 'Decoding finished, total frames: %{public}d', this.frameCount);
            return;
          }

          this.frameCount += 1;
          this.frameWidth = width;
          this.frameHeight = height;
          this.notify();
          this.renderFrame(frame, width, height, currentToken);

          hilog.debug(0x0000, TAG, 'Frame #%{public}d %{public}dx%{public}d bytes=%{public}d',
            this.frameCount, width, height, frame.byteLength);
        },
        filesDir
      );
      return true;
    } catch (e) {
      hilog.error(0x0000, TAG, 'startDecode error: %{public}s', JSON.stringify(e));
      this.status = `Error: ${JSON.stringify(e)}`;
      this.isDecoding = false;
      this.notify();
      this.closeFile();
      return false;
    }
  }

  private renderFrame(rgba: ArrayBuffer, width: number, height: number, decodeToken: number): void {
    if (this.frameCount % 10 !== 0) {
      return;
    }

    const opts: image.InitializationOptions = {
      size: { width: width, height: height },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: false,
    };

    image.createPixelMap(rgba, opts).then((pm: PixelMap) => {
      if (decodeToken !== this.decodeToken) {
        pm.release();
        return;
      }
      this.latestFramePixelMap = pm;
      this.notify();
    }).catch((e: Error) => {
      hilog.warn(0x0000, TAG, 'createPixelMap failed: %{public}s', e.message);
    });
  }

  private notify(): void {
    const snapshot = this.getSnapshot();
    this.listeners.forEach((listener: VideoDecoderListener) => {
      listener(snapshot);
    });
  }

  private closeFile(): void {
    const currentFile = this.file;
    this.file = null;
    if (currentFile === null) {
      return;
    }

    fileIo.close(currentFile.fd).catch((e: Error) => {
      hilog.warn(0x0000, TAG, 'close fd failed: %{public}s', e.message);
    });
  }
}
