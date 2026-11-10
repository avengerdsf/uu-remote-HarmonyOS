#ifndef UU_MEDIA_PIPELINE_H
#define UU_MEDIA_PIPELINE_H

#include <cstdint>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <thread>
#include <string>
#include <vector>

#if __has_include(<multimedia/player_framework/native_avcodec_videodecoder.h>)
#include <multimedia/player_framework/native_avcodec_base.h>
#include <multimedia/player_framework/native_avcodec_videodecoder.h>
#include <multimedia/player_framework/native_avbuffer.h>
#else
#include <native_avcodec_base.h>
#include <native_avcodec_videodecoder.h>
#include <native_avbuffer.h>
#endif
#if __has_include(<multimedia/player_framework/native_avcapability.h>)
#include <multimedia/player_framework/native_avcapability.h>
#define UU_HAS_AVCAPABILITY 1
#elif __has_include(<native_avcapability.h>)
#include <native_avcapability.h>
#define UU_HAS_AVCAPABILITY 1
#endif
#include <native_window/external_window.h>
#if __has_include(<ohaudio/native_audiostream_base.h>)
#include <ohaudio/native_audiostream_base.h>
#include <ohaudio/native_audiostreambuilder.h>
#include <ohaudio/native_audiorenderer.h>
#else
#include <native_audiostream_base.h>
#include <native_audiostreambuilder.h>
#include <native_audiorenderer.h>
#endif

struct AccessUnit {
    int32_t codec;  // 1 = H.264, 2 = H.265
    int32_t width;
    int32_t height;
    int64_t ptsUs;
    uint32_t flags;
    bool picture;
    std::vector<uint8_t> data;
};

struct OpusDecoder;

class MediaPipeline {
public:
    MediaPipeline();
    ~MediaPipeline();

    int32_t SubmitVideo(int32_t codec, int32_t width, int32_t height, int64_t ptsUs,
                        const uint8_t* data, size_t len);
    int32_t SubmitAudio(int32_t sampleRate, int32_t channels, const int16_t* pcm, size_t samples);
    int32_t SubmitAudioPacket(uint16_t seq, int64_t ptsUs, const uint8_t* data, size_t len);
    /* Mute drops queued PCM and stops OHAudio; unmute lets the next packet restart it. */
    int32_t SetAudioMuted(bool muted);
    int32_t SetAudioVolume(float volume);
    int32_t AttachSurface(const char* surfaceId, int32_t width, int32_t height);
    int32_t DetachSurface(const char* surfaceId);
    void Shutdown();

    /// Queries the platform video decoder without opening a session. The
    /// public AVCodec capability API exposes frame-rate ranges but not chroma
    /// sampling, so `chroma444` stays false until a real device proves it.
    struct DecoderCapabilities {
        int32_t maxFps;
        bool chroma444;
        bool hardware;
        bool probed;
        bool hevc;
        int32_t maxWidth;
        int32_t maxHeight;
    };
    static DecoderCapabilities QueryDecoderCapabilities();

    struct VideoStats {
        uint64_t submitted;
        uint64_t decoded;
        uint64_t rendered;
        uint64_t dropped;
        uint64_t pushed;
        uint64_t pushFailed;
        uint64_t inputCallbacks;
        uint64_t outputCallbacks;
        uint64_t resets;
        uint64_t pictureUnits;
        uint64_t configUnits;
        uint64_t otherUnits;
        uint64_t ptsRegressions;
        uint64_t renderFailed;
        int64_t lastInputPts;
        int64_t lastOutputPts;
        int32_t lastError;
        size_t pendingInputs;
        size_t queuedUnits;
    };
    VideoStats Stats() const;

private:
    void StartDecoderLocked(int32_t codec, int32_t width, int32_t height);
    void StopDecoderLocked();
    void DecoderLoop();
    bool ConfigureDecoder(OH_AVCodec* codec, int32_t width, int32_t height);
    void CacheParameterSets(int32_t codec, const uint8_t* data, size_t len);
    static void OnStreamChanged(OH_AVCodec* codec, OH_AVFormat* format, void* userData);
    static void OnDecoderError(OH_AVCodec* codec, int32_t error, void* userData);
    static void OnNeedInputBuffer(OH_AVCodec* codec, uint32_t index, OH_AVBuffer* buffer, void* userData);
    static void OnNewOutputBuffer(OH_AVCodec* codec, uint32_t index, OH_AVBuffer* buffer, void* userData);

    // Audio
    void StartAudioLocked(int32_t sampleRate, int32_t channels);
    void StopAudioLocked();
    bool QueueAudioLocked(const int16_t* pcm, size_t samples);
    bool EnsureOpusLocked();
    void DecodeOpusLocked(uint16_t seq, const uint8_t* data, size_t len);
    static OH_AudioData_Callback_Result OnAudioWrite(
        OH_AudioRenderer* renderer, void* userData, void* audioData, int32_t audioDataSize);

    mutable std::mutex mutex_;
    std::condition_variable inputCv_;
    std::thread worker_;
    bool running_ = false;

    OHNativeWindow* window_ = nullptr;
    std::string surfaceId_;
    OH_AVCodec* decoder_ = nullptr;
    int32_t decoderCodec_ = 0;
    int32_t decoderWidth_ = 0;
    int32_t decoderHeight_ = 0;
    struct DecoderInput { uint32_t index; OH_AVBuffer* buffer; };
    // Codec callbacks must not wait on the lifecycle lock during Stop/Destroy.
    mutable std::mutex decoderCallbackMutex_;
    OH_AVCodec* callbackDecoder_ = nullptr;
    bool decoderFailed_ = false;
    std::chrono::steady_clock::time_point pendingOutputSince_{};
    uint32_t pictureInputsSinceOutput_ = 0;
    bool needsKeyFrame_ = true;
    std::chrono::steady_clock::time_point restartWaitSince_{};
    int32_t parameterCodec_ = 0;
    std::vector<uint8_t> parameterSets_[3];
    bool inputPtsValid_ = false;
    std::deque<DecoderInput> inputs_;
    std::deque<uint32_t> outputs_;
    std::deque<AccessUnit> queue_;
    VideoStats stats_{};

    // Audio ring buffer of interleaved S16 samples.
    OH_AudioRenderer* audioRenderer_ = nullptr;
    int32_t audioSampleRate_ = 48000;
    int32_t audioChannels_ = 2;
    std::deque<int16_t> audio_;
    size_t audioCapacitySamples_ = 48000;
    OpusDecoder* opus_ = nullptr;
    bool audioSequenceValid_ = false;
    bool audioMuted_ = false;
    float audioVolume_ = 1.0f;
    uint16_t audioLastSeq_ = 0;
    uint64_t audioDecoded_ = 0;
    uint64_t audioLost_ = 0;
};

#endif
