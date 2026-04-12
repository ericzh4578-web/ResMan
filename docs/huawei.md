参考以下示例代码，可以完成Buffer模式下视频解码的全流程，实现异步模式的数据轮转。此处以输入H.264码流文件，解码成YUV文件为例。

添加头文件。



```c++
#include <multimedia/player_framework/native_avcodec_videodecoder.h>
#include <multimedia/player_framework/native_avcapability.h>
#include <multimedia/player_framework/native_avcodec_base.h>
#include <multimedia/player_framework/native_avformat.h>
#include <multimedia/player_framework/native_avbuffer.h>
#include <native_buffer/native_buffer.h>
#include <fstream>
```

创建解码器实例。

与Surface模式相同，此处不再赘述。

```c++
// 通过codecname创建解码器，应用有特殊需求，比如选择支持某种分辨率规格的解码器，可先查询capability，再根据codec name创建解码器。
OH_AVCapability *capability = OH_AVCodec_GetCapability(OH_AVCODEC_MIMETYPE_VIDEO_AVC, false);
const char *name = OH_AVCapability_GetName(capability);
OH_AVCodec *videoDec = OH_VideoDecoder_CreateByName(name);
// 通过MIME TYPE创建解码器，只能创建系统推荐的特定编解码器。
// 涉及创建多路编解码器时，优先创建硬件解码器实例，硬件资源不够时再创建软件解码器实例。
// 软/硬解：创建H.264解码器。
OH_AVCodec *videoDec = OH_VideoDecoder_CreateByMime(OH_AVCODEC_MIMETYPE_VIDEO_AVC);
// 硬解：创建H.265解码器。
OH_AVCodec *videoDec = OH_VideoDecoder_CreateByMime(OH_AVCODEC_MIMETYPE_VIDEO_HEVC);
```

调用OH_VideoDecoder_RegisterCallback()设置回调函数。

注册回调函数指针集合OH_AVCodecCallback，包括：

OH_AVCodecOnError 解码器运行错误，返回的错误码详情请参见：OH_AVCodecOnError；
OH_AVCodecOnStreamChanged 码流信息变化，如码流宽、高变化；
OH_AVCodecOnNeedInputBuffer 运行过程中需要新的输入数据，即解码器已准备好，可以输入数据；
OH_AVCodecOnNewOutputBuffer 运行过程中产生了新的输出数据，即解码完成。
开发者可以通过处理该回调报告的信息，确保解码器正常运转。

回调函数的具体实现可参考示例工程。

