//! C ABI platform callbacks supplied by the HarmonyOS N-API layer.

use std::ffi::c_void;

pub type SubmitVideoFn = Option<
    unsafe extern "C" fn(
        user: *mut c_void,
        codec: i32,
        width: i32,
        height: i32,
        pts_us: i64,
        data: *const u8,
        len: usize,
    ) -> i32,
>;
pub type SubmitAudioFn = Option<
    unsafe extern "C" fn(
        user: *mut c_void,
        sample_rate: i32,
        channels: i32,
        pcm: *const i16,
        samples: usize,
    ) -> i32,
>;
pub type SurfaceFn = Option<
    unsafe extern "C" fn(
        user: *mut c_void,
        surface_id: *const std::ffi::c_char,
        width: i32,
        height: i32,
    ) -> i32,
>;
pub type DetachFn =
    Option<unsafe extern "C" fn(user: *mut c_void, surface_id: *const std::ffi::c_char) -> i32>;
pub type CapabilityFn =
    Option<unsafe extern "C" fn(user: *mut c_void, capture: *mut i32, injection: *mut i32) -> i32>;
pub type RequestInjectionFn = Option<unsafe extern "C" fn(user: *mut c_void) -> i32>;
/// Stops or resumes the native OHAudio renderer and clears queued PCM. Combined
/// with the Rust-side gate this guarantees muted sessions do not emit any sample.
pub type SetAudioMutedFn = Option<unsafe extern "C" fn(user: *mut c_void, muted: i32) -> i32>;
/// One RTP Opus payload (TOC included). The native layer decodes it to 48 kHz
/// stereo S16 PCM and renders through OHAudio. `seq` is used for packet-loss
/// concealment across RTP sequence gaps.
pub type SubmitAudioPacketFn = Option<
    unsafe extern "C" fn(
        user: *mut c_void,
        seq: u16,
        pts_us: i64,
        data: *const u8,
        len: usize,
    ) -> i32,
>;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct PlatformOps {
    pub user: *mut c_void,
    pub submit_video: SubmitVideoFn,
    pub submit_audio: SubmitAudioFn,
    pub attach_surface: SurfaceFn,
    pub detach_surface: DetachFn,
    pub input_capability: CapabilityFn,
    pub request_input_injection: RequestInjectionFn,
    pub submit_audio_packet: SubmitAudioPacketFn,
    pub set_audio_muted: SetAudioMutedFn,
}

unsafe impl Send for PlatformOps {}
unsafe impl Sync for PlatformOps {}

#[derive(Clone, Copy)]
pub struct Platform {
    ops: PlatformOps,
}

impl Platform {
    pub fn new(ops: PlatformOps) -> Self {
        Self { ops }
    }

    pub fn submit_video(&self, codec: i32, width: i32, height: i32, pts_us: i64, data: &[u8]) -> bool {
        match self.ops.submit_video {
            Some(callback) => unsafe {
                callback(self.ops.user, codec, width, height, pts_us, data.as_ptr(), data.len()) == 0
            },
            None => false,
        }
    }

    pub fn submit_audio(&self, sample_rate: i32, channels: i32, pcm: &[i16]) -> bool {
        match self.ops.submit_audio {
            Some(callback) => unsafe {
                callback(self.ops.user, sample_rate, channels, pcm.as_ptr(), pcm.len()) == 0
            },
            None => false,
        }
    }

    /// Forwards one Opus RTP payload to the native decoder. Returns false when
    /// no native decoder is attached or the packet was rejected.
    pub fn submit_audio_packet(&self, seq: u16, pts_us: i64, data: &[u8]) -> bool {
        match self.ops.submit_audio_packet {
            Some(callback) => unsafe {
                callback(self.ops.user, seq, pts_us, data.as_ptr(), data.len()) == 0
            },
            None => false,
        }
    }

    pub fn has_audio_decoder(&self) -> bool {
        self.ops.submit_audio_packet.is_some()
    }

