if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface VideoDecoderPage_Params {
    status?: string;
    frameCount?: number;
    frameWidth?: number;
    frameHeight?: number;
    isDecoding?: boolean;
    latestFramePixelMap?: PixelMap | undefined;
}
import libentry from "@normalized:Y&&&libentry.so&";
import photoAccessHelper from "@ohos:file.photoAccessHelper";
import hilog from "@ohos:hilog";
import image from "@ohos:multimedia.image";
import fileIo from "@ohos:file.fs";
const TAG = 'VideoDecoderPage';
export class VideoDecoderPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__status = new ObservedPropertySimplePU('Idle', this, "status");
        this.__frameCount = new ObservedPropertySimplePU(0, this, "frameCount");
        this.__frameWidth = new ObservedPropertySimplePU(0, this, "frameWidth");
        this.__frameHeight = new ObservedPropertySimplePU(0, this, "frameHeight");
        this.__isDecoding = new ObservedPropertySimplePU(false, this, "isDecoding");
        this.__latestFramePixelMap = new ObservedPropertyObjectPU(undefined, this, "latestFramePixelMap");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: VideoDecoderPage_Params) {
        if (params.status !== undefined) {
            this.status = params.status;
        }
        if (params.frameCount !== undefined) {
            this.frameCount = params.frameCount;
        }
        if (params.frameWidth !== undefined) {
            this.frameWidth = params.frameWidth;
        }
        if (params.frameHeight !== undefined) {
            this.frameHeight = params.frameHeight;
        }
        if (params.isDecoding !== undefined) {
            this.isDecoding = params.isDecoding;
        }
        if (params.latestFramePixelMap !== undefined) {
            this.latestFramePixelMap = params.latestFramePixelMap;
        }
    }
    updateStateVars(params: VideoDecoderPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__status.purgeDependencyOnElmtId(rmElmtId);
        this.__frameCount.purgeDependencyOnElmtId(rmElmtId);
        this.__frameWidth.purgeDependencyOnElmtId(rmElmtId);
        this.__frameHeight.purgeDependencyOnElmtId(rmElmtId);
        this.__isDecoding.purgeDependencyOnElmtId(rmElmtId);
        this.__latestFramePixelMap.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__status.aboutToBeDeleted();
        this.__frameCount.aboutToBeDeleted();
        this.__frameWidth.aboutToBeDeleted();
        this.__frameHeight.aboutToBeDeleted();
        this.__isDecoding.aboutToBeDeleted();
        this.__latestFramePixelMap.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    // ── State ──────────────────────────────────────────────────────────────
    private __status: ObservedPropertySimplePU<string>;
    get status() {
        return this.__status.get();
    }
    set status(newValue: string) {
        this.__status.set(newValue);
    }
    private __frameCount: ObservedPropertySimplePU<number>;
    get frameCount() {
        return this.__frameCount.get();
    }
    set frameCount(newValue: number) {
        this.__frameCount.set(newValue);
    }
    private __frameWidth: ObservedPropertySimplePU<number>;
    get frameWidth() {
        return this.__frameWidth.get();
    }
    set frameWidth(newValue: number) {
        this.__frameWidth.set(newValue);
    }
    private __frameHeight: ObservedPropertySimplePU<number>;
    get frameHeight() {
        return this.__frameHeight.get();
    }
    set frameHeight(newValue: number) {
        this.__frameHeight.set(newValue);
    }
    private __isDecoding: ObservedPropertySimplePU<boolean>;
    get isDecoding() {
        return this.__isDecoding.get();
    }
    set isDecoding(newValue: boolean) {
        this.__isDecoding.set(newValue);
    }
    // Latest RGBA frame rendered via PixelMap (optional display)
    private __latestFramePixelMap: ObservedPropertyObjectPU<PixelMap | undefined>;
    get latestFramePixelMap() {
        return this.__latestFramePixelMap.get();
    }
    set latestFramePixelMap(newValue: PixelMap | undefined) {
        this.__latestFramePixelMap.set(newValue);
    }
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
        }
        catch (e) {
            hilog.error(0x0000, TAG, 'pickVideo error: %{public}s', JSON.stringify(e));
        }
        return null;
    }
    // ── Start decoding ─────────────────────────────────────────────────────
    private async startDecode(uri: string): Promise<void> {
        this.frameCount = 0;
        this.isDecoding = true;
        this.status = 'Decoding…';
        let file: fileIo.File | null = null;
        try {
            // Open the URI as a file descriptor so Native can use OH_AVSource_CreateWithFD
            file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
            const stat = await fileIo.stat(file.fd);
            const fileSize = stat.size;
            libentry.decodeVideoFrames(file.fd, fileSize, (frame: ArrayBuffer | null, width: number, height: number, isEos: number) => {
                if (isEos === 1 || frame === null) {
                    this.status = `Done — ${this.frameCount} frames decoded`;
                    this.isDecoding = false;
                    // Close the fd after decoding is complete
                    if (file !== null) {
                        fileIo.close(file.fd).catch((e: Error) => {
                            hilog.warn(0x0000, TAG, 'close fd failed: %{public}s', e.message);
                        });
                        file = null;
                    }
                    hilog.info(0x0000, TAG, 'Decoding finished, total frames: %{public}d', this.frameCount);
                    return;
                }
                this.frameCount += 1;
                this.frameWidth = width;
                this.frameHeight = height;
                this.renderFrame(frame, width, height);
                hilog.debug(0x0000, TAG, 'Frame #%{public}d  %{public}dx%{public}d  bytes=%{public}d', this.frameCount, width, height, frame.byteLength);
            }, getContext(this).filesDir);
        }
        catch (e) {
            hilog.error(0x0000, TAG, 'startDecode error: %{public}s', JSON.stringify(e));
            this.status = `Error: ${JSON.stringify(e)}`;
            this.isDecoding = false;
            if (file !== null) {
                fileIo.close(file.fd).catch(() => { });
            }
        }
    }
    // ── Render one RGBA frame into a PixelMap ──────────────────────────────
    private renderFrame(rgba: ArrayBuffer, width: number, height: number): void {
        if (this.frameCount % 10 !== 0)
            return;
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
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            NavDestination.create(() => {
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Scroll.create();
                    Scroll.scrollable(ScrollDirection.Vertical);
                    Scroll.scrollBar(BarState.Auto);
                }, Scroll);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Column.create({ space: 16 });
                    Column.width('100%');
                    Column.padding({ left: 16, right: 16, top: 16, bottom: 16 });
                }, Column);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    If.create();
                    // Preview area
                    if (this.latestFramePixelMap !== undefined) {
                        this.ifElseBranchUpdateFunction(0, () => {
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Image.create(this.latestFramePixelMap);
                                Image.width('100%');
                                Image.aspectRatio(this.frameWidth > 0 ? this.frameWidth / this.frameHeight : 1.78);
                                Image.objectFit(ImageFit.Contain);
                                Image.borderRadius(8);
                            }, Image);
                        });
                    }
                    else {
                        this.ifElseBranchUpdateFunction(1, () => {
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Row.create();
                                Row.width('100%');
                                Row.height(200);
                                Row.justifyContent(FlexAlign.Center);
                                Row.backgroundColor('#1A000000');
                                Row.borderRadius(8);
                            }, Row);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create('No frame yet');
                                Text.fontSize(14);
                                Text.fontColor('#888888');
                            }, Text);
                            Text.pop();
                            Row.pop();
                        });
                    }
                }, If);
                If.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    // Stats
                    Column.create({ space: 4 });
                    // Stats
                    Column.width('100%');
                    // Stats
                    Column.padding(12);
                    // Stats
                    Column.backgroundColor('#F5F5F5');
                    // Stats
                    Column.borderRadius(8);
                }, Column);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(`Status: ${this.status}`);
                    Text.fontSize(14);
                    Text.fontColor(this.isDecoding ? '#007DFF' : '#333333');
                }, Text);
                Text.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(`Frames decoded: ${this.frameCount}`);
                    Text.fontSize(14);
                }, Text);
                Text.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    If.create();
                    if (this.frameWidth > 0) {
                        this.ifElseBranchUpdateFunction(0, () => {
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(`Resolution: ${this.frameWidth} × ${this.frameHeight}`);
                                Text.fontSize(14);
                            }, Text);
                            Text.pop();
                        });
                    }
                    else {
                        this.ifElseBranchUpdateFunction(1, () => {
                        });
                    }
                }, If);
                If.pop();
                // Stats
                Column.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    // Action button
                    Button.createWithLabel(this.isDecoding ? 'Decoding…' : 'Pick Video & Decode');
                    // Action button
                    Button.width('100%');
                    // Action button
                    Button.enabled(!this.isDecoding);
                    // Action button
                    Button.fontWeight(500);
                    // Action button
                    Button.fontSize(16);
                    // Action button
                    Button.onClick(async () => {
                        const path = await this.pickVideo();
                        if (path) {
                            await this.startDecode(path);
                        }
                        else {
                            this.status = 'No video selected';
                        }
                    });
                }, Button);
                // Action button
                Button.pop();
                Column.pop();
                Scroll.pop();
            }, { moduleName: "entry", pagePath: "entry/src/main/ets/pages/VideoDecoderPage" });
            NavDestination.title('Video Decoder (Buffer Mode)');
            NavDestination.backgroundColor({ "id": 16777238, "type": 10001, params: [], "bundleName": "com.samples.nativecase", "moduleName": "entry" });
        }, NavDestination);
        NavDestination.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
    static getEntryName(): string {
        return "VideoDecoderPage";
    }
}
registerNamedRoute(() => new VideoDecoderPage(undefined, {}), "", { bundleName: "com.samples.nativecase", moduleName: "entry", pagePath: "pages/VideoDecoderPage", pageFullPath: "entry/src/main/ets/pages/VideoDecoderPage", integratedHsp: "false", moduleType: "followWithHap" });
