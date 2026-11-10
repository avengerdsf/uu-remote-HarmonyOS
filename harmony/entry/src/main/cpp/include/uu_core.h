#ifndef UU_CORE_H
#define UU_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define UU_CORE_ABI_VERSION 3
#define UU_EVENT_BUFFER_BYTES (256 * 1024)

typedef struct uu_core uu_core;

/*
 * Platform callbacks. The core never owns a Surface or an AVCodec object:
 * decoded video stays in the native pipeline and audio is rendered by OHAudio.
 */
typedef struct uu_platform_ops {
    void* user;
    int (*submit_video)(void* user, int32_t codec, int32_t width, int32_t height,
                        int64_t pts_us, const uint8_t* data, size_t len);
    int (*submit_audio)(void* user, int32_t sample_rate, int32_t channels,
                        const int16_t* pcm, size_t samples);
    int (*attach_surface)(void* user, const char* surface_id, int32_t width, int32_t height);
    int (*detach_surface)(void* user, const char* surface_id);
    int (*input_capability)(void* user, int32_t* capture, int32_t* injection);
    int (*request_input_injection)(void* user);
    /* One RTP Opus payload, TOC included. Native side owns the decoder. */
    int (*submit_audio_packet)(void* user, uint16_t seq, int64_t pts_us,
                               const uint8_t* data, size_t len);
    /* 1 stops the renderer and drops queued PCM, 0 lets the next packet restart it. */
    int (*set_audio_muted)(void* user, int32_t muted);
} uu_platform_ops;

uu_core* uu_core_create(const char* config_json, const uu_platform_ops* ops);
void uu_core_destroy(uu_core* core);

/* Returns 0 when the command was accepted, negative for a malformed command. */
int32_t uu_core_command(uu_core* core, const char* command_json);

/*
 * Copies one queued event JSON into buf (NUL terminated) and returns its length,
 * or 0 when the queue is empty, or -1 when buf is too small.
 */
int32_t uu_core_poll_event(uu_core* core, char* buf, size_t cap);

int32_t uu_core_abi_version(void);

#ifdef __cplusplus
}
#endif

#endif
