//
// Created on 2025/1/10.
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

#include "LibUvCase.h"
#include <thread>
extern int g_value;
static uv_loop_t *loop = nullptr;
static uv_async_t *async = nullptr;

void LibUvCase::Async_handler(uv_async_t *handle) {
    CallbackContext *context = reinterpret_cast<CallbackContext *>(handle->data);
    napi_handle_scope scope = nullptr;
    napi_open_handle_scope(context->env, &scope);
    if (scope == nullptr) {
        napi_delete_reference(context->env, context->callbackRef);
        delete context;
        context = nullptr;
        if (handle != nullptr) {
            delete handle;
            handle = nullptr;
        }
        return;
    }
    napi_value callback = nullptr;
    napi_get_reference_value(context->env, context->callbackRef, &callback);
    napi_value retArg;
    napi_create_int32(context->env, g_value, &retArg);
    napi_value result;
    napi_call_function(context->env, nullptr, callback, 1, &retArg, &result);
    napi_get_value_int32(context->env, result, &g_value);
    napi_close_handle_scope(context->env, scope);
    napi_delete_reference(context->env, context->callbackRef);
    delete context;
    context = nullptr;
    uv_close((uv_handle_t *)async, [](uv_handle_t *handle) { delete (uv_async_t *)handle; });
}

void LibUvCase::CallbackUvWorkTest(CallbackContext *context) {
    if (context == nullptr) {
        return;
    }

    async->data = reinterpret_cast<void *>(context);
    uv_async_send(async);
}

napi_value LibUvCase::LibUvCaseFun(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value callback_function;
    napi_get_cb_info(env, info, &argc, &callback_function, nullptr, nullptr);

    napi_valuetype valueType = napi_undefined;
    napi_typeof(env, callback_function, &valueType);
    if (valueType != napi_valuetype::napi_function) {
        return nullptr;
    }

    loop = uv_default_loop();
    async = new uv_async_t;
    uv_async_init(loop, async, Async_handler);

    auto asyncContext = new CallbackContext();
    if (asyncContext == nullptr) {
        return nullptr;
    }
    asyncContext->env = env;
    napi_create_reference(env, callback_function, 1, &asyncContext->callbackRef);
    std::thread caseThread(CallbackUvWorkTest, asyncContext);
    caseThread.detach();
    uv_run(loop, UV_RUN_DEFAULT);
    return nullptr;
}