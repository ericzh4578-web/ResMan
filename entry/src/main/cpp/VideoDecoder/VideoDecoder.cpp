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

#include "VideoDecoder.h"

#include <multimedia/player_framework/native_avcodec_videodecoder.h>
#include <multimedia/player_framework/native_avcapability.h>
#include <multimedia/player_framework/native_avcodec_base.h>
#include <multimedia/player_framework/native_avformat.h>
#include <multimedia/player_framework/native_avbuffer.h>
#include <multimedia/player_framework/native_avdemuxer.h>
#include <multimedia/player_framework/native_avsource.h>

#include <string>
#include <thread>
#include <atomic>
#include <mutex>
#include <condition_variable>
#include <queue>
#include <memory>
#include <cstring>

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

namespace {

struct CodecBufferInfo {
    uint32_t index{0};
    OH_AVBuffer *buffer{nullptr};
    bool isValid{true};
    CodecBufferInfo(uint32_t idx, OH_AVBuffer *buf) : index(idx), buffer(buf) {}
};

// Simple thread-safe queue
template <typename T>
class SafeQueue {
public:
    void Enqueue(T item) {
        std::unique_lock<std::mutex> lk(mtx_);
        queue_.push(std::move(item));
        cv_.notify_one();
    }

    T Dequeue() {
        std::unique_lock<std::mutex> lk(mtx_);
        cv_.wait(lk, [this] { return !queue_.empty() || flushed_; });
        if (queue_.empty()) return nullptr;
        T item = std::move(queue_.front());
        queue_.pop();
        return item;
    }

    void Flush() {
        std::unique_lock<std::mutex> lk(mtx_);
        flushed_ = true;
        while (!queue_.empty()) {
            queue_.pop();
        }
        cv_.notify_all();
    }

    void Reset() {
        std::unique_lock<std::mutex> lk(mtx_);
        flushed_ = false;
    }

private:
    std::mutex mtx_;
    std::condition_variable cv_;
    std::queue<T> queue_;
    bool flushed_{false};
};

// ─────────────────────────────────────────────────────────────────────────────
// NV12 → RGBA conversion (row-by-row, handles stride padding)
// ─────────────────────────────────────────────────────────────────────────────
// NV12 layout: Y plane (wStride × hStride), then interleaved UV plane (wStride × hStride/2)
// Output: RGBA8888, tightly packed (width × height × 4 bytes)
static void NV12ToRGBA(const uint8_t *src, int width, int height, int wStride, int hStride,
                       uint8_t *dst) {
    const uint8_t *yPlane = src;
    const uint8_t *uvPlane = src + wStride * hStride;

    for (int row = 0; row < height; ++row) {
        const uint8_t *yRow = yPlane + row * wStride;
        const uint8_t *uvRow = uvPlane + (row / 2) * wStride;
        uint8_t *dstRow = dst + row * width * 4;

        for (int col = 0; col < width; ++col) {
            int Y = yRow[col];
            int U = uvRow[(col & ~1)];     // even index
            int V = uvRow[(col & ~1) + 1]; // odd index

            // BT.601 full-range
            int C = Y - 16;
            int D = U - 128;
            int E = V - 128;

            int R = (298 * C + 409 * E + 128) >> 8;
            int G = (298 * C - 100 * D - 208 * E + 128) >> 8;
            int B = (298 * C + 516 * D + 128) >> 8;

            dstRow[col * 4 + 0] = (uint8_t)(R < 0 ? 0 : R > 255 ? 255 : R);
            dstRow[col * 4 + 1] = (uint8_t)(G < 0 ? 0 : G > 255 ? 255 : G);
            dstRow[col * 4 + 2] = (uint8_t)(B < 0 ? 0 : B > 255 ? 255 : B);
            dstRow[col * 4 + 3] = 255; // alpha
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Context shared between callbacks and the worker thread
// ─────────────────────────────────────────────────────────────────────────────
struct DecodeContext {
    // Decoder
    OH_AVCodec *videoDec{nullptr};

    // Demuxer / source
    OH_AVSource *avSource{nullptr};
    OH_AVDemuxer *avDemuxer{nullptr};
    int32_t videoTrackIndex{-1};

    // Video geometry (filled on first output frame)
    int32_t width{0};
    int32_t height{0};
    int32_t wStride{0};
    int32_t hStride{0};

    // Queues
    SafeQueue<std::shared_ptr<CodecBufferInfo>> inQueue;
    SafeQueue<std::shared_ptr<CodecBufferInfo>> outQueue;

    // Thread-safe function to call JS callback
    napi_threadsafe_function tsfn{nullptr};

    std::atomic<bool> eosSent{false};
    std::atomic<bool> eosReceived{false};
    std::atomic<bool> hasError{false};
};

// ─────────────────────────────────────────────────────────────────────────────
// Data passed to the JS callback via the thread-safe function
// ─────────────────────────────────────────────────────────────────────────────
struct FrameData {
    std::unique_ptr<uint8_t[]> rgba;
    size_t size{0};
    int32_t width{0};
    int32_t height{0};
    bool isEos{false};
};

// ─────────────────────────────────────────────────────────────────────────────
// Decoder callbacks
// ─────────────────────────────────────────────────────────────────────────────
static void OnError(OH_AVCodec * /*codec*/, int32_t /*errorCode*/, void *userData) {
    auto *ctx = static_cast<DecodeContext *>(userData);
    ctx->hasError = true;
    ctx->inQueue.Flush();
    ctx->outQueue.Flush();
}

static void OnStreamChanged(OH_AVCodec * /*codec*/, OH_AVFormat *format, void *userData) {
    auto *ctx = static_cast<DecodeContext *>(userData);
    OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_PIC_WIDTH, &ctx->width);
    OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_PIC_HEIGHT, &ctx->height);
    OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_STRIDE, &ctx->wStride);
    OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_SLICE_HEIGHT, &ctx->hStride);
}

