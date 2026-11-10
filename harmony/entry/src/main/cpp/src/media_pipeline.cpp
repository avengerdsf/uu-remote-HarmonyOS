#include "media_pipeline.h"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <utility>

#include <hilog/log.h>
#if __has_include(<opus/opus.h>)
#include <opus/opus.h>
#else
#include <opus.h>
#endif

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3200
#define LOG_TAG "UUCoreMedia"

namespace {
constexpr size_t kMaxQueue = 12;
constexpr int32_t kOpusSampleRate = 48000;
constexpr int32_t kOpusChannels = 2;
constexpr int32_t kMaxOpusFrame = 5760;  // 120 ms at 48 kHz
constexpr int32_t kOpusPlcFrame = 960;   // 20 ms concealment per lost packet
constexpr uint16_t kMaxConcealment = 3;

bool H264IntraSlice(const uint8_t* data, size_t len) {
    size_t bit = 0;
    auto ue = [&]() -> int64_t {
        size_t zeros = 0;
        while (bit < len * 8 && ((data[bit / 8] >> (7 - bit % 8)) & 1) == 0) {
            bit++;
            if (++zeros > 31) { return -1; }
        }
        if (bit++ >= len * 8 || zeros > len * 8 - bit) { return -1; }
        uint32_t value = 0;
        for (size_t i = 0; i < zeros; i++, bit++) { value = (value << 1) | ((data[bit / 8] >> (7 - bit % 8)) & 1); }
        return (int64_t{1} << zeros) - 1 + value;
    };
    if (ue() < 0) { return false; }
    const auto sliceType = ue();
    return sliceType == 2 || sliceType == 7;
}

bool H264ImmediateRecovery(const uint8_t* data, size_t len) {
    while (len > 0 && data[len - 1] == 0) { len--; }
    std::vector<uint8_t> rbsp;
    for (size_t i = 0; i < len; i++) {
        if (i >= 2 && data[i] == 3 && data[i - 1] == 0 && data[i - 2] == 0) { continue; }
        rbsp.push_back(data[i]);
    }
    size_t offset = 0;
    while (offset < rbsp.size()) {
        size_t type = 0, size = 0;
        uint8_t value;
        do { if (offset == rbsp.size()) { return false; } value = rbsp[offset++]; type += value; } while (value == 255);
        do { if (offset == rbsp.size()) { return false; } value = rbsp[offset++]; size += value; } while (value == 255);
        if (size > rbsp.size() - offset) { return false; }
        // recovery_frame_cnt=0, exact_match_flag=1, changing_slice_group_idc=0.
        if (type == 6 && size > 0 && (rbsp[offset] & 0xD8) == 0xC0) { return true; }
        offset += size;
    }
    return false;
}

uint32_t FrameFlags(int32_t codec, const uint8_t* data, size_t len, bool& picture, bool& allIntra, int32_t& restart,
                    uint32_t& parameterMask) {
    uint32_t flags = AVCODEC_BUFFER_FLAGS_NONE;
    for (size_t i = 0; i + 3 < len; i++) {
        if (data[i] != 0 || data[i + 1] != 0 || data[i + 2] != 1) { continue; }
        const auto type = codec == 2 ? (data[i + 3] >> 1) & 63 : data[i + 3] & 31;
        const bool pictureNal = codec == 2 ? type <= 31 : type >= 1 && type <= 5;
        picture |= pictureNal;
        // Match viewer::desktop::is_key_frame: official hosts can answer PLI
        // with an intra slice or recovery-point SEI instead of an IDR (#136).
        const bool intra = type == 1 && H264IntraSlice(data + i + 4, len - i - 4);
        if (pictureNal && !(codec == 1 && type == 1 && intra)) { allIntra = false; }
        size_t end = i + 4;
        if (codec == 1 && type == 6) {
            while (end + 3 < len && !(data[end] == 0 && data[end + 1] == 0 && data[end + 2] == 1)) { end++; }
            if (end + 3 >= len) { end = len; }
        }
        const bool recovery = codec == 1 && type == 6 && H264ImmediateRecovery(data + i + 4, end - i - 4);
        const bool h264Recovery = type == 5 || intra || recovery;
        restart = std::max(restart, codec == 2 ? (type >= 16 && type <= 21 ? 3 : 0) :
            (type == 5 ? 3 : (recovery ? 2 : (intra ? 1 : 0))));
        if (codec == 2 ? type >= 16 && type <= 21 : h264Recovery) {
            flags |= AVCODEC_BUFFER_FLAGS_SYNC_FRAME;
        }
        if (codec == 2 ? type >= 32 && type <= 34 : type == 7 || type == 8) {
            flags |= AVCODEC_BUFFER_FLAGS_CODEC_DATA;
            parameterMask |= 1u << (codec == 2 ? type - 32 : type == 7 ? 1 : 2);
        }
    }
    return flags;
}
}  // namespace

