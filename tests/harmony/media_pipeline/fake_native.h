#pragma once
#include <array>
#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#define LOG_APP 0
template<class... Args> inline void FakeLog(Args&&...) {}
#define OH_LOG_ERROR(...) FakeLog(__VA_ARGS__)
#define OH_LOG_INFO(...) FakeLog(__VA_ARGS__)
#define OH_LOG_WARN(...) FakeLog(__VA_ARGS__)
constexpr int AV_ERR_OK = 0;
constexpr uint32_t AVCODEC_BUFFER_FLAGS_NONE = 0;
constexpr uint32_t AVCODEC_BUFFER_FLAGS_SYNC_FRAME = 2;
constexpr uint32_t AVCODEC_BUFFER_FLAGS_CODEC_DATA = 8;
constexpr int AV_PIXEL_FORMAT_SURFACE_FORMAT = 4;
constexpr int AV_PIXEL_FORMAT_NV12 = 2;
constexpr auto OH_AVCODEC_MIMETYPE_VIDEO_AVC = "video/avc";
constexpr auto OH_AVCODEC_MIMETYPE_VIDEO_HEVC = "video/hevc";
constexpr auto OH_MD_KEY_WIDTH = "width";
constexpr auto OH_MD_KEY_HEIGHT = "height";
constexpr auto OH_MD_KEY_PIXEL_FORMAT = "pixel_format";
constexpr auto OH_MD_KEY_VIDEO_ENABLE_LOW_LATENCY = "low_latency";
struct OH_AVCodecBufferAttr { int64_t pts; int32_t size; int32_t offset; uint32_t flags; };
struct OH_AVBuffer { std::array<uint8_t, 1024> bytes; OH_AVCodecBufferAttr attr{}; };
struct OH_AVFormat { int32_t pixelFormat = -1; };
struct OHNativeWindow { uint64_t id; bool destroyed = false; };
struct OH_AVCodec;
struct OH_AVCodecCallback {
    void (*onError)(OH_AVCodec*, int32_t, void*);
    void (*onStreamChanged)(OH_AVCodec*, OH_AVFormat*, void*);
    void (*onNeedInputBuffer)(OH_AVCodec*, uint32_t, OH_AVBuffer*, void*);
    void (*onNewOutputBuffer)(OH_AVCodec*, uint32_t, OH_AVBuffer*, void*);
};
struct OH_AVCodec {
    OH_AVCodecCallback callbacks{};
    void* user = nullptr;
    OHNativeWindow* window = nullptr;
    std::array<OH_AVBuffer, 4> buffers{};
    bool stopped = false;
    bool hasConfiguration = false;
};
namespace fake {
inline std::mutex mutex;
inline std::vector<OH_AVCodec*> codecs;
inline std::vector<OHNativeWindow*> windows;
inline std::vector<uint32_t> pushed;
inline std::vector<uint32_t> flags;
inline std::vector<int64_t> timestamps;
inline std::vector<std::vector<uint8_t>> payloads;
inline std::atomic<int> slots{3}, pushError{0}, configureError{0}, renderError{0}, renderCount{0};
inline std::atomic<bool> badWindowOrder{false};
inline std::atomic<bool> produceOutput{true}, recycleInput{false};
inline int32_t configuredPixelFormat = -1;
inline void Reset() {
    std::lock_guard<std::mutex> lock(mutex);
    for (auto codec : codecs) { delete codec; }
    for (auto window : windows) { delete window; }
    codecs.clear(); windows.clear(); pushed.clear(); flags.clear(); timestamps.clear(); payloads.clear();
    slots = 3; pushError = 0; configureError = 0; renderError = 0; renderCount = 0; badWindowOrder = false;
    produceOutput = true; recycleInput = false;
    configuredPixelFormat = -1;
}
inline OH_AVCodec* LastCodec() { std::lock_guard<std::mutex> lock(mutex); return codecs.back(); }
}
inline OH_AVCodec* OH_VideoDecoder_CreateByMime(const char*) {
    auto codec = new OH_AVCodec;
    std::lock_guard<std::mutex> lock(fake::mutex); fake::codecs.push_back(codec); return codec;
}
inline int OH_VideoDecoder_RegisterCallback(OH_AVCodec* c, OH_AVCodecCallback cb, void* user) { c->callbacks = cb; c->user = user; return 0; }
inline OH_AVFormat* OH_AVFormat_Create() { return new OH_AVFormat; }
inline void OH_AVFormat_Destroy(OH_AVFormat* f) { delete f; }
inline bool OH_AVFormat_GetIntValue(OH_AVFormat*, const char*, int32_t*) { return false; }
inline bool OH_AVFormat_SetIntValue(OH_AVFormat* f, const char* key, int32_t value) {
    if (std::string(key) == OH_MD_KEY_PIXEL_FORMAT) { f->pixelFormat = value; }
    return true;
}
inline int OH_VideoDecoder_Configure(OH_AVCodec*, OH_AVFormat* f) {
    fake::configuredPixelFormat = f->pixelFormat; return fake::configureError;
}
inline int OH_VideoDecoder_SetSurface(OH_AVCodec* c, OHNativeWindow* w) { c->window = w; return 0; }
inline int OH_VideoDecoder_Prepare(OH_AVCodec*) { return 0; }
inline int OH_VideoDecoder_Start(OH_AVCodec* c) {
    for (int i = 0; i < fake::slots; i++) { c->callbacks.onNeedInputBuffer(c, i, &c->buffers[i], c->user); }
    return 0;
}
inline int OH_VideoDecoder_Stop(OH_AVCodec* c) {
    // Synchronous callbacks during Stop must not wait on the lifecycle lock.
    c->callbacks.onNeedInputBuffer(c, 3, &c->buffers[3], c->user);
    c->callbacks.onNewOutputBuffer(c, 3, &c->buffers[3], c->user);
    c->stopped = true; return 0;
}
inline int OH_VideoDecoder_Destroy(OH_AVCodec*) { return 0; }
inline uint8_t* OH_AVBuffer_GetAddr(OH_AVBuffer* b) { return b->bytes.data(); }
inline int32_t OH_AVBuffer_GetCapacity(OH_AVBuffer* b) { return b->bytes.size(); }
inline int OH_AVBuffer_SetBufferAttr(OH_AVBuffer* b, OH_AVCodecBufferAttr* a) { b->attr = *a; return 0; }
inline int OH_AVBuffer_GetBufferAttr(OH_AVBuffer* b, OH_AVCodecBufferAttr* a) { *a = b->attr; return 0; }
inline int OH_VideoDecoder_PushInputBuffer(OH_AVCodec* c, uint32_t index) {
    if (fake::pushError != 0) { return fake::pushError; }
    const auto& attr = c->buffers[index].attr;
    { std::lock_guard<std::mutex> lock(fake::mutex); fake::pushed.push_back(index); fake::flags.push_back(attr.flags); fake::timestamps.push_back(attr.pts);
      fake::payloads.emplace_back(c->buffers[index].bytes.begin(), c->buffers[index].bytes.begin() + attr.size); }
    if (attr.flags & AVCODEC_BUFFER_FLAGS_CODEC_DATA) { c->hasConfiguration = true; }
    if (fake::produceOutput && c->hasConfiguration && attr.flags != AVCODEC_BUFFER_FLAGS_CODEC_DATA) { c->callbacks.onNewOutputBuffer(c, index, &c->buffers[index], c->user); }
    if (fake::recycleInput) { c->callbacks.onNeedInputBuffer(c, index, &c->buffers[index], c->user); }
    return 0;
}
inline int OH_VideoDecoder_RenderOutputBuffer(OH_AVCodec*, uint32_t) { fake::renderCount++; return fake::renderError; }
inline int OH_VideoDecoder_FreeOutputBuffer(OH_AVCodec*, uint32_t) { return 0; }
inline int OH_NativeWindow_CreateNativeWindowFromSurfaceId(uint64_t id, OHNativeWindow** out) {
    *out = new OHNativeWindow{id}; std::lock_guard<std::mutex> lock(fake::mutex); fake::windows.push_back(*out); return 0;
}
inline void OH_NativeWindow_DestroyNativeWindow(OHNativeWindow* w) {
    std::lock_guard<std::mutex> lock(fake::mutex);
    for (auto c : fake::codecs) { if (c->window == w && !c->stopped) { fake::badWindowOrder = true; } }
    w->destroyed = true;
}

