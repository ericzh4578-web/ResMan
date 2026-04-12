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

#include "napi/native_api.h"
#include "./SyncCallback/SyncCallback.h"
#include "./AsyncCallback/AsyncCallback.h"
#include "./AsyncPromise/AsyncPromise.h"
#include "./ThreadSafeCase/ThreadSafeCase.h"
#include "./LibUvCase/LibUvCase.h"
extern int g_value;

static napi_value Destroy(napi_env env, napi_callback_info info) {
    g_value = 0;
    return nullptr;
};

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"syncCallbackRead", nullptr, SyncCallback::SyncCallbackRead, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"asyncCallbackRead", nullptr, AsyncCallback::AsyncCallbackRead, nullptr, nullptr, nullptr, napi_default,
         nullptr},
        {"asyncPromiseRead", nullptr, AsyncPromise::AsyncPromiseRead, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"threadSafeCaseFun", nullptr, ThreadSafeCase::ThreadSafeCaseFun, nullptr, nullptr, nullptr, napi_default,
         nullptr},
        {"libUvCaseFun", nullptr, LibUvCase::LibUvCaseFun, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"destroy", nullptr, Destroy, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) { napi_module_register(&demoModule); }
