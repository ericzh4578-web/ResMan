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

import { resourceManager } from '@kit.LocalizationKit';
import testNapi from 'libentry.so';
import { TitleComponent } from '../view/TitleComponent'

@Component
export struct SyncAndAsyncWork {
  @Consume('pageInfos') pageInfos: NavPathStack;
  private resMgr: resourceManager.ResourceManager = this.getUIContext().getHostContext()!.resourceManager;
  @State message: ResourceStr = $r('app.string.read_text_desc');

  build() {
    NavDestination() {
      Column() {
        TextArea({ text: this.message })
          .fontSize(16)
          .focusable(false)
          .fontWeight(400)
          .height('30%')
          .borderRadius(16)
          .backgroundColor(Color.White)
          .margin({ top: 16 })

        Blank();

        Button($r('app.string.sync_callback_button'))
          .width('100%')
          .fontWeight(500)
          .fontSize(16)
          .onClick(() => {
            testNapi.syncCallbackRead('SyncCallback.txt', this.resMgr, (res: string) => {
              this.message = res;
            })
          })

        Button($r('app.string.async_callback_button'))
          .width('100%')
          .fontWeight(500)
          .fontSize(16)
          .margin({ top: 12 })
          .onClick(() => {
            testNapi.asyncCallbackRead('AsyncCallback.txt', this.resMgr, (res: string) => {
              this.message = res;
            })
          })

        Button($r('app.string.async_promise_button'))
          .width('100%')
          .fontWeight(500)
          .fontSize(16)
          .margin({ top: 12 })
          .onClick(() => {
            testNapi.asyncPromiseRead('AsyncPromise.txt', this.resMgr).then((res: string) => {
              this.message = res;
            });
          })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .padding({ left: 16, right: 16, bottom: 16 })
    }
    .backgroundColor($r('app.color.background_color'))
    .title(TitleComponent($r('app.string.work_title'), $r('app.string.work_title_desc')))
  }
}