static void OnNeedInputBuffer(OH_AVCodec * /*codec*/, uint32_t index, OH_AVBuffer *buffer, void *userData) {
    auto *ctx = static_cast<DecodeContext *>(userData);
    ctx->inQueue.Enqueue(std::make_shared<CodecBufferInfo>(index, buffer));
}

static void OnNewOutputBuffer(OH_AVCodec *codec, uint32_t index, OH_AVBuffer *buffer, void *userData) {
    auto *ctx = static_cast<DecodeContext *>(userData);

    // Lazily fetch geometry on first frame
    if (ctx->width == 0) {
        auto fmt = std::shared_ptr<OH_AVFormat>(OH_VideoDecoder_GetOutputDescription(codec), OH_AVFormat_Destroy);
        if (fmt) {
            OH_AVFormat_GetIntValue(fmt.get(), OH_MD_KEY_VIDEO_PIC_WIDTH, &ctx->width);
            OH_AVFormat_GetIntValue(fmt.get(), OH_MD_KEY_VIDEO_PIC_HEIGHT, &ctx->height);
            OH_AVFormat_GetIntValue(fmt.get(), OH_MD_KEY_VIDEO_STRIDE, &ctx->wStride);
            OH_AVFormat_GetIntValue(fmt.get(), OH_MD_KEY_VIDEO_SLICE_HEIGHT, &ctx->hStride);
        }
    }

    ctx->outQueue.Enqueue(std::make_shared<CodecBufferInfo>(index, buffer));
}

