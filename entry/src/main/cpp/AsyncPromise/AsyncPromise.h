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

#ifndef NATIVECASE_ASYNCPROMISE_H
#define NATIVECASE_ASYNCPROMISE_H
#include "napi/native_api.h"
#include "rawfile/raw_file_manager.h"
#include <string>

class AsyncPromise {
public:
    struct PromiseData {
        napi_async_work asyncWork = nullptr;
        napi_deferred deferred = nullptr;
        char fileNameBuf[256] = {};
        NativeResourceManager *resMgr = nullptr;
        std::string result = "";
    };

    static napi_value AsyncPromiseRead(napi_env env, napi_callback_info info);
    static void ExecuteCB(napi_env env, void *data);
    static void CompleteCB(napi_env env, napi_status status, void *data);
};
#endif //NATIVECASE_ASYNCPROMISE_H