using OH_AudioData_Callback_Result = int;
constexpr int AUDIOSTREAM_SUCCESS = 0, AUDIOSTREAM_TYPE_RENDERER = 0, AUDIOSTREAM_SAMPLE_S16LE = 0;
constexpr int AUDIOSTREAM_USAGE_MOVIE = 10;
constexpr int AUDIOSTREAM_ENCODING_TYPE_RAW = 0, AUDIO_DATA_CALLBACK_RESULT_VALID = 0, AUDIO_DATA_CALLBACK_RESULT_INVALID = -1;
struct OH_AudioRenderer;
using AudioWrite = int (*)(OH_AudioRenderer*, void*, void*, int32_t);
struct OH_AudioStreamBuilder { AudioWrite callback = nullptr; void* user = nullptr; };
struct OH_AudioRenderer { AudioWrite callback; void* user; };
inline int OH_AudioStreamBuilder_Create(OH_AudioStreamBuilder** b, int) { *b = new OH_AudioStreamBuilder; return 0; }
inline int OH_AudioStreamBuilder_Destroy(OH_AudioStreamBuilder* b) { delete b; return 0; }
inline int OH_AudioStreamBuilder_SetSamplingRate(OH_AudioStreamBuilder*, int) { return 0; }
inline int OH_AudioStreamBuilder_SetChannelCount(OH_AudioStreamBuilder*, int) { return 0; }
inline int OH_AudioStreamBuilder_SetSampleFormat(OH_AudioStreamBuilder*, int) { return 0; }
inline int OH_AudioStreamBuilder_SetEncodingType(OH_AudioStreamBuilder*, int) { return 0; }
inline int OH_AudioStreamBuilder_SetRendererWriteDataCallback(OH_AudioStreamBuilder* b, AudioWrite cb, void* u) { b->callback = cb; b->user = u; return 0; }
inline int OH_AudioStreamBuilder_SetRendererInfo(OH_AudioStreamBuilder*, int) { return 0; }
inline int OH_AudioStreamBuilder_GenerateRenderer(OH_AudioStreamBuilder* b, OH_AudioRenderer** r) { *r = new OH_AudioRenderer{b->callback, b->user}; return 0; }
inline int OH_AudioRenderer_Start(OH_AudioRenderer*) { return 0; }
inline int OH_AudioRenderer_SetVolume(OH_AudioRenderer*, float) { return 0; }
inline int OH_AudioRenderer_Stop(OH_AudioRenderer* r) {
    std::thread callback([r]() { int16_t pcm[2]; r->callback(r, r->user, pcm, sizeof(pcm)); });
    callback.join(); return 0;
}
inline int OH_AudioRenderer_Release(OH_AudioRenderer* r) { delete r; return 0; }
using opus_int32 = int32_t;
constexpr int OPUS_OK = 0;
struct OpusDecoder {};
inline OpusDecoder* opus_decoder_create(int, int, int* error) { *error = 0; return new OpusDecoder; }
inline void opus_decoder_destroy(OpusDecoder* d) { delete d; }
inline int opus_decode(OpusDecoder*, const uint8_t*, int32_t, int16_t*, int, int) { return 0; }