```c++
int32_t cropTop = 0;
int32_t cropBottom = 0;
int32_t cropLeft = 0;
int32_t cropRight = 0;
bool isFirstFrame = true;
// 解码异常回调OH_AVCodecOnError实现。
static void OnError(OH_AVCodec *codec, int32_t errorCode, void *userData)
{
    // 回调的错误码由开发者判断处理。
    (void)codec;
    (void)errorCode;
    (void)userData;
}

// 解码数据流变化回调OH_AVCodecOnStreamChanged实现。
static void OnStreamChanged(OH_AVCodec *codec, OH_AVFormat *format, void *userData)
{
    // 可选，开发者需要获取视频宽、高、跨距等时可配置。
    // 可通过format获取到变化后的视频宽、高、跨距等。
    (void)codec;
    (void)userData;
    bool ret = OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_PIC_WIDTH, &width) &&
               OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_PIC_HEIGHT, &height) &&
               OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_STRIDE, &widthStride) &&
               OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_SLICE_HEIGHT, &heightStride) &&
               // 获取裁剪矩形信息可选。
               OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_CROP_TOP, &cropTop) &&
               OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_CROP_BOTTOM, &cropBottom) &&
               OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_CROP_LEFT, &cropLeft) &&
               OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_CROP_RIGHT, &cropRight);
    if (!ret) {
        // 异常处理。
    }
}

// 解码输入回调OH_AVCodecOnNeedInputBuffer实现。
static void OnNeedInputBuffer(OH_AVCodec *codec, uint32_t index, OH_AVBuffer *buffer, void *userData)
{
    // 输入帧的数据buffer和对应的index送入inQueue队列。
    (void)codec;
    (void)userData;
    inQueue.Enqueue(std::make_shared<CodecBufferInfo>(index, buffer));
}

// 解码输出回调OH_AVCodecOnNewOutputBuffer实现。
static void OnNewOutputBuffer(OH_AVCodec *codec, uint32_t index, OH_AVBuffer *buffer, void *userData)
{
    // 可选，开发者需要获取视频宽、高、跨距等时可配置。
    // 获取视频宽、高、跨距。
    if (isFirstFrame) {
        auto format = std::shared_ptr<OH_AVFormat>(OH_VideoDecoder_GetOutputDescription(codec), OH_AVFormat_Destroy);
        if (format == nullptr) {
            // 异常处理。
        }
        bool ret = OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_VIDEO_PIC_WIDTH, &width) &&
                   OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_VIDEO_PIC_HEIGHT, &height) &&
                   OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_VIDEO_STRIDE, &widthStride) &&
                   OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_VIDEO_SLICE_HEIGHT, &heightStride) &&
                   // 获取裁剪矩形信息可选。
                   OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_VIDEO_CROP_TOP, &cropTop) &&
                   OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_VIDEO_CROP_BOTTOM, &cropBottom) &&
                   OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_VIDEO_CROP_LEFT, &cropLeft) &&
                   OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_VIDEO_CROP_RIGHT, &cropRight);
        if (!ret) {
            // 异常处理。
        }
        isFirstFrame = false;
    }
    // 完成帧的数据buffer和对应的index送入outQueue队列。
    (void)userData;
    outQueue.Enqueue(std::make_shared<CodecBufferInfo>(index, buffer));
}
// 配置异步回调，调用OH_VideoDecoder_RegisterCallback接口。
OH_AVCodecCallback cb = {&OnError, &OnStreamChanged, &OnNeedInputBuffer, &OnNewOutputBuffer};
// 配置异步回调。
OH_AVErrCode ret = OH_VideoDecoder_RegisterCallback(videoDec, cb, nullptr); // nullptr:开发者执行回调所依赖的数据userData为空。
if (ret != AV_ERR_OK) {
    // 异常处理。
}
```
说明
在回调函数中，对数据队列进行操作时，需要注意多线程同步的问题。

（可选）OH_VideoDecoder_SetDecryptionConfig设置解密配置。在获取到DRM信息（参考音视频解封装开发步骤第4步），完成DRM许可证申请后，通过此接口进行解密配置。此接口需在Prepare前调用。在Buffer模式下，DRM解密能力仅支持非安全视频通路。DRM相关接口详见DRM API文档。

添加头文件。

```c++
#include <multimedia/drm_framework/native_mediakeysystem.h>
#include <multimedia/drm_framework/native_mediakeysession.h>
#include <multimedia/drm_framework/native_drm_err.h>
#include <multimedia/drm_framework/native_drm_common.h>
```
在 CMake 脚本中链接动态库。

target_link_libraries(sample PUBLIC libnative_drm.so)
使用示例：