// ─────────────────────────────────────────────────────────────────────────────
// Thread-safe function JS call: runs on the main JS thread
// ─────────────────────────────────────────────────────────────────────────────
static void CallJsCallback(napi_env env, napi_value jsCallback, void * /*context*/, void *data) {
    auto *frame = static_cast<FrameData *>(data);
    std::unique_ptr<FrameData> frameOwner(frame); // auto-delete

    if (env == nullptr || jsCallback == nullptr) return;

    napi_value argv[4];

    if (frame->isEos) {
        // EOS: pass null buffer
        napi_get_null(env, &argv[0]);
        napi_create_int32(env, 0, &argv[1]);
        napi_create_int32(env, 0, &argv[2]);
        napi_create_int32(env, 1, &argv[3]); // isEos = true (1)
    } else {
        // Wrap RGBA bytes in an ArrayBuffer (zero-copy via external)
        // We transfer ownership to JS; the finalizer will delete[] the buffer.
        void *rawPtr = frame->rgba.get();
        napi_value arrayBuffer;
        napi_create_external_arraybuffer(
            env, rawPtr, frame->size,
            [](napi_env /*e*/, void *finalize_data, void * /*hint*/) {
                delete[] static_cast<uint8_t *>(finalize_data);
            },
            nullptr, &arrayBuffer);
        frame->rgba.release(); // ownership transferred to JS finalizer

        argv[0] = arrayBuffer;
        napi_create_int32(env, frame->width, &argv[1]);
        napi_create_int32(env, frame->height, &argv[2]);
        napi_create_int32(env, 0, &argv[3]); // isEos = false (0)
    }

    napi_value global;
    napi_get_global(env, &global);
    napi_call_function(env, global, jsCallback, 4, argv, nullptr);
}

// ─────────────────────────────────────────────────────────────────────────────
// Worker thread: feeds demuxed packets → decoder, drains decoded frames → JS
// ─────────────────────────────────────────────────────────────────────────────
static void DecoderWorker(DecodeContext *ctx) {
    // ── Input feeding thread ──────────────────────────────────────────────
    std::thread inputThread([ctx]() {
        while (!ctx->eosSent && !ctx->hasError) {
            auto bufInfo = ctx->inQueue.Dequeue();
            if (!bufInfo || !bufInfo->isValid) break;

            OH_AVCodecBufferAttr attr{};

            // Read one packet from demuxer
            OH_AVErrCode readRet = OH_AVDemuxer_ReadSampleBuffer(ctx->avDemuxer, ctx->videoTrackIndex,
                                                                  bufInfo->buffer);
            if (readRet != AV_ERR_OK) {
                // Signal EOS
                attr.flags = AVCODEC_BUFFER_FLAGS_EOS;
                attr.size = 0;
                OH_AVBuffer_SetBufferAttr(bufInfo->buffer, &attr);
                OH_VideoDecoder_PushInputBuffer(ctx->videoDec, bufInfo->index);
                ctx->eosSent = true;
                break;
            }

            OH_AVBuffer_GetBufferAttr(bufInfo->buffer, &attr);
            if (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) {
                OH_VideoDecoder_PushInputBuffer(ctx->videoDec, bufInfo->index);
                ctx->eosSent = true;
                break;
            }

            OH_VideoDecoder_PushInputBuffer(ctx->videoDec, bufInfo->index);
        }
    });

    // ── Output draining (current thread) ─────────────────────────────────
    while (!ctx->eosReceived && !ctx->hasError) {
        auto bufInfo = ctx->outQueue.Dequeue();
        if (!bufInfo || !bufInfo->isValid) break;

        OH_AVCodecBufferAttr attr{};
        OH_AVBuffer_GetBufferAttr(bufInfo->buffer, &attr);

        if (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) {
            // Send EOS notification to JS
            auto *frame = new FrameData();
            frame->isEos = true;
            napi_call_threadsafe_function(ctx->tsfn, frame, napi_tsfn_blocking);
            ctx->eosReceived = true;
            OH_VideoDecoder_FreeOutputBuffer(ctx->videoDec, bufInfo->index);
            break;
        }

        // Convert NV12 → RGBA
        uint8_t *srcAddr = OH_AVBuffer_GetAddr(bufInfo->buffer);
        if (srcAddr && ctx->width > 0 && ctx->height > 0) {
            size_t rgbaSize = static_cast<size_t>(ctx->width) * ctx->height * 4;
            auto *frame = new FrameData();
            frame->rgba = std::make_unique<uint8_t[]>(rgbaSize);
            frame->size = rgbaSize;
            frame->width = ctx->width;
            frame->height = ctx->height;
            frame->isEos = false;

            NV12ToRGBA(srcAddr, ctx->width, ctx->height, ctx->wStride, ctx->hStride,
                       frame->rgba.get());

            napi_call_threadsafe_function(ctx->tsfn, frame, napi_tsfn_blocking);
        }

        OH_VideoDecoder_FreeOutputBuffer(ctx->videoDec, bufInfo->index);
    }

    inputThread.join();

    // Release the thread-safe function (allows GC of the JS callback)
    napi_release_threadsafe_function(ctx->tsfn, napi_tsfn_release);
    ctx->tsfn = nullptr;

    // Tear down decoder
    if (ctx->videoDec) {
        OH_VideoDecoder_Stop(ctx->videoDec);
        OH_VideoDecoder_Destroy(ctx->videoDec);
        ctx->videoDec = nullptr;
    }
    if (ctx->avDemuxer) {
        OH_AVDemuxer_Destroy(ctx->avDemuxer);
        ctx->avDemuxer = nullptr;
    }
    if (ctx->avSource) {
        OH_AVSource_Destroy(ctx->avSource);
        ctx->avSource = nullptr;
    }

    delete ctx;
}

} // anonymous namespace

