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

import { promptAction } from '@kit.ArkUI';
import testNapi from 'libentry.so';
import { TitleComponent } from '../view/TitleComponent';

@Component
export struct SubMainThreadCom {
  @Consume('pageInfos') pageInfos: NavPathStack;
  @State value: number = 0;
  private message: ResourceStr = $r('app.string.calculation_text_desc');

  work: Function = (param: number) => {
    param += 30;
    this.value = param;
    return param;
  }

  aboutToDisappear(): void {
    testNapi.destroy();
  }

  build() {
    NavDestination() {
      Column() {
        Text(this.message)
          .fontSize(14)
          .width('100%')
          .textAlign(TextAlign.Start)
          .fontColor(Color.Black)
          .opacity(0.6)
          .fontWeight(500)
          .margin({ top: 24 })
        TextInput({ text: JSON.stringify(this.value) })
          .fontSize(16)
          .focusable(false)
          .fontColor(Color.Black)
          .backgroundColor(Color.White)
          .fontWeight(FontWeight.Normal)
          .margin({ top: 12 })

        Blank();

        Button($r('app.string.thread_safe_func_button'))
          .width('100%')
          .onClick(() => {
            testNapi.threadSafeCaseFun(this.work);
            this.getUIContext().getPromptAction().showToast({
              message: $r('app.string.thread_com_toast'),
              duration: 2000
            })
          })
        Button($r('app.string.lib_uv_method_button'))
          .width('100%')
          .margin({ top: 12 })
          .onClick(() => {
            testNapi.libUvCaseFun(this.work);
            this.getUIContext().getPromptAction().showToast({
              message: $r('app.string.lib_uv_toast'),
              duration: 2000
            })
          })
      }
      .justifyContent(FlexAlign.End)
      .padding({ left: 16, right: 16, bottom: 16 })
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('app.color.background_color'))
    .title(TitleComponent($r('app.string.thread_com_title'), $r('app.string.thread_com_title_desc')))
  }
}