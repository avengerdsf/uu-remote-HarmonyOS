//! Asynchronous core service driven by JSON commands from the ArkTS layer.

use crate::auth::{Credentials, UUAuthClient, BASE_URL, DEFAULT_SIGN_KEY};
use crate::harmony::input::TouchMode;
use crate::harmony::login;
use crate::harmony::platform::Platform;
use crate::harmony::session::{self, OpenOptions, SessionCommand, SessionHandle, ToolLink};
use crate::harmony::session::remote_unlock;
use crate::harmony::video::{CHROMA_420, CHROMA_444, DecoderCapabilities, VideoSettings};
use crate::harmony::{
    event, CoreConfig, DeviceItem, DevicesSnapshot, EventQueue, LoginSnapshot, SessionSnapshot,
};
use crate::viewer::api::Api;
use crate::harmony::tools::files::{Entry as RemoteEntry, Files};
use crate::harmony::tools::portmap::PortMap;
use crate::harmony::tools::terminal::{Event as TerminalEvent, Terminal};
use crate::viewer::wire::{self, Codec as WireCodec, Decoder, Display, Shape};
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::mpsc;

#[derive(Deserialize)]
pub struct Envelope {
    #[serde(default)]
    pub id: u64,
    pub method: String,
    #[serde(default)]
    pub params: Value,
}

impl Drop for Envelope {
    fn drop(&mut self) {
        if self.method == "unlockRemote" {
            // Replacement and shutdown may discard the command before dispatch.
            if let Some(Value::String(password)) = self.params.get_mut("password").map(Value::take) {
                drop(remote_unlock::Secret::from(password));
            }
        }
    }
}

#[derive(Clone)]
enum ConnectionTarget { Device(String), Share(String, String) }

fn tool_event(events: &EventQueue, generation: u64, kind: &str, mut data: Value) {
    data["generation"] = json!(generation);
    event(events, kind, data);
}

enum Internal {
    LoginDone(u64, Result<Credentials, String>),
    DevicesDone(u64, Result<Value, String>),
    JoinFailed(u64, String, crate::viewer::api::Error),
    SessionOpened(u64, Result<SessionHandle, String>, String, String, bool),
}

struct SettingsState {
    video: VideoSettings,
    decoder: DecoderCapabilities,
    touch_mode: TouchMode,
    clipboard_policy: String,
    view_only: bool,
    audio_muted: bool,
}

pub struct CoreService {    config: CoreConfig,
    events: EventQueue,
    platform: Platform,
    api: Option<Arc<Api>>,
    credentials: Option<Credentials>,
    devices: Vec<DeviceItem>,
    devices_generation: u64,
    login_generation: u64,
    login_cancel: Arc<AtomicBool>,
    login_task: Option<tokio::task::JoinHandle<()>>,
    connect_task: Option<tokio::task::JoinHandle<()>>,
    opening_cleanup: crate::viewer::signal::CleanupBarrier,
    cleanup_error: Option<String>,
    session: Option<SessionHandle>,
    session_generation: u64,
    settings: SettingsState,
    surface_size: (u32, u32),
    internal_tx: mpsc::UnboundedSender<Internal>,
    tool_sessions: Vec<SessionHandle>,
    target: Option<ConnectionTarget>,
    files: Option<Arc<Files>>,
    files_path: String,
    files_entries: Vec<RemoteEntry>,
    files_progress: Option<tokio::task::JoinHandle<()>>,
    transfer_tasks: Vec<tokio::task::JoinHandle<()>>,
    terminal: Option<Arc<Terminal>>,
    terminal_session: u32,
    terminal_events: Option<tokio::task::JoinHandle<()>>,
    portmap: Option<Arc<PortMap>>,
    port_rules: BTreeMap<String, (u64, Value)>,
}

