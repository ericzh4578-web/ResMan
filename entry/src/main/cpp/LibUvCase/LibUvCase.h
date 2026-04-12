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

#ifndef NATIVECASE_LIBUVCASE_H
#define NATIVECASE_LIBUVCASE_H
#include "napi/native_api.h"
#include <uv.h>

class LibUvCase {
public:
    struct CallbackContext {
        napi_env env = nullptr;
        napi_ref callbackRef = nullptr;
    };

    static void Async_handler(uv_async_t *handle);
    static void CallbackUvWorkTest(CallbackContext *context);
    static napi_value LibUvCaseFun(napi_env env, napi_callback_info info);
};
#endif // NATIVECASE_LIBUVCASE_H
