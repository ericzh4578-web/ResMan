if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface SyncAndAsyncWork_Params {
    pageInfos?: NavPathStack;
    resMgr?: resourceManager.ResourceManager;
    message?: ResourceStr;
}
import type resourceManager from "@ohos:resourceManager";
import testNapi from "@normalized:Y&&&libentry.so&";
import { TitleComponent } from "@normalized:N&&&entry/src/main/ets/view/TitleComponent&";
export class SyncAndAsyncWork extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__pageInfos = this.initializeConsume('pageInfos', "pageInfos");
        this.resMgr = this.getUIContext().getHostContext()!.resourceManager;
        this.__message = new ObservedPropertyObjectPU({ "id": 16777226, "type": 10003, params: [], "bundleName": "com.example.nativecase", "moduleName": "entry" }, this, "message");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: SyncAndAsyncWork_Params) {
        if (params.resMgr !== undefined) {
            this.resMgr = params.resMgr;
        }
        if (params.message !== undefined) {
            this.message = params.message;
        }
    }
    updateStateVars(params: SyncAndAsyncWork_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__pageInfos.purgeDependencyOnElmtId(rmElmtId);
        this.__message.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__pageInfos.aboutToBeDeleted();
        this.__message.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __pageInfos: ObservedPropertyAbstractPU<NavPathStack>;
    get pageInfos() {
        return this.__pageInfos.get();
    }
    set pageInfos(newValue: NavPathStack) {
        this.__pageInfos.set(newValue);
    }
    private resMgr: resourceManager.ResourceManager;
    private __message: ObservedPropertyObjectPU<ResourceStr>;
    get message() {
        return this.__message.get();
    }
    set message(newValue: ResourceStr) {
        this.__message.set(newValue);
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            NavDestination.create(() => {
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Column.create();
                    Column.width('100%');
                    Column.height('100%');
                    Column.justifyContent(FlexAlign.End);
                    Column.padding({ left: 16, right: 16, bottom: 16 });
                }, Column);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    TextArea.create({ text: this.message });
                    TextArea.fontSize(16);
                    TextArea.focusable(false);
                    TextArea.fontWeight(400);
                    TextArea.height('30%');
                    TextArea.borderRadius(16);
                    TextArea.backgroundColor(Color.White);
                    TextArea.margin({ top: 16 });
                }, TextArea);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Blank.create();
                }, Blank);
                Blank.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Button.createWithLabel({ "id": 16777228, "type": 10003, params: [], "bundleName": "com.example.nativecase", "moduleName": "entry" });
                    Button.width('100%');
                    Button.fontWeight(500);
                    Button.fontSize(16);
                    Button.onClick(() => {
                        testNapi.syncCallbackRead('SyncCallback.txt', this.resMgr, (res: string) => {
                            this.message = res;
                        });
                    });
                }, Button);
                Button.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Button.createWithLabel({ "id": 16777220, "type": 10003, params: [], "bundleName": "com.example.nativecase", "moduleName": "entry" });
                    Button.width('100%');
                    Button.fontWeight(500);
                    Button.fontSize(16);
                    Button.margin({ top: 12 });
                    Button.onClick(() => {
                        testNapi.asyncCallbackRead('AsyncCallback.txt', this.resMgr, (res: string) => {
                            this.message = res;
                        });
                    });
                }, Button);
                Button.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Button.createWithLabel({ "id": 16777221, "type": 10003, params: [], "bundleName": "com.example.nativecase", "moduleName": "entry" });
                    Button.width('100%');
                    Button.fontWeight(500);
                    Button.fontSize(16);
                    Button.margin({ top: 12 });
                    Button.onClick(() => {
                        testNapi.asyncPromiseRead('AsyncPromise.txt', this.resMgr).then((res: string) => {
                            this.message = res;
                        });
                    });
                }, Button);
                Button.pop();
                Column.pop();
            }, { moduleName: "entry", pagePath: "entry/src/main/ets/pages/SyncAndAsyncWork" });
            NavDestination.backgroundColor({ "id": 16777237, "type": 10001, params: [], "bundleName": "com.example.nativecase", "moduleName": "entry" });
            NavDestination.title({ builder: () => {
                    TitleComponent.call(this, { "id": 16777235, "type": 10003, params: [], "bundleName": "com.example.nativecase", "moduleName": "entry" }, { "id": 16777236, "type": 10003, params: [], "bundleName": "com.example.nativecase", "moduleName": "entry" });
                } });
        }, NavDestination);
        NavDestination.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
