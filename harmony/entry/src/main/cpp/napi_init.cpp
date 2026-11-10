#include <cstdint>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include <napi/native_api.h>
#include <hilog/log.h>

#include "input_bridge.h"
#include "gamepad_bridge.h"
#include "media_pipeline.h"
#include "uu_core.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3200
#define LOG_TAG "UUCoreNapi"

namespace {
struct CoreBinding {
    uu_core* core = nullptr;
    MediaPipeline media;
};

std::mutex g_mutex;
std::unordered_map<uint32_t, CoreBinding*> g_bindings;
uint32_t g_nextHandle = 1;

int32_t SubmitVideo(void* user, int32_t codec, int32_t width, int32_t height, int64_t ptsUs,
                    const uint8_t* data, size_t len) {
    auto* binding = static_cast<CoreBinding*>(user);
    if (binding == nullptr) {
        return -1;
    }
    return binding->media.SubmitVideo(codec, width, height, ptsUs, data, len);
}

int32_t SubmitAudio(void* user, int32_t sampleRate, int32_t channels, const int16_t* pcm,
                    size_t samples) {
    auto* binding = static_cast<CoreBinding*>(user);
    if (binding == nullptr) {
        return -1;
    }
    return binding->media.SubmitAudio(sampleRate, channels, pcm, samples);
}

int32_t SubmitAudioPacket(void* user, uint16_t seq, int64_t ptsUs, const uint8_t* data,
                          size_t len) {
    auto* binding = static_cast<CoreBinding*>(user);
    if (binding == nullptr) {
        return -1;
    }
    return binding->media.SubmitAudioPacket(seq, ptsUs, data, len);
}

int32_t SetAudioMuted(void* user, int32_t muted) {
    auto* binding = static_cast<CoreBinding*>(user);
    if (binding == nullptr) {
        return -1;
    }
    return binding->media.SetAudioMuted(muted != 0);
}

int32_t AttachSurface(void* user, const char* surfaceId, int32_t width, int32_t height) {
    auto* binding = static_cast<CoreBinding*>(user);
    if (binding == nullptr) {
        return -1;
    }
    return binding->media.AttachSurface(surfaceId, width, height);
}

int32_t DetachSurface(void* user, const char* surfaceId) {
    auto* binding = static_cast<CoreBinding*>(user);
    if (binding == nullptr) {
        return -1;
    }
    return binding->media.DetachSurface(surfaceId);
}

int32_t InputCapability(void* user, int32_t* capture, int32_t* injection) {
    (void)user;
    bool hasCapture = false;
    bool hasInjection = false;
    InputBridge::Capabilities(&hasCapture, &hasInjection);
    if (capture != nullptr) {
        *capture = hasCapture ? 1 : 0;
    }
    if (injection != nullptr) {
        *injection = hasInjection ? 1 : 0;
    }
    return 0;
}

int32_t RequestInputInjection(void* user) {
    (void)user;
    return InputBridge::RequestInjection();
}

std::string ReadString(napi_env env, napi_value value) {
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return std::string();
    }
    std::string text(length, '\0');
    napi_get_value_string_utf8(env, value, text.data(), length + 1, &length);
    return text;
}

napi_value Create(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return nullptr;
    }
    std::string config = ReadString(env, args[0]);
    if (uu_core_abi_version() != UU_CORE_ABI_VERSION) {
        OH_LOG_ERROR(LOG_APP, "uu_core ABI mismatch: native=%{public}d expected=%{public}d",
                     uu_core_abi_version(), UU_CORE_ABI_VERSION);
        return nullptr;
    }
    auto binding = std::make_unique<CoreBinding>();
    uu_platform_ops ops{};
    ops.user = binding.get();
    ops.submit_video = SubmitVideo;
    ops.submit_audio = SubmitAudio;
    ops.attach_surface = AttachSurface;
    ops.detach_surface = DetachSurface;
    ops.input_capability = InputCapability;
    ops.request_input_injection = RequestInputInjection;
    ops.submit_audio_packet = SubmitAudioPacket;
    ops.set_audio_muted = SetAudioMuted;
    binding->core = uu_core_create(config.c_str(), &ops);
    if (binding->core == nullptr) {
        return nullptr;
    }
    uint32_t handle = 0;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        handle = g_nextHandle++;
        g_bindings[handle] = binding.release();
    }
    napi_value result = nullptr;
    napi_create_uint32(env, handle, &result);
    return result;
}

CoreBinding* Binding(napi_env env, napi_value value) {
    uint32_t handle = 0;
    if (napi_get_value_uint32(env, value, &handle) != napi_ok) {
        return nullptr;
    }
    std::lock_guard<std::mutex> lock(g_mutex);
    auto found = g_bindings.find(handle);
    return found == g_bindings.end() ? nullptr : found->second;
}

napi_value Command(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        return nullptr;
    }
    CoreBinding* binding = Binding(env, args[0]);
    if (binding == nullptr || binding->core == nullptr) {
        return nullptr;
    }
    std::string command = ReadString(env, args[1]);
    int32_t code = uu_core_command(binding->core, command.c_str());
    if (command.find("\"method\":\"unlockRemote\"") != std::string::npos) {
        volatile char* data = command.data();
        for (size_t index = 0; index < command.size(); ++index) { data[index] = 0; }
    }
    napi_value result = nullptr;
    napi_create_int32(env, code, &result);
    return result;
}

