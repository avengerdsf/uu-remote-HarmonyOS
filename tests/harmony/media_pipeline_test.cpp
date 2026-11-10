#include "media_pipeline.h"
#include <cassert>
#include <chrono>
#include <iostream>

namespace {
const uint8_t key[] = {0,0,0,1,0x67,1,0,0,0,1,0x68,1,0,0,0,1,0x65,1};
const uint8_t delta[] = {0,0,0,1,0x61,1};
int Submit(MediaPipeline& p, bool sync = false) {
    return p.SubmitVideo(1, 1920, 1080, 1000, sync ? key : delta, sync ? sizeof(key) : sizeof(delta));
}
template<class Predicate> void Wait(Predicate ready) {
    const auto end = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (!ready() && std::chrono::steady_clock::now() < end) { std::this_thread::sleep_for(std::chrono::milliseconds(1)); }
    assert(ready());
}
void InputSlotsAndSynchronousCallbacks() {
    MediaPipeline p;
    assert(p.AttachSurface("100", 1920, 1080) == 0);
    assert(Submit(p, true) == 0); assert(Submit(p) == 0); assert(Submit(p) == 0);
    Wait([&]() { return p.Stats().rendered == 3; });
    assert(p.Stats().inputCallbacks == 3 && p.Stats().pushed == 3);
    assert((fake::pushed == std::vector<uint32_t>{0,1,2}));
    assert(fake::flags[0] == (AVCODEC_BUFFER_FLAGS_SYNC_FRAME | AVCODEC_BUFFER_FLAGS_CODEC_DATA));
    assert(fake::flags[1] == AVCODEC_BUFFER_FLAGS_NONE);
    assert(p.Stats().pictureUnits == 3 && p.Stats().configUnits == 1 && p.Stats().otherUnits == 0);
    assert(p.Stats().lastInputPts == 1000 && p.Stats().lastOutputPts == 1000);
    assert(p.AttachSurface("100", 1920, 1080) == 0);
    assert(p.Stats().rendered == 3); // Same Surface is idempotent.
}
void PushFailureAndKeyframeRecovery() {
    MediaPipeline p;
    p.AttachSurface("100", 1920, 1080);
    fake::pushError = -7;
    assert(Submit(p, true) == 0);
    Wait([&]() { return p.Stats().pushFailed == 1; });
    assert(p.Stats().lastError == -7 && p.Stats().rendered == 0);
    auto old = fake::LastCodec();
    assert(Submit(p) == -1);
    fake::pushError = 0;
    assert(Submit(p, true) == 0);
    old->callbacks.onNeedInputBuffer(old, 3, &old->buffers[3], old->user);
    Wait([&]() { return p.Stats().rendered == 1; });
    assert(p.Stats().resets == 1 && p.Stats().inputCallbacks == 6);
}
void SurfaceGenerationAndReleaseOrder() {
    MediaPipeline p;
    p.AttachSurface("100", 1920, 1080); Submit(p, true);
    Wait([&]() { return p.Stats().rendered == 1; });
    auto old = fake::LastCodec();
    p.AttachSurface("200", 1920, 1080);
    p.DetachSurface("100");
    old->callbacks.onNewOutputBuffer(old, 3, &old->buffers[3], old->user);
    assert(p.Stats().outputCallbacks == 0);
    assert(Submit(p, true) == 0);
    Wait([&]() { return p.Stats().rendered == 1; });
    assert(!fake::badWindowOrder);
    p.DetachSurface("200");
    assert(Submit(p, true) == -1);
}
void OverflowIsBoundedAndRequestsRecovery() {
    MediaPipeline p; fake::slots = 0;
    p.AttachSurface("100", 1920, 1080); assert(Submit(p, true) == 0);
    for (int i = 0; i < 11; i++) { assert(Submit(p) == 0); }
    assert(p.Stats().queuedUnits == 12);
    assert(Submit(p) == -1);
    assert(p.Stats().resets == 1 && p.Stats().queuedUnits == 0);
    fake::slots = 3; assert(Submit(p, true) == 0);
    Wait([&]() { return p.Stats().rendered == 1; });
}
void DecoderErrorAndConfigureFailure() {
    MediaPipeline p;
    p.AttachSurface("100", 1920, 1080); fake::configureError = -8;
    assert(Submit(p, true) == -1 && p.Stats().submitted == 0);
    assert(p.Stats().lastError == -8);
    fake::configureError = 0; assert(Submit(p, true) == 0);
    Wait([&]() { return p.Stats().rendered == 1; });
    auto c = fake::LastCodec(); c->callbacks.onError(c, -9, c->user);
    assert(p.Stats().lastError == -9); assert(Submit(p) == -1);
    assert(Submit(p, true) == 0);
    Wait([&]() { return p.Stats().rendered == 2; });
}
void AudioShutdownDoesNotBlockCallback() {
    MediaPipeline p;
    p.AttachSurface("100", 1920, 1080); Submit(p, true);
    Wait([&]() { return p.Stats().rendered == 1; });
    int16_t pcm[2]{}; assert(p.SubmitAudio(48000, 2, pcm, 2) == 0);
    p.Shutdown();
    assert(fake::windows[0]->destroyed && !fake::badWindowOrder);
    assert(Submit(p, true) == -1); p.Shutdown();
}
void ZeroTimestampIsPreserved() {
    MediaPipeline p;
    p.AttachSurface("100", 1920, 1080);
    assert(p.SubmitVideo(1, 1920, 1080, 0, key, sizeof(key)) == 0);
    Wait([&]() { return p.Stats().rendered == 1; });
    assert(fake::timestamps[0] == 0);
}
void RenderFailureRequestsKeyframeRecovery() {
    MediaPipeline p;
    p.AttachSurface("100", 1920, 1080); fake::renderError = -10;
    assert(Submit(p, true) == 0);
    Wait([&]() { return p.Stats().lastError == -10; });
    assert(p.Stats().renderFailed == 1);
    assert(p.Stats().rendered == 0);
    assert(Submit(p) == -1);
    fake::renderError = 0;
    assert(Submit(p, true) == 0);
    Wait([&]() { return p.Stats().rendered == 1; });
    assert(p.Stats().resets == 1);
}
void SilentOutputStallRequestsKeyframeRecovery() {
    MediaPipeline p; fake::recycleInput = true;
    p.AttachSurface("100", 1920, 1080); assert(Submit(p, true) == 0);
    Wait([&]() { return p.Stats().rendered == 1; });
    fake::produceOutput = false;
    bool requested = false;
    const auto end = std::chrono::steady_clock::now() + std::chrono::seconds(3);
    while (std::chrono::steady_clock::now() < end) {
        if (Submit(p) == -1) { requested = true; break; }
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    const auto stalled = p.Stats();
    fake::produceOutput = true;
    if (requested) {
        assert(Submit(p) == -1);
        assert(Submit(p, true) == 0);
        Wait([&]() { return p.Stats().rendered == 2; });
    }
    const auto recovered = p.Stats();
    p.Shutdown();
    assert(stalled.pushFailed == 0 && stalled.lastError == 0);
    assert(stalled.pushed > 8 && stalled.inputCallbacks > 8 && stalled.rendered == 1);
    assert(requested && "successful input with silent output must request a new keyframe");
    assert(stalled.resets == 1 && recovered.rendered == 2);
}
void IdleSurfaceDoesNotTriggerDecoderRecovery() {
    MediaPipeline p; fake::recycleInput = true;
    p.AttachSurface("100", 1920, 1080); assert(Submit(p, true) == 0);
    Wait([&]() { return p.Stats().rendered == 1; });
    std::this_thread::sleep_for(std::chrono::milliseconds(2100));
    const auto idle = p.Stats();
    const auto result = Submit(p);
    if (result == 0) { Wait([&]() { return p.Stats().rendered == 2; }); }
    const auto resumed = p.Stats();
    p.Shutdown();
    assert(idle.resets == 0 && idle.rendered == 1 && idle.pushed == 1);
    assert(result == 0 && resumed.resets == 0 && resumed.rendered == 2);
}
void ContinuousOutputDoesNotTriggerDecoderRecovery() {
    MediaPipeline p; fake::recycleInput = true;
    p.AttachSurface("100", 1920, 1080); assert(Submit(p, true) == 0);
    Wait([&]() { return p.Stats().rendered == 1; });
    uint64_t submitted = 1;
    bool accepted = true;
    const auto end = std::chrono::steady_clock::now() + std::chrono::milliseconds(2100);
    while (std::chrono::steady_clock::now() < end) {
        if (Submit(p) != 0) { accepted = false; break; }
        submitted++;
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    if (accepted) { Wait([&]() { return p.Stats().rendered == submitted; }); }
    const auto healthy = p.Stats();
    p.Shutdown();
    assert(accepted && healthy.resets == 0 && healthy.rendered == submitted && healthy.pushFailed == 0);
}
void IdleThenBurstWaitsForActualPendingOutput() {
    MediaPipeline p; fake::recycleInput = true;
    p.AttachSurface("100", 1920, 1080); assert(Submit(p, true) == 0);
    Wait([&]() { return p.Stats().rendered == 1; });
    std::this_thread::sleep_for(std::chrono::milliseconds(2100));
    fake::produceOutput = false;
    bool accepted = true;
    for (uint64_t i = 0; i < 9; i++) {
        if (Submit(p) != 0) { accepted = false; break; }
        Wait([&]() { return p.Stats().pushed == i + 2; });
    }
    const auto burst = p.Stats();
    fake::produceOutput = true;
    if (accepted) { assert(Submit(p) == 0); Wait([&]() { return p.Stats().rendered == 2; }); }
    p.Shutdown();
    assert(accepted && burst.resets == 0 && "idle time is not decoder output wait time");
}
void H264IntraSliceUsesSyncFlagOnExistingDecoder() {
    MediaPipeline p; fake::recycleInput = true;
    p.AttachSurface("100", 1920, 1080); assert(Submit(p, true) == 0);
    Wait([&]() { return p.Stats().rendered == 1; });
    const uint8_t intra[] = {0,0,0,1,0x41,0x88,0};
    assert(p.SubmitVideo(1, 1920, 1080, 2000, intra, sizeof(intra)) == 0);
    Wait([&]() { return p.Stats().rendered == 2; });
    assert(fake::flags.back() & AVCODEC_BUFFER_FLAGS_SYNC_FRAME);
}
void DecoderRestartReplaysConfigurationBeforeBareIdr() {
    MediaPipeline p; fake::recycleInput = true;
    p.AttachSurface("100", 1920, 1080); assert(Submit(p, true) == 0);
    Wait([&]() { return p.Stats().rendered == 1; });
    fake::pushError = -7; assert(Submit(p) == 0);
    Wait([&]() { return p.Stats().pushFailed == 1; });
    assert(Submit(p) == -1); fake::pushError = 0;
    const uint8_t idr[] = {0,0,0,1,0x65,1};
    assert(p.SubmitVideo(1, 1920, 1080, 2000, idr, sizeof(idr)) == 0);
    Wait([&]() { return p.Stats().rendered == 2; });
    assert(fake::flags[fake::flags.size() - 2] == AVCODEC_BUFFER_FLAGS_CODEC_DATA);
    const std::vector<uint8_t> config = {0,0,0,1,0x67,1,0,0,0,1,0x68,1};
    assert(fake::payloads[fake::payloads.size() - 2] == config);
    assert(fake::payloads.back() == std::vector<uint8_t>(idr, idr + sizeof(idr)));
}
void DecoderUsesYuvSurfaceFormat() {
    MediaPipeline p;
    p.AttachSurface("100", 1920, 1080); assert(Submit(p, true) == 0);
    Wait([&]() { return p.Stats().rendered == 1; });
    assert(fake::configuredPixelFormat == AV_PIXEL_FORMAT_NV12);
}
void FreshDecoderRequiresCompleteParameterSets() {
    for (int codec : {1, 2}) {
        MediaPipeline p; fake::recycleInput = true;
        p.AttachSurface("100", 1920, 1080);
        const std::vector<uint8_t> partial = codec == 1 ?
            std::vector<uint8_t>{0,0,0,1,0x67,1,0,0,0,1,0x65,1} :
            std::vector<uint8_t>{0,0,0,1,0x40,1,1,0,0,0,1,0x42,1,1,0,0,0,1,0x26,1,1};
        assert(p.SubmitVideo(codec, 1920, 1080, 1000, partial.data(), partial.size()) == -1);
        assert(p.Stats().submitted == 0);
        const std::vector<uint8_t> missing = codec == 1 ?
            std::vector<uint8_t>{0,0,0,1,0x68,1,0,0,0,1,0x65,1} :
            std::vector<uint8_t>{0,0,0,1,0x44,1,1,0,0,0,1,0x26,1,1};
        assert(p.SubmitVideo(codec, 1920, 1080, 2000, missing.data(), missing.size()) == 0);
        Wait([&]() { return p.Stats().rendered == 1; });
        assert(fake::flags[fake::flags.size() - 2] == AVCODEC_BUFFER_FLAGS_CODEC_DATA);
    }
}
void DecoderRestartRejectsOrdinaryIntraAndIncompleteRecoveryPoint() {
    MediaPipeline p; fake::recycleInput = true;
    p.AttachSurface("100", 1920, 1080); assert(Submit(p, true) == 0);
    Wait([&]() { return p.Stats().rendered == 1; });
    fake::pushError = -7; assert(Submit(p) == 0);
    Wait([&]() { return p.Stats().pushFailed == 1; });
    fake::pushError = 0;
    const uint8_t intra[] = {0,0,0,1,0x41,0x88,0};
    assert(p.SubmitVideo(1, 1920, 1080, 2000, intra, sizeof(intra)) == -1);
    const uint8_t recovery[] = {0,0,0,1,0x06,6,1,0x50,0x80,0,0,0,1,0x41,0x88,0};
    assert(p.SubmitVideo(1, 1920, 1080, 3000, recovery, sizeof(recovery)) == -1);
    assert(Submit(p) == -1);
    assert(Submit(p, true) == 0);
    Wait([&]() { return p.Stats().rendered == 2; });
}
void DecoderRestartAcceptsImmediateRecoveryWithCachedConfiguration() {
    MediaPipeline p; fake::recycleInput = true;
    p.AttachSurface("100", 1920, 1080); assert(Submit(p, true) == 0);
    Wait([&]() { return p.Stats().rendered == 1; });
    fake::pushError = -7; assert(Submit(p) == 0);
    Wait([&]() { return p.Stats().pushFailed == 1; });
    fake::pushError = 0;
    const uint8_t truncated[] = {0,0,0,1,0x06,6,2,0xC0,0,0,0,1,0x41,0x88,0};
    assert(p.SubmitVideo(1, 1920, 1080, 2000, truncated, sizeof(truncated)) == -1);
    const uint8_t immediate[] = {0,0,0,1,0x06,6,1,0xC0,0x80,0,0,0,1,0x41,0x88,0};
    assert(p.SubmitVideo(1, 1920, 1080, 3000, immediate, sizeof(immediate)) == 0);
    Wait([&]() { return p.Stats().rendered == 2; });
    assert(fake::flags[fake::flags.size() - 2] == AVCODEC_BUFFER_FLAGS_CODEC_DATA);
}
void DecoderRestartBoundsWaitForCompleteH264Intra() {
    MediaPipeline p; fake::recycleInput = true;
    p.AttachSurface("100", 1920, 1080); assert(Submit(p, true) == 0);
    Wait([&]() { return p.Stats().rendered == 1; });
    fake::pushError = -7; assert(Submit(p) == 0);
    Wait([&]() { return p.Stats().pushFailed == 1; });
    fake::pushError = 0;
    const uint8_t intra[] = {0,0,0,1,0x41,0x88,0};
    const uint8_t predicted[] = {0,0,0,1,0x41,0xC0};
    const uint8_t bidirectional[] = {0,0,0,1,0x41,0xA0};
    const uint8_t mixed[] = {0,0,0,1,0x41,0x88,0,0,0,0,1,0x41,0xC0};
    assert(p.SubmitVideo(1, 1920, 1080, 2000, intra, sizeof(intra)) == -1);
    MediaPipeline incomplete;
    incomplete.AttachSurface("200", 1920, 1080);
    const uint8_t sps[] = {0,0,0,1,0x67,1};
    assert(incomplete.SubmitVideo(1, 1920, 1080, 1000, sps, sizeof(sps)) == -1);
    std::this_thread::sleep_for(std::chrono::milliseconds(1550));
    assert(p.SubmitVideo(1, 1920, 1080, 3000, predicted, sizeof(predicted)) == -1);
    assert(p.SubmitVideo(1, 1920, 1080, 4000, bidirectional, sizeof(bidirectional)) == -1);
    assert(p.SubmitVideo(1, 1920, 1080, 5000, mixed, sizeof(mixed)) == -1);
    assert(incomplete.SubmitVideo(1, 1920, 1080, 6000, intra, sizeof(intra)) == -1);
    assert(p.SubmitVideo(1, 1920, 1080, 7000, intra, sizeof(intra)) == 0);
    Wait([&]() { return p.Stats().rendered == 2; });
    const std::vector<uint8_t> config = {0,0,0,1,0x67,1,0,0,0,1,0x68,1};
    assert(fake::flags[fake::flags.size() - 2] == AVCODEC_BUFFER_FLAGS_CODEC_DATA);
    assert(fake::payloads[fake::payloads.size() - 2] == config);
    assert(fake::flags.back() == AVCODEC_BUFFER_FLAGS_SYNC_FRAME);
    assert(fake::payloads.back() == std::vector<uint8_t>(intra, intra + sizeof(intra)));
    assert(p.Stats().resets == 1 && p.Stats().rendered == 2);
}
}
int main(int argc, char** argv) {
    for (const auto& test : {std::pair<const char*, void(*)()>{"InputSlotsAndSynchronousCallbacks", InputSlotsAndSynchronousCallbacks},
         {"PushFailureAndKeyframeRecovery", PushFailureAndKeyframeRecovery},
         {"SurfaceGenerationAndReleaseOrder", SurfaceGenerationAndReleaseOrder},
         {"OverflowIsBoundedAndRequestsRecovery", OverflowIsBoundedAndRequestsRecovery},
         {"DecoderErrorAndConfigureFailure", DecoderErrorAndConfigureFailure},
         {"AudioShutdownDoesNotBlockCallback", AudioShutdownDoesNotBlockCallback},
         {"ZeroTimestampIsPreserved", ZeroTimestampIsPreserved},
         {"RenderFailureRequestsKeyframeRecovery", RenderFailureRequestsKeyframeRecovery},
         {"IdleSurfaceDoesNotTriggerDecoderRecovery", IdleSurfaceDoesNotTriggerDecoderRecovery},
         {"ContinuousOutputDoesNotTriggerDecoderRecovery", ContinuousOutputDoesNotTriggerDecoderRecovery},
         {"IdleThenBurstWaitsForActualPendingOutput", IdleThenBurstWaitsForActualPendingOutput},
         {"H264IntraSliceUsesSyncFlagOnExistingDecoder", H264IntraSliceUsesSyncFlagOnExistingDecoder},
         {"DecoderRestartReplaysConfigurationBeforeBareIdr", DecoderRestartReplaysConfigurationBeforeBareIdr},
         {"DecoderUsesYuvSurfaceFormat", DecoderUsesYuvSurfaceFormat},
         {"FreshDecoderRequiresCompleteParameterSets", FreshDecoderRequiresCompleteParameterSets},
         {"DecoderRestartRejectsOrdinaryIntraAndIncompleteRecoveryPoint", DecoderRestartRejectsOrdinaryIntraAndIncompleteRecoveryPoint},
         {"DecoderRestartAcceptsImmediateRecoveryWithCachedConfiguration", DecoderRestartAcceptsImmediateRecoveryWithCachedConfiguration},
         {"DecoderRestartBoundsWaitForCompleteH264Intra", DecoderRestartBoundsWaitForCompleteH264Intra},
         {"SilentOutputStallRequestsKeyframeRecovery", SilentOutputStallRequestsKeyframeRecovery}}) {
        if (argc > 1 && std::string(argv[1]) != test.first) { continue; }
        fake::Reset(); test.second(); std::cout << "PASS " << test.first << std::endl;
    }
    fake::Reset();
}