```c++
// 根据DRM信息创建指定的DRM系统，以创建"com.wiseplay.drm"为例。
MediaKeySystem *system = nullptr;
int32_t ret = OH_MediaKeySystem_Create("com.wiseplay.drm", &system);
if (system == nullptr) {
    printf("create media key system failed");
    return;
}

// 创建解密会话。
// 使用非安全视频通路，应创建CONTENT_PROTECTION_LEVEL_SW_CRYPTO及以上内容保护级别的MediaKeySession。
MediaKeySession *session = nullptr;
DRM_ContentProtectionLevel contentProtectionLevel = CONTENT_PROTECTION_LEVEL_SW_CRYPTO;
ret = OH_MediaKeySystem_CreateMediaKeySession(system, &contentProtectionLevel, &session);
if (ret != DRM_OK) {
    // 如创建失败，请查看DRM接口文档及日志信息。
    printf("create media key session failed.");
    return;
}
if (session == nullptr) {
    printf("media key session is nullptr.");
    return;
}
// 获取许可证请求、设置许可证响应等。
// 设置解密配置，即将解密会话、安全视频通路标志设置到解码器中。
bool secureVideoPath = false;
ret = OH_VideoDecoder_SetDecryptionConfig(videoDec, session, secureVideoPath);
调用OH_VideoDecoder_Configure()配置解码器。

与Surface模式相同，此处不再赘述。

auto format = std::shared_ptr<OH_AVFormat>(OH_AVFormat_Create(), OH_AVFormat_Destroy);
if (format == nullptr) {
    // 异常处理。
}
// 写入format。
OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_WIDTH, width); // 必须配置。
OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_HEIGHT, height); // 必须配置。
OH_AVFormat_SetIntValue(format.get(), OH_MD_KEY_PIXEL_FORMAT, pixelFormat);
// 配置解码器。
OH_AVErrCode ret = OH_VideoDecoder_Configure(videoDec, format.get());
if (ret != AV_ERR_OK) {
    // 异常处理。
}
调用OH_VideoDecoder_Prepare()解码器就绪。

该接口将在解码器运行前进行一些数据的准备工作。

OH_AVErrCode ret = OH_VideoDecoder_Prepare(videoDec);
if (ret != AV_ERR_OK) {
    // 异常处理。
}
调用OH_VideoDecoder_Start()启动解码器。

std::unique_ptr<std::ofstream> outputFile = std::make_unique<std::ofstream>();
if (outputFile != nullptr) {
    outputFile->open("/*yourpath*.yuv", std::ios::out | std::ios::binary | std::ios::ate);
}
// 启动解码器，开始解码。
OH_AVErrCode ret = OH_VideoDecoder_Start(videoDec);
if (ret != AV_ERR_OK) {
    // 异常处理。
}
（可选）OH_VideoDecoder_SetParameter()动态配置解码器参数。

详细可配置选项的说明请参考视频专有键值对。

auto format = std::shared_ptr<OH_AVFormat>(OH_AVFormat_Create(), OH_AVFormat_Destroy);
if (format == nullptr) {
    // 异常处理。
}
// 配置帧率。
OH_AVFormat_SetDoubleValue(format.get(), OH_MD_KEY_FRAME_RATE, 30.0);
OH_AVErrCode ret = OH_VideoDecoder_SetParameter(videoDec, format.get());
if (ret != AV_ERR_OK) {
    // 异常处理。
}
```
（可选）调用OH_AVCencInfo_SetAVBuffer()，设置cencInfo。

与Surface模式相同，此处不再赘述。