napi_value Poll(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return nullptr;
    }
    CoreBinding* binding = Binding(env, args[0]);
    if (binding == nullptr || binding->core == nullptr) {
        return nullptr;
    }
    std::vector<char> buffer(UU_EVENT_BUFFER_BYTES);
    int32_t length = uu_core_poll_event(binding->core, buffer.data(), buffer.size());
    napi_value result = nullptr;
    if (length <= 0) {
        napi_create_string_utf8(env, "", 0, &result);
    } else {
        napi_create_string_utf8(env, buffer.data(), static_cast<size_t>(length), &result);
    }
    return result;
}

napi_value Destroy(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return nullptr;
    }
    CoreBinding* binding = Binding(env, args[0]);
    if (binding != nullptr) {
        uint32_t handle = 0;
        napi_get_value_uint32(env, args[0], &handle);
        {
            std::lock_guard<std::mutex> lock(g_mutex);
            g_bindings.erase(handle);
        }
        binding->media.Shutdown();
        if (binding->core != nullptr) {
            SetGamepadEnabled(binding->core, false);
            uu_core_destroy(binding->core);
        }
        delete binding;
    }
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value DecoderCaps(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return nullptr;
    }
    CoreBinding* binding = Binding(env, args[0]);
    if (binding == nullptr) {
        return nullptr;
    }
    MediaPipeline::DecoderCapabilities caps = MediaPipeline::QueryDecoderCapabilities();
    char text[256];
    snprintf(text, sizeof(text),
             "{\"maxFps\":%d,\"chroma444\":%s,\"hardware\":%s,\"probed\":%s,\"hevc\":%s,\"maxWidth\":%d,\"maxHeight\":%d}",
             caps.maxFps, caps.chroma444 ? "true" : "false", caps.hardware ? "true" : "false",
             caps.probed ? "true" : "false", caps.hevc ? "true" : "false", caps.maxWidth, caps.maxHeight);
    napi_value result = nullptr;
    napi_create_string_utf8(env, text, NAPI_AUTO_LENGTH, &result);
    return result;
}

napi_value MediaStats(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    CoreBinding* binding = argc > 0 ? Binding(env, args[0]) : nullptr;
    if (binding == nullptr) { return nullptr; }
    auto stats = binding->media.Stats();
    std::string text = "{\"framesDecoded\":" + std::to_string(stats.decoded) +
        ",\"framesRendered\":" + std::to_string(stats.rendered) +
        ",\"framesSubmitted\":" + std::to_string(stats.submitted) +
        ",\"framesDropped\":" + std::to_string(stats.dropped) +
        ",\"framesPushed\":" + std::to_string(stats.pushed) +
        ",\"pushFailures\":" + std::to_string(stats.pushFailed) +
        ",\"inputCallbacks\":" + std::to_string(stats.inputCallbacks) +
        ",\"outputCallbacks\":" + std::to_string(stats.outputCallbacks) +
        ",\"decoderResets\":" + std::to_string(stats.resets) +
        ",\"pictureUnits\":" + std::to_string(stats.pictureUnits) +
        ",\"configUnits\":" + std::to_string(stats.configUnits) +
        ",\"otherUnits\":" + std::to_string(stats.otherUnits) +
        ",\"ptsRegressions\":" + std::to_string(stats.ptsRegressions) +
        ",\"renderFailures\":" + std::to_string(stats.renderFailed) +
        ",\"lastInputPtsUs\":" + std::to_string(stats.lastInputPts) +
        ",\"lastOutputPtsUs\":" + std::to_string(stats.lastOutputPts) +
        ",\"decoderError\":" + std::to_string(stats.lastError) +
        ",\"pendingInputs\":" + std::to_string(stats.pendingInputs) +
        ",\"queuedUnits\":" + std::to_string(stats.queuedUnits) + "}";
    napi_value result = nullptr;
    napi_create_string_utf8(env, text.c_str(), text.size(), &result);
    return result;
}

napi_value SetAudioVolume(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    CoreBinding* binding = argc == 2 ? Binding(env, args[0]) : nullptr;
    double volume = -1.0;
    int32_t code = -1;
    if (binding != nullptr && napi_get_value_double(env, args[1], &volume) == napi_ok) {
        code = binding->media.SetAudioVolume(static_cast<float>(volume));
    }
    napi_value result = nullptr;
    napi_create_int32(env, code, &result);
    return result;
}

napi_value Version(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value result = nullptr;
    std::string text = std::to_string(uu_core_abi_version());
    napi_create_string_utf8(env, text.c_str(), text.size(), &result);
    return result;
}

napi_value GamepadEnabled(napi_env env, napi_callback_info info) {
    size_t argc = 2; napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    CoreBinding* binding = argc == 2 ? Binding(env, args[0]) : nullptr;
    bool enabled = false;
    int32_t code = -1;
    if (binding != nullptr && napi_get_value_bool(env, args[1], &enabled) == napi_ok) {
        code = SetGamepadEnabled(binding->core, enabled);
    }
    napi_value result = nullptr; napi_create_int32(env, code, &result); return result;
}

napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor descriptors[] = {
        {"create", nullptr, Create, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"command", nullptr, Command, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"poll", nullptr, Poll, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"destroy", nullptr, Destroy, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"decoderCaps", nullptr, DecoderCaps, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaStats", nullptr, MediaStats, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setAudioVolume", nullptr, SetAudioVolume, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setGamepadEnabled", nullptr, GamepadEnabled, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"version", nullptr, Version, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
    return exports;
}

napi_module coreModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "uu_core",
    .nm_priv = nullptr,
    .reserved = {nullptr},
};
}  // namespace

extern "C" __attribute__((constructor)) void RegisterUUCoreModule() {
    napi_module_register(&coreModule);
}
