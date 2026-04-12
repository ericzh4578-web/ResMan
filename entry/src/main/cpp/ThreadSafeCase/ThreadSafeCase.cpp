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

#include "ThreadSafeCase.h"
#include <thread>

/*
 * calculation result.
 */
int g_value = 0;

static napi_threadsafe_function tsFn = nullptr;

void ThreadSafeCase::SubThread(CallbackContext *asyncContext) {
    if (asyncContext == nullptr) {
        return;
    }
    napi_acquire_threadsafe_function(tsFn);
    napi_call_threadsafe_function(tsFn, asyncContext, napi_tsfn_nonblocking);
    napi_release_threadsafe_function(tsFn, napi_tsfn_release);
}

void ThreadSafeCase::ThreadSafeCallJs(napi_env env, napi_value js_callBack, void *context, void *data) {
    CallbackContext *argContext = reinterpret_cast<CallbackContext *>(data);
    if (argContext != nullptr) {
        napi_get_reference_value(env, argContext->callbackRef, &js_callBack);
    } else {
        return;
    }

    napi_valuetype valueType = napi_undefined;
    napi_typeof(env, js_callBack, &valueType);
    if (valueType != napi_valuetype::napi_function) {
        napi_delete_reference(env, argContext->callbackRef);
        delete argContext;
        argContext = nullptr;
        return;
    }

    napi_value argv;
    napi_create_int32(env, g_value, &argv);
    napi_value result = nullptr;
    napi_call_function(env, nullptr, js_callBack, 1, &argv, &result);
    napi_get_value_int32(env, result, &g_value);
    napi_delete_reference(env, argContext->callbackRef);
    delete argContext;
    argContext = nullptr;
}

napi_value ThreadSafeCase::ThreadSafeCaseFun(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value js_callback;
    napi_value workName;
    napi_get_cb_info(env, info, &argc, &js_callback, nullptr, nullptr);

    napi_valuetype valueType = napi_undefined;
    napi_typeof(env, js_callback, &valueType);
    if (valueType != napi_valuetype::napi_function) {
        return nullptr;
    }

    napi_create_string_utf8(env, "ThreadSafeCase", NAPI_AUTO_LENGTH, &workName);

    napi_create_threadsafe_function(env, nullptr, nullptr, workName, 0, 1, nullptr, nullptr, nullptr, ThreadSafeCallJs,
                                    &tsFn);

    auto asyncContext = new CallbackContext();
    asyncContext->env = env;
    napi_create_reference(env, js_callback, 1, &asyncContext->callbackRef);

    std::thread t(SubThread, asyncContext);
    t.detach();
    return nullptr;
}