使用示例：
```c++
uint32_t keyIdLen = DRM_KEY_ID_SIZE;
uint8_t keyId[] = {
    0xd4, 0xb2, 0x01, 0xe4, 0x61, 0xc8, 0x98, 0x96,
    0xcf, 0x05, 0x22, 0x39, 0x8d, 0x09, 0xe6, 0x28};
uint32_t ivLen = DRM_KEY_IV_SIZE;
uint8_t iv[] = {
    0xbf, 0x77, 0xed, 0x51, 0x81, 0xde, 0x36, 0x3e,
    0x52, 0xf7, 0x20, 0x4f, 0x72, 0x14, 0xa3, 0x95};
uint32_t encryptedBlockCount = 0;
uint32_t skippedBlockCount = 0;
uint32_t firstEncryptedOffset = 0;
uint32_t subsampleCount = 1;
DrmSubsample subsamples[1] = { {0x10, 0x16} };
// 创建CencInfo实例。
OH_AVCencInfo *cencInfo = OH_AVCencInfo_Create();
if (cencInfo == nullptr) {
    // 异常处理。
}
// 设置解密算法。
OH_AVErrCode errNo = OH_AVCencInfo_SetAlgorithm(cencInfo, DRM_ALG_CENC_AES_CTR);
if (errNo != AV_ERR_OK) {
    // 异常处理。
}
// 设置KeyId和Iv。
errNo = OH_AVCencInfo_SetKeyIdAndIv(cencInfo, keyId, keyIdLen, iv, ivLen);
if (errNo != AV_ERR_OK) {
    // 异常处理。
}
// 设置Sample信息。
errNo = OH_AVCencInfo_SetSubsampleInfo(cencInfo, encryptedBlockCount, skippedBlockCount, firstEncryptedOffset,
    subsampleCount, subsamples);
if (errNo != AV_ERR_OK) {
    // 异常处理。
}
// 设置模式：KeyId、Iv和SubSamples已被设置。
errNo = OH_AVCencInfo_SetMode(cencInfo, DRM_CENC_INFO_KEY_IV_SUBSAMPLES_SET);
if (errNo != AV_ERR_OK) {
    // 异常处理。
}
// 将CencInfo设置到AVBuffer中。
errNo = OH_AVCencInfo_SetAVBuffer(cencInfo, buffer);
if (errNo != AV_ERR_OK) {
    // 异常处理。
}
// 销毁CencInfo实例。
errNo = OH_AVCencInfo_Destroy(cencInfo);
if (errNo != AV_ERR_OK) {
    // 异常处理。
}
调用OH_VideoDecoder_PushInputBuffer()写入解码码流。

与Surface模式相同，此处不再赘述。

std::shared_ptr<CodecBufferInfo> bufferInfo = inQueue.Dequeue();
std::shared_lock<std::shared_mutex> lock(codecMutex);
if (bufferInfo == nullptr || !bufferInfo->isValid) {
    // 异常处理。
}
// 写入码流数据。
uint8_t *addr = OH_AVBuffer_GetAddr(bufferInfo->buffer);
if (addr == nullptr) {
   // 异常处理。
}
int32_t capacity = OH_AVBuffer_GetCapacity(bufferInfo->buffer);
if (size > capacity) {
    // 异常处理。
}
memcpy(addr, frameData, size);
// 配置帧数据的输入尺寸、偏移量、时间戳等字段信息。
OH_AVCodecBufferAttr info;
info.size = size;
info.offset = offset;
info.pts = pts;
info.flags = flags;
// info信息写入buffer。
OH_AVErrCode setBufferRet = OH_AVBuffer_SetBufferAttr(bufferInfo->buffer, &info);
if (setBufferRet != AV_ERR_OK) {
    // 异常处理。
}
// 送入解码输入队列进行解码，index为对应buffer队列的下标。
OH_AVErrCode pushInputRet = OH_VideoDecoder_PushInputBuffer(videoDec, bufferInfo->index);
if (pushInputRet != AV_ERR_OK) {
    // 异常处理。
}
```
调用OH_VideoDecoder_FreeOutputBuffer()释放解码帧。

以下示例中，bufferInfo的成员变量：

index：回调函数OnNewOutputBuffer传入的参数，与buffer唯一对应的标识；
buffer： 回调函数OnNewOutputBuffer传入的参数，可以通过OH_AVBuffer_GetAddr接口获取图像虚拟地址；
isValid：bufferInfo中存储的buffer实例是否有效。
```c++
std::shared_ptr<CodecBufferInfo> bufferInfo = outQueue.Dequeue();
std::shared_lock<std::shared_mutex> lock(codecMutex);
if (bufferInfo == nullptr || !bufferInfo->isValid) {
    // 异常处理。
}
// 获取解码后信息。
OH_AVCodecBufferAttr info;
OH_AVErrCode getBufferRet = OH_AVBuffer_GetBufferAttr(bufferInfo->buffer, &info);
if (getBufferRet != AV_ERR_OK) {
    // 异常处理。
}
// 将解码完成数据data写入到对应输出文件中。
uint8_t *addr = OH_AVBuffer_GetAddr(bufferInfo->buffer);
if (addr == nullptr) {
   // 异常处理。
}
if (outputFile != nullptr && outputFile->is_open()) {
    outputFile->write(reinterpret_cast<char *>(addr), info.size);
}
// Buffer模式，释放已完成写入的数据，index为对应buffer队列的下标。
OH_AVErrCode freeOutputRet = OH_VideoDecoder_FreeOutputBuffer(videoDec, bufferInfo->index);
if (freeOutputRet != AV_ERR_OK) {
    // 异常处理。
}
```
NV12/NV21图像如果需要依次将Y、U、V三个分量拷贝至另一块buffer中，以NV12图像为例，按行拷贝示例如下：

以NV12图像为例，width、height、wStride、hStride图像排布参考下图：

