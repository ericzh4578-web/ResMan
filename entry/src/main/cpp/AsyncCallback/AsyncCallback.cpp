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

#include "AsyncCallback.h"
#include <memory>

extern size_t g_contextLen;

napi_value AsyncCallback::AsyncCallbackRead(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};

    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    auto asyncContext = new CallbackData();

    size_t fileNameSize;
    napi_get_value_string_utf8(env, args[0], asyncContext->fileNameBuf, sizeof(asyncContext->fileNameBuf),
                               &fileNameSize);

    asyncContext->resMgr = OH_ResourceManager_InitNativeResourceManager(env, args[1]);
    napi_create_reference(env, args[2], 1, &asyncContext->callbackRef);

    napi_value asyncWorkName = nullptr;
    napi_create_string_utf8(env, "asyncWorkCallback", NAPI_AUTO_LENGTH, &asyncWorkName);

    napi_create_async_work(env, nullptr, asyncWorkName, ExecuteCB, CompleteCB, asyncContext, &asyncContext->asyncWork);

    napi_queue_async_work(env, asyncContext->asyncWork);
    return nullptr;
};
void AsyncCallback::ExecuteCB(napi_env env, void *data) {
    CallbackData *asyncContext = reinterpret_cast<CallbackData *>(data);

    RawFile *rawFile = OH_ResourceManager_OpenRawFile(asyncContext->resMgr, asyncContext->fileNameBuf);
    
    std::unique_ptr<char[]> fileData = std::make_unique<char[]>(g_contextLen);

    long offset = 0;
    while (OH_ResourceManager_GetRawFileRemainingLength(rawFile) > 0) {
        OH_ResourceManager_ReadRawFile(rawFile, fileData.get() + offset, 100);
        offset += 100;
    }
    
    OH_ResourceManager_CloseRawFile(rawFile);
    OH_ResourceManager_ReleaseNativeResourceManager(asyncContext->resMgr);

    char *temp = fileData.get();
    asyncContext->result = temp;
};
void AsyncCallback::CompleteCB(napi_env env, napi_status status, void *data) {
    CallbackData *asyncContext = static_cast<CallbackData *>(data);

    napi_value callback = nullptr;
    napi_get_reference_value(env, asyncContext->callbackRef, &callback);

    napi_value contents;
    napi_create_string_utf8(env, asyncContext->result.c_str(), NAPI_AUTO_LENGTH, &contents);

    napi_value res;
    napi_call_function(env, nullptr, callback, 1, &contents, &res);

    napi_delete_reference(env, asyncContext->callbackRef);
    napi_delete_async_work(env, asyncContext->asyncWork);
    delete asyncContext;
};