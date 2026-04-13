if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface SubMainThreadCom_Params {
    pageInfos?: NavPathStack;
    value?: number;
    message?: ResourceStr;
    work?: Function;
}
import testNapi from "@normalized:Y&&&libentry.so&";
import { TitleComponent } from "@normalized:N&&&entry/src/main/ets/view/TitleComponent&";
export class SubMainThreadCom extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__pageInfos = this.initializeConsume('pageInfos', "pageInfos");
        this.__value = new ObservedPropertySimplePU(0, this, "value");
        this.message = { "id": 16777222, "type": 10003, params: [], "bundleName": "com.samples.nativecase", "moduleName": "entry" };
        this.work = (param: number) => {
            param += 30;
            this.value = param;
            return param;
        };
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: SubMainThreadCom_Params) {
        if (params.value !== undefined) {
            this.value = params.value;
        }
        if (params.message !== undefined) {
            this.message = params.message;
        }
        if (params.work !== undefined) {
            this.work = params.work;
        }
    }
    updateStateVars(params: SubMainThreadCom_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__pageInfos.purgeDependencyOnElmtId(rmElmtId);
        this.__value.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__pageInfos.aboutToBeDeleted();
        this.__value.aboutToBeDeleted();
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
    private __value: ObservedPropertySimplePU<number>;
    get value() {
        return this.__value.get();
    }
    set value(newValue: number) {
        this.__value.set(newValue);
    }
    private message: ResourceStr;
    private work: Function;
    aboutToDisappear(): void {
        testNapi.destroy();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            NavDestination.create(() => {
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Column.create();
                    Column.justifyContent(FlexAlign.End);
                    Column.padding({ left: 16, right: 16, bottom: 16 });
                    Column.width('100%');
                    Column.height('100%');
                }, Column);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(this.message);
                    Text.fontSize(14);
                    Text.width('100%');
                    Text.textAlign(TextAlign.Start);
                    Text.fontColor(Color.Black);
                    Text.opacity(0.6);
                    Text.fontWeight(500);
                    Text.margin({ top: 24 });
                }, Text);
                Text.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    TextInput.create({ text: JSON.stringify(this.value) });
                    TextInput.fontSize(16);
                    TextInput.focusable(false);
                    TextInput.fontColor(Color.Black);
                    TextInput.backgroundColor(Color.White);
                    TextInput.fontWeight(FontWeight.Normal);
                    TextInput.margin({ top: 12 });
                }, TextInput);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Blank.create();
                }, Blank);
                Blank.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Button.createWithLabel({ "id": 16777234, "type": 10003, params: [], "bundleName": "com.samples.nativecase", "moduleName": "entry" });
                    Button.width('100%');
                    Button.onClick(() => {
                        testNapi.threadSafeCaseFun(this.work);
                        this.getUIContext().getPromptAction().showToast({
                            message: { "id": 16777233, "type": 10003, params: [], "bundleName": "com.samples.nativecase", "moduleName": "entry" },
                            duration: 2000
                        });
                    });
                }, Button);
                Button.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Button.createWithLabel({ "id": 16777223, "type": 10003, params: [], "bundleName": "com.samples.nativecase", "moduleName": "entry" });
                    Button.width('100%');
                    Button.margin({ top: 12 });
                    Button.onClick(() => {
                        testNapi.libUvCaseFun(this.work);
                        this.getUIContext().getPromptAction().showToast({
                            message: { "id": 16777224, "type": 10003, params: [], "bundleName": "com.samples.nativecase", "moduleName": "entry" },
                            duration: 2000
                        });
                    });
                }, Button);
                Button.pop();
                Column.pop();
            }, { moduleName: "entry", pagePath: "entry/src/main/ets/pages/SubMainThreadCom" });
            NavDestination.backgroundColor({ "id": 16777238, "type": 10001, params: [], "bundleName": "com.samples.nativecase", "moduleName": "entry" });
            NavDestination.title({ builder: () => {
                    TitleComponent.call(this, { "id": 16777231, "type": 10003, params: [], "bundleName": "com.samples.nativecase", "moduleName": "entry" }, { "id": 16777232, "type": 10003, params: [], "bundleName": "com.samples.nativecase", "moduleName": "entry" });
                } });
        }, NavDestination);
        NavDestination.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