OH_MD_KEY_VIDEO_PIC_WIDTH表示width；
OH_MD_KEY_VIDEO_PIC_HEIGHT表示height；
OH_MD_KEY_VIDEO_STRIDE表示wStride；
OH_MD_KEY_VIDEO_SLICE_HEIGHT表示hStride。


添加头文件。
```c++
#include <string.h>
使用示例：

// 源内存区域的宽、高，通过回调函数OnStreamChanged或接口OH_VideoDecoder_GetOutputDescription获取。
struct Rect
{
    int32_t width;
    int32_t height;
};

struct DstRect // 目标内存区域的宽跨距、高跨距，由开发者自行设置。
{
    int32_t wStride;
    int32_t hStride;
};
// 源内存区域的宽跨距、高跨距，通过回调函数OnStreamChanged或接口OH_VideoDecoder_GetOutputDescription获取。
struct SrcRect
{
    int32_t wStride;
    int32_t hStride;
};

Rect rect = {320, 240};
DstRect dstRect = {320, 240};
SrcRect srcRect = {320, 256};
uint8_t* dst = new uint8_t[dstRect.hStride * dstRect.wStride * 3 / 2]; // 目标内存区域的指针。
uint8_t* src = new uint8_t[srcRect.hStride * srcRect.wStride * 3 / 2]; // 源内存区域的指针。
uint8_t* dstTemp = dst;
uint8_t* srcTemp = src;
rect.height = ((rect.height + 1) / 2)  * 2 // 避免height为奇数；
rect.width = ((rect.width + 1) / 2)  * 2 // 避免width为奇数；

// Y 将Y区域的源数据复制到另一个区域的目标数据中。
for (int32_t i = 0; i < rect.height; ++i) {
    // 将源数据的一行数据复制到目标数据的一行中。
    memcpy(dstTemp, srcTemp, rect.width);
    // 更新源数据和目标数据的指针，进行下一行的复制。每更新一次源数据和目标数据的指针都向下移动一个wStride。
    dstTemp += dstRect.wStride;
    srcTemp += srcRect.wStride;
}
// padding。
// 更新源数据和目标数据的指针，指针都向下移动一个padding。
dstTemp += (dstRect.hStride - rect.height) * dstRect.wStride;
srcTemp += (srcRect.hStride - rect.height) * srcRect.wStride;
rect.height >>= 1;
// UV 将UV区域的源数据复制到另一个区域的目标数据中。
for (int32_t i = 0; i < rect.height; ++i) {
    memcpy(dstTemp, srcTemp, rect.width);
    dstTemp += dstRect.wStride;
    srcTemp += srcRect.wStride;
}

delete[] dst;
dst = nullptr;
delete[] src;
src = nullptr;
```
硬件解码在处理buffer数据时（释放数据前），输出回调开发者收到的AVbuffer是宽、高对齐后的图像数据。

一般需要获取数据的宽、高、跨距、像素格式来保证解码输出数据被正确的处理。

具体实现请参考：Buffer模式的步骤3-调用OH_VideoDecoder_RegisterCallback()设置回调函数来获取数据的宽、高、跨距、像素格式。

后续流程（包括刷新、重置、停止和销毁解码器）与Surface模式基本一致，请参考Surface模式的步骤13-16。

下面是Surface模式的刷新
可选）调用OH_VideoDecoder_Flush()刷新解码器。

调用OH_VideoDecoder_Flush接口后，解码器仍处于运行态，但会清除解码器中缓存的输入和输出数据及参数集如H.264格式的PPS/SPS。此时需调用OH_VideoDecoder_Start接口重新开始解码。

以下示例中：