MediaPipeline::DecoderCapabilities MediaPipeline::QueryDecoderCapabilities() {
    DecoderCapabilities caps{60, false, false, false, false, 1920, 1080};
#ifdef UU_HAS_AVCAPABILITY
    OH_AVCapability* avc = OH_AVCodec_GetCapabilityByCategory(OH_AVCODEC_MIMETYPE_VIDEO_AVC, false, HARDWARE);
    if (avc == nullptr) { avc = OH_AVCodec_GetCapability(OH_AVCODEC_MIMETYPE_VIDEO_AVC, false); }
    if (avc == nullptr) { return caps; }
    OH_AVCapability* hevc = OH_AVCodec_GetCapability(OH_AVCODEC_MIMETYPE_VIDEO_HEVC, false);
    caps.hevc = hevc != nullptr && OH_AVCapability_IsVideoSizeSupported(hevc, 1920, 1080);
    caps.hardware = OH_AVCapability_IsHardware(avc);
    for (auto size : {std::pair<int32_t, int32_t>{3840, 2160}, {2560, 1440}, {1920, 1080}, {1280, 720}}) {
        if (!OH_AVCapability_IsVideoSizeSupported(avc, size.first, size.second) ||
            (caps.hevc && !OH_AVCapability_IsVideoSizeSupported(hevc, size.first, size.second))) { continue; }
        OH_AVRange range{0, 0};
        if (OH_AVCapability_GetVideoFrameRateRangeForSize(avc, size.first, size.second, &range) != AV_ERR_OK || range.maxVal < 30) { continue; }
        int32_t ceiling = range.maxVal;
        if (caps.hevc) {
            if (OH_AVCapability_GetVideoFrameRateRangeForSize(hevc, size.first, size.second, &range) != AV_ERR_OK || range.maxVal < 30) { continue; }
            ceiling = std::min(ceiling, range.maxVal);
        }
        caps.maxWidth = size.first;
        caps.maxHeight = size.second;
        caps.maxFps = ceiling;
        caps.probed = true;
        break;
    }
#endif
    return caps;
}

MediaPipeline::MediaPipeline() {
    running_ = true;
    worker_ = std::thread([this]() { DecoderLoop(); });
}

MediaPipeline::~MediaPipeline() {
    Shutdown();
}

void MediaPipeline::Shutdown() {
    // Stop waits for audio callbacks, which also acquire mutex_.
    SetAudioMuted(true);
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!running_) {
            return;
        }
        running_ = false;
        queue_.clear();
        StopAudioLocked();
        StopDecoderLocked();
        if (window_ != nullptr) {
            OH_NativeWindow_DestroyNativeWindow(window_);
            window_ = nullptr;
            surfaceId_.clear();
        }
    }
    inputCv_.notify_all();
    if (worker_.joinable()) {
        worker_.join();
    }
}

