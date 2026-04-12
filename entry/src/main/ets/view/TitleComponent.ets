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

/*
 * General Title Component.
 */
@Builder
export function TitleComponent(title: ResourceStr, description: ResourceStr) {
  Column() {
    Text(title)
      .fontSize(20)
      .height(27)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .fontWeight(FontWeight.Bold)
    Text(description)
      .fontSize(14)
      .height(19)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .fontColor(Color.Black)
      .opacity(0.6)
      .fontWeight(400)
      .margin({ top: 2 })
  }
  .margin({ left: 8, top: 4, bottom: 4 })
  .alignItems(HorizontalAlign.Start)
}