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

#include "AsyncPromise.h"
#include <memory>
extern size_t g_contextLen;

napi_value AsyncPromise::AsyncPromiseRead(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};

    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value promise = nullptr;

    auto asyncContext = new PromiseData();
    napi_create_promise(env, &asyncContext->deferred, &promise);

    size_t fileNameSize;
    napi_get_value_string_utf8(env, args[0], asyncContext->fileNameBuf, sizeof(asyncContext->fileNameBuf),
                               &fileNameSize);

    asyncContext->resMgr = OH_ResourceManager_InitNativeResourceManager(env, args[1]);

    napi_value asyncWorkName = nullptr;
    napi_create_string_utf8(env, "asyncWorkPromise", NAPI_AUTO_LENGTH, &asyncWorkName);

    napi_create_async_work(env, nullptr, asyncWorkName, ExecuteCB, CompleteCB, asyncContext, &asyncContext->asyncWork);

    napi_queue_async_work(env, asyncContext->asyncWork);
    return promise;
};
void AsyncPromise::ExecuteCB(napi_env env, void *data) {
    PromiseData *asyncContext = reinterpret_cast<PromiseData *>(data);

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
void AsyncPromise::CompleteCB(napi_env env, napi_status status, void *data) {
    PromiseData *asyncContext = reinterpret_cast<PromiseData *>(data);

    napi_value contents;
//     napi_create_string_utf8(env, asyncContext->result, NAPI_AUTO_LENGTH, &contents);
    napi_create_string_utf8(env, asyncContext->result.c_str(), NAPI_AUTO_LENGTH, &contents);

    if (contents != nullptr) {
        napi_resolve_deferred(env, asyncContext->deferred, contents);
    } else {
        napi_reject_deferred(env, asyncContext->deferred, contents);
    }

    napi_delete_async_work(env, asyncContext->asyncWork);
    delete asyncContext;
};