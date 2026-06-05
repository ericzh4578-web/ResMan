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

#include "SysfsReader.h"
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace {

unsigned long ReadSysfsFile(const char* path) {
    FILE* f = fopen(path, "r");
    if (!f) return 0;
    unsigned long value = 0;
    fscanf(f, "%lu", &value);
    fclose(f);
    return value;
}

int GetOnlineCpuCount() {
    FILE* f = fopen("/sys/devices/system/cpu/online", "r");
    if (!f) {
        f = fopen("/sys/devices/system/cpu/present", "r");
        if (!f) return 4;
    }
    char buf[64] = {};
    fgets(buf, sizeof(buf), f);
    fclose(f);
    int start = 0, end = 0;
    if (sscanf(buf, "%d-%d", &start, &end) == 2) return end - start + 1;
    return 4;
}

std::vector<unsigned long> ReadAllCpuFreqsInternal() {
    std::vector<unsigned long> freqs;
    int cpuCount = GetOnlineCpuCount();
    for (int i = 0; i < cpuCount; i++) {
        char path[128];
        snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu%d/cpufreq/scaling_cur_freq", i);
        unsigned long freq = ReadSysfsFile(path);
        if (freq == 0) {
            snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu%d/cpufreq/cpuinfo_cur_freq", i);
            freq = ReadSysfsFile(path);
        }
        freqs.push_back(freq);
    }
    return freqs;
}

unsigned long ReadGpuFreqInternal() {
    const char* gpuPaths[] = {
        "/sys/class/kgsl/kgsl-3d0/gpuclk",
        "/sys/class/devfreq/ffa30000.gpu/cur_freq",
        "/sys/devices/platform/ffa30000.gpu/devfreq/ffa30000.gpu/cur_freq",
        "/sys/class/misc/mali0/device/cur_frequency",
    };
    for (const char* p : gpuPaths) {
        unsigned long v = ReadSysfsFile(p);
        if (v > 0) return v;
    }
    return 0;
}

} // anonymous namespace

namespace SysfsReader {

napi_value ReadCpuFreq(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t coreIndex = 0;
    if (argc >= 1) {
        napi_get_value_int32(env, args[0], &coreIndex);
    }

    char path[128];
    snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu%d/cpufreq/scaling_cur_freq", coreIndex);
    unsigned long freq = ReadSysfsFile(path);
    if (freq == 0) {
        snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu%d/cpufreq/cpuinfo_cur_freq", coreIndex);
        freq = ReadSysfsFile(path);
    }

    napi_value result;
    napi_create_uint32(env, static_cast<uint32_t>(freq), &result);
    return result;
}

napi_value ReadAllCpuFreqs(napi_env env, napi_callback_info info) {
    auto freqs = ReadAllCpuFreqsInternal();
    napi_value arr;
    napi_create_array_with_length(env, freqs.size(), &arr);
    for (size_t i = 0; i < freqs.size(); i++) {
        napi_value obj;
        napi_create_object(env, &obj);

        napi_value coreVal, freqVal;
        napi_create_uint32(env, static_cast<uint32_t>(i), &coreVal);
        napi_create_uint32(env, static_cast<uint32_t>(freqs[i]), &freqVal);

        napi_set_named_property(env, obj, "core", coreVal);
        napi_set_named_property(env, obj, "freqKHz", freqVal);

        napi_set_element(env, arr, i, obj);
    }
    return arr;
}

napi_value ReadGpuFreq(napi_env env, napi_callback_info info) {
    unsigned long freq = ReadGpuFreqInternal();
    napi_value result;
    napi_create_uint32(env, static_cast<uint32_t>(freq), &result);
    return result;
}

napi_value ReadCpuFreqsCsv(napi_env env, napi_callback_info info) {
    auto freqs = ReadAllCpuFreqsInternal();
    std::string csv;
    for (size_t i = 0; i < freqs.size(); i++) {
        if (i > 0) csv += ",";
        csv += std::to_string(freqs[i]);
    }
    napi_value result;
    napi_create_string_utf8(env, csv.c_str(), csv.length(), &result);
    return result;
}

} // namespace SysfsReader
