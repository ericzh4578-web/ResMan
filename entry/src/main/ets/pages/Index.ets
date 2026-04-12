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

import { SubMainThreadCom } from './SubMainThreadCom';
import { SyncAndAsyncWork } from './SyncAndAsyncWork';

@Entry
@Component
struct Index {
  @Provide('pageInfos') pageInfos: NavPathStack = new NavPathStack();

  @Builder
  PageMap(name: string) {
    if (name === 'SyncAndAsyncWork') {
      SyncAndAsyncWork();
    } else if (name === 'SubMainThreadCom') {
      SubMainThreadCom();
    } else {
      Index();
    }
  }

  build() {
    Navigation(this.pageInfos) {
      Column() {
        Text($r('app.string.sample_title'))
          .width('100%')
          .height(56)
          .fontSize(30)
          .textAlign(TextAlign.Start)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 64 })

        Blank();

        Button($r('app.string.work_button'))
          .width('100%')
          .fontWeight(500)
          .fontSize(16)
          .margin({ top: 12 })
          .onClick(() => {
            this.pageInfos.pushPath({ name: 'SyncAndAsyncWork' });
          })

        Button($r('app.string.thread_com_button'))
          .width('100%')
          .fontWeight(500)
          .fontSize(16)
          .margin({ top: 12 })
          .onClick(() => {
            this.pageInfos.pushPath({ name: 'SubMainThreadCom' });
          })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .padding({ left: 16, right: 16, bottom: 16})
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .backgroundColor($r('app.color.background_color'))
    .navDestination(this.PageMap)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
