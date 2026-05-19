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

#include "ResourceSimulator.h"

#include <thread>
#include <atomic>
#include <mutex>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <chrono>
#include <memory>
#include <unistd.h>

// ─────────────────────────────────────────────────────────────────────────────
// Internal state
// ─────────────────────────────────────────────────────────────────────────────

namespace {

// ── CPU Load ──
std::atomic<bool> g_cpuActive{false};
std::atomic<int>  g_cpuLevel{0};   // 0–4 → 0% / 25% / 50% / 75% / 100%
std::thread       g_cpuThread;

// ── Memory Load ──
std::atomic<bool> g_memActive{false};
std::atomic<int>  g_memLevel{0};   // 0–3 → 10% / 15% / 20% / 25%
uint8_t          *g_memBuffer{nullptr};
size_t            g_memAllocSize{0};
std::mutex        g_memMutex;

// ── I/O Load ──
std::atomic<bool> g_ioActive{false};
std::atomic<int>  g_ioLevel{0};    // 0–2 → weak / medium / strong
std::thread       g_ioThread;
std::string       g_ioFilePath;
std::mutex        g_ioMutex;

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

static size_t GetTotalPhysicalMemory() {
    long pages = sysconf(_SC_PHYS_PAGES);
    long pageSize = sysconf(_SC_PAGE_SIZE);
    if (pages > 0 && pageSize > 0) {
        return static_cast<size_t>(pages) * static_cast<size_t>(pageSize);
    }
    FILE *f = fopen("/proc/meminfo", "r");
    if (f) {
        char line[256] = {};
        size_t totalKb = 0;
        while (fgets(line, sizeof(line), f)) {
            if (sscanf(line, "MemTotal: %zu kB", &totalKb) == 1) {
                fclose(f);
                return totalKb * 1024;
            }
        }
        fclose(f);
    }
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// CPU Load Worker
// ─────────────────────────────────────────────────────────────────────────────

static void CpuLoadWorker() {
    while (g_cpuActive) {
        int level = g_cpuLevel;
        if (level <= 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            continue;
        }
        int workMs  = level * 25;
        int sleepMs = 100 - workMs;

        auto start = std::chrono::steady_clock::now();
        while (std::chrono::steady_clock::now() - start < std::chrono::milliseconds(workMs)) {
            volatile double x = 0.0;
            for (int i = 0; i < 5000; ++i) {
                x += i * 0.001;
            }
        }

        if (sleepMs > 0 && g_cpuActive) {
            std::this_thread::sleep_for(std::chrono::milliseconds(sleepMs));
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// I/O Load Worker
// ─────────────────────────────────────────────────────────────────────────────

static void IoLoadWorker() {
    // blockSize per level: weak=4KB, medium=64KB, strong=256KB
    const int blockSizes[] = {4096, 65536, 262144};
    // sleepMs per level between operations
    const int sleepMs[] = {100, 50, 5};

    while (g_ioActive) {
        int level = g_ioLevel;
        if (level < 0 || level > 2) level = 0;
        int blockSize = blockSizes[level];
        int sleepTime = sleepMs[level];

        std::unique_lock<std::mutex> lk(g_ioMutex);
        if (g_ioFilePath.empty()) {
            lk.unlock();
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            continue;
        }
        std::string path = g_ioFilePath;
        lk.unlock();

        FILE *f = fopen(path.c_str(), "r+b");
        if (!f) {
            if (sleepTime > 0 && g_ioActive) {
                std::this_thread::sleep_for(std::chrono::milliseconds(sleepTime));
            }
            continue;
        }

        fseek(f, 0, SEEK_END);
        long fileSize = ftell(f);
        if (fileSize > static_cast<long>(blockSize)) {
            long offset = rand() % (fileSize - blockSize);
            auto buf = std::make_unique<char[]>(blockSize);
            if (rand() % 2 == 0) {
                fseek(f, offset, SEEK_SET);
                fread(buf.get(), 1, blockSize, f);
            } else {
                fseek(f, offset, SEEK_SET);
                fwrite(buf.get(), 1, blockSize, f);
            }
        }
        fclose(f);

        if (sleepTime > 0 && g_ioActive) {
            std::this_thread::sleep_for(std::chrono::milliseconds(sleepTime));
        }
    }
}

} // anonymous namespace

// ─────────────────────────────────────────────────────────────────────────────
// Public NAPI entry points
// ─────────────────────────────────────────────────────────────────────────────

namespace ResourceSimulator {

// ── StartCpuLoad(level: number) ──────────────────────────────────────────────
napi_value StartCpuLoad(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1) {
        napi_throw_error(env, nullptr, "startCpuLoad: expected 1 argument (level: 0-4)");
        return nullptr;
    }

    int32_t level = 0;
    napi_get_value_int32(env, args[0], &level);
    if (level < 0 || level > 4) {
        napi_throw_error(env, nullptr, "startCpuLoad: level must be 0-4 (0%25/25%25/50%25/75%25/100%25)");
        return nullptr;
    }

    if (g_cpuActive) {
        g_cpuLevel = level;
        return nullptr;
    }

    g_cpuLevel  = level;
    g_cpuActive = true;
    g_cpuThread = std::thread(CpuLoadWorker);

    return nullptr;
}

// ── StopCpuLoad() ────────────────────────────────────────────────────────────
napi_value StopCpuLoad(napi_env env, napi_callback_info info) {
    if (!g_cpuActive) return nullptr;

    g_cpuActive = false;
    if (g_cpuThread.joinable()) {
        g_cpuThread.join();
    }
    g_cpuLevel = 0;
    return nullptr;
}

// ── StartMemoryLoad(level: number) ───────────────────────────────────────────
napi_value StartMemoryLoad(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1) {
        napi_throw_error(env, nullptr, "startMemoryLoad: expected 1 argument (level: 0-2)");
        return nullptr;
    }

    int32_t level = 0;
    napi_get_value_int32(env, args[0], &level);
    if (level < 0 || level > 3) {
        napi_throw_error(env, nullptr, "startMemoryLoad: level must be 0-3 (10%25/15%25/20%25/25%25)");
        return nullptr;
    }

    std::unique_lock<std::mutex> lk(g_memMutex);

    // Free previous allocation if any
    if (g_memBuffer) {
        delete[] g_memBuffer;
        g_memBuffer   = nullptr;
        g_memAllocSize = 0;
    }

    size_t totalMem = GetTotalPhysicalMemory();
    if (totalMem == 0) {
        napi_throw_error(env, nullptr, "startMemoryLoad: unable to determine physical memory size");
        return nullptr;
    }

    const float ratios[] = {0.10f, 0.15f, 0.20f, 0.25f};
    g_memAllocSize = static_cast<size_t>(totalMem * ratios[level]);

    try {
        g_memBuffer = new uint8_t[g_memAllocSize];
    } catch (const std::bad_alloc &) {
        g_memBuffer   = nullptr;
        g_memAllocSize = 0;
        napi_throw_error(env, nullptr, "startMemoryLoad: allocation failed (not enough memory)");
        return nullptr;
    }

    // Touch every page so physical pages are actually committed
    std::memset(g_memBuffer, 0xAB, g_memAllocSize);

    g_memLevel = level;
    g_memActive = true;

    return nullptr;
}

// ── StopMemoryLoad() ─────────────────────────────────────────────────────────
napi_value StopMemoryLoad(napi_env env, napi_callback_info info) {
    std::unique_lock<std::mutex> lk(g_memMutex);
    if (g_memBuffer) {
        delete[] g_memBuffer;
        g_memBuffer   = nullptr;
        g_memAllocSize = 0;
    }
    g_memActive = false;
    g_memLevel  = 0;
    return nullptr;
}

// ── StartIoLoad(level: number, filesDir: string) ─────────────────────────────
napi_value StartIoLoad(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 2) {
        napi_throw_error(env, nullptr, "startIoLoad: expected 2 arguments (level: 0-2, filesDir: string)");
        return nullptr;
    }

    int32_t level = 0;
    napi_get_value_int32(env, args[0], &level);
    if (level < 0 || level > 2) {
        napi_throw_error(env, nullptr, "startIoLoad: level must be 0-2 (weak/medium/strong)");
        return nullptr;
    }

    char dirBuf[512] = {};
    size_t dirLen = 0;
    napi_get_value_string_utf8(env, args[1], dirBuf, sizeof(dirBuf), &dirLen);

    // Stop previous I/O load if running
    if (g_ioActive) {
        g_ioActive = false;
        if (g_ioThread.joinable()) {
            g_ioThread.join();
        }
    }

    std::unique_lock<std::mutex> lk(g_ioMutex);
    g_ioFilePath = std::string(dirBuf, dirLen) + "/io_sim_testfile.dat";
    lk.unlock();

    // Create / overwrite test file (64 MB)
    {
        FILE *f = fopen(g_ioFilePath.c_str(), "wb");
        if (!f) {
            napi_throw_error(env, nullptr, "startIoLoad: cannot create test file");
            return nullptr;
        }
        // Write a sparse-ish pattern to quickly initialize
        const int chunkSize = 65536;
        auto chunk = std::make_unique<char[]>(chunkSize);
        std::memset(chunk.get(), 0xCD, chunkSize);
        for (int i = 0; i < 1024; ++i) {   // 1024 × 64KB = 64MB
            fwrite(chunk.get(), 1, chunkSize, f);
        }
        fclose(f);
    }

    g_ioLevel  = level;
    g_ioActive = true;
    g_ioThread = std::thread(IoLoadWorker);

    return nullptr;
}

// ── StopIoLoad() ─────────────────────────────────────────────────────────────
napi_value StopIoLoad(napi_env env, napi_callback_info info) {
    if (g_ioActive) {
        g_ioActive = false;
        if (g_ioThread.joinable()) {
            g_ioThread.join();
        }
    }
    // Clean up test file
    std::unique_lock<std::mutex> lk(g_ioMutex);
    if (!g_ioFilePath.empty()) {
        std::remove(g_ioFilePath.c_str());
        g_ioFilePath.clear();
    }
    g_ioLevel = 0;
    return nullptr;
}

// ── GetSimulatorStatus() → { cpuActive, cpuLevel, memActive, memLevel, ioActive, ioLevel } ─
napi_value GetSimulatorStatus(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_create_object(env, &result);

    auto setBool = [&](const char *key, bool val) {
        napi_value v;
        napi_get_boolean(env, val, &v);
        napi_set_named_property(env, result, key, v);
    };
    auto setInt = [&](const char *key, int val) {
        napi_value v;
        napi_create_int32(env, val, &v);
        napi_set_named_property(env, result, key, v);
    };

    setBool("cpuActive", g_cpuActive);
    setInt("cpuLevel", g_cpuLevel);
    setBool("memActive", g_memActive);
    setInt("memLevel", g_memLevel);
    setBool("ioActive", g_ioActive);
    setInt("ioLevel", g_ioLevel);

    return result;
}

} // namespace ResourceSimulator