    /// Called on mute/unmute. Returns false when the native layer has no renderer
    /// callback (the Rust gate still prevents packets from being submitted).
    pub fn set_audio_muted(&self, muted: bool) -> bool {
        match self.ops.set_audio_muted {
            Some(callback) => unsafe { callback(self.ops.user, i32::from(muted)) == 0 },
            None => false,
        }
    }

    /// One Opus RTP payload when the session is not muted. Muting is checked here,
    /// before any decoder or OHAudio call, so the native layer receives no PCM.
    pub fn submit_audio_packet_if_unmuted(
        &self,
        muted: bool,
        seq: u16,
        pts_us: i64,
        data: &[u8],
    ) -> bool {
        if muted {
            return false;
        }
        self.submit_audio_packet(seq, pts_us, data)
    }

    pub fn attach_surface(&self, surface_id: &str, width: i32, height: i32) -> bool {
        match self.ops.attach_surface {
            Some(callback) => {
                let Ok(text) = std::ffi::CString::new(surface_id) else {
                    return false;
                };
                unsafe { callback(self.ops.user, text.as_ptr(), width, height) == 0 }
            }
            None => false,
        }
    }

    pub fn detach_surface(&self, surface_id: &str) -> bool {
        match self.ops.detach_surface {
            Some(callback) => {
                let Ok(text) = std::ffi::CString::new(surface_id) else {
                    return false;
                };
                unsafe { callback(self.ops.user, text.as_ptr()) == 0 }
            }
            None => false,
        }
    }

    pub fn input_capability(&self) -> (bool, bool) {
        let mut capture = 0;
        let mut injection = 0;
        if let Some(callback) = self.ops.input_capability {
            unsafe {
                callback(self.ops.user, &mut capture, &mut injection);
            }
        }
        (capture != 0, injection != 0)
    }

    pub fn request_input_injection(&self) -> bool {
        match self.ops.request_input_injection {
            Some(callback) => unsafe { callback(self.ops.user) == 0 },
            None => false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    static SUBMITTED: AtomicUsize = AtomicUsize::new(0);
    static MUTE_CALLS: AtomicUsize = AtomicUsize::new(0);
    static MUTE_VALUE: AtomicUsize = AtomicUsize::new(0);

    unsafe extern "C" fn count_submit(
        _user: *mut c_void,
        _seq: u16,
        _pts_us: i64,
        _data: *const u8,
        _len: usize,
    ) -> i32 {
        SUBMITTED.fetch_add(1, Ordering::SeqCst);
        0
    }

    unsafe extern "C" fn record_mute(_user: *mut c_void, muted: i32) -> i32 {
        MUTE_CALLS.fetch_add(1, Ordering::SeqCst);
        MUTE_VALUE.store(muted as usize, Ordering::SeqCst);
        0
    }

    fn platform() -> Platform {
        Platform::new(PlatformOps {
            user: std::ptr::null_mut(),
            submit_video: None,
            submit_audio: None,
            attach_surface: None,
            detach_surface: None,
            input_capability: None,
            request_input_injection: None,
            submit_audio_packet: Some(count_submit),
            set_audio_muted: Some(record_mute),
        })
    }

    #[test]
    fn muted_packets_never_reach_the_native_decoder() {
        SUBMITTED.store(0, Ordering::SeqCst);
        let platform = platform();
        assert!(platform.submit_audio_packet_if_unmuted(false, 1, 0, &[1, 2, 3]));
        assert!(!platform.submit_audio_packet_if_unmuted(true, 2, 0, &[1, 2, 3]));
        assert!(!platform.submit_audio_packet_if_unmuted(true, 3, 0, &[1, 2, 3]));
        assert_eq!(SUBMITTED.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn mute_switch_reaches_the_native_renderer() {
        MUTE_CALLS.store(0, Ordering::SeqCst);
        let platform = platform();
        assert!(platform.set_audio_muted(true));
        assert_eq!(MUTE_VALUE.load(Ordering::SeqCst), 1);
        assert!(platform.set_audio_muted(false));
        assert_eq!(MUTE_VALUE.load(Ordering::SeqCst), 0);
        assert_eq!(MUTE_CALLS.load(Ordering::SeqCst), 2);
    }
}