impl CoreService {
    pub async fn run(
        config: CoreConfig,
        events: EventQueue,
        platform: Platform,
        mut commands: mpsc::UnboundedReceiver<Envelope>,
    ) {
        let (internal_tx, mut internal_rx) = mpsc::unbounded_channel();
        let mut service = Self {
            config,
            events,
            platform,
            api: None,
            credentials: None,
            devices: Vec::new(),
            devices_generation: 0,
            login_generation: 0,
            login_cancel: Arc::new(AtomicBool::new(false)),
            login_task: None,
            connect_task: None,
            opening_cleanup: Default::default(),
            cleanup_error: None,
            session: None,
            session_generation: 0,
            settings: SettingsState {
                video: VideoSettings::default(),
                decoder: DecoderCapabilities::default(),
                touch_mode: TouchMode::Trackpad,
                clipboard_policy: "manual".into(),
                view_only: false,
                audio_muted: false,
            },
            surface_size: (1280, 720),
            internal_tx,
            tool_sessions: Vec::new(),
            target: None,
            files: None,
            files_path: ":/".into(),
            files_entries: Vec::new(),
            files_progress: None,
            transfer_tasks: Vec::new(),
            terminal: None,
            terminal_session: 0,
            terminal_events: None,
            portmap: None,
            port_rules: BTreeMap::new(),
        };
        let mut pending = VecDeque::new();
        'commands: loop {
            let command = if let Some(command) = pending.pop_front() { command } else {
                tokio::select! {
                    command = commands.recv() => match command { Some(value) => value, None => break },
                    internal = internal_rx.recv() => {
                        if let Some(internal) = internal { service.handle_internal(internal).await; }
                        continue;
                    }
                }
            };
            let interrupted_method = command.method.clone();
            let interrupted_device = (interrupted_method == "wakeDevice")
                .then(|| command.params.get("deviceId").and_then(Value::as_str).unwrap_or("").to_owned());
            // Finish peer cleanup before a replacement can open a new capture.
            let has_value = |key| command.params.get(key).and_then(Value::as_str).is_some_and(|value| !value.is_empty());
            let replaces_session = match interrupted_method.as_str() {
                "connect" => service.api.is_some() && has_value("deviceId"),
                "joinShare" => service.api.is_some() && has_value("connectId") && has_value("verifyCode"),
                "selectTarget" => has_value("deviceId"),
                "disconnect" | "logout" | "shutdown" => true,
                _ => false,
            };
            let interruptible = !replaces_session;
            if !interruptible {
                if let Some(task) = service.connect_task.take() {
                    task.abort();
                    let _ = task.await;
                }
                // A completed opening task may already have handed its peer to
                // this queue. Close it before joining the replacement room.
                while let Ok(internal) = internal_rx.try_recv() {
                    match internal {
                        Internal::SessionOpened(_, result, _, _, _) => {
                            if let Ok(handle) = result { if let Err(error) = handle.close().await { service.cleanup_error = Some(error); } }
                        }
                        internal => service.handle_internal(internal).await,
                    }
                }
            }
            let replacement = {
                let operation = service.handle(command);
                tokio::pin!(operation);
                loop {
                    tokio::select! {
                        // Apply ready settings before a queued connection can cancel them.
                        biased;
                        stop = &mut operation => { if stop { break 'commands; } break None; },
                        next = commands.recv(), if interruptible => {
                            match next {
                                Some(next) if matches!(next.method.as_str(), "disconnect" | "logout" | "shutdown" | "loginCancel" | "connect" | "joinShare" | "selectTarget") => break Some(next),
                                Some(next) => pending.push_back(next),
                                None => break Some(Envelope { id: 0, method: "shutdown".into(), params: Value::Null }),
                            }
                        }
                    }
                }
            };
            if let Some(next) = replacement {
                if matches!(interrupted_method.as_str(), "mkdir" | "unbindDevice" | "wakeDevice") {
                    let mut response = json!({"operation": interrupted_method, "success": false, "error": "操作已取消"});
                    if let Some(id) = interrupted_device { response["deviceId"] = json!(id); }
                    event(&service.events, "operationResult", response);
                }
                pending.clear();
                pending.push_front(next);
            }
        }
        service.shutdown().await;
    }

    async fn handle(&mut self, mut command: Envelope) -> bool {
        let mut params = std::mem::take(&mut command.params);
        match command.method.as_str() {
            "init" => {}
            "setCredentials" => {
                if let Ok(mut creds) = serde_json::from_value::<Credentials>(params) {
                    if creds.sign_key.is_empty() {
                        creds.sign_key = DEFAULT_SIGN_KEY.into();
                    }
                    self.credentials = Some(creds.clone());
                    self.api = Some(Arc::new(Api::new(UUAuthClient::new(creds), BASE_URL)));
                }
            }
            "loginStart" => {
                self.login_generation += 1;
                let generation = self.login_generation;
                self.login_cancel.store(true, Ordering::Release);
                if let Some(task) = self.login_task.take() {
                    task.abort();
                }
                let cancel = Arc::new(AtomicBool::new(false));
                self.login_cancel = cancel.clone();
                let mut config = self.config.clone();
                if let Some(creds) = &self.credentials {
                    config.device_id = creds.device_id.clone();
                    config.client_id = creds.client_id.clone();
                    config.system_id = creds.system_id.clone();
                }
                let events = self.events.clone();
                let sender = self.internal_tx.clone();
                self.emit_login(LoginSnapshot {
                    phase: "loadingQr".into(),
                    status_text: "正在生成二维码…".into(),
                    qr_payload: None,
                    polling_active: true,
                    authenticated: false,
                    error: None,
                    generation,
                });
                self.login_task = Some(tokio::spawn(async move {
                    let result = login::run(&config, &events, generation, cancel).await;
                    let _ = sender.send(Internal::LoginDone(generation, result));
                }));
            }
            "loginCancel" => {
                self.login_generation += 1;
                self.login_cancel.store(true, Ordering::Release);
                if let Some(task) = self.login_task.take() {
                    task.abort();
                }
                self.emit_login(LoginSnapshot {
                    phase: "failed".into(),
                    status_text: "已取消登录".into(),
                    qr_payload: None,
                    polling_active: false,
                    authenticated: false,
                    error: None,
                    generation: self.login_generation,
                });
            }
            "listDevices" => {
                let Some(api) = self.api.clone() else {
                    self.emit_devices(DevicesSnapshot {
                        phase: "authExpired".into(),
                        devices: Vec::new(),
                        error: Some("尚未登录".into()),
                        generation: self.devices_generation,
                    });
                    return false;
                };
                self.devices_generation += 1;
                let generation = self.devices_generation;
                let sender = self.internal_tx.clone();
                tokio::spawn(async move {
                    let (controlled, groups) = tokio::join!(api.device_list(), api.device_groups());
                    let result = controlled.map(|mut data| {
                        if let (Some(data), Ok(groups)) = (data.as_object_mut(), groups) {
                            data.insert("device_groups".into(), groups);
                        }
                        data
                    }).map_err(|error| error.to_string());
                    let _ = sender.send(Internal::DevicesDone(generation, result));
                });
            }
            "connect" | "joinShare" => {
                let method = command.method.clone();
                let device_id = params.get("deviceId").and_then(Value::as_str).unwrap_or("").to_owned();
                let connect_id = params.get("connectId").and_then(Value::as_str).unwrap_or("").to_owned();
                let verify_code = params.get("verifyCode").and_then(Value::as_str).unwrap_or("").to_owned();
                if command.method == "connect" && device_id.is_empty() {
                    return false;
                }
                if command.method == "joinShare" && (connect_id.is_empty() || verify_code.is_empty()) {
                    return false;
                }
                let Some(api) = self.api.clone() else {
                    return false;
                };
                self.session_generation += 1;
                let generation = self.session_generation;
                if let Err(error) = self.close_session().await {
                    self.emit_session(SessionSnapshot { generation, error: Some(error), ..SessionSnapshot::ended() });
                    return false;
                }
                let target_id = if method == "connect" { device_id.clone() } else { connect_id.clone() };
                let target_device = self
                    .devices
                    .iter()
                    .find(|device| device.id == target_id);
                let target_windows = target_device.is_some_and(|device| device.platform.eq_ignore_ascii_case("Windows"));
                let target_name = target_device
                    .map(|device| device.name.clone())
                    .unwrap_or_else(|| if method == "connect" { target_id.clone() } else { "远程协助".into() });
                self.emit_session(SessionSnapshot {
                    phase: "connecting".into(),
                    session_id: String::new(),
                    generation,
                    resource_epoch: 0,
                    target_id: target_id.clone(),
                    target_name: target_name.clone(),
                    view_only: self.settings.view_only,
                    first_frame_received: false,
                    error: None,
                    video_width: 0,
                    video_height: 0,
                });
                self.target = Some(if method == "connect" { ConnectionTarget::Device(device_id.clone()) } else { ConnectionTarget::Share(connect_id.clone(), verify_code.clone()) });
                let shape = self.shape();
                let events = self.events.clone();
                let platform = self.platform;
                let mut config = self.config.clone();
                if let Some(creds) = &self.credentials {
                    config.device_id = creds.device_id.clone();
                    config.client_id = creds.client_id.clone();
                    config.system_id = creds.system_id.clone();
                }
                let sender = self.internal_tx.clone();
                let video = self.settings.video;
                let touch_mode = self.settings.touch_mode;
                let audio_muted = self.settings.audio_muted;
                let view_only_setting = self.settings.view_only;
                let force = params.get("force").and_then(Value::as_bool).unwrap_or(false);
                let cleanup = self.opening_cleanup.clone();
                self.connect_task = Some(tokio::spawn(async move {
                    let room = if method == "connect" {
                        api.join(&device_id, force, true).await
                    } else {
                        api.join_share(&connect_id, &verify_code).await
                    };
                    let room = match room {
                        Ok(room) => room,
                        Err(error) => {
                            let _ = sender.send(Internal::JoinFailed(generation, target_id, error));
                            return;
                        }
                    };
                    let mac = api
                        .target_is_mac(&room, if method == "connect" { Some(device_id.as_str()) } else { None })
                        .await;
                    let mut view_only = view_only_setting;
                    let mac_failed = mac.is_err();
                    let target_mac = mac.unwrap_or(false);
                    if mac_failed {
                        view_only = true;
                    }
                    let result = session::open_tracked(
                        &api,
                        &room,
                        &shape,
                        &config.device_id,
                        &config.client_id,
                        OpenOptions {
                            view_only,
                            target_id: target_id.clone(),
                            target_name: target_name.clone(),
                            mac: target_mac,
                            capture_cursor: room.publisher_platform.map_or(target_windows, |platform| platform == 1),
                            video,
                            touch_mode,
                            audio_muted,
                        },
                        events,
                        platform,
                        generation,
                        Duration::from_millis(u64::from(config.signaling_timeout_ms)),
                        Some(&cleanup),
                    )
                    .await;
                    let _ = sender.send(Internal::SessionOpened(generation, result, target_id, target_name, view_only));
                }));
            }
            "disconnect" => {
                self.session_generation += 1;
                let result = self.close_session().await;
                self.emit_session(SessionSnapshot { generation: self.session_generation, error: result.as_ref().err().cloned(), ..SessionSnapshot::ended() });
                let mut response = json!({"operation":"disconnect", "success":result.is_ok()});
                if let Err(error) = result { response["error"] = json!(error); }
                event(&self.events, "operationResult", response);
            }
            "sendInput" | "sendText" | "releaseAllInput" => {
                if let Some(handle) = &self.session {
                    let input = match command.method.as_str() {
                        "sendInput" => SessionCommand::Input(params.get("json").and_then(Value::as_str).unwrap_or("").to_owned()),
                        "sendText" => SessionCommand::Text(params.get("text").and_then(Value::as_str).unwrap_or("").to_owned()),
                        _ => SessionCommand::Release,
                    };
                    // Preserve button/key transitions when pointer traffic fills the queue.
                    if handle.tx.send(input).await.is_err() {
                        event(&self.events, "inputError", json!({
                            "generation": self.session_generation,
                            "message": "远程输入发送失败，请重新连接。"
                        }));
                    }
                }
            }
            "setViewOnly" => {
                self.settings.view_only = params.get("viewOnly").and_then(Value::as_bool).unwrap_or(false);
                let value = self.settings.view_only;
                if let Some(handle) = &self.session {
                    let _ = handle.tx.send(SessionCommand::ViewOnly(value)).await;
                }
            }
            "gamepadState" => {
                let value = params.get("state").cloned().unwrap_or(Value::Null);
                let state = if value.is_null() { Ok(None) } else {
                    serde_json::from_value::<crate::viewer::native_gamepad::State>(value).map(Some)
                };
                if let Ok(state) = state {
                    if let Some(handle) = &self.session {
                        if handle.tx.send(SessionCommand::Gamepad(state)).await.is_err() {
                            event(&self.events, "inputError", json!({"generation": self.session_generation,
                                "message": "远程输入发送失败，请重新连接。"}));
                        }
                    }
                }
            }
            "resizeViewport" => {
                let width = params.get("width").and_then(Value::as_u64).unwrap_or(0).min(16384) as u32;
                let height = params.get("height").and_then(Value::as_u64).unwrap_or(0).min(16384) as u32;
                if width >= 2 && height >= 2 {
                    self.surface_size = (width, height);
                    let next = self.video_for_viewport(self.settings.video);
                    if next != self.settings.video {
                        self.settings.video = next;
                        self.sync_session_video_settings().await;
                    }
                }
            }
            "attachSurface" => {
                let surface_id = params.get("surfaceId").and_then(Value::as_str).unwrap_or("");
                let width = params.get("width").and_then(Value::as_i64).unwrap_or(0) as i32;
                let height = params.get("height").and_then(Value::as_i64).unwrap_or(0) as i32;
                if !surface_id.is_empty() {
                    self.platform.attach_surface(surface_id, width, height);
                    if width >= 2 && height >= 2 {
                        self.surface_size = (width as u32, height as u32);
                        let next = self.video_for_viewport(self.settings.video);
                        if next != self.settings.video {
                            self.settings.video = next;
                            self.sync_session_video_settings().await;
                        }
                    }
                    self.with_session(|handle| {
                        let _ = handle.tx.try_send(SessionCommand::Resize(width.max(0) as u32, height.max(0) as u32));
                    });
                }
            }
            "detachSurface" => {
                let surface_id = params.get("surfaceId").and_then(Value::as_str).unwrap_or("");
                if !surface_id.is_empty() {
                    self.platform.detach_surface(surface_id);
                }
            }
            "setVideoSettings" | "setVideoQuality" | "setFrameRate" | "setTrueColor"
            | "setVideoProfile" => {
                let mut next = self.settings.video;
                match command.method.as_str() {
                    "setVideoQuality" => {
                        let quality = params.get("quality").and_then(Value::as_str).unwrap_or("auto");
                        next.apply_params(&json!({"quality": quality}));
                    }
                    "setFrameRate" => {
                        let fps = params.get("fps").and_then(Value::as_u64).unwrap_or(60);
                        next.apply_params(&json!({"fps": fps}));
                    }
                    "setTrueColor" => {
                        let enabled = params.get("enabled").and_then(Value::as_bool).unwrap_or(false);
                        next.apply_params(&json!({"trueColor": enabled}));
                    }
                    "setVideoProfile" => {
                        let profile = params.get("profile").and_then(Value::as_str).unwrap_or("auto");
                        next.apply_params(&json!({"profile": profile}));
                    }
                    _ => {
                        next.apply_params(&params);
                    }
                }
                self.settings.video = self.video_for_viewport(next);
                self.sync_session_video_settings().await;
            }
            "videoRendered" => {
                if params.get("generation").and_then(Value::as_u64) == Some(self.session_generation) {
                    self.with_session(|handle| { let _ = handle.tx.try_send(SessionCommand::Rendered); });
                }
            }
            "setDecoderCaps" => {
                let max_fps = params.get("maxFps").and_then(Value::as_u64).unwrap_or(60) as u32;
                let chroma_444 = params.get("chroma444").and_then(Value::as_bool).unwrap_or(false);
                self.settings.decoder = DecoderCapabilities { max_fps, chroma_444,
                    hevc: params.get("hevc").and_then(Value::as_bool).unwrap_or(false),
                    max_width: params.get("maxWidth").and_then(Value::as_u64).unwrap_or(1920).min(3840) as u32,
                    max_height: params.get("maxHeight").and_then(Value::as_u64).unwrap_or(1080).min(2160) as u32,
                }.sanitized();
                let next = self.settings.video.limited(self.settings.decoder);
                if next != self.settings.video {
                    self.settings.video = next;
                    self.sync_session_video_settings().await;
                }
            }
            "setTouchMode" => {
                let mode = TouchMode::parse(
                    params.get("mode").and_then(Value::as_str).unwrap_or("trackpad"),
                );
                self.settings.touch_mode = mode;
                if let Some(handle) = &self.session {
                    let _ = handle.tx.try_send(SessionCommand::TouchMode(mode));
                }
            }
            "setAudioMuted" => {
                let muted = params.get("muted").and_then(Value::as_bool).unwrap_or(false);
                self.settings.audio_muted = muted;
                if let Some(handle) = &self.session {
                    let _ = handle.tx.try_send(SessionCommand::AudioMuted(muted));
                }
            }
            "setClipboardPolicy" => {
                self.settings.clipboard_policy = params.get("policy").and_then(Value::as_str).unwrap_or("manual").to_owned();
            }
            "selectTarget" => {
                let device = params.get("deviceId").and_then(Value::as_str).unwrap_or("");
                let mut result = if device.is_empty() { Err("请选择远端设备".to_owned()) } else { Ok(()) };
                if !device.is_empty() {
                    self.session_generation += 1;
                    result = self.close_session().await;
                    if result.is_ok() {
                        self.target = Some(ConnectionTarget::Device(device.to_owned()));
                        self.emit_session(SessionSnapshot { generation: self.session_generation, target_id: device.to_owned(), ..SessionSnapshot::ended() });
                    }
                }
                event(&self.events, "operationResult", json!({"operation":"selectTarget", "success":result.is_ok(), "error":result.err()}));
            }
            "unbindDevice" => {
                let id = params.get("deviceId").and_then(Value::as_str).unwrap_or("");
                let shared = params.get("shared").and_then(Value::as_bool).unwrap_or(false);
                let result = if let Some(api) = &self.api { api.unbind(id, shared).await.map_err(|error| error.to_string()) }
                    else { Err("请先登录".into()) };
                event(&self.events, "operationResult", json!({"operation": "unbindDevice", "success": result.is_ok(), "error": result.err()}));
                if let Some(api) = self.api.clone() {
                    self.devices_generation += 1;
                    let generation = self.devices_generation;
                    let sender = self.internal_tx.clone();
                    tokio::spawn(async move { let _ = sender.send(Internal::DevicesDone(generation, api.device_list().await.map_err(|error| error.to_string()))); });
                }
            }
            "wakeDevice" => {
                let id = params.get("deviceId").and_then(Value::as_str).unwrap_or("");
                let result = if let Some(api) = &self.api {
                    if !id.is_empty() && id != self.config.device_id && self.devices.iter().any(|device|
                        device.id == id && !device.online && device.capabilities.iter().any(|value| value == "wake"))
                    {
                        api.wake_device(id).await.map_err(|error| match error {
                            crate::viewer::api::Error::Api(code, _) => crate::tr!("远程开机请求失败（错误码 {code}）", "Remote power-on request failed (error {code})"),
                            error => error.to_string(),
                        })
                    } else {
                        Err(crate::i18n::s("该设备当前不可远程开机。", "Remote power-on is unavailable for this device.").into())
                    }
                } else { Err(crate::i18n::s("请先登录", "Sign in first.").into()) };
                event(&self.events, "operationResult", json!({
                    "operation":"wakeDevice", "deviceId":id, "success":result.is_ok(), "error":result.err()
                }));
            }
            "sendClipboard" => {
                let text = params.get("text").and_then(Value::as_str).unwrap_or("").to_owned();
                if let Some(handle) = &self.session {
                    let _ = handle.tx.try_send(SessionCommand::Clipboard(text));
                } else {
                    event(&self.events, "operationResult", json!({"operation": "clipboard", "success": false, "error": "请先建立远程桌面连接"}));
                }
            }
            "remoteAction" => {
                let name = params.get("action").and_then(Value::as_str).unwrap_or("");
                let enabled = params.get("enabled").and_then(Value::as_bool).unwrap_or(false);
                if self.settings.view_only || self.session.is_none() {
                    event(&self.events, "operationResult", json!({"operation": "remoteAction", "success": false, "error": "当前会话不可执行系统操作"}));
                } else {
                    match super::actions::RemoteAction::parse(name, enabled) {
                        Ok(action) => self.with_session(|handle| { let _ = handle.tx.try_send(SessionCommand::RemoteAction(action)); }),
                        Err(error) => event(&self.events, "operationResult", json!({"operation":"remoteAction", "success":false, "error":error})),
                    }
                }
            }
            "unlockRemote" => {
                let generation = params.get("generation").and_then(Value::as_u64);
                let target = params.get("targetId").and_then(Value::as_str).filter(|id| !id.is_empty());
                let handle = self.session.as_ref().filter(|handle| {
                    !self.settings.view_only && generation == Some(self.session_generation)
                        && generation == Some(handle.snapshot.generation)
                        && target == Some(handle.snapshot.target_id.as_str())
                });
                let secret = match params.get_mut("password").map(Value::take) {
                    Some(Value::String(password)) => Some(remote_unlock::Secret::from(password)),
                    _ => None,
                };
                let queued = if let (Some(handle), Some(password)) = (handle, secret) {
                    handle.tx.try_send(SessionCommand::UnlockRemote(command.id, password)).is_ok()
                } else { false };
                if !queued {
                    remote_unlock::result(&self.events, generation.unwrap_or(self.session_generation), command.id,
                        Some(remote_unlock::Failure::Unavailable));
                }
            }
            "mkdir" => {
                let path = params.get("path").and_then(Value::as_str).unwrap_or("");
                let result = match self.ensure_files().await {
                    Ok(files) => files.mkdir(path).await, Err(error) => Err(error),
                };
                event(&self.events, "operationResult", json!({"operation": "mkdir", "success": result.is_ok(), "error": result.as_ref().err()}));
                if result.is_ok() { self.open_remote_files(self.files_path.clone()).await; }
                else { self.files_event("ready", result.err()); }
            }
            "openFiles" => {
                let path = params.get("path").and_then(Value::as_str).unwrap_or(":/").to_owned();
                self.open_remote_files(path).await;
            }
            "openTerminal" => {
                self.open_remote_terminal(None).await;
            }
            "attachTerminal" => {
                if let Some(id) = params.get("ptyId").and_then(Value::as_u64).and_then(|id| u32::try_from(id).ok()) {
                    self.open_remote_terminal(Some(id)).await;
                }
            }
            "terminalSessions" => {
                let result = match self.ensure_terminal().await {
                    Ok(terminal) => terminal.list_sessions().await,
                    Err(error) => Err(error),
                };
                let rows: Vec<Value> = result.as_ref().map(|items| items.iter().filter_map(|item| {
                    let id = item.get("session_id")?.as_u64()?;
                    Some(json!({"sessionId":id, "shell":item.get("shell").and_then(Value::as_str).unwrap_or(""),
                        "state":item.get("state").and_then(Value::as_str).unwrap_or("")}))
                }).collect()).unwrap_or_default();
                tool_event(&self.events, self.session_generation, "terminalSessions", json!({"sessions":rows, "error":result.err()}));
            }
            "killTerminal" => {
                let id = params.get("ptyId").and_then(Value::as_u64).and_then(|id| u32::try_from(id).ok());
                let result = match (self.terminal.clone(), id) {
                    (Some(terminal), Some(id)) => terminal.kill(id).await,
                    _ => Err("终端会话不可用".into()),
                };
                event(&self.events, "operationResult", json!({"operation":"killTerminal", "success":result.is_ok(), "error":result.err()}));
            }
            "terminalState" => {
                if self.terminal.is_some() {
                    tool_event(&self.events, self.session_generation, "terminalState", json!({
                        "phase": "ready",
                        "sessionId": self.session.as_ref().map(|s| s.snapshot.session_id.clone()).unwrap_or_default(),
                        "output": "",
                        "error": null
                    }));
                }
            }
            "terminalWrite" => {
                let text = params.get("text").and_then(Value::as_str).unwrap_or("").to_owned();
                if let Some(terminal) = self.terminal.clone() {
                    if let Err(error) = terminal.write(self.terminal_session, text.as_bytes()).await {
                        tool_event(&self.events, self.session_generation, "terminalState", json!({
                            "phase": "failed",
                            "sessionId": self.session.as_ref().map(|s| s.snapshot.session_id.clone()).unwrap_or_default(),
                            "output": "",
                            "error": error
                        }));
                    }
                }
            }
            "terminalResize" => {
                let columns = params.get("columns").and_then(Value::as_u64).unwrap_or(80).clamp(1, 1000) as u16;
                let rows = params.get("rows").and_then(Value::as_u64).unwrap_or(24).clamp(1, 1000) as u16;
                if let Some(terminal) = self.terminal.clone() {
                    let _ = terminal.resize(self.terminal_session, columns, rows).await;
                }
            }
            "closeTerminal" => {
                if let Some(terminal) = self.terminal.take() {
                    let _ = terminal.close(self.terminal_session).await;
                }
                if let Some(task) = self.terminal_events.take() {
                    task.abort();
                }
                self.terminal_session = 0;
                tool_event(&self.events, self.session_generation, "terminalState", json!({
                    "phase": "disconnected",
                    "sessionId": self.session.as_ref().map(|s| s.snapshot.session_id.clone()).unwrap_or_default(),
                    "output": "",
                    "error": null
                }));
            }
            "startPortMap" => {
                let rule_id = params.get("id").and_then(Value::as_str).unwrap_or("").to_owned();
                let listen_port = params.get("listenPort").and_then(Value::as_u64).filter(|p| (1024..=65535).contains(p));
                let target_host = params.get("targetHost").and_then(Value::as_str).unwrap_or("").trim().to_owned();
                let target_port = params.get("targetPort").and_then(Value::as_u64).filter(|p| (1..=65535).contains(p));
                let allow_lan = params.get("allowLan").and_then(Value::as_bool).unwrap_or(false);
                if rule_id.is_empty() || target_host.is_empty() || listen_port.is_none() || target_port.is_none() {
                    self.portmap_event(Some("Invalid forwarding rule".into()));
                } else if self.port_rules.contains_key(&rule_id) {
                    self.portmap_event(Some("Forwarding rule already exists".into()));
                } else {
                    match self.ensure_portmap().await {
                        Ok(portmap) => {
                            let bind = if allow_lan { std::net::Ipv4Addr::UNSPECIFIED } else { std::net::Ipv4Addr::LOCALHOST };
                            match portmap.add_rule_on(bind, rule_id.clone(), listen_port.unwrap() as u16, target_host.clone(), target_port.unwrap() as u16).await {
                                Ok(id) => {
                                    let rule = json!({"id": rule_id, "listenAddress": bind.to_string(),
                                        "listenPort": listen_port, "targetHost": target_host,
                                        "targetPort": target_port, "allowLan": allow_lan});
                                    self.port_rules.insert(rule_id, (id, rule));
                                    self.portmap_event(None);
                                }
                                Err(error) => self.portmap_event(Some(error)),
                            }
                        }
                        Err(error) => self.portmap_event(Some(error)),
                    }
                }
            }
            "stopPortMap" => {
                let ids: Vec<String> = match params.get("id").and_then(Value::as_str).filter(|id| !id.is_empty()) {
                    Some(id) => vec![id.to_owned()],
                    None => self.port_rules.keys().cloned().collect(),
                };
                let mut error = None;
                if let Some(portmap) = self.portmap.clone() {
                    for key in ids {
                        if let Some((id, _)) = self.port_rules.remove(&key) {
                            if let Err(reason) = portmap.remove_rule(id).await { error = Some(reason); }
                        }
                    }
                }
                self.portmap_event(error);
            }
            "requestCaptureConsent" | "requestInputConsent" | "stopHost" => {
                let (capture, injection) = self.platform.input_capability();
                event(&self.events, "hostState", json!({
                    "phase": if capture { "waitingConsent" } else { "unsupported" },
                    "capabilities": {
                        "capture": capture,
                        "inputInjection": injection,
                        "background": false,
                        "inputScope": if self.config.is_pc() { "pc" } else { "phone" },
                        "reason": if self.config.is_pc() {
                            "需要目标系统公开的输入授权适配；此包未启用"
                        } else {
                            "此设备不支持全系统输入控制，仅可共享画面"
                        }
                    },
                    "statusText": if capture { "等待系统授权…" } else { "能力不可用" }
                }));
            }
            "startTransfer" => {
                let remote = params.get("remotePath").and_then(Value::as_str).unwrap_or("").to_owned();
                let local = params.get("localPath").and_then(Value::as_str).unwrap_or("").to_owned();
                let upload = params.get("upload").and_then(Value::as_bool).unwrap_or(false);
                if remote.is_empty() || local.is_empty() {
                    tool_event(&self.events, self.session_generation, "transferState", json!({
                        "id": "0", "state": "failed", "transferredBytes": 0, "totalBytes": 0, "localPath": local,
                        "error": "本地路径或远端路径为空"
                    }));
                } else if self.transfer_tasks.iter().any(|task| !task.is_finished()) {
                    tool_event(&self.events, self.session_generation, "transferState", json!({
                        "id": "0", "state": "failed", "transferredBytes": 0, "totalBytes": 0, "localPath": local,
                        "error": "已有文件传输进行中"
                    }));
                } else {
                    match self.ensure_files().await {
                        Ok(files) => {
                            let id = files.allocate_task();
                            let name = remote.rsplit(['/', '\\']).next().unwrap_or("file").to_owned();
                            tool_event(&self.events, self.session_generation, "transferState", json!({
                                "id": id.to_string(),
                                "name": name,
                                "state": "running",
                                "transferredBytes": 0,
                                "totalBytes": 0,
                                "localPath": local.clone(),
                                "remotePath": remote.clone(),
                                "upload": upload
                            }));
                            let events = self.events.clone();
                            let generation = self.session_generation;
                            let remote_for_task = remote.clone();
                            let local_for_task = local.clone();
                            let handle = tokio::spawn(async move {
                                let result = if upload {
                                    files.upload_task(local_for_task, &remote_for_task, id).await
                                } else {
                                    files.download_task(&remote_for_task, local_for_task, id).await
                                };
                                match result {
                                    Ok(()) => tool_event(&events, generation, "transferState", json!({
                                        "id": id.to_string(), "state": "completed"
                                    })),
                                    Err(error) if error == "File transfer canceled" => tool_event(&events, generation, "transferState", json!({
                                        "id": id.to_string(), "state": "canceled"
                                    })),
                                    Err(error) => tool_event(&events, generation, "transferState", json!({
                                        "id": id.to_string(), "state": "failed", "error": error
                                    })),
                                }
                            });
                            self.transfer_tasks.push(handle);
                            self.transfer_tasks.retain(|task| !task.is_finished());
                        }
                        Err(error) => tool_event(&self.events, self.session_generation, "transferState", json!({
                            "id": "0", "state": "failed", "transferredBytes": 0, "totalBytes": 0, "localPath": local,
                            "error": error
                        })),
                    }
                }
            }
            "cancelTransfer" => {
                if let Some(files) = self.files.clone() {
                    files.cancel();
                }

            }
            "logout" => {
                self.login_generation += 1;
                self.devices_generation += 1;
                self.session_generation += 1;
                let _ = self.close_session().await;
                self.login_cancel.store(true, Ordering::Release);
                if let Some(task) = self.login_task.take() { task.abort(); }
                self.credentials = None;
                self.api = None;
                self.devices.clear();
                self.emit_login(LoginSnapshot {
                    phase: "loadingQr".into(),
                    status_text: "".into(),
                    qr_payload: None,
                    polling_active: false,
                    authenticated: false,
                    error: None,
                    generation: self.login_generation,
                });
                self.emit_devices(DevicesSnapshot { phase: "authExpired".into(), devices: Vec::new(), error: None, generation: self.devices_generation });
                self.emit_session(SessionSnapshot { generation: self.session_generation, ..SessionSnapshot::ended() });
            }
            "shutdown" => return true,
            _ => {
                log::warn!("unknown harmony command: {}", command.method);
            }
        }
        false
    }

    async fn handle_internal(&mut self, internal: Internal) {
        match internal {
            Internal::LoginDone(generation, _) if generation != self.login_generation => {},
            Internal::DevicesDone(generation, _) if generation != self.devices_generation => {},
            Internal::JoinFailed(generation, _, _) if generation != self.session_generation => {},
            Internal::SessionOpened(generation, result, _, _, _) if generation != self.session_generation => {
                if let Ok(handle) = result { if let Err(error) = handle.close().await { self.cleanup_error = Some(error); } }
            }
            Internal::LoginDone(_, Ok(creds)) => {
                self.config.device_id = creds.device_id.clone();
                self.config.client_id = creds.client_id.clone();
                self.config.system_id = creds.system_id.clone();
                self.credentials = Some(creds.clone());
                self.api = Some(Arc::new(Api::new(UUAuthClient::new(creds.clone()), BASE_URL)));
                event(&self.events, "credentials", json!({
                    "generation": self.login_generation, "userId": creds.user_id,
                    "deviceId": creds.device_id, "clientId": creds.client_id,
                    "systemId": creds.system_id, "token": creds.token, "csrf": creds.csrf
                }));
                self.emit_login(LoginSnapshot {
                    phase: "authenticated".into(),
                    status_text: "登录成功".into(),
                    qr_payload: None,
                    polling_active: false,
                    authenticated: true,
                    error: None,
                    generation: self.login_generation,
                });
            }
            Internal::LoginDone(_, Err(error)) => {
                if error != "cancelled" {
                    event(&self.events, "loginError", json!({"message": error, "generation": self.login_generation}));
                }
            }
            Internal::DevicesDone(_, Ok(data)) => {
                let mut devices = map_devices(&data);
                // A failed supplemental request must not erase the last list of account devices.
                if data.get("device_groups").is_none() {
                    for previous in self.devices.iter().filter(|device| device.grouped_only) {
                        if !devices.iter().any(|device| device.id == previous.id) {
                            devices.push(previous.clone());
                        }
                    }
                    sort_devices(&mut devices);
                }
                self.devices = devices;
                self.emit_devices(DevicesSnapshot {
                    phase: if self.devices.is_empty() { "empty".into() } else { "ready".into() },
                    devices: self.devices.clone(),
                    error: None,
                    generation: self.devices_generation,
                });
            }
            Internal::DevicesDone(_, Err(error)) => {
                event(&self.events, "deviceList", json!({
                    "phase": "refreshFailed",
                    "devices": self.devices,
                    "error": error,
                    "generation": self.devices_generation
                }));
            }
            Internal::SessionOpened(_, Ok(handle), target_id, target_name, view_only) => {
                self.set_device_controlled(&target_id, false);
                let snapshot = SessionSnapshot {
                    phase: "waitingFirstFrame".into(),
                    session_id: handle.snapshot.session_id.clone(),
                    generation: handle.snapshot.generation,
                    resource_epoch: 0,
                    target_id,
                    target_name,
                    view_only,
                    first_frame_received: false,
                    error: None,
                    video_width: handle.snapshot.video_width,
                    video_height: handle.snapshot.video_height,
                };
                handle.finish_opening(&self.opening_cleanup);
                self.session = Some(handle);

                self.emit_session(snapshot);
                self.sync_session_video_settings().await;
            }
            Internal::JoinFailed(_, target_id, error) => {
                if matches!(error, crate::viewer::api::Error::Api(2002, _)) {
                    self.set_device_controlled(&target_id, true);
                }
                self.emit_session(SessionSnapshot {
                    generation: self.session_generation,
                    error: Some(error.to_string()),
                    ..SessionSnapshot::ended()
                });
            }
            Internal::SessionOpened(_, Err(error), _target_id, _target_name, _view_only) => {
                self.emit_session(SessionSnapshot {
                    phase: "ended".into(),
                    error: Some(error),
                    generation: self.session_generation,
                    ..SessionSnapshot::ended()
                });
            }
        }
    }

    fn emit_login(&self, snapshot: LoginSnapshot) {
        event(&self.events, "loginState", serde_json::to_value(snapshot).unwrap_or(Value::Null));
    }

    fn emit_devices(&self, snapshot: DevicesSnapshot) {
        event(&self.events, "deviceList", serde_json::to_value(snapshot).unwrap_or(Value::Null));
    }

    fn set_device_controlled(&mut self, target_id: &str, controlled: bool) {
        let Some(device) = self.devices.iter_mut().find(|device| device.id == target_id) else { return; };
        let value = controlled.then_some(true);
        if device.controlled == value { return; }
        device.controlled = value;
        device.status_text = if controlled { "被控中".into() } else if !device.online { "离线".into() }
            else if device.busy == Some(true) { "在线 · 使用中".into() } else { "在线 · 可连接".into() };
        self.emit_devices(DevicesSnapshot {
            phase: "ready".into(), devices: self.devices.clone(), error: None, generation: self.devices_generation,
        });
    }

    fn emit_session(&self, snapshot: SessionSnapshot) {
        event(&self.events, "sessionState", serde_json::to_value(snapshot).unwrap_or(Value::Null));
    }

    fn video_for_viewport(&self, mut video: VideoSettings) -> VideoSettings {
        let (width, height) = self.surface_size;
        video.resolution = video.resolution.resized(width, height, self.config.device_type.eq_ignore_ascii_case("phone"));
        video.limited(self.settings.decoder)
    }

    async fn sync_session_video_settings(&self) {
        if let Some(handle) = &self.session {
            if handle.tx.send(SessionCommand::VideoSettings(self.settings.video)).await.is_err() {
                event(&self.events, "videoSettingsError", json!({"generation": self.session_generation,
                    "message": "画面设置发送失败，请重试。"}));
            }
        }
    }

    fn with_session(&self, action: impl FnOnce(&SessionHandle)) {
        if let Some(handle) = &self.session {
            action(handle);
        }
    }

    fn portmap_event(&self, error: Option<String>) {
        let rules: Vec<Value> = self.port_rules.values().map(|(_, rule)| rule.clone()).collect();
        tool_event(&self.events, self.session_generation, "portMapState", json!({
            "phase": if rules.is_empty() { if error.is_some() { "failed" } else { "stopped" } } else { "running" },
            "rule": rules.last(), "rules": rules, "statusText": "", "error": error, "boundAddress": ""
        }));
    }

    async fn stop_tools(&mut self) -> Result<(), String> {
        let mut result = Ok(());
        if let Some(files) = self.files.take() {
            files.cancel();
        }
        if let Some(task) = self.files_progress.take() {
            task.abort();
        }
        for task in self.transfer_tasks.drain(..) {
            task.abort();
        }
        if let Some(terminal) = self.terminal.take() {
            let id = self.terminal_session;
            let _ = terminal.close(id).await;
        }
        if let Some(task) = self.terminal_events.take() {
            task.abort();
        }
        if let Some(portmap) = self.portmap.take() {
            drop(portmap);
        }
        for handle in self.tool_sessions.drain(..) { result = handle.close().await.and(result); }
        self.files_path = ":/".into();
        self.files_entries.clear();
        self.terminal_session = 0;
        self.port_rules.clear();
        result
    }

    async fn open_tool_peer(&mut self, capture_type: u32) -> Result<ToolLink, String> {
        let api = self.api.clone().ok_or("请先登录")?;
        let target = self.target.clone().ok_or("请先选择远端设备")?;
        let room = match &target {
            ConnectionTarget::Device(id) => api.join(id, false, true).await,
            ConnectionTarget::Share(id, code) => api.join_share(id, code).await,
        }.map_err(|error| error.to_string())?;
        let mut shape = self.shape();
        shape.capture_type = capture_type;
        shape.feature_flag.clear();
        if capture_type != 5 {
            shape.decoders.clear(); shape.codecs.clear(); shape.displays.clear(); shape.display_modes.clear();
        }
        let credentials = self.credentials.as_ref().ok_or("请先登录")?;
        let target_id = match target { ConnectionTarget::Device(id) | ConnectionTarget::Share(id, _) => id };
        let handle = session::open_tracked(&api, &room, &shape, &credentials.device_id, &credentials.client_id,
            OpenOptions { view_only: false, target_id, target_name: String::new(), mac: false, capture_cursor: false,
                video: self.settings.video, touch_mode: self.settings.touch_mode, audio_muted: true },
            self.events.clone(), self.platform, self.session_generation,
            Duration::from_millis(u64::from(self.config.signaling_timeout_ms)), Some(&self.opening_cleanup)).await?;
        if let Err(error) = handle.wait_ready().await { let _ = handle.close().await; return Err(error); }
        handle.finish_opening(&self.opening_cleanup);
        let link = handle.tools.clone();
        self.tool_sessions.push(handle);
        Ok(link)
    }

    async fn ensure_files(&mut self) -> Result<Arc<Files>, String> {
        if let Some(files) = self.files.clone() {
            return Ok(files);
        }
        let link = self.open_tool_peer(5).await?;
        let (transport, rx) = link.attach();
        let (files, mut progress) = Files::new(transport, rx);
        let files = Arc::new(files);
        let events = self.events.clone();
        let generation = self.session_generation;
        let task = tokio::spawn(async move {
            while let Some(update) = progress.recv().await {
                tool_event(&events, generation, "transferState",
                    json!({
                        "id": update.task.to_string(),
                        "state": "running",
                        "transferredBytes": update.transferred,
                        "totalBytes": update.total
                    }),
                );
            }
        });
        self.files = Some(files.clone());
        self.files_progress = Some(task);
        Ok(files)
    }

    async fn ensure_terminal(&mut self) -> Result<Arc<Terminal>, String> {
        if let Some(terminal) = self.terminal.clone() {
            return Ok(terminal);
        }
        let link = self.open_tool_peer(8).await?;
        let (transport, rx) = link.attach();
        let (terminal, mut events) = Terminal::new(transport, rx);
        let terminal = Arc::new(terminal);
        let queue = self.events.clone();
        let generation = self.session_generation;
        let session_id = self
            .session
            .as_ref()
            .map(|handle| handle.snapshot.session_id.clone())
            .unwrap_or_default();
        let task = tokio::spawn(async move {
            let mut text_streams: BTreeMap<u32, super::text_stream::Utf8Stream> = BTreeMap::new();
            while let Some(update) = events.recv().await {
                match update {
                    TerminalEvent::Output { session, data } => {
                        if !text_streams.contains_key(&session) && text_streams.len() >= 32 {
                            if let Some(id) = text_streams.keys().next().copied() { text_streams.remove(&id); }
                        }
                        tool_event(&queue, generation, "terminalOutput",
                            json!({"ptyId":session, "text": text_streams.entry(session).or_default().push(&data)}),
                        );
                    }
                    TerminalEvent::Exit { session, code } => {
                        text_streams.remove(&session);
                        tool_event(&queue, generation, "terminalState",
                            json!({
                                "phase": "disconnected",
                                "ptyId": session,
                                "sessionId": session_id.clone(),
                                "output": "",
                                "error": format!("远端终端已退出（{code}）")
                            }),
                        );
                    }
                    TerminalEvent::Error { session } => {
                        tool_event(&queue, generation, "terminalState",
                            json!({
                                "phase": "failed",
                                "ptyId": session,
                                "sessionId": session_id.clone(),
                                "output": "",
                                "error": "远端终端报告错误"
                            }),
                        );
                    }
                }
            }
        });
        self.terminal = Some(terminal.clone());
        self.terminal_events = Some(task);
        Ok(terminal)
    }

    async fn ensure_portmap(&mut self) -> Result<Arc<PortMap>, String> {
        if let Some(portmap) = self.portmap.clone() {
            return Ok(portmap);
        }
        let link = self.open_tool_peer(9).await?;
        let (transport, rx) = link.attach();
        let portmap = Arc::new(PortMap::new(transport, rx));
        self.portmap = Some(portmap.clone());
        Ok(portmap)
    }

    fn files_event(&self, phase: &str, error: Option<String>) {
        let entries: Vec<Value> = self
            .files_entries
            .iter()
            .map(|entry| {
                json!({
                    "name": entry.name,
                    "path": entry.path,
                    "isDirectory": entry.kind == 0 || entry.kind == 3,
                    "sizeBytes": entry.size
                })
            })
            .collect();
        tool_event(&self.events, self.session_generation, "filesState",
            json!({
                "phase": phase,
                "path": self.files_path,
                "entries": entries,
                "transfers": [],
                "error": error
            }),
        );
    }

    async fn open_remote_files(&mut self, path: String) {
        if self.transfer_tasks.iter().any(|task| !task.is_finished()) {
            self.files_path = path;
            self.files_event("ready", Some("文件传输进行中，完成后再刷新目录".into()));
            return;
        }
        let files = match self.ensure_files().await {
            Ok(files) => files,
            Err(error) => {
                self.files_path = path;
                self.files_entries.clear();
                self.files_event("failed", Some(error));
                return;
            }
        };
        self.files_path = path.clone();
        match files.list_dir(&path).await {
            Ok(entries) => {
                self.files_entries = entries;
                self.files_event("ready", None);
            }
            Err(error) => {
                self.files_entries.clear();
                self.files_event("failed", Some(error));
            }
        }
    }

    async fn open_remote_terminal(&mut self, attach: Option<u32>) {
        let terminal = match self.ensure_terminal().await {
            Ok(terminal) => terminal,
            Err(error) => {
                tool_event(&self.events, self.session_generation, "terminalState", json!({
                    "phase": "failed",
                    "sessionId": self.session.as_ref().map(|s| s.snapshot.session_id.clone()).unwrap_or_default(),
                    "output": "",
                    "error": error
                }));
                return;
            }
        };
        let session_id = self
            .session
            .as_ref()
            .map(|handle| handle.snapshot.session_id.clone())
            .unwrap_or_default();
        if let Err(error) = terminal.check_env().await {
            tool_event(&self.events, self.session_generation, "terminalState", json!({
                "phase": "failed",
                "sessionId": session_id,
                "output": "",
                "error": error
            }));
            return;
        }
        let result = if let Some(id) = attach { terminal.attach(id, 80, 24).await } else { terminal.open(80, 24).await };
        match result {
            Ok(id) => {
                self.terminal_session = id;
                tool_event(&self.events, self.session_generation, "terminalState", json!({
                    "phase": "ready",
                    "ptyId": id,
                    "sessionId": session_id,
                    "output": "",
                    "error": null
                }));
            }
            Err(error) => {
                tool_event(&self.events, self.session_generation, "terminalState", json!({
                    "phase": "failed",
                    "sessionId": session_id,
                    "output": "",
                    "error": error
                }));
            }
        }
    }

    async fn close_session(&mut self) -> Result<(), String> {
        if let Some(task) = self.connect_task.take() {
            task.abort();
            let _ = task.await;
        }
        let mut result = self.stop_tools().await;
        result = self.opening_cleanup.wait().await.and(result);
        if let Some(error) = self.cleanup_error.take() { result = Err(error); }
        self.target = None;
        if let Some(handle) = self.session.take() { return handle.close().await.and(result); }
        result
    }

    fn shape(&self) -> Shape {
        video_shape(self.config.platform, self.settings.video, self.settings.decoder)
    }

    async fn shutdown(&mut self) {
        self.login_cancel.store(true, Ordering::Release);
        if let Some(task) = self.login_task.take() {
            task.abort();
        }
        let _ = self.close_session().await;
    }
}

fn video_shape(platform: u32, video: VideoSettings, caps: DecoderCapabilities) -> Shape {
    let (requested_width, requested_height) = video.resolution.size();
    let width = requested_width.min(caps.max_width);
    let height = requested_height.min(caps.max_height);
    // Start at 60 fps; decoders and display modes advertise the probed ceiling
    // (never more than this device proved it can decode). The saved choice is
    // applied with the first CaptureSettingRequest.
    let fps = 60.min(caps.max_fps);
    let max_fps = caps.max_fps;
    let mut chromas = vec![CHROMA_420];
    if caps.chroma_444 {
        chromas.push(CHROMA_444);
    }
    let codec_ids = if caps.hevc { vec![2, 1] } else { vec![1] };
    let decoders = codec_ids.iter().flat_map(|codec| chromas
        .iter()
        .copied()
        .map(|chroma| Decoder {
            fps: max_fps,
            codec: *codec,
            width: caps.max_width,
            height: caps.max_height,
            chroma,
        }))
        .collect();
    let codecs = codec_ids.iter().flat_map(|codec| chromas
        .iter()
        .copied()
        .map(|chroma_sampling| WireCodec {
            video_codec: *codec,
            chroma_sampling,
            codec_impl: 34,
            bit_depth: 8,
            width: caps.max_width,
            height: caps.max_height,
        }))
        .collect();
    let mut display_modes = vec![[width, height, fps]];
    if max_fps > fps {
        display_modes.push([width, height, max_fps]);
    }
    Shape {
        capture_type: 1,
        platform: platform.clamp(3, 4),
        client_version: "4.42.0".into(),
        width,
        height,
        fps,
        chroma: CHROMA_420,
        decoders,
        display_modes,
        displays: vec![Display {
            id: 1,
            fps: max_fps,
            r#type: 0,
            hdr: 0,
        }],
        codecs,
        feature_flag: wire::VIEWER_FEATURES.to_vec(),
    }
}

fn map_devices(data: &Value) -> Vec<DeviceItem> {
    let mut devices = Vec::new();
    let groups = &data["device_groups"];
    let current = groups.get("current_device_id").and_then(Value::as_str);
    let mut seen = BTreeSet::new();
    let lists = [
        (data, "my_binded_devices", false, None),
        (data, "others_shared_devices", true, None),
        (groups, "desktop_devices", false, Some("电脑")),
        (groups, "mobile_devices", false, Some("移动设备")),
        (groups, "tv_devices", false, Some("电视")),
    ];
    for (source, key, shared, group_label) in lists {
        let Some(list) = source.get(key).and_then(Value::as_array) else {
            continue;
        };
        let grouped_only = group_label.is_some();
        for item in list {
            let Some(id) = item.get("device_id").and_then(Value::as_str).filter(|id| !id.is_empty()) else {
                continue;
            };
            if current == Some(id) || !seen.insert(id) { continue; }
            let name = item
                .get("alias")
                .and_then(Value::as_str)
                .filter(|value| !value.is_empty())
                .unwrap_or(id)
                .to_owned();
            let platform = item.get("platform").and_then(Value::as_i64).unwrap_or(0);
            let status = item.get("status").and_then(Value::as_str);
            let online = status == Some("CONNECTED");
            let busy = item.get("participants_info").and_then(Value::as_array).map(|participants| !participants.is_empty());
            let platform_name = match platform {
                1 => "Windows",
                2 => "Android",
                3 => "iOS",
                4 => "macOS",
                5 => "电视",
                51 => "云电脑",
                _ => group_label.unwrap_or("未知平台"),
            };
            let can_connect = !grouped_only && item.get("controlled_support").and_then(Value::as_bool) != Some(false);
            let mut capabilities = if can_connect {
                match platform {
                    1 => vec!["desktop", "files", "terminal", "textInput"],
                    4 => vec!["desktop", "files", "terminal"],
                    _ => vec!["desktop"],
                }
            } else { Vec::new() };
            if platform == 1 && can_connect && !shared && !online && status.is_some_and(|value| !value.trim().is_empty())
                && item.get("support_wol").and_then(Value::as_bool) == Some(true)
            {
                capabilities.push("wake");
            }
            let status_text = if !online { "离线" } else if !can_connect { "在线" }
                else if busy == Some(true) { "在线 · 使用中" } else { "在线 · 可连接" };
            let connect_label = if !can_connect { "不可远控" } else if online { "连接" } else { "设备离线" };
            devices.push(DeviceItem {
                id: id.to_owned(),
                name,
                platform: platform_name.into(),
                online,
                status_text: status_text.into(),
                capabilities: capabilities.into_iter().map(str::to_owned).collect(),
                connect_label: connect_label.into(),
                busy,
                controlled: None,
                shared,
                grouped_only,
            });
        }
    }
    sort_devices(&mut devices);
    devices
}

fn sort_devices(devices: &mut [DeviceItem]) {
    devices.sort_by(|a, b| {
        b.online
            .cmp(&a.online)
            .then_with(|| a.name.cmp(&b.name))
            .then_with(|| a.id.cmp(&b.id))
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn device_service() -> CoreService {
        let (internal_tx, _) = mpsc::unbounded_channel();
        CoreService {
            config: serde_json::from_value(json!({})).unwrap(), events: Default::default(),
            platform: Platform::new(crate::harmony::platform::PlatformOps {
                user: std::ptr::null_mut(), submit_video: None, submit_audio: None,
                attach_surface: None, detach_surface: None, input_capability: None,
                request_input_injection: None, submit_audio_packet: None, set_audio_muted: None,
            }),
            api: None, credentials: None,
            devices: map_devices(&json!({"my_binded_devices":[
                {"device_id":"target","status":"CONNECTED","participants_info":[]},
                {"device_id":"other","status":"CONNECTED","participants_info":[{}]}
            ]})),
            devices_generation: 3, login_generation: 0, login_cancel: Arc::new(AtomicBool::new(false)),
            login_task: None, connect_task: None, opening_cleanup: Default::default(), cleanup_error: None,
            session: None, session_generation: 7,
            settings: SettingsState { video: VideoSettings::default(), decoder: DecoderCapabilities::default(),
                touch_mode: TouchMode::Trackpad, clipboard_policy: "manual".into(), view_only: false, audio_muted: false },
            surface_size: (1280, 720), internal_tx, tool_sessions: Vec::new(), target: None,
            files: None, files_path: ":/".into(), files_entries: Vec::new(), files_progress: None,
            transfer_tasks: Vec::new(), terminal: None, terminal_session: 0, terminal_events: None,
            portmap: None, port_rules: BTreeMap::new(),
        }
    }

    #[tokio::test]
    async fn phone_portrait_window_resolution_uses_viewport_width() {
        let mut service = device_service();
        service.config.device_type = "phone".into();
        for (method, params) in [
            ("attachSurface", json!({"surfaceId":"test","width":1260,"height":2800})),
            ("setVideoProfile", json!({"profile":"window"})),
        ] {
            service.handle(Envelope { id: 0, method: method.into(), params }).await;
        }
        assert_eq!(service.settings.video.resolution.size(), (1260, 708));

        service.handle(Envelope { id: 0, method: "resizeViewport".into(),
            params: json!({"width":1600,"height":900}) }).await;
        assert_eq!(service.settings.video.resolution.size(), (1600, 900));

        service.handle(Envelope { id: 0, method: "resizeViewport".into(),
            params: json!({"width":1260,"height":2800}) }).await;
        assert_eq!(service.settings.video.resolution.size(), (1260, 708));
    }

    #[tokio::test]
    async fn device_controlled_requires_structured_join_2002_for_the_current_target() {
        let mut service = device_service();
        service.handle_internal(Internal::JoinFailed(7, "target".into(), crate::viewer::api::Error::Api(2002, String::new()))).await;
        let target = service.devices.iter().find(|device| device.id == "target").unwrap();
        assert_eq!(target.controlled, Some(true));
        assert_eq!(target.status_text, "被控中");
        assert_eq!(target.busy, Some(false));
        assert_eq!(service.devices.iter().find(|device| device.id == "other").unwrap().controlled, None);
        let events = service.events.lock().unwrap();
        let event: Value = serde_json::from_str(&events[0]).unwrap();
        assert_eq!(event["type"], "deviceList");
        let data: Value = serde_json::from_str(event["data"].as_str().unwrap()).unwrap();
        assert_eq!(data["generation"], 3);
        assert_eq!(data["devices"].as_array().unwrap().iter().find(|device| device["id"] == "target").unwrap()["controlled"], true);
    }

    #[tokio::test]
    async fn device_controlled_ignores_non_2002_messages_and_stale_join_failures() {
        let mut service = device_service();
        for failure in [
            Internal::JoinFailed(7, "target".into(), crate::viewer::api::Error::Api(5000, "2002 被控中".into())),
            Internal::JoinFailed(6, "target".into(), crate::viewer::api::Error::Api(2002, String::new())),
        ] { service.handle_internal(failure).await; }
        assert!(service.devices.iter().all(|device| device.controlled.is_none()));
        assert!(!service.events.lock().unwrap().iter().any(|raw| {
            serde_json::from_str::<Value>(raw).unwrap()["type"] == "deviceList"
        }));
        let data = serde_json::to_value(&service.devices).unwrap();
        assert!(data.as_array().unwrap().iter().all(|device| device.get("controlled").is_none()));
    }

    #[tokio::test]
    async fn device_controlled_is_cleared_by_a_successful_device_refresh() {
        let mut service = device_service();
        service.handle_internal(Internal::JoinFailed(7, "target".into(), crate::viewer::api::Error::Api(2002, String::new()))).await;
        service.handle_internal(Internal::DevicesDone(2, Ok(json!({})))).await;
        assert_eq!(service.devices.iter().find(|device| device.id == "target").unwrap().controlled, Some(true));
        service.handle_internal(Internal::DevicesDone(3, Ok(json!({"my_binded_devices":[
            {"device_id":"target","status":"CONNECTED","participants_info":[{}]}
        ]})))).await;
        assert_eq!(service.devices[0].controlled, None);
        assert_eq!(service.devices[0].busy, Some(true));
        assert_eq!(service.devices[0].status_text, "在线 · 使用中");
    }

    #[test]
    fn device_controlled_clear_restores_the_reported_occupancy() {
        let mut service = device_service();
        for (id, status) in [("target", "在线 · 可连接"), ("other", "在线 · 使用中")] {
            service.set_device_controlled(id, true);
            service.set_device_controlled(id, false);
            let device = service.devices.iter().find(|device| device.id == id).unwrap();
            assert_eq!(device.controlled, None);
            assert_eq!(device.status_text, status);
        }
    }

    #[test]
    fn device_occupancy_preserves_unknown_and_maps_participants() {
        let devices = map_devices(&json!({"my_binded_devices":[
            {"device_id":"unknown","status":"CONNECTED"},
            {"device_id":"free","status":"CONNECTED","participants_info":[]},
            {"device_id":"busy","status":"CONNECTED","participants_info":[{}]},
            {"device_id":"invalid","status":"CONNECTED","participants_info":null}
        ]}));
        for (id, busy) in [("unknown",None),("free",Some(false)),("busy",Some(true)),("invalid",None)] {
            assert_eq!(devices.iter().find(|device| device.id==id).unwrap().busy,busy);
        }
    }

    #[test]
    fn official_device_groups_keep_all_categories_without_promoting_devices_to_controllable() {
        let devices = map_devices(&json!({
            "my_binded_devices": [
                {"device_id":"pc","alias":"Controlled PC","platform":1,"status":"CONNECTED"},
                {"device_id":"blocked","platform":1,"status":"CONNECTED","controlled_support":false}
            ],
            "others_shared_devices": [{"device_id":"shared","platform":4,"status":"CONNECTED"}],
            "device_groups": {
                "current_device_id":"local",
                "desktop_devices":[{"device_id":"pc","alias":"Grouped PC","status":"CONNECTED"},
                    {"device_id":"desktop","status":"CONNECTED"}],
                "mobile_devices":[{"device_id":"phone","alias":"My phone","platform":2,"status":"CONNECTED"},
                    {"device_id":"ipad","platform":3,"status":"DISCONNECTED"},
                    {"device_id":"local","status":"CONNECTED"},{}],
                "tv_devices":[{"device_id":"tv","status":"DISCONNECTED"}]
            }
        }));
        assert_eq!(devices.len(), 7);
        assert_eq!(devices.iter().find(|d| d.id == "pc").unwrap().name, "Controlled PC");
        assert!(devices.iter().find(|d| d.id == "shared").unwrap().shared);
        for id in ["blocked", "desktop", "phone", "ipad", "tv"] {
            assert!(devices.iter().find(|d| d.id == id).unwrap().capabilities.is_empty());
        }
        assert!(devices.iter().find(|d| d.id == "phone").unwrap().online);
        assert_eq!(devices.iter().find(|d| d.id == "phone").unwrap().platform, "Android");
        assert_eq!(devices.iter().find(|d| d.id == "ipad").unwrap().platform, "iOS");
        assert!(!devices.iter().find(|d| d.id == "tv").unwrap().online);
        assert!(!devices.iter().any(|d| d.id == "local"));
    }

    #[tokio::test]
    async fn wake_capability_and_command_require_an_eligible_owned_offline_windows_device() {
        let mut service = device_service();
        service.devices = map_devices(&json!({
            "my_binded_devices":[
                {"device_id":"eligible","platform":1,"status":"OFFLINE","support_wol":true},
                {"device_id":"online","platform":1,"status":"CONNECTED","support_wol":true},
                {"device_id":"unknown-status","platform":1,"support_wol":true},
                {"device_id":"empty-status","platform":1,"status":"","support_wol":true},
                {"device_id":"uncontrollable","platform":1,"status":"DISCONNECTED","support_wol":true,"controlled_support":false},
                {"device_id":"unsupported","platform":1,"status":"DISCONNECTED","support_wol":false},
                {"device_id":"missing-flag","platform":1,"status":"DISCONNECTED"},
                {"device_id":"malformed-flag","platform":1,"status":"DISCONNECTED","support_wol":"true"},
                {"device_id":"mac","platform":4,"status":"DISCONNECTED","support_wol":true}
            ],
            "others_shared_devices":[{"device_id":"shared","platform":1,"status":"DISCONNECTED","support_wol":true}],
            "device_groups":{"desktop_devices":[{"device_id":"group-only","platform":1,"status":"DISCONNECTED","support_wol":true}]}
        }));
        assert_eq!(service.devices.iter().filter(|device| device.capabilities.iter().any(|value| value == "wake"))
            .map(|device| device.id.as_str()).collect::<Vec<_>>(), vec!["eligible"]);

        service.api = Some(Arc::new(Api::new(UUAuthClient::new(Credentials {
            user_id: "synthetic-user".into(), token: "synthetic-auth".into(), ..Default::default()
        }), "http://127.0.0.1:1")));
        service.config.device_id = "eligible".into();
        for id in ["unknown", "online", "unknown-status", "empty-status", "uncontrollable", "shared", "group-only", "eligible"] {
            service.handle(Envelope { id: 0, method: "wakeDevice".into(), params: json!({"deviceId":id}) }).await;
            let raw = service.events.lock().unwrap().pop_front().unwrap();
            let event: Value = serde_json::from_str(&raw).unwrap();
            let result: Value = serde_json::from_str(event["data"].as_str().unwrap()).unwrap();
            assert_eq!(event["type"], "operationResult");
            assert_eq!(result["operation"], "wakeDevice");
            assert_eq!(result["deviceId"], id);
            assert_eq!(result["success"], false);
            assert_eq!(result["error"], crate::i18n::s("该设备当前不可远程开机。", "Remote power-on is unavailable for this device."));
        }
    }

    #[tokio::test]
    async fn failed_group_refresh_preserves_devices_until_the_next_group_reply() {
        let mut service = device_service();
        service.handle_internal(Internal::DevicesDone(3, Ok(json!({"device_groups":{"mobile_devices":[
            {"device_id":"phone","platform":2,"status":"CONNECTED"}
        ]}})))).await;
        service.handle_internal(Internal::DevicesDone(3, Ok(json!({"my_binded_devices":[
            {"device_id":"pc","platform":1,"status":"CONNECTED"}
        ]})))).await;
        assert!(service.devices.iter().any(|device| device.id == "pc"));
        assert!(service.devices.iter().any(|device| device.id == "phone"));
        service.handle_internal(Internal::DevicesDone(3, Ok(json!({"device_groups":{"mobile_devices":[]}})))).await;
        assert!(!service.devices.iter().any(|device| device.id == "phone"));
    }

    #[tokio::test]
    async fn disconnect_acknowledges_cleanup_after_the_ended_state() {
        let events: EventQueue = Default::default();
        let (tx, rx) = mpsc::unbounded_channel();
        for method in ["disconnect", "shutdown"] {
            tx.send(Envelope { id: 0, method: method.into(), params: Value::Null }).unwrap();
        }
        drop(tx);
        let platform = Platform::new(crate::harmony::platform::PlatformOps {
            user: std::ptr::null_mut(), submit_video: None, submit_audio: None,
            attach_surface: None, detach_surface: None, input_capability: None,
            request_input_injection: None, submit_audio_packet: None, set_audio_muted: None,
        });
        CoreService::run(serde_json::from_value(json!({})).unwrap(), events.clone(), platform, rx).await;
        let events: Vec<Value> = events.lock().unwrap().iter().map(|raw| serde_json::from_str(raw).unwrap()).collect();
        let ack = events.iter().position(|value| value["type"] == "operationResult" &&
            serde_json::from_str::<Value>(value["data"].as_str().unwrap()).unwrap() ==
                json!({"operation":"disconnect", "success":true})).expect("disconnect cleanup completion was not acknowledged");
        let state: Value = serde_json::from_str(events[ack - 1]["data"].as_str().unwrap()).unwrap();
        assert_eq!(events[ack - 1]["type"], "sessionState");
        assert_eq!(state["phase"], "ended");
    }

    #[tokio::test]
    async fn queued_credentials_and_view_only_are_applied_before_connect() {
        for _ in 0..32 {
            let events: EventQueue = Default::default();
            let (tx, rx) = mpsc::unbounded_channel();
            for (method, params) in [
                ("setCredentials", serde_json::to_value(Credentials::default()).unwrap()),
                ("setViewOnly", json!({"viewOnly": true})),
                ("connect", json!({"deviceId": "synthetic-device"})),
                ("shutdown", Value::Null),
            ] {
                tx.send(Envelope { id: 0, method: method.into(), params }).unwrap();
            }
            drop(tx);
            let platform = Platform::new(crate::harmony::platform::PlatformOps {
                user: std::ptr::null_mut(), submit_video: None, submit_audio: None,
                attach_surface: None, detach_surface: None, input_capability: None,
                request_input_injection: None, submit_audio_packet: None, set_audio_muted: None,
            });
            // The current-thread runtime aborts the opening task before it can
            // run: this checks command ordering without contacting a server.
            let config: CoreConfig = serde_json::from_value(json!({})).unwrap();
            tokio::time::timeout(Duration::from_secs(2), CoreService::run(config, events.clone(), platform, rx))
                .await.expect("queued command cleanup timed out");
            let connecting = events.lock().unwrap().iter().find_map(|raw| {
                let event: Value = serde_json::from_str(raw).ok()?;
                if event["type"] != "sessionState" { return None; }
                let state: Value = serde_json::from_str(event["data"].as_str()?).ok()?;
                (state["phase"] == "connecting").then_some(state)
            });
            let state = connecting.expect("queued credentials were cancelled before connect");
            assert_eq!(state["viewOnly"], true, "queued readonly setting was cancelled before connect");
        }
    }

    #[test]
    fn shape_advertises_144fps_and_true_color_capabilities() {
        let shape = video_shape(
            3,
            VideoSettings {
                resolution: crate::harmony::video::Resolution::Size(1920, 1080),
                ..VideoSettings::default()
            },
            DecoderCapabilities { max_fps: 144, chroma_444: true, max_width: 3840, max_height: 2160, ..Default::default() },
        );
        shape.validate_session().unwrap();
        assert_eq!((shape.width, shape.height, shape.fps), (1920, 1080, 60));
        assert_eq!(shape.display_modes, vec![[1920, 1080, 60], [1920, 1080, 144]]);
        assert!(shape.decoders.iter().all(|decoder| decoder.fps == 144));
        assert!(shape.decoders.iter().all(|decoder| (decoder.width, decoder.height) == (3840, 2160)));
        assert!(shape.codecs.iter().all(|codec| (codec.width, codec.height) == (3840, 2160)));
        assert!(shape.decoders.iter().any(|decoder| decoder.chroma == CHROMA_444));
        assert!(shape.decoders.iter().any(|decoder| decoder.chroma == CHROMA_420));
        assert!(shape.codecs.iter().any(|codec| codec.chroma_sampling == CHROMA_444));
        // The initial 4:2:0 default means the first frame stays compatible until
        // the saved CaptureSettingRequest arrives.
        assert_eq!(shape.chroma, CHROMA_420);
    }

    #[test]
    fn shape_without_a_device_probe_stays_at_420_and_60fps() {
        let shape = video_shape(
            3,
            VideoSettings {
                resolution: crate::harmony::video::Resolution::Size(1920, 1080),
                ..VideoSettings::default()
            },
            DecoderCapabilities::default(),
        );
        shape.validate_session().unwrap();
        assert_eq!(shape.display_modes, vec![[1920, 1080, 60]]);
        assert!(shape.decoders.iter().all(|decoder| decoder.fps == 60));
        assert!(shape.decoders.iter().all(|decoder| decoder.chroma == CHROMA_420));
        assert!(shape.codecs.iter().all(|codec| codec.chroma_sampling == CHROMA_420));
        assert_eq!(shape.displays[0].fps, 60);
    }
}
