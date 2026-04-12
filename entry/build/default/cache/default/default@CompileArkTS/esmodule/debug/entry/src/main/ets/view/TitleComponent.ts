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
export function TitleComponent(title: ResourceStr, description: ResourceStr, parent = null) {
    (parent ? parent : this).observeComponentCreation2((elmtId, isInitialRender) => {
        Column.create();
        Column.margin({ left: 8, top: 4, bottom: 4 });
        Column.alignItems(HorizontalAlign.Start);
    }, Column);
    (parent ? parent : this).observeComponentCreation2((elmtId, isInitialRender) => {
        Text.create(title);
        Text.fontSize(20);
        Text.height(27);
        Text.maxLines(1);
        Text.textOverflow({ overflow: TextOverflow.Ellipsis });
        Text.fontWeight(FontWeight.Bold);
    }, Text);
    Text.pop();
    (parent ? parent : this).observeComponentCreation2((elmtId, isInitialRender) => {
        Text.create(description);
        Text.fontSize(14);
        Text.height(19);
        Text.maxLines(1);
        Text.textOverflow({ overflow: TextOverflow.Ellipsis });
        Text.fontColor(Color.Black);
        Text.opacity(0.6);
        Text.fontWeight(400);
        Text.margin({ top: 2 });
    }, Text);
    Text.pop();
    Column.pop();
}
