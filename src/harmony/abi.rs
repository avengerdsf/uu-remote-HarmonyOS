//! Versioned C ABI consumed by `entry/src/main/cpp/napi_init.cpp`.

use crate::harmony::platform::{Platform, PlatformOps};
use crate::harmony::service::{CoreService, Envelope};
use crate::harmony::{CoreConfig, EventQueue};
use std::collections::VecDeque;
use std::ffi::{c_char, c_void, CStr};
use std::sync::{Arc, Mutex};
use tokio::sync::mpsc;

pub const ABI_VERSION: i32 = 3;

#[repr(C)]
pub struct UuPlatformOps {
    pub user: *mut c_void,
    pub submit_video: Option<
        unsafe extern "C" fn(
            *mut c_void,
            i32,
            i32,
            i32,
            i64,
            *const u8,
            usize,
        ) -> i32,
    >,
    pub submit_audio: Option<
        unsafe extern "C" fn(*mut c_void, i32, i32, *const i16, usize) -> i32,
    >,
    pub attach_surface: Option<
        unsafe extern "C" fn(*mut c_void, *const c_char, i32, i32) -> i32,
    >,
    pub detach_surface: Option<unsafe extern "C" fn(*mut c_void, *const c_char) -> i32>,
    pub input_capability:
        Option<unsafe extern "C" fn(*mut c_void, *mut i32, *mut i32) -> i32>,
    pub request_input_injection: Option<unsafe extern "C" fn(*mut c_void) -> i32>,
    pub submit_audio_packet: Option<
        unsafe extern "C" fn(*mut c_void, u16, i64, *const u8, usize) -> i32,
    >,
    /// Stops/resumes the OHAudio renderer and clears queued PCM (ABI v3).
    pub set_audio_muted: Option<unsafe extern "C" fn(*mut c_void, i32) -> i32>,
}

pub struct UuCore {
    commands: mpsc::UnboundedSender<Envelope>,
    events: EventQueue,
    thread: Mutex<Option<std::thread::JoinHandle<()>>>,
}

unsafe impl Send for UuCore {}
unsafe impl Sync for UuCore {}

fn empty_ops() -> PlatformOps {
    PlatformOps {
        user: std::ptr::null_mut(),
        submit_video: None,
        submit_audio: None,
        attach_surface: None,
        detach_surface: None,
        input_capability: None,
        request_input_injection: None,
        submit_audio_packet: None,
        set_audio_muted: None,
    }
}

unsafe fn read_ops(ops: *const UuPlatformOps) -> PlatformOps {
    if ops.is_null() {
        return empty_ops();
    }
    let ops = &*ops;
    PlatformOps {
        user: ops.user,
        submit_video: ops.submit_video,
        submit_audio: ops.submit_audio,
        attach_surface: ops.attach_surface,
        detach_surface: ops.detach_surface,
        input_capability: ops.input_capability,
        request_input_injection: ops.request_input_injection,
        submit_audio_packet: ops.submit_audio_packet,
        set_audio_muted: ops.set_audio_muted,
    }
}

#[no_mangle]
pub unsafe extern "C" fn uu_core_create(
    config_json: *const c_char,
    ops: *const UuPlatformOps,
) -> *mut UuCore {
    if config_json.is_null() {
        return std::ptr::null_mut();
    }
    let Ok(text) = CStr::from_ptr(config_json).to_str() else {
        return std::ptr::null_mut();
    };
    let Ok(config) = serde_json::from_str::<CoreConfig>(text) else {
        return std::ptr::null_mut();
    };
    let platform = Platform::new(read_ops(ops));
    let events: EventQueue = Arc::new(Mutex::new(VecDeque::new()));
    let (tx, rx) = mpsc::unbounded_channel::<Envelope>();
    let worker_events = events.clone();
    let handle = std::thread::Builder::new()
        .name("uu-core".into())
        .spawn(move || {
            let runtime = tokio::runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .enable_all()
                .build();
            if let Ok(runtime) = runtime {
                runtime.block_on(CoreService::run(config, worker_events, platform, rx));
            }
        })
        .ok();
    let Some(handle) = handle else {
        return std::ptr::null_mut();
    };
    Box::into_raw(Box::new(UuCore {
        commands: tx,
        events,
        thread: Mutex::new(Some(handle)),
    }))
}

#[no_mangle]
pub unsafe extern "C" fn uu_core_destroy(core: *mut UuCore) {
    if core.is_null() {
        return;
    }
    let core = Box::from_raw(core);
    let _ = core.commands.send(Envelope {
        id: 0,
        method: "shutdown".into(),
        params: serde_json::Value::Null,
    });
    let thread = core
        .thread
        .lock()
        .ok()
        .and_then(|mut guard| guard.take());
    drop(core);
    if let Some(handle) = thread {
        let _ = handle.join();
    }
}

#[no_mangle]
pub unsafe extern "C" fn uu_core_command(core: *mut UuCore, command_json: *const c_char) -> i32 {
    if core.is_null() || command_json.is_null() {
        return -1;
    }
    let Ok(text) = CStr::from_ptr(command_json).to_str() else {
        return -1;
    };
    let Ok(command) = serde_json::from_str::<Envelope>(text) else {
        return -1;
    };
    let core = &*core;
    if core.commands.send(command).is_err() {
        return -1;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn uu_core_poll_event(core: *mut UuCore, buf: *mut c_char, cap: usize) -> i32 {
    if core.is_null() || buf.is_null() || cap == 0 {
        return -1;
    }
    let core = &*core;
    let Ok(mut queue) = core.events.lock() else {
        return -1;
    };
    let Some(front) = queue.front() else {
        return 0;
    };
    let bytes = front.as_bytes();
    if bytes.len() + 1 > cap {
        return -1;
    }
    std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf as *mut u8, bytes.len());
    *buf.add(bytes.len()) = 0;
    let length = bytes.len() as i32;
    queue.pop_front();
    length
}

#[no_mangle]
pub extern "C" fn uu_core_abi_version() -> i32 {
    ABI_VERSION
}