// ─────────────────────────────────────────────────────────────────────────────
// Public NAPI entry point
// ─────────────────────────────────────────────────────────────────────────────
namespace VideoDecoder {

/**
 * JS signature:
 *   decodeVideoFrames(filePath: string,
 *                     callback: (frame: ArrayBuffer | null, width: number,
 *                                height: number, isEos: number) => void): void
 */
napi_value DecodeVideoFrames(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 2) {
        napi_throw_error(env, nullptr, "decodeVideoFrames: expected 2 arguments (filePath, callback)");
        return nullptr;
    }

    // ── 1. Extract file path ──────────────────────────────────────────────
    size_t pathLen = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &pathLen);
    std::string filePath(pathLen + 1, '\0');
    napi_get_value_string_utf8(env, args[0], &filePath[0], pathLen + 1, &pathLen);
    filePath.resize(pathLen);

    // ── 2. Validate callback ──────────────────────────────────────────────
    napi_valuetype cbType;
    napi_typeof(env, args[1], &cbType);
    if (cbType != napi_function) {
        napi_throw_type_error(env, nullptr, "decodeVideoFrames: second argument must be a function");
        return nullptr;
    }

    // ── 3. Open source & demuxer ──────────────────────────────────────────
    OH_AVSource *avSource = OH_AVSource_CreateWithURI(const_cast<char *>(filePath.c_str()));
    if (!avSource) {
        napi_throw_error(env, nullptr, "decodeVideoFrames: failed to create AVSource");
        return nullptr;
    }

    OH_AVDemuxer *avDemuxer = OH_AVDemuxer_CreateWithSource(avSource);
    if (!avDemuxer) {
        OH_AVSource_Destroy(avSource);
        napi_throw_error(env, nullptr, "decodeVideoFrames: failed to create AVDemuxer");
        return nullptr;
    }

    // ── 4. Find video track ───────────────────────────────────────────────
    OH_AVFormat *srcFormat = OH_AVSource_GetSourceFormat(avSource);
    int32_t trackCount = 0;
    OH_AVFormat_GetIntValue(srcFormat, OH_MD_KEY_TRACK_COUNT, &trackCount);
    OH_AVFormat_Destroy(srcFormat);

    int32_t videoTrackIndex = -1;
    const char *mimeType = nullptr;
    int32_t videoWidth = 0, videoHeight = 0;

    for (int32_t i = 0; i < trackCount; ++i) {
        OH_AVFormat *trackFmt = OH_AVSource_GetTrackFormat(avSource, i);
        if (!trackFmt) continue;

        OH_AVFormat_GetStringValue(trackFmt, OH_MD_KEY_CODEC_MIME, &mimeType);
        if (mimeType &&
            (strncmp(mimeType, "video/avc", 9) == 0 || strncmp(mimeType, "video/hevc", 10) == 0)) {
            videoTrackIndex = i;
            OH_AVFormat_GetIntValue(trackFmt, OH_MD_KEY_WIDTH, &videoWidth);
            OH_AVFormat_GetIntValue(trackFmt, OH_MD_KEY_HEIGHT, &videoHeight);
            OH_AVFormat_Destroy(trackFmt);
            break;
        }
        OH_AVFormat_Destroy(trackFmt);
    }

    if (videoTrackIndex < 0) {
        OH_AVDemuxer_Destroy(avDemuxer);
        OH_AVSource_Destroy(avSource);
        napi_throw_error(env, nullptr, "decodeVideoFrames: no H.264/H.265 video track found");
        return nullptr;
    }

    OH_AVDemuxer_SelectTrackByID(avDemuxer, videoTrackIndex);

    // ── 5. Create decoder ─────────────────────────────────────────────────
    // Re-read mime for decoder creation
    OH_AVFormat *trackFmt = OH_AVSource_GetTrackFormat(avSource, videoTrackIndex);
    OH_AVFormat_GetStringValue(trackFmt, OH_MD_KEY_CODEC_MIME, &mimeType);

    OH_AVCodec *videoDec = nullptr;
    if (mimeType && strncmp(mimeType, "video/hevc", 10) == 0) {
        videoDec = OH_VideoDecoder_CreateByMime(OH_AVCODEC_MIMETYPE_VIDEO_HEVC);
    } else {
        videoDec = OH_VideoDecoder_CreateByMime(OH_AVCODEC_MIMETYPE_VIDEO_AVC);
    }
    OH_AVFormat_Destroy(trackFmt);

    if (!videoDec) {
        OH_AVDemuxer_Destroy(avDemuxer);
        OH_AVSource_Destroy(avSource);
        napi_throw_error(env, nullptr, "decodeVideoFrames: failed to create video decoder");
        return nullptr;
    }

    // ── 6. Build context ──────────────────────────────────────────────────
    auto *ctx = new DecodeContext();
    ctx->videoDec = videoDec;
    ctx->avSource = avSource;
    ctx->avDemuxer = avDemuxer;
    ctx->videoTrackIndex = videoTrackIndex;

    // ── 7. Create thread-safe function ────────────────────────────────────
    napi_value resourceName;
    napi_create_string_utf8(env, "VideoDecoderCallback", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_threadsafe_function(env, args[1], nullptr, resourceName,
                                    0,    // max_queue_size (0 = unlimited)
                                    1,    // initial_thread_count
                                    nullptr, nullptr, nullptr,
                                    CallJsCallback, &ctx->tsfn);

    // ── 8. Register decoder callbacks ────────────────────────────────────
    OH_AVCodecCallback cb = {OnError, OnStreamChanged, OnNeedInputBuffer, OnNewOutputBuffer};
    OH_VideoDecoder_RegisterCallback(videoDec, cb, ctx);

    // ── 9. Configure decoder ──────────────────────────────────────────────
    auto fmt = std::shared_ptr<OH_AVFormat>(OH_AVFormat_Create(), OH_AVFormat_Destroy);
    OH_AVFormat_SetIntValue(fmt.get(), OH_MD_KEY_WIDTH, videoWidth);
    OH_AVFormat_SetIntValue(fmt.get(), OH_MD_KEY_HEIGHT, videoHeight);
    OH_AVFormat_SetIntValue(fmt.get(), OH_MD_KEY_PIXEL_FORMAT,
                            AV_PIXEL_FORMAT_NV12); // request NV12 output
    OH_VideoDecoder_Configure(videoDec, fmt.get());

    // ── 10. Prepare & start ───────────────────────────────────────────────
    OH_VideoDecoder_Prepare(videoDec);
    OH_VideoDecoder_Start(videoDec);

    // ── 11. Spin up worker thread (owns ctx, destroys it when done) ───────
    std::thread(DecoderWorker, ctx).detach();

    return nullptr;
}

} // namespace VideoDecoder