xpsData、xpsSize：PPS/SPS信息，获取方式可以参考音视频解封装。
```c++
std::unique_lock<std::shared_mutex> lock(codecMutex);
// 刷新解码器videoDec。
OH_AVErrCode flushRet = OH_VideoDecoder_Flush(videoDec);
if (flushRet != AV_ERR_OK) {
    // 异常处理。
}
inQueue.Flush();
outQueue.Flush();
// 重新开始解码。
OH_AVErrCode startRet = OH_VideoDecoder_Start(videoDec);
if (startRet != AV_ERR_OK) {
    // 异常处理。
}

std::shared_ptr<CodecBufferInfo> bufferInfo = inQueue.Dequeue();
if (bufferInfo == nullptr || !bufferInfo->isValid) {
    // 异常处理。
}
// 重传PPS/SPS。
// 配置帧数据PPS/SPS信息。
uint8_t *addr = OH_AVBuffer_GetAddr(bufferInfo->buffer);
if (addr == nullptr) {
   // 异常处理
}
int32_t capacity = OH_AVBuffer_GetCapacity(bufferInfo->buffer);
if (xpsSize > capacity) {
    // 异常处理。
}
memcpy(addr, xpsData, xpsSize);
OH_AVCodecBufferAttr info;
info.flags = AVCODEC_BUFFER_FLAG_CODEC_DATA;
// info信息写入buffer。
OH_AVErrCode setBufferRet = OH_AVBuffer_SetBufferAttr(bufferInfo->buffer, &info);
if (setBufferRet != AV_ERR_OK) {
    // 异常处理。
}
// 将帧数据推送到解码器中，index为对应buffer队列的下标。
OH_AVErrCode pushInputRet = OH_VideoDecoder_PushInputBuffer(videoDec, bufferInfo->index);
if (pushInputRet != AV_ERR_OK) {
    // 异常处理。
}
```
注意
Flush之后，重新调用OH_VideoDecoder_Start接口时，需要重新传PPS/SPS。

（可选）调用OH_VideoDecoder_Reset()重置解码器。

调用OH_VideoDecoder_Reset接口后，解码器回到初始化的状态，需要调用OH_VideoDecoder_Configure接口、OH_VideoDecoder_SetSurface接口和OH_VideoDecoder_Prepare接口重新配置。

```c++
std::unique_lock<std::shared_mutex> lock(codecMutex);
// 重置解码器videoDec。
OH_AVErrCode resetRet = OH_VideoDecoder_Reset(videoDec);
if (resetRet != AV_ERR_OK) {
    // 异常处理。
}
inQueue.Flush();
outQueue.Flush();
// 重新配置解码器参数。
auto format = std::shared_ptr<OH_AVFormat>(OH_AVFormat_Create(), OH_AVFormat_Destroy);
if (format == nullptr) {
    // 异常处理。
}
OH_AVErrCode configRet = OH_VideoDecoder_Configure(videoDec, format.get());
if (configRet != AV_ERR_OK) {
    // 异常处理。
}
// Surface模式重新配置surface，而Buffer模式不需要配置surface。
OH_AVErrCode setRet = OH_VideoDecoder_SetSurface(videoDec, nativeWindow);
if (setRet != AV_ERR_OK) {
    // 异常处理。
}
// 解码器重新就绪。
OH_AVErrCode prepareRet = OH_VideoDecoder_Prepare(videoDec);
if (prepareRet != AV_ERR_OK) {
    // 异常处理。
}
```
（可选）调用OH_VideoDecoder_Stop()停止解码器。

调用OH_VideoDecoder_Stop()后，解码器保留了解码实例，释放输入输出buffer。开发者可以直接调用OH_VideoDecoder_Start接口继续解码，输入的第一个buffer需要携带参数集，从IDR帧开始送入。

```c++
std::unique_lock<std::shared_mutex> lock(codecMutex);
// 终止解码器videoDec。
OH_AVErrCode ret = OH_VideoDecoder_Stop(videoDec);
if (ret != AV_ERR_OK) {
    // 异常处理。
}
inQueue.Flush();
outQueue.Flush();
调用OH_VideoDecoder_Destroy()销毁解码器实例，释放资源。

说明
不能在回调函数中调用；
执行该步骤之后，需要开发者将videoDec指向nullptr，防止野指针导致程序错误。
std::unique_lock<std::shared_mutex> lock(codecMutex);
// 释放nativeWindow实例。
if(nativeWindow != nullptr){
    OH_NativeWindow_DestroyNativeWindow(nativeWindow);
    nativeWindow = nullptr;
}
// 调用OH_VideoDecoder_Destroy，注销解码器。
OH_AVErrCode ret = AV_ERR_OK;
if (videoDec != nullptr) {
    OH_VideoDecoder_Destroy(videoDec);
    videoDec = nullptr;
}
inQueue.Flush();
outQueue.Flush();
```