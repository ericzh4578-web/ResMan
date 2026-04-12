/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
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

#include "SyncCallback.h"
#include <memory>

/*
 * Read the length of the text.
 */
size_t g_contextLen = 50000;

napi_value SyncCallback::SyncCallbackRead(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};

    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    size_t fileNameSize;
    char fileNameBuf[256];
    napi_get_value_string_utf8(env, args[0], fileNameBuf, sizeof(fileNameBuf), &fileNameSize);

    NativeResourceManager *mNativeResMgr = OH_ResourceManager_InitNativeResourceManager(env, args[1]);

    RawFile *rawFile = OH_ResourceManager_OpenRawFile(mNativeResMgr, fileNameBuf);

    std::unique_ptr<char[]> fileData = std::make_unique<char[]>(g_contextLen);

    long offset = 0;
    while (OH_ResourceManager_GetRawFileRemainingLength(rawFile) > 0) {
        OH_ResourceManager_ReadRawFile(rawFile, fileData.get() + offset, 100);
        offset += 100;
    }

    OH_ResourceManager_CloseRawFile(rawFile);
    OH_ResourceManager_ReleaseNativeResourceManager(mNativeResMgr);
    napi_value contents;
    napi_create_string_utf8(env, fileData.get(), NAPI_AUTO_LENGTH, &contents);

    napi_value res = nullptr;
    napi_call_function(env, nullptr, args[2], 1, &contents, &res);
    return nullptr;
}