int32_t MediaPipeline::SubmitVideo(int32_t codec, int32_t width, int32_t height, int64_t ptsUs,
                                   const uint8_t* data, size_t len) {
    if (data == nullptr || len == 0) {
        return -1;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    if (!running_) {
        return -1;
    }
    if (window_ == nullptr) {
        return -1;  // No Surface yet: do not claim a displayed first frame.
    }
    bool failed, stalled;
    {
        std::lock_guard<std::mutex> callbackLock(decoderCallbackMutex_);
        failed = decoderFailed_;
        stalled = decoder_ != nullptr && pictureInputsSinceOutput_ >= 8 &&
            std::chrono::steady_clock::now() - pendingOutputSince_ >= std::chrono::seconds(2);
    }
    if (failed || stalled || queue_.size() >= kMaxQueue) {
        if (stalled) { OH_LOG_WARN(LOG_APP, "Video output stalled; requesting keyframe recovery"); }
        stats_.dropped += queue_.size();
        stats_.resets++;
        StopDecoderLocked();
    }
    if (decoder_ != nullptr && decoderCodec_ != codec) { StopDecoderLocked(); }
    bool picture = false, allIntra = true;
    int32_t restart = 0;
    uint32_t parameterMask = 0;
    const uint32_t flags = FrameFlags(codec, data, len, picture, allIntra, restart, parameterMask);
    if (parameterCodec_ != codec) {
        for (auto& set : parameterSets_) { set.clear(); }
        parameterCodec_ = codec;
    }
    if (flags & AVCODEC_BUFFER_FLAGS_CODEC_DATA) { CacheParameterSets(codec, data, len); }
    const uint32_t requiredParameters = codec == 2 ? 7 : 6;
    const bool completeParameters = !parameterSets_[1].empty() && !parameterSets_[2].empty() &&
        (codec != 2 || !parameterSets_[0].empty());
    // Some hosts answer PLI with non-IDR I pictures. Keep the strict restart
    // preference, but bound that wait without admitting reference-dependent slices.
    const bool boundedIntra = codec == 1 && picture && allIntra &&
        std::chrono::steady_clock::now() - restartWaitSince_ >= std::chrono::milliseconds(1500);
    if (needsKeyFrame_ && (!completeParameters || (picture ? restart < 2 && !boundedIntra :
        !(flags & AVCODEC_BUFFER_FLAGS_CODEC_DATA)))) {
        stats_.dropped++;
        if (stats_.dropped % 120 == 1 || restart > 0) {
            OH_LOG_INFO(LOG_APP, "Video awaiting restart: codec=%{public}d picture=%{public}d restart=%{public}d parameters=%{public}d dropped=%{public}llu",
                codec, picture, restart, completeParameters, static_cast<unsigned long long>(stats_.dropped));
        }
        return -1;  // Ask the RTP reader for a new keyframe after a reset/drop.
    }
    if (decoder_ == nullptr || decoderCodec_ != codec) {
        StopDecoderLocked();
        StartDecoderLocked(codec, width > 0 ? width : 1920, height > 0 ? height : 1080);
        if (decoder_ != nullptr && (parameterMask & requiredParameters) != requiredParameters) {
            AccessUnit config{codec, width, height, ptsUs, AVCODEC_BUFFER_FLAGS_CODEC_DATA, false, {}};
            for (const auto& set : parameterSets_) { config.data.insert(config.data.end(), set.begin(), set.end()); }
            if (!config.data.empty()) {
                queue_.push_back(std::move(config));
                stats_.submitted++;
                stats_.configUnits++;
            }
        }
    }
    if (decoder_ == nullptr) { return -1; }
    if (flags != AVCODEC_BUFFER_FLAGS_NONE) {
        OH_LOG_INFO(LOG_APP, "Video restart input: codec=%{public}d flags=%{public}u picture=%{public}d restart=%{public}d bytes=%{public}zu", codec, flags, picture, restart, len);
    }
    AccessUnit unit;
    unit.codec = codec;
    unit.width = width > 0 ? width : 1920;
    unit.height = height > 0 ? height : 1080;
    unit.ptsUs = ptsUs;
    unit.flags = flags;
    unit.picture = picture;
    unit.data.assign(data, data + len);
    queue_.push_back(std::move(unit));
    stats_.submitted++;
    if (picture) { stats_.pictureUnits++; }
    if (flags & AVCODEC_BUFFER_FLAGS_CODEC_DATA) { stats_.configUnits++; }
    if (!picture && !(flags & AVCODEC_BUFFER_FLAGS_CODEC_DATA)) { stats_.otherUnits++; }
    if (flags & AVCODEC_BUFFER_FLAGS_SYNC_FRAME) { needsKeyFrame_ = false; }
    inputCv_.notify_all();
    return 0;
}

int32_t MediaPipeline::AttachSurface(const char* surfaceId, int32_t width, int32_t height) {
    if (surfaceId == nullptr || surfaceId[0] == '\0') {
        return -1;
    }
    uint64_t id = strtoull(surfaceId, nullptr, 10);
    if (id == 0) {
        return -1;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    if (!running_) { return -1; }
    if (surfaceId_ == surfaceId && window_ != nullptr) { return 0; }
    // Stop the codec while its old window is still valid.
    StopDecoderLocked();
    if (window_ != nullptr) {
        OH_NativeWindow_DestroyNativeWindow(window_);
        window_ = nullptr;
    }
    surfaceId_.clear();
    for (auto& set : parameterSets_) { set.clear(); }
    OHNativeWindow* created = nullptr;
    if (OH_NativeWindow_CreateNativeWindowFromSurfaceId(id, &created) != 0 || created == nullptr) {
        OH_LOG_ERROR(LOG_APP, "CreateNativeWindowFromSurfaceId failed");
        return -1;
    }
    window_ = created;
    surfaceId_ = surfaceId;
    { std::lock_guard<std::mutex> callbackLock(decoderCallbackMutex_); stats_ = {}; }
    OH_LOG_INFO(LOG_APP, "surface attached %{public}dx%{public}d", width, height);
    return 0;
}

int32_t MediaPipeline::DetachSurface(const char* surfaceId) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (surfaceId == nullptr || surfaceId_ != surfaceId) { return 0; }
    StopDecoderLocked();
    if (window_ != nullptr) {
        OH_NativeWindow_DestroyNativeWindow(window_);
        window_ = nullptr;
    }
    surfaceId_.clear();
    for (auto& set : parameterSets_) { set.clear(); }
    return 0;
}

void MediaPipeline::CacheParameterSets(int32_t codec, const uint8_t* data, size_t len) {
    for (size_t i = 0; i + 3 < len; i++) {
        if (data[i] != 0 || data[i + 1] != 0 || data[i + 2] != 1) { continue; }
        const auto type = codec == 2 ? (data[i + 3] >> 1) & 63 : data[i + 3] & 31;
        const int slot = codec == 2 ? (type >= 32 && type <= 34 ? type - 32 : -1) :
            (type == 7 ? 1 : (type == 8 ? 2 : -1));
        if (slot < 0) { continue; }
        size_t end = i + 4;
        while (end + 3 < len && !(data[end] == 0 && data[end + 1] == 0 && data[end + 2] == 1)) { end++; }
        if (end + 3 >= len) { end = len; }
        while (end > i + 4 && data[end - 1] == 0) { end--; }
        if (end - i > 65536) { continue; }
        auto& set = parameterSets_[slot];
        set.assign({0, 0, 0, 1});
        set.insert(set.end(), data + i + 3, data + end);
    }
}

void MediaPipeline::StartDecoderLocked(int32_t codec, int32_t width, int32_t height) {
    if (window_ == nullptr) {
        return;
    }
    const char* mime = codec == 2 ? OH_AVCODEC_MIMETYPE_VIDEO_HEVC : OH_AVCODEC_MIMETYPE_VIDEO_AVC;
    decoder_ = OH_VideoDecoder_CreateByMime(mime);
    if (decoder_ == nullptr) {
        OH_LOG_ERROR(LOG_APP, "OH_VideoDecoder_CreateByMime failed");
        return;
    }
    decoderCodec_ = codec;
    decoderWidth_ = width;
    decoderHeight_ = height;
    {
        std::lock_guard<std::mutex> lock(decoderCallbackMutex_);
        callbackDecoder_ = decoder_;
        pendingOutputSince_ = {};
        pictureInputsSinceOutput_ = 0;
    }
    OH_AVCodecCallback callback{};
    callback.onError = &MediaPipeline::OnDecoderError;
    callback.onStreamChanged = &MediaPipeline::OnStreamChanged;
    callback.onNeedInputBuffer = &MediaPipeline::OnNeedInputBuffer;
    callback.onNewOutputBuffer = &MediaPipeline::OnNewOutputBuffer;
    if (OH_VideoDecoder_RegisterCallback(decoder_, callback, this) != AV_ERR_OK) {
        OH_LOG_ERROR(LOG_APP, "RegisterCallback failed");
        StopDecoderLocked();
        return;
    }
    if (!ConfigureDecoder(decoder_, width, height)) {
        StopDecoderLocked();
        return;
    }
    if (OH_VideoDecoder_SetSurface(decoder_, window_) != AV_ERR_OK) {
        OH_LOG_ERROR(LOG_APP, "SetSurface failed");
        StopDecoderLocked();
        return;
    }
    if (OH_VideoDecoder_Prepare(decoder_) != AV_ERR_OK ||
        OH_VideoDecoder_Start(decoder_) != AV_ERR_OK) {
        OH_LOG_ERROR(LOG_APP, "Prepare/Start failed");
        StopDecoderLocked();
        return;
    }
}

bool MediaPipeline::ConfigureDecoder(OH_AVCodec* codec, int32_t width, int32_t height) {
    OH_AVFormat* format = OH_AVFormat_Create();
    if (format == nullptr) {
        return false;
    }
    OH_AVFormat_SetIntValue(format, OH_MD_KEY_WIDTH, width);
    OH_AVFormat_SetIntValue(format, OH_MD_KEY_HEIGHT, height);
    OH_AVFormat_SetIntValue(format, OH_MD_KEY_PIXEL_FORMAT, AV_PIXEL_FORMAT_NV12);
    OH_AVFormat_SetIntValue(format, OH_MD_KEY_VIDEO_ENABLE_LOW_LATENCY, 1);
    OH_LOG_INFO(LOG_APP, "Video decoder configured: codec=%{public}d width=%{public}d height=%{public}d", decoderCodec_, width, height);
    const auto result = OH_VideoDecoder_Configure(codec, format);
    OH_AVFormat_Destroy(format);
    if (result != AV_ERR_OK) {
        std::lock_guard<std::mutex> callbackLock(decoderCallbackMutex_);
        stats_.lastError = result;
    }
    return result == AV_ERR_OK;
}

void MediaPipeline::StopDecoderLocked() {
    {
        std::lock_guard<std::mutex> lock(decoderCallbackMutex_);
        callbackDecoder_ = nullptr;
        inputs_.clear();
        outputs_.clear();
        decoderFailed_ = false;
        pictureInputsSinceOutput_ = 0;
    }
    queue_.clear();
    needsKeyFrame_ = true;
    restartWaitSince_ = std::chrono::steady_clock::now();
    inputPtsValid_ = false;
    if (decoder_ != nullptr) {
        OH_VideoDecoder_Stop(decoder_);
        OH_VideoDecoder_Destroy(decoder_);
        decoder_ = nullptr;
    }
}

void MediaPipeline::DecoderLoop() {
    std::unique_lock<std::mutex> lock(mutex_);
    while (running_) {
        inputCv_.wait_for(lock, std::chrono::milliseconds(50), [this]() {
            std::lock_guard<std::mutex> callbackLock(decoderCallbackMutex_);
            return !running_ || !outputs_.empty() || (!queue_.empty() && !inputs_.empty() && decoder_ != nullptr && !decoderFailed_);
        });
        if (!running_) {
            break;
        }
        if (decoder_ == nullptr) {
            continue;
        }
        DecoderInput input;
        std::deque<uint32_t> outputs;
        {
            std::lock_guard<std::mutex> callbackLock(decoderCallbackMutex_);
            outputs.swap(outputs_);
        }
        for (auto index : outputs) {
            const auto result = OH_VideoDecoder_RenderOutputBuffer(decoder_, index);
            if (result == AV_ERR_OK) { stats_.rendered++; }
            else {
                {
                    std::lock_guard<std::mutex> callbackLock(decoderCallbackMutex_);
                    stats_.lastError = result;
                    stats_.renderFailed++;
                    decoderFailed_ = true;
                }
                OH_VideoDecoder_FreeOutputBuffer(decoder_, index);
            }
        }
        if (queue_.empty()) { continue; }
        {
            std::lock_guard<std::mutex> callbackLock(decoderCallbackMutex_);
            if (inputs_.empty() || decoderFailed_) { continue; }
            input = inputs_.front();
            inputs_.pop_front();
        }
        AccessUnit unit = std::move(queue_.front());
        queue_.pop_front();
        uint32_t index = input.index;
        OH_AVBuffer* buffer = input.buffer;
        if (buffer == nullptr) {
            stats_.dropped++;
            std::lock_guard<std::mutex> callbackLock(decoderCallbackMutex_);
            decoderFailed_ = true;
            continue;
        }
        uint8_t* addr = OH_AVBuffer_GetAddr(buffer);
        int32_t capacity = OH_AVBuffer_GetCapacity(buffer);
        if (addr == nullptr || capacity <= 0 || static_cast<size_t>(capacity) < unit.data.size()) {
            stats_.dropped++;
            std::lock_guard<std::mutex> callbackLock(decoderCallbackMutex_);
            decoderFailed_ = true;
            continue;
        }
        std::memcpy(addr, unit.data.data(), unit.data.size());
        OH_AVCodecBufferAttr attr{};
        attr.pts = unit.ptsUs;
        attr.size = static_cast<int32_t>(unit.data.size());
        attr.offset = 0;
        attr.flags = unit.flags;
        auto result = OH_AVBuffer_SetBufferAttr(buffer, &attr);
        if (result == AV_ERR_OK) {
            // Count before Push: the platform may invoke output synchronously.
            if (unit.picture) {
                std::lock_guard<std::mutex> callbackLock(decoderCallbackMutex_);
                if (pictureInputsSinceOutput_ == 0) { pendingOutputSince_ = std::chrono::steady_clock::now(); }
                pictureInputsSinceOutput_++;
            }
            result = OH_VideoDecoder_PushInputBuffer(decoder_, index);
        }
        if (result != AV_ERR_OK) {
            stats_.dropped++;
            stats_.pushFailed++;
            std::lock_guard<std::mutex> callbackLock(decoderCallbackMutex_);
            stats_.lastError = result;
            decoderFailed_ = true;
            OH_LOG_ERROR(LOG_APP, "Video input submission failed: %{public}d", result);
        } else {
            if (unit.picture && inputPtsValid_ && unit.ptsUs == stats_.lastInputPts) {
                OH_LOG_WARN(LOG_APP, "Repeated video picture timestamp");
            }
            if (inputPtsValid_ && unit.ptsUs < stats_.lastInputPts) { stats_.ptsRegressions++; }
            stats_.lastInputPts = unit.ptsUs;
            inputPtsValid_ = true;
            stats_.pushed++;
        }
    }
}

void MediaPipeline::OnDecoderError(OH_AVCodec* codec, int32_t error, void* userData) {
    auto* self = static_cast<MediaPipeline*>(userData);
    if (self == nullptr) { return; }
    std::lock_guard<std::mutex> lock(self->decoderCallbackMutex_);
    if (codec != self->callbackDecoder_) { return; }
    self->stats_.lastError = error;
    self->decoderFailed_ = true;
    OH_LOG_ERROR(LOG_APP, "Video decoder error: %{public}d", error);
}

void MediaPipeline::OnStreamChanged(OH_AVCodec* codec, OH_AVFormat* format, void* userData) {
    auto* self = static_cast<MediaPipeline*>(userData);
    if (self == nullptr || format == nullptr) { return; }
    std::lock_guard<std::mutex> lock(self->decoderCallbackMutex_);
    if (codec != self->callbackDecoder_) { return; }
    int32_t width = 0, height = 0, pixel = 0;
    OH_AVFormat_GetIntValue(format, OH_MD_KEY_WIDTH, &width);
    OH_AVFormat_GetIntValue(format, OH_MD_KEY_HEIGHT, &height);
    OH_AVFormat_GetIntValue(format, OH_MD_KEY_PIXEL_FORMAT, &pixel);
    OH_LOG_INFO(LOG_APP, "Video output format: width=%{public}d height=%{public}d pixel=%{public}d", width, height, pixel);
}

void MediaPipeline::OnNeedInputBuffer(OH_AVCodec* codec, uint32_t index, OH_AVBuffer* buffer,
                                      void* userData) {
    auto* self = static_cast<MediaPipeline*>(userData);
    if (self == nullptr) {
        return;
    }
    std::lock_guard<std::mutex> lock(self->decoderCallbackMutex_);
    if (codec != self->callbackDecoder_) {
        return;
    }
    self->stats_.inputCallbacks++;
    self->inputs_.push_back({index, buffer});
    self->inputCv_.notify_all();
}

void MediaPipeline::OnNewOutputBuffer(OH_AVCodec* codec, uint32_t index, OH_AVBuffer* buffer,
                                      void* userData) {
    auto* self = static_cast<MediaPipeline*>(userData);
    if (self == nullptr) {
        return;
    }
    std::lock_guard<std::mutex> lock(self->decoderCallbackMutex_);
    if (codec != self->callbackDecoder_) { return; }
    self->pictureInputsSinceOutput_ = 0;
    self->stats_.outputCallbacks++;
    self->stats_.decoded++;
    OH_AVCodecBufferAttr attr{};
    if (buffer != nullptr && OH_AVBuffer_GetBufferAttr(buffer, &attr) == AV_ERR_OK) {
        self->stats_.lastOutputPts = attr.pts;
    }
    self->outputs_.push_back(index);
    self->inputCv_.notify_all();
}

int32_t MediaPipeline::SubmitAudio(int32_t sampleRate, int32_t channels, const int16_t* pcm,
                                   size_t samples) {
    if (pcm == nullptr || samples == 0) {
        return -1;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    if (!running_ || audioMuted_) {
        return -1;
    }
    if (audioRenderer_ == nullptr) {
        StartAudioLocked(sampleRate > 0 ? sampleRate : 48000, channels > 0 ? channels : 2);
    }
    return QueueAudioLocked(pcm, samples) ? 0 : -1;
}

int32_t MediaPipeline::SubmitAudioPacket(uint16_t seq, int64_t ptsUs, const uint8_t* data,
                                         size_t len) {
    (void)ptsUs;
    if (data == nullptr || len == 0 || len > 8192) {
        return -1;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    if (!running_ || audioMuted_ || !EnsureOpusLocked()) {
        return -1;
    }
    if (audioRenderer_ == nullptr) {
        StartAudioLocked(kOpusSampleRate, kOpusChannels);
        if (audioRenderer_ == nullptr) {
            return -1;
        }
    }
    if (audioSequenceValid_) {
        const uint16_t delta = static_cast<uint16_t>(seq - audioLastSeq_);
        if (delta > 1 && delta < 0x8000) {
            const uint16_t missing = std::min<uint16_t>(static_cast<uint16_t>(delta - 1),
                                                        kMaxConcealment);
            for (uint16_t i = 0; i < missing; i++) {
                int16_t pcm[kOpusPlcFrame * kOpusChannels];
                const int decoded = opus_decode(opus_, nullptr, 0, pcm, kOpusPlcFrame, 0);
                if (decoded <= 0 || !QueueAudioLocked(pcm, static_cast<size_t>(decoded) * kOpusChannels)) {
                    break;
                }
                audioLost_++;
            }
        }
    }
    int16_t pcm[kMaxOpusFrame * kOpusChannels];
    const int decoded = opus_decode(opus_, data, static_cast<opus_int32>(len), pcm,
                                    kMaxOpusFrame, 0);
    if (decoded <= 0) {
        OH_LOG_WARN(LOG_APP, "Opus decode failed: %{public}d", decoded);
        return -1;
    }
    if (!QueueAudioLocked(pcm, static_cast<size_t>(decoded) * kOpusChannels)) {
        return -1;
    }
    audioSequenceValid_ = true;
    audioLastSeq_ = seq;
    audioDecoded_++;
    return 0;
}

int32_t MediaPipeline::SetAudioMuted(bool muted) {
    OH_AudioRenderer* renderer = nullptr;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!running_) {
            return -1;
        }
        if (audioMuted_ == muted) {
            return 0;
        }
        audioMuted_ = muted;
        if (muted) {
            // Detach under the lock, then stop outside it: OHAudio_Stop waits for
            // the write callback, which itself needs mutex_.
            renderer = audioRenderer_;
            audioRenderer_ = nullptr;
            if (opus_ != nullptr) {
                opus_decoder_destroy(opus_);
                opus_ = nullptr;
            }
            audioSequenceValid_ = false;
            audio_.clear();
        }
    }
    if (renderer != nullptr) {
        OH_AudioRenderer_Stop(renderer);
        OH_AudioRenderer_Release(renderer);
    }
    return 0;
}

bool MediaPipeline::EnsureOpusLocked() {
    if (opus_ != nullptr) {
        return true;
    }
    int error = OPUS_OK;
    opus_ = opus_decoder_create(kOpusSampleRate, kOpusChannels, &error);
    if (opus_ == nullptr || error != OPUS_OK) {
        OH_LOG_ERROR(LOG_APP, "opus_decoder_create failed: %{public}d", error);
        opus_ = nullptr;
        return false;
    }
    audioSequenceValid_ = false;
    audioLastSeq_ = 0;
    audioDecoded_ = 0;
    audioLost_ = 0;
    return true;
}

bool MediaPipeline::QueueAudioLocked(const int16_t* pcm, size_t samples) {
    if (pcm == nullptr || samples == 0) {
        return false;
    }
    const size_t maxSamples = audioCapacitySamples_ * static_cast<size_t>(std::max(audioChannels_, 1));
    const size_t append = std::min(samples, maxSamples);
    if (audio_.size() + append > maxSamples) {
        const size_t drop = audio_.size() + append - maxSamples;
        audio_.erase(audio_.begin(), audio_.begin() + static_cast<std::ptrdiff_t>(drop));
    }
    audio_.insert(audio_.end(), pcm, pcm + append);
    return append == samples;
}

int32_t MediaPipeline::SetAudioVolume(float volume) {
    if (!(volume >= 0.0f && volume <= 1.0f)) { return -1; }
    std::lock_guard<std::mutex> lock(mutex_);
    if (audioRenderer_ != nullptr && OH_AudioRenderer_SetVolume(audioRenderer_, volume) != AUDIOSTREAM_SUCCESS) {
        return -1;
    }
    audioVolume_ = volume;
    return 0;
}

void MediaPipeline::StartAudioLocked(int32_t sampleRate, int32_t channels) {
    OH_AudioStreamBuilder* builder = nullptr;
    if (OH_AudioStreamBuilder_Create(&builder, AUDIOSTREAM_TYPE_RENDERER) != AUDIOSTREAM_SUCCESS) {
        return;
    }
    OH_AudioStreamBuilder_SetSamplingRate(builder, sampleRate);
    OH_AudioStreamBuilder_SetChannelCount(builder, channels);
    OH_AudioStreamBuilder_SetSampleFormat(builder, AUDIOSTREAM_SAMPLE_S16LE);
    OH_AudioStreamBuilder_SetEncodingType(builder, AUDIOSTREAM_ENCODING_TYPE_RAW);
    OH_AudioStreamBuilder_SetRendererInfo(builder, AUDIOSTREAM_USAGE_MOVIE);
    OH_AudioStreamBuilder_SetRendererWriteDataCallback(builder, &MediaPipeline::OnAudioWrite, this);
    OH_AudioRenderer* renderer = nullptr;
    if (OH_AudioStreamBuilder_GenerateRenderer(builder, &renderer) != AUDIOSTREAM_SUCCESS) {
        OH_AudioStreamBuilder_Destroy(builder);
        return;
    }
    OH_AudioStreamBuilder_Destroy(builder);
    if (OH_AudioRenderer_SetVolume(renderer, audioVolume_) != AUDIOSTREAM_SUCCESS ||
        OH_AudioRenderer_Start(renderer) != AUDIOSTREAM_SUCCESS) {
        OH_AudioRenderer_Release(renderer);
        return;
    }
    audioRenderer_ = renderer;
    audioSampleRate_ = sampleRate;
    audioChannels_ = channels;
    audioCapacitySamples_ = static_cast<size_t>(sampleRate);  // ~1 second
}

void MediaPipeline::StopAudioLocked() {
    if (audioRenderer_ != nullptr) {
        OH_AudioRenderer_Stop(audioRenderer_);
        OH_AudioRenderer_Release(audioRenderer_);
        audioRenderer_ = nullptr;
    }
    if (opus_ != nullptr) {
        opus_decoder_destroy(opus_);
        opus_ = nullptr;
    }
    audioSequenceValid_ = false;
    audio_.clear();
}

OH_AudioData_Callback_Result MediaPipeline::OnAudioWrite(OH_AudioRenderer* renderer, void* userData,
                                                          void* audioData, int32_t audioDataSize) {
    (void)renderer;
    auto* self = static_cast<MediaPipeline*>(userData);
    if (self == nullptr || audioData == nullptr || audioDataSize <= 0) {
        return AUDIO_DATA_CALLBACK_RESULT_INVALID;
    }
    std::lock_guard<std::mutex> lock(self->mutex_);
    const size_t wanted = static_cast<size_t>(audioDataSize) / sizeof(int16_t);
    auto* out = static_cast<int16_t*>(audioData);
    if (self->audioMuted_) {
        std::fill(out, out + wanted, 0);
        return AUDIO_DATA_CALLBACK_RESULT_VALID;
    }
    const size_t available = std::min(wanted, self->audio_.size());
    for (size_t i = 0; i < available; i++) {
        out[i] = self->audio_.front();
        self->audio_.pop_front();
    }
    if (available < wanted) {
        std::fill(out + available, out + wanted, 0);
    }
    return AUDIO_DATA_CALLBACK_RESULT_VALID;
}

MediaPipeline::VideoStats MediaPipeline::Stats() const {
    std::lock_guard<std::mutex> lock(mutex_);
    std::lock_guard<std::mutex> callbackLock(decoderCallbackMutex_);
    auto result = stats_;
    result.pendingInputs = inputs_.size();
    result.queuedUnits = queue_.size();
    return result;
}
