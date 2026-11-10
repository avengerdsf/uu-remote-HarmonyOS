//! Controller session for HarmonyOS: signaling, ICE/WebRTC, video RTP reassembly
//! and input. Reuses the viewer wire shapes, signal client and RTP receiver.

use crate::harmony::input::{InputTranslator, TouchMode};
use crate::harmony::platform::Platform;
use crate::harmony::tools::{channel_transport, Packet, Transport};
use crate::harmony::video::{self, VideoSettings};
use crate::harmony::{event, EventQueue, SessionSnapshot};
use crate::viewer::api::Api;
use crate::viewer::clipboard_state::SyncState;
use crate::viewer::media::{self, Codec};
use crate::viewer::signal::Signal;
use crate::viewer::wire::{self, Shape, CHANNELS};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, Weak};
use std::time::{Duration, Instant};
use tokio::sync::mpsc;
use webrtc::api::interceptor_registry::register_default_interceptors;
use webrtc::api::media_engine::MediaEngine;
use webrtc::api::setting_engine::SettingEngine;
use webrtc::api::APIBuilder;
use webrtc::data_channel::data_channel_init::RTCDataChannelInit;
use webrtc::data_channel::data_channel_message::DataChannelMessage;
use webrtc::data_channel::RTCDataChannel;
use webrtc::ice_transport::ice_candidate::RTCIceCandidateInit;
use webrtc::ice_transport::ice_credential_type::RTCIceCredentialType;
use webrtc::ice_transport::ice_server::RTCIceServer;
use webrtc::peer_connection::configuration::RTCConfiguration;
use webrtc::peer_connection::peer_connection_state::RTCPeerConnectionState;
use webrtc::peer_connection::sdp::session_description::RTCSessionDescription;
use webrtc::peer_connection::RTCPeerConnection;
use webrtc::rtcp::payload_feedbacks::picture_loss_indication::PictureLossIndication;
use webrtc::rtp_transceiver::rtp_codec::{RTCRtpCodecCapability, RTCRtpCodecParameters, RTPCodecType};
use webrtc::rtp_transceiver::rtp_transceiver_direction::RTCRtpTransceiverDirection;
use webrtc::rtp_transceiver::RTCRtpTransceiverInit;
use webrtc::track::track_remote::TrackRemote;

#[path = "remote_unlock.rs"]
pub(super) mod remote_unlock;

pub enum SessionCommand {
    Input(String),
    Gamepad(Option<crate::viewer::native_gamepad::State>),
    Text(String),
    Release,
    Rendered,
    ViewOnly(bool),
    Resize(u32, u32),
    VideoSettings(VideoSettings),
    TouchMode(TouchMode),
    AudioMuted(bool),
    Clipboard(String),
    RemoteAction(super::actions::RemoteAction),
    UnlockRemote(u64, remote_unlock::Secret),
    Close,
}

pub struct SessionHandle {
    pub tx: mpsc::Sender<SessionCommand>,
    task: Option<tokio::task::JoinHandle<()>>,
    pub snapshot: SessionSnapshot,
    pub tools: ToolLink,
    peer: Arc<Peer>,
    signal_closed: tokio::sync::watch::Receiver<Option<crate::viewer::signal::CloseReport>>,
}

impl SessionHandle {
    pub fn finish_opening(&self, cleanup: &crate::viewer::signal::CleanupBarrier) {
        cleanup.detach(&self.signal_closed);
    }
    pub async fn wait_ready(&self) -> Result<(), String> {
        let ready = async {
            loop {
                if self.task.as_ref().is_none_or(|task| task.is_finished()) { return Err("Tool connection closed".into()); }
                let data_channel = if self.peer.capture_type == 8 { 4 } else { 3 };
                let open = [0, data_channel].iter().all(|index|
                    self.peer.tools.channels[*index].ready_state() ==
                        webrtc::data_channel::data_channel_state::RTCDataChannelState::Open);
                if open && self.peer.echo_received.load(Ordering::Acquire) { return Ok(()); }
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        };
        tokio::time::timeout(Duration::from_secs(30), ready).await.map_err(|_| "Tool connection timed out")?
    }

    pub async fn close(mut self) -> Result<(), String> {
        let _ = self.tx.try_send(SessionCommand::Close);
        let result = if let Some(task) = self.task.as_mut() {
            Self::finish_close(task, &self.peer, &mut self.signal_closed).await
        } else { Ok(()) };
        self.task.take();
        result
    }

    async fn finish_close(task: &mut tokio::task::JoinHandle<()>, peer: &Arc<Peer>,
        signal_closed: &mut tokio::sync::watch::Receiver<Option<crate::viewer::signal::CloseReport>>) -> Result<(), String> {
        let forced = tokio::time::timeout(Duration::from_millis(1500), &mut *task).await.is_err();
        if forced {
            peer.stop().await;
            task.abort();
            let _ = (&mut *task).await;
        }
        let result = loop {
            if let Some(report) = signal_closed.borrow_and_update().as_ref() { break report.result(); }
            if signal_closed.changed().await.is_err() { break Err("信令清理失败，远端会话释放尚未确认".into()); }
        };
        if forced {
            match tokio::time::timeout(Duration::from_millis(750), peer.pc.close()).await {
                Ok(Ok(())) => {},
                _ => return result.and(Err("本地媒体清理未完成".into())),
            }
        }
        result
    }
}

impl Drop for SessionHandle {
    fn drop(&mut self) {
        // Cancellation during join/readiness must also release its peer and room.
        if let Some(mut task) = self.task.take() {
            let _ = self.tx.try_send(SessionCommand::Close);
            let peer = self.peer.clone();
            let mut signal_closed = self.signal_closed.clone();
            tokio::spawn(async move {
                let _ = Self::finish_close(&mut task, &peer, &mut signal_closed).await;
            });
        }
    }
}

/// Owns the peer's CONTROL/FILE/BINARY channel set and the single tool inbox.
/// Only one tool manager is active at a time; attaching replaces the previous
/// inbox, which closes the old receiver without touching the RTC channels.
#[derive(Clone)]
pub struct ToolLink {
    channels: Vec<Arc<RTCDataChannel>>,
    inbox: Arc<Mutex<Option<mpsc::Sender<Packet>>>>,
}

impl ToolLink {
    fn new(channels: Vec<Arc<RTCDataChannel>>) -> Self {
        Self {
            channels,
            inbox: Arc::new(Mutex::new(None)),
        }
    }

    pub fn attach(&self) -> (Transport, mpsc::Receiver<Packet>) {
        let (tx, rx) = mpsc::channel(256);
        if let Ok(mut slot) = self.inbox.lock() {
            *slot = Some(tx);
        }
        (channel_transport(self.channels.clone()), rx)
    }

    pub fn detach(&self) {
        if let Ok(mut slot) = self.inbox.lock() {
            *slot = None;
        }
    }

    fn forward(&self, channel: usize, data: &[u8]) {
        use crate::harmony::tools::{blob, BINARY, CONTROL, FILE};
        let channel = match channel {
            FILE | BINARY => channel,
            0 | 1 => {
                // Windows also returns FTP messages on TEXT; downloads can send
                // host-initiated FTP requests on CONTROL. Keep terminal RPCs separate.
                let file = blob(data, 21).is_some_and(|rpc| blob(rpc, 8).is_some())
                    || blob(data, 22).is_some_and(|rpc| blob(rpc, 4).is_some())
                    || blob(data, 27).is_some();
                if file { FILE }
                else if channel == CONTROL && blob(data, 22).is_some() { CONTROL }
                else { return; }
            }
            _ => return,
        };
        if let Ok(slot) = self.inbox.lock() {
            if let Some(sender) = slot.as_ref() {
                let _ = sender.try_send((channel, data.to_vec()));
            }
        }
    }
}

struct VideoDelivery {
    requested: VideoSettings,
    sent: Option<VideoSettings>,
    screen: Option<video::ResolutionScreen>,
    initial_screen_modes: HashMap<u32, video::ScreenMode>,
    sent_resolution: Vec<(u32, u64)>,
}

impl VideoDelivery {
    fn new(requested: VideoSettings) -> Self {
        Self { requested, sent: None, screen: None, initial_screen_modes: HashMap::new(), sent_resolution: Vec::new() }
    }
}

struct Peer {
    capture_type: u32,
    clipboard: Mutex<SyncState>,
    cursor: crate::viewer::cursor::State,
    capture_cursor: bool,
    cursor_capture: Mutex<(Option<u64>, bool)>,
    remote_unlock: Mutex<remote_unlock::State>,
    pc: Arc<RTCPeerConnection>,
    control: Arc<RTCDataChannel>,
    text: Arc<RTCDataChannel>,
    input: Mutex<InputTranslator>,
    gamepad: Mutex<crate::viewer::native_gamepad::Gate>,
    input_error_reported: AtomicBool,
    input_commands: AtomicU64,
    input_messages: AtomicU64,
    view_only: AtomicBool,
    audio_muted: AtomicBool,
    video: tokio::sync::Mutex<VideoDelivery>,
    answered: AtomicBool,
    early: Mutex<Vec<RTCIceCandidateInit>>,
    app_id: String,
    ice_id: String,
    remote_client: String,
    echo_received: AtomicBool,
    first_frame: AtomicBool,
    video_size: Mutex<(u32, u32)>,
    events: EventQueue,
    generation: u64,
    session_id: String,
    target_id: String,
    target_name: String,
    media_packets: AtomicU64,
    audio_packets: AtomicU64,
    audio_frames: AtomicU64,
    frames: AtomicU64,
    control_seq: AtomicU64,
    ended: Mutex<bool>,
    stopped: tokio::sync::Notify,
    platform: Platform,
    tools: ToolLink,
}

fn media_engine(shape: &Shape) -> Result<MediaEngine, String> {
    let mut engine = MediaEngine::default();
    let mut codecs = vec![
        (RTPCodecType::Video, "video/H264", 90000, 0,
         "level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f", 102),
        (RTPCodecType::Audio, "audio/opus", 48000, 2, "minptime=10;useinbandfec=1", 111),
    ];
    if shape.decoders.iter().any(|d| d.codec == 2) {
        codecs.insert(0, (RTPCodecType::Video, "video/H265", 90000, 0, "", 104));
    }
    for (kind, mime, rate, channels, fmtp, payload) in codecs {
        engine
            .register_codec(
                RTCRtpCodecParameters {
                    capability: RTCRtpCodecCapability {
                        mime_type: mime.into(),
                        clock_rate: rate,
                        channels,
                        sdp_fmtp_line: fmtp.into(),
                        ..Default::default()
                    },
                    payload_type: payload,
                    ..Default::default()
                },
                kind,
            )
            .map_err(|_| "codec initialization failed")?;
    }
    Ok(engine)
}

fn rtc_configuration(result: &Value) -> Result<RTCConfiguration, String> {
    let list = result
        .get("iceServers")
        .and_then(Value::as_array)
        .ok_or("control acknowledgement missing iceServers")?;
    let mut servers = Vec::new();
    for server in list {
        let urls = match server.get("urls") {
            Some(Value::String(value)) => vec![value.clone()],
            Some(Value::Array(values)) => values
                .iter()
                .map(|item| item.as_str().map(str::to_owned).ok_or("invalid ICE URL"))
                .collect::<Result<Vec<_>, _>>()?,
            _ => return Err("invalid ICE URLs".into()),
        };
        if urls.is_empty()
            || urls.iter().any(|url| {
                !["stun:", "stuns:", "turn:", "turns:"]
                    .iter()
                    .any(|prefix| url.starts_with(prefix))
            })
        {
            return Err("invalid ICE URL scheme".into());
        }
        let string = |key: &str| match server.get(key) {
            Some(Value::String(value)) => Ok(value.clone()),
            None => Ok(String::new()),
            _ => Err("invalid ICE authentication".to_string()),
        };
        servers.push(RTCIceServer {
            urls,
            username: string("username")?,
            credential: string("credential")?,
            credential_type: RTCIceCredentialType::Password,
        });
    }
    let relay = match result.get("force_relay") {
        None => false,
        Some(Value::Bool(value)) => *value,
        _ => return Err("invalid relay policy".into()),
    };
    if relay
        && !servers.iter().any(|server| {
            server
                .urls
                .iter()
                .any(|url| url.starts_with("turn:") || url.starts_with("turns:"))
        })
    {
        return Err("relay-only session without TURN".into());
    }
    let mut config = RTCConfiguration {
        ice_servers: servers,
        ..Default::default()
    };
    if relay {
        config.ice_transport_policy =
            webrtc::peer_connection::policy::ice_transport_policy::RTCIceTransportPolicy::Relay;
    }
    Ok(config)
}

fn answer_sdp(body: &Value) -> Result<String, String> {
    if let Some(value) = body.get("sdp").and_then(Value::as_str) {
        if value.len() <= 1024 * 1024 {
            return Ok(value.into());
        }
    }
    if let Some(value) = body.get("gzip_sdp").and_then(Value::as_str) {
        use base64::Engine;
        use std::io::Read;
        if value.len() > 2 * 1024 * 1024 {
            return Err("compressed answer too large".into());
        }
        let data = base64::engine::general_purpose::STANDARD
            .decode(value)
            .map_err(|_| "invalid compressed answer")?;
        let mut output = String::new();
        flate2::read::GzDecoder::new(data.as_slice())
            .take(1024 * 1024 + 1)
            .read_to_string(&mut output)
            .map_err(|_| "invalid compressed answer")?;
        if output.len() <= 1024 * 1024 {
            return Ok(output);
        }
    }
    Err("answer missing or too large".into())
}

fn with_max_message_size(sdp: &str) -> String {
    if sdp.contains("a=max-message-size:") {
        return sdp.to_owned();
    }
    let eol = if sdp.contains("\r\n") { "\r\n" } else { "\n" };
    let mut out = String::with_capacity(sdp.len() + 32);
    for line in sdp.split_inclusive('\n') {
        out.push_str(line);
        if line.trim_end().starts_with("a=sctp-port:") {
            out.push_str("a=max-message-size:262144");
            out.push_str(eol);
        }
    }
    out
}

impl Peer {
    async fn request_remote_unlock_state(&self) {
        let sequence = self.control_seq.fetch_add(1, Ordering::Relaxed);
        let _ = self.send_control_bytes(remote_unlock::query(sequence)).await;
    }

    fn receive_remote_unlock(&self, data: &[u8]) {
        if self.capture_type != 1 { return; }
        let Some(update) = remote_unlock::host_update(data) else { return };
        if self.ended.lock().map(|ended| *ended).unwrap_or(true) { return; }
        match update {
            remote_unlock::HostUpdate::Lock(lock) => {
                let Ok(mut state) = self.remote_unlock.lock() else { return };
                let (changed, finished) = state.observe(lock);
                if changed {
                    event(&self.events, "remoteUnlockState", json!({
                        "generation":self.generation, "locked":lock.locked, "supported":lock.supported
                    }));
                }
                if let Some(id) = finished { remote_unlock::result(&self.events, self.generation, id, None); }
            }
            remote_unlock::HostUpdate::Failure => self.fail_remote_unlock(remote_unlock::Failure::Rejected),
        }
    }

    fn fail_remote_unlock(&self, failure: remote_unlock::Failure) {
        if let Ok(mut state) = self.remote_unlock.lock() {
            if let Some(id) = state.finish() { remote_unlock::result(&self.events, self.generation, id, Some(failure)); }
        }
    }

    fn expire_remote_unlock(&self) {
        if let Ok(mut state) = self.remote_unlock.lock() {
            if let Some(id) = state.expire(Instant::now()) {
                remote_unlock::result(&self.events, self.generation, id, Some(remote_unlock::Failure::TimedOut));
            }
        }
    }

    async fn request_remote_unlock(&self, request_id: u64, password: remote_unlock::Secret) {
        use remote_unlock::Failure;
        use webrtc::data_channel::data_channel_state::RTCDataChannelState;
        let allowed = self.capture_type == 1 && self.echo_received.load(Ordering::Acquire)
            && !self.view_only.load(Ordering::Acquire) && self.control.ready_state() == RTCDataChannelState::Open
            && self.ended.lock().is_ok_and(|ended| !*ended) && password.password().is_some();
        let start = if allowed {
            self.remote_unlock.lock().map_err(|_| Failure::Unavailable)
                .and_then(|mut state| state.begin(request_id, Instant::now()))
        } else { Err(Failure::Unavailable) };
        match start {
            Ok(true) => {}
            Ok(false) => return,
            Err(failure) => {
                remote_unlock::result(&self.events, self.generation, request_id, Some(failure));
                return;
            }
        }
        let sequence = self.control_seq.fetch_add(1, Ordering::Relaxed);
        let sent = match remote_unlock::unlock_packet(sequence, password) {
            Some(packet) => matches!(tokio::time::timeout(Duration::from_secs(2), self.control.send(&packet)).await, Ok(Ok(_))),
            None => false,
        };
        if !sent {
            if let Ok(mut state) = self.remote_unlock.lock() {
                if let Some(id) = state.finish_request(request_id) {
                    remote_unlock::result(&self.events, self.generation, id, Some(Failure::Unavailable));
                }
            }
        }
    }

    async fn receive_resolution_screen(&self, data: &[u8]) {
        let Some(mut screen) = video::parse_resolution_screen(data) else { return };
        {
            let mut video = self.video.lock().await;
            if let Some(initial) = video.initial_screen_modes.get(&screen.id) {
                screen.initial = Some(*initial);
            } else if let Some(initial) = screen.initial {
                if video.initial_screen_modes.len() < 64 {
                    video.initial_screen_modes.insert(screen.id, initial);
                }
            }
            if video.screen.as_ref() == Some(&screen) { return; }
            let modes = screen.modes.iter().map(|mode| {
                let (width, height) = mode.physical;
                json!({"width":width,"height":height})
            }).collect::<Vec<_>>();
            event(&self.events, "videoResolutionModes", json!({"generation":self.generation,"modes":modes}));
            video.screen = Some(screen);
        }
        if let Err(error) = self.flush_video_settings(None).await {
            log::warn!("video settings for the active screen not sent: {error}");
            self.report_video_settings_error("画面设置发送失败，请重试。");
        }
    }

    fn receive_video_sync(&self, data: &[u8]) {
        if let Some(sync) = video::parse_capture_sync(data) {
            if sync.width > 0 && sync.height > 0 {
                if let Ok(mut size) = self.video_size.lock() { *size = (sync.width, sync.height); }
                if let Ok(mut input) = self.input.lock() { input.set_screen(sync.width, sync.height); }
            }
            event(&self.events, "videoSettingsSync", json!({
                "sessionId":self.session_id, "generation":self.generation,
                "fps":sync.fps, "quality":sync.quality, "chroma":sync.chroma,
                "width":sync.width, "height":sync.height
            }));
        }
    }

    async fn receive_video_settings(&self, data: &[u8]) {
        if self.capture_type != 1 { return; }
        self.receive_video_sync(data);
        self.receive_resolution_screen(data).await;
        if video::capture_setting_rejected(data) {
            self.video.lock().await.sent = None;
            self.report_video_settings_error("被控端未接受画面设置。");
        }
    }
    fn receive_cursor(&self, data: &[u8]) {
        if self.capture_type != 1 { return; }
        self.cursor.receive(data);
        if let Some(shape) = self.cursor.take() {
            use base64::Engine as _;
            event(&self.events, "remoteCursor", json!({"generation":self.generation,
                "png":base64::engine::general_purpose::STANDARD.encode(&shape.png),
                "width":shape.width, "height":shape.height, "hotX":shape.hot_x, "hotY":shape.hot_y}));
        }
    }

    fn emit_cursor_capture(&self, enabled: bool) {
        event(&self.events, "remoteCursorCapture", json!({"generation":self.generation, "enabled":enabled}));
    }

    async fn request_cursor_capture(&self) {
        if !self.capture_cursor { return; }
        let seq = self.control_seq.fetch_add(1, Ordering::Relaxed);
        if let Ok(mut capture) = self.cursor_capture.lock() { capture.0 = Some(seq); }
        if let Err(error) = self.send_control_bytes(wire::request_cursor_capture(seq)).await {
            if let Ok(mut capture) = self.cursor_capture.lock() { capture.0 = None; }
            log::warn!("remote cursor capture request not sent: {error}");
        }
    }

    fn receive_cursor_capture(&self, data: &[u8]) -> bool {
        if !self.capture_cursor { return false; }
        let Ok(mut capture) = self.cursor_capture.lock() else { return false };
        if crate::viewer::cursor::capture_unavailable(data) {
            if capture.1 { self.emit_cursor_capture(false); }
            *capture = (None, false);
            return true;
        }
        let Some(accepted) = capture.0.and_then(|seq| crate::viewer::cursor::capture_response(data, seq)) else { return false };
        *capture = (None, accepted);
        if accepted { self.emit_cursor_capture(true); }
        true
    }
    fn snapshot(&self, phase: &str, error: Option<&str>) -> SessionSnapshot {
        let (width, height) = self.video_size.lock().map(|size| *size).unwrap_or((1920, 1080));
        SessionSnapshot {
            phase: phase.into(),
            session_id: self.session_id.clone(),
            generation: self.generation,
            resource_epoch: 0,
            target_id: self.target_id.clone(),
            target_name: self.target_name.clone(),
            view_only: self.view_only.load(Ordering::Acquire),
            first_frame_received: self.first_frame.load(Ordering::Acquire),
            error: error.map(str::to_owned),
            video_width: width,
            video_height: height,
        }
    }

    fn emit_state(&self, phase: &str, error: Option<&str>) {
        let Ok(mut ended) = self.ended.lock() else { return };
        if *ended { return; }
        if phase == "ended" {
            *ended = true;
            self.stopped.notify_one();
        }
        if self.capture_type != 1 { return; }
        event(
            &self.events,
            "sessionState",
            serde_json::to_value(self.snapshot(phase, error)).unwrap_or(Value::Null),
        );
    }

    async fn offer(&self) -> Result<Value, String> {
        let offer = self.pc.create_offer(None).await.map_err(|_| "create offer failed")?;
        let mut sdp = offer.sdp.clone();
        self.pc
            .set_local_description(offer)
            .await
            .map_err(|_| "set local offer failed")?;
        if !sdp.contains("a=x-uuremote-quic") {
            if let Some(index) = sdp.find("a=group:BUNDLE") {
                sdp.insert_str(index, "a=x-uuremote-quic\r\n");
            }
        }
        sdp = with_max_message_size(&sdp);
        Ok(json!({
            "client_id": self.remote_client,
            "data": {
                "type": "offer",
                "sdp": sdp,
                "ice_id": self.ice_id,
                "app_control_id": self.app_id,
                "ice_network_type": 3
            }
        }))
    }

    async fn receive(&self, event: &Value) -> Result<(), String> {
        let body = event.get("data").unwrap_or(event);
        if !self.matches_route(event) {
            return Ok(());
        }
        match body.get("type").and_then(Value::as_str) {
            Some("answer") => {
                if self.answered.swap(true, Ordering::AcqRel) {
                    return Ok(());
                }
                let sdp = answer_sdp(body)?;
                let answer = RTCSessionDescription::answer(sdp).map_err(|_| "invalid answer")?;
                self.pc
                    .set_remote_description(answer)
                    .await
                    .map_err(|_| "set remote answer failed")?;
                let early = std::mem::take(&mut *self.early.lock().map_err(|_| "ICE lock")?);
                for candidate in early {
                    self.pc
                        .add_ice_candidate(candidate)
                        .await
                        .map_err(|_| "queued ICE candidate failed")?;
                }
            }
            Some("candidate") => {
                let value = body.get("candidate").ok_or("missing candidate")?;
                let candidate: RTCIceCandidateInit = if let Some(text) = value.as_str() {
                    RTCIceCandidateInit {
                        candidate: text.into(),
                        sdp_mid: body.get("sdp_mid").and_then(Value::as_str).map(str::to_owned),
                        sdp_mline_index: body
                            .get("sdp_mline_index")
                            .and_then(Value::as_u64)
                            .and_then(|value| u16::try_from(value).ok()),
                        ..Default::default()
                    }
                } else {
                    serde_json::from_value(value.clone()).map_err(|_| "invalid candidate")?
                };
                if self.answered.load(Ordering::Acquire) {
                    self.pc
                        .add_ice_candidate(candidate)
                        .await
                        .map_err(|_| "ICE candidate failed")?;
                } else {
                    let mut early = self.early.lock().map_err(|_| "ICE lock")?;
                    if early.len() >= 256 {
                        return Err("too many early ICE candidates".into());
                    }
                    early.push(candidate);
                }
            }
            _ => {}
        }
        Ok(())
    }

    fn matches_route(&self, event: &Value) -> bool {
        let body = event.get("data").unwrap_or(event);
        !body
            .get("ice_id")
            .is_some_and(|value| value.as_str() != Some(self.ice_id.as_str()))
            && !body
                .get("app_control_id")
                .is_some_and(|value| value.as_str() != Some(self.app_id.as_str()))
            && !event
                .get("client_id")
                .is_some_and(|value| value.as_str() != Some(self.remote_client.as_str()))
    }

    async fn send_control_bytes(&self, data: Vec<u8>) -> Result<(), String> {
        if self.control.ready_state()
            != webrtc::data_channel::data_channel_state::RTCDataChannelState::Open
        {
            return Err("CONTROL is not open".into());
        }
        self.control
            .send(&bytes::Bytes::from(data))
            .await
            .map(|_| ())
            .map_err(|_| "CONTROL send failed".into())
    }

    async fn send_text_bytes(&self, data: Vec<u8>) -> Result<(), String> {
        if self.text.ready_state()
            != webrtc::data_channel::data_channel_state::RTCDataChannelState::Open
        {
            return Err("TEXT is not open".into());
        }
        self.text
            .send(&bytes::Bytes::from(data))
            .await
            .map(|_| ())
            .map_err(|_| "TEXT send failed".into())
    }

    async fn send_capture_fields(&self, fields: &[(u32, u64)]) -> Result<(), String> {
        if fields.is_empty() {
            return Ok(());
        }
        let seq = self.control_seq.fetch_add(1, Ordering::Relaxed);
        self.send_text_bytes(wire::capture_setting(seq, fields)).await
    }

    async fn apply_video_settings(&self, next: VideoSettings) -> Result<(), String> {
        self.flush_video_settings(Some(next)).await
    }

    /// Replay the latest preferences once CONTROL echo and the TEXT data channel are ready.
    async fn flush_video_settings(&self, update: Option<VideoSettings>) -> Result<(), String> {
        let mut video = self.video.lock().await;
        if let Some(next) = update { video.requested = next; }
        if !self.echo_received.load(Ordering::Acquire)
            || self.text.ready_state() != webrtc::data_channel::data_channel_state::RTCDataChannelState::Open
        { return Ok(()); }
        let next = video.requested;
        let resolution = next.resolution.fields_for_screen(video.screen.as_ref());
        let mut fields = next.settings_fields(video.sent);
        if !resolution.is_empty() && (video.sent.is_none() || video.sent_resolution != resolution) {
            fields.extend_from_slice(&resolution);
        } else if !fields.is_empty() {
            if let Some(screen) = &video.screen { fields.push((4, u64::from(screen.id))); }
        }
        self.send_capture_fields(&fields).await?;
        video.sent = Some(next);
        video.sent_resolution = resolution;
        Ok(())
    }

    fn report_video_settings_error(&self, message: &str) {
        event(&self.events, "videoSettingsError", json!({"generation": self.generation, "message": message}));
    }

    fn set_audio_muted(&self, muted: bool) {
        self.audio_muted.store(muted, Ordering::Release);
        // Stop OHAudio immediately so samples already decoded are dropped too.
        self.platform.set_audio_muted(muted);
    }

    async fn send_input(&self, value: &Value) -> Result<(), String> {
        if self.control.ready_state()
            != webrtc::data_channel::data_channel_state::RTCDataChannelState::Open
        {
            return Err("CONTROL is not open".into());
        }
        self.control
            .send(&bytes::Bytes::from(value.to_string()))
            .await
            .map(|_| { self.input_messages.fetch_add(1, Ordering::Relaxed); })
            .map_err(|_| "CONTROL input send failed".into())
    }

    async fn handle_input(&self, text: &str) -> Result<(), String> {
        self.input_commands.fetch_add(1, Ordering::Relaxed);
        if self.view_only.load(Ordering::Acquire) { return Ok(()); }
        let outgoing = {
            let mut input = self.input.lock().map_err(|_| "input lock")?;
            input.handle(text)?
        };
        for value in outgoing {
            self.send_input(&value).await?;
        }
        Ok(())
    }

    async fn handle_gamepad(&self, state: Option<crate::viewer::native_gamepad::State>) -> Result<(), String> {
        let outgoing = self.gamepad.lock().map_err(|_| "gamepad lock")?
            .step(state, !self.view_only.load(Ordering::Acquire), Instant::now());
        for value in outgoing { self.send_input(&value).await?; }
        Ok(())
    }

    fn report_input_error(&self) {
        if !self.input_error_reported.swap(true, Ordering::AcqRel) {
            event(&self.events, "inputError", json!({
                "generation": self.generation,
                "message": "远程输入发送失败，请重新连接。"
            }));
        }
    }

    /// Mobile input-method commits use the official `text_input {content}` field on
    /// CONTROL. Text is never logged and is capped at the parser's 16 KiB limit.
    async fn send_text_input(&self, text: &str) -> Result<(), String> {
        if self.view_only.load(Ordering::Acquire) {
            return Ok(());
        }
        if text.len() > 16 * 1024 {
            return Err("text_input content exceeds 16 KiB".into());
        }
        self.send_input(&json!({"action": "text_input", "content": text})).await
    }

    async fn release_all(&self) {
        let mut actions = match self.input.lock() {
            Ok(mut input) => input.release_all(),
            Err(_) => Vec::new(),
        };
        if let Ok(mut gamepad) = self.gamepad.lock() { actions.extend(gamepad.close()); }
        for action in actions {
            let _ = self.send_input(&action).await;
        }
    }

    async fn run_video(self: Arc<Self>, track: Arc<TrackRemote>) {
        let mut receiver = media::Receiver::new(Codec::H264);
        let mut tick = tokio::time::interval(Duration::from_millis(40));
        tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        let mut last_pli = Instant::now() - Duration::from_secs(1);
        let mut need_pli = false;
        let mut clock = video::RtpClock::default();
        // Keep an in-flight read across expiry ticks: interceptors may already
        // have consumed its SRTP packet before their future becomes ready.
        let packet = track.read_rtp();
        tokio::pin!(packet);
        loop {
            let output = tokio::select! {
                value = &mut packet => {
                    packet.set(track.read_rtp());
                    match value {
                    Ok((packet, _)) => {
                        self.media_packets.fetch_add(1, Ordering::Relaxed);
                        let Some(codec) = Codec::from_mime(&track.codec().capability.mime_type) else { continue };
                        if receiver.codec() != codec {
                            receiver = media::Receiver::new(codec);
                        }
                        receiver.push(media::Packet {
                            seq: packet.header.sequence_number,
                            timestamp: packet.header.timestamp,
                            marker: packet.header.marker,
                            payload: packet.payload.to_vec(),
                        })
                    }
                    Err(_) => break,
                    }
                },
                _ = tick.tick() => receiver.expire(),
            };
            need_pli |= output.pli;
            for unit in output.units {
                let codec = if unit.codec == Codec::H265 { 2 } else { 1 };
                let pts = clock.micros(unit.timestamp);
                let submitted = {
                    let Ok(ended) = self.ended.lock() else { return };
                    if *ended { return; }
                    let (width, height) = self.video_size.lock().map(|size| *size).unwrap_or((1920, 1080));
                    self.platform.submit_video(codec, width as i32, height as i32, pts, &unit.data)
                };
                if submitted {
                    self.frames.fetch_add(1, Ordering::Relaxed);
                } else {
                    need_pli = true;
                }
            }
            if need_pli && last_pli.elapsed() >= Duration::from_millis(250) {
                last_pli = Instant::now();
                let sent = self
                    .pc
                    .write_rtcp(&[Box::new(PictureLossIndication {
                        sender_ssrc: 0,
                        media_ssrc: track.ssrc(),
                    })])
                    .await;
                if sent.is_ok() { need_pli = false; }
            }
        }
        self.emit_state("ended", Some("video track ended"));
    }

    async fn run_audio(&self, track: Arc<TrackRemote>) {
        if !self.platform.has_audio_decoder() {
            event(
                &self.events,
                "audioUnavailable",
                json!({
                    "sessionId": self.session_id,
                    "reason": "native Opus decoder is not attached"
                }),
            );
            // Drain the track so the video reader is not blocked by backpressure.
            while track.read_rtp().await.is_ok() {}
            return;
        }
        let mut started = false;
        let mut failures = 0u64;
        while let Ok((packet, _)) = track.read_rtp().await {
            self.audio_packets.fetch_add(1, Ordering::Relaxed);
            let seq = packet.header.sequence_number;
            let pts_us = i64::from(packet.header.timestamp) * 1_000_000 / 48_000;
            let muted = self.audio_muted.load(Ordering::Acquire);
            // The gate sits before the native decoder: a muted session submits no
            // payload, so no PCM is decoded or queued at all.
            let submitted = {
                let Ok(ended) = self.ended.lock() else { return };
                if *ended { return; }
                self.platform.submit_audio_packet_if_unmuted(muted, seq, pts_us, &packet.payload)
            };
            if submitted {
                failures = 0;
                self.audio_frames.fetch_add(1, Ordering::Relaxed);
                if !started {
                    started = true;
                    event(
                        &self.events,
                        "audioStarted",
                        json!({
                            "sessionId": self.session_id,
                            "generation": self.generation,
                            "sampleRate": 48000,
                            "channels": 2
                        }),
                    );
                }
            } else if !muted {
                failures += 1;
                if failures == 25 {
                    event(
                        &self.events,
                        "audioDecodeFailed",
                        json!({
                            "sessionId": self.session_id,
                            "reason": "Opus packets were rejected by the native decoder"
                        }),
                    );
                }
            }
        }
    }

    async fn stop(&self) {
        let ended = self.ended.lock().map(|mut ended| std::mem::replace(&mut *ended, true)).unwrap_or(true);
        self.stopped.notify_one();
        self.fail_remote_unlock(remote_unlock::Failure::Cancelled);
        if self.capture_type == 1 { self.set_audio_muted(true); }
        // Upstream stop_capture uses TEXT action 7 and screen_id=-1 (all screens).
        // Windows 4.46 dispatch distinguishes stopCapture (7) from quitCapture (21).
        // Neither a successful send nor transport close confirms room release.
        // Evidence: docs/diagnosis/diagnosis_20261109_rea_lifecycle.md.
        // A released/failed peer no longer owns capture. Only an explicit local
        // departure sends stop_capture; never send it after another viewer takes over.
        if self.capture_type != 1 || ended { return; }
        let seq = self.control_seq.fetch_add(1, Ordering::Relaxed);
        let _ = tokio::time::timeout(
            Duration::from_millis(300),
            self.send_text_bytes(wire::stop_capture(seq)),
        )
        .await;
        // Let SCTP deliver the stop before the peer connection goes away.
        tokio::time::sleep(Duration::from_millis(150)).await;
    }

    #[cfg(test)]
    async fn close(&self) {
        self.stop().await;
        let _ = self.pc.close().await;
    }
}

fn install_handlers(peer: &Arc<Peer>) {
    let weak = Arc::downgrade(peer);
    peer.pc.on_peer_connection_state_change(Box::new(move |state| {
        let weak = weak.clone();
        Box::pin(async move {
            if matches!(state, RTCPeerConnectionState::Failed | RTCPeerConnectionState::Closed) {
                if let Some(peer) = weak.upgrade() {
                    peer.emit_state("ended", Some("peer connection closed"));
                }
            }
        })
    }));

    let weak = Arc::downgrade(peer);
    peer.pc.on_track(Box::new(move |track, _receiver, _transceiver| {
        let weak: Weak<Peer> = weak.clone();
        Box::pin(async move {
            tokio::spawn(async move {
                let Some(peer) = weak.upgrade() else { return };
                let mime = track.codec().capability.mime_type.clone();
                if mime.eq_ignore_ascii_case("audio/opus") {
                    peer.run_audio(track).await;
                } else if Codec::from_mime(&mime).is_some() {
                    peer.run_video(track).await;
                }
            });
        })
    }));

    peer.pc.on_data_channel(Box::new(|channel| {
        Box::pin(async move {
            let label = channel.label().to_owned();
            log::info!("remote data channel opened: {label}");
        })
    }));

    let peer_weak = Arc::downgrade(peer);
    peer.control.on_open(Box::new(move || {
        let peer_weak = peer_weak.clone();
        Box::pin(async move {
            if let Some(peer) = peer_weak.upgrade() {
                let _ = peer
                    .control
                    .send(&bytes::Bytes::from(wire::echo_request_with_clipboard(1, peer.capture_type == 1)))
                    .await;
                if peer.capture_type == 1 {
                    let _ = peer.control.send(&bytes::Bytes::from(wire::request_video_track())).await;
                }
                peer.emit_state("negotiating", None);
            }
        })
    }));

    let peer_weak = Arc::downgrade(peer);
    peer.control.on_message(Box::new(move |message: DataChannelMessage| {
        let peer_weak = peer_weak.clone();
        Box::pin(async move {
            if let Some(peer) = peer_weak.upgrade() {
                if peer.receive_cursor_capture(&message.data) { return; }
                peer.receive_remote_unlock(&message.data);
                peer.receive_cursor(&message.data);
                if peer.gamepad.lock().is_ok_and(|gamepad| gamepad.active()) && !peer.view_only.load(Ordering::Acquire) {
                    if let Some(motors) = crate::viewer::native_rumble::decode(&message.data) {
                        event(&peer.events, "gamepadVibration", json!({
                            "generation": peer.generation, "left": motors.left, "right": motors.right
                        }));
                    }
                }
                peer.receive_video_settings(&message.data).await;
                let echo = wire::echo_matches(&message.data, 1)
                    || wire::echo_request_seq(&message.data).is_some();
                if wire::echo_matches(&message.data, 1) {
                    let first_echo = !peer.echo_received.swap(true, Ordering::AcqRel);
                    if peer.capture_type == 1 {
                        if first_echo {
                            peer.request_cursor_capture().await;
                            peer.request_remote_unlock_state().await;
                        }
                        if let Err(error) = peer.flush_video_settings(None).await {
                            log::warn!("initial video settings not sent: {error}");
                            peer.report_video_settings_error("画面设置发送失败，请重试。");
                        }
                    }
                }
                if let Some(request) = wire::echo_request_seq(&message.data) {
                    let _ = peer
                        .control
                        .send(&bytes::Bytes::from(wire::echo_response(1_000_000 + request, request)))
                        .await;
                }
                if !echo {
                    peer.tools.forward(0, &message.data);
                }
            }
        })
    }));

    let peer_weak = Arc::downgrade(peer);
    peer.text.on_open(Box::new(move || {
        Box::pin(async move {
            if let Some(peer) = peer_weak.upgrade() {
                if peer.capture_type == 1 {
                    if let Err(error) = peer.flush_video_settings(None).await {
                        log::warn!("initial video settings not sent: {error}");
                        peer.report_video_settings_error("画面设置发送失败，请重试。");
                    }
                }
            }
        })
    }));

    {
        let weak = Arc::downgrade(peer);
        peer.text.on_message(Box::new(move |message: DataChannelMessage| {
            let weak = weak.clone();
            Box::pin(async move {
                let Some(peer) = weak.upgrade() else { return };
                peer.tools.forward(1, &message.data);
                if peer.capture_type != 1 { return; }
                peer.receive_remote_unlock(&message.data);
                peer.receive_cursor(&message.data);
                peer.receive_video_settings(&message.data).await;
                let response = peer.clipboard.lock().ok().and_then(|mut state| state.receive(&message.data).ok());
                if let Some((replies, value)) = response {
                    for reply in replies { let _ = peer.send_text_bytes(reply).await; }
                    if let Some(text) = value {
                        event(&peer.events, "clipboardText", json!({
                            "sessionId": peer.session_id, "generation": peer.generation, "text": text
                        }));
                    }
                }
            })
        }));
    }

    // FILE and BINARY carry file transfer, port mapping and terminal frames.
    for index in [3usize, 4usize] {
        let Some(channel) = peer.tools.channels.get(index).cloned() else {
            continue;
        };
        let peer_weak = Arc::downgrade(peer);
        channel.on_message(Box::new(move |message: DataChannelMessage| {
            if let Some(peer) = peer_weak.upgrade() {
                peer.tools.forward(index, &message.data);
            }
            Box::pin(async {})
        }));
    }
}

pub struct OpenOptions {
    pub view_only: bool,
    pub target_id: String,
    pub target_name: String,
    pub mac: bool,
    pub capture_cursor: bool,
    pub video: VideoSettings,
    pub touch_mode: TouchMode,
    pub audio_muted: bool,
}

struct OpeningPeer(Option<Arc<RTCPeerConnection>>, Option<Signal>);
impl OpeningPeer {
    async fn close(&mut self) {
        if let Some(mut signal) = self.1.take() { signal.close().await; }
        if let Some(pc) = self.0.take() { let _ = pc.close().await; }
    }
}
impl Drop for OpeningPeer {
    fn drop(&mut self) {
        let pc = self.0.take();
        let signal = self.1.take();
        if pc.is_some() || signal.is_some() {
            tokio::spawn(async move { OpeningPeer(pc, signal).close().await; });
        }
    }
}

pub async fn open(
    _api: &Api,
    room: &crate::viewer::api::JoinData,
    shape: &Shape,
    device_id: &str,
    client_id: &str,
    options: OpenOptions,
    events: EventQueue,
    platform: Platform,
    generation: u64,
    timeout: Duration,
) -> Result<SessionHandle, String> {
    open_tracked(_api, room, shape, device_id, client_id, options, events, platform, generation, timeout, None).await
}

pub async fn open_tracked(
    _api: &Api, room: &crate::viewer::api::JoinData, shape: &Shape, device_id: &str, client_id: &str,
    options: OpenOptions, events: EventQueue, platform: Platform, generation: u64, timeout: Duration,
    cleanup: Option<&crate::viewer::signal::CleanupBarrier>,
) -> Result<SessionHandle, String> {
    shape.validate_session()?;
    let app = wire::uuid();
    let ice = hex::encode(rand::random::<[u8; 16]>());
    let connect_timeout = if room.ws_connect_timeout_ms > 0 {
        Duration::from_millis((room.ws_connect_timeout_ms as u64).min(30_000))
    } else { timeout };
    let signal = Signal::connect_tracked(&room.signaling_list, &room.token, connect_timeout, true, cleanup).await?;
    let mut opening = OpeningPeer(None, Some(signal));
    let result = async {
        let signal = opening.1.as_mut().unwrap();
        let ack = signal
            .control(shape.control(client_id, &app, &ice)?, shape.connect_options(device_id, shape.capture_type == 1)?, timeout)
            .await?;
        if ack.get("app_control_id").is_some_and(|id| id.as_str() != Some(app.as_str())) {
            return Err("Control acknowledgement belongs to another session".into());
        }
        let ice = ack
            .get("ice_id")
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty() && value.len() <= 128)
            .map(str::to_owned)
            .ok_or("Control acknowledgement missing ICE route")?;
        let remote = ack
            .get("client_id")
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .ok_or("control acknowledgement missing peer route")?
            .to_owned();
        let config = rtc_configuration(&ack)?;
        let mut engine = media_engine(shape)?;
        for uri in [
            "http://www.webrtc.org/experiments/rtp-hdrext/video-capture-index",
            "http://www.webrtc.org/experiments/rtp-hdrext/video-frame-is-new-frame",
        ] {
            engine
                .register_header_extension(
                    webrtc::rtp_transceiver::rtp_codec::RTCRtpHeaderExtensionCapability { uri: uri.into() },
                    RTPCodecType::Video,
                    None,
                )
                .map_err(|_| "RTP header extension registration failed")?;
        }
        let registry = register_default_interceptors(webrtc::interceptor::registry::Registry::new(), &mut engine)
            .map_err(|_| "RTP interceptor initialization failed")?;
        let builder = APIBuilder::new()
            .with_media_engine(engine)
            .with_setting_engine(SettingEngine::default())
            .with_interceptor_registry(registry);
        let pc = Arc::new(
            builder
                .build()
                .new_peer_connection(config)
                .await
                .map_err(|_| "peer creation failed")?,
        );
        opening.0 = Some(pc.clone());
        if shape.capture_type == 1 {
        pc.add_transceiver_from_kind(
            RTPCodecType::Video,
            Some(RTCRtpTransceiverInit {
                direction: RTCRtpTransceiverDirection::Recvonly,
                send_encodings: vec![],
            }),
        )
        .await
        .map_err(|_| "media transceiver failed")?;
        pc.add_transceiver_from_kind(
            RTPCodecType::Audio,
            Some(RTCRtpTransceiverInit {
                direction: RTCRtpTransceiverDirection::Recvonly,
                send_encodings: vec![],
            }),
        )
        .await
        .map_err(|_| "audio transceiver failed")?;
        }
        let mut channels = Vec::new();
        for label in CHANNELS {
            channels.push(
                pc.create_data_channel(
                    label,
                    Some(RTCDataChannelInit {
                        ordered: Some(true),
                        ..Default::default()
                    }),
                )
                .await
                .map_err(|_| "data channel creation failed")?,
            );
        }
        let session_id = format!("hs-{}", &app[..8]);
        let mut input = InputTranslator::new(options.view_only, options.touch_mode, options.mac);
        input.set_screen(shape.width, shape.height);
        let tools = ToolLink::new(channels.clone());
        let peer = Arc::new(Peer {
            capture_type: shape.capture_type,
            cursor: Default::default(),
            capture_cursor: shape.capture_type == 1 && options.capture_cursor,
            cursor_capture: Mutex::new((None, false)),
            remote_unlock: Mutex::new(remote_unlock::State::default()),
            clipboard: Mutex::new(SyncState { target_mac: Some(options.mac), ..Default::default() }),
            pc: pc.clone(),
            control: channels[0].clone(),
            text: channels[1].clone(),
            input: Mutex::new(input),
            gamepad: Mutex::new(Default::default()),
            input_error_reported: AtomicBool::new(false),
            input_commands: AtomicU64::new(0),
            input_messages: AtomicU64::new(0),
            view_only: AtomicBool::new(options.view_only),
            audio_muted: AtomicBool::new(options.audio_muted),
            video: tokio::sync::Mutex::new(VideoDelivery::new(options.video)),
            answered: AtomicBool::new(false),
            early: Mutex::new(Vec::new()),
            app_id: app.clone(),
            ice_id: ice,
            remote_client: remote,
            echo_received: AtomicBool::new(false),
            first_frame: AtomicBool::new(false),
            video_size: Mutex::new((shape.width, shape.height)),
            events: events.clone(),
            generation,
            session_id: session_id.clone(),
            target_id: options.target_id.clone(),
            target_name: options.target_name.clone(),
            media_packets: AtomicU64::new(0),
            audio_packets: AtomicU64::new(0),
            audio_frames: AtomicU64::new(0),
            frames: AtomicU64::new(0),
            control_seq: AtomicU64::new(0),
            ended: Mutex::new(false),
            stopped: tokio::sync::Notify::new(),
            platform,
            tools: tools.clone(),
        });
        install_handlers(&peer);
        let (candidate_tx, candidate_rx) = mpsc::channel(256);
        let weak = Arc::downgrade(&peer);
        pc.on_ice_candidate(Box::new(move |candidate| {
            let weak = weak.clone();
            let sender = candidate_tx.clone();
            Box::pin(async move {
                if let Some(candidate) = candidate {
                    if let Ok(mut value) = candidate.to_json() {
                        if let Some(peer) = weak.upgrade() {
                            if let Some(local) = peer.pc.local_description().await {
                                if let Some(mid) = local.sdp.lines().find_map(|line| line.strip_prefix("a=mid:")) {
                                    value.sdp_mid = Some(mid.trim().into());
                                    value.sdp_mline_index = Some(0);
                                }
                            }
                            let _ = sender
                                .send(json!({
                                    "client_id": peer.remote_client,
                                    "data": {
                                        "type": "candidate",
                                        "candidate": value,
                                        "ice_id": peer.ice_id,
                                        "app_control_id": peer.app_id
                                    }
                                }))
                                .await;
                        }
                    }
                }
            })
        }));
        let offer = peer.offer().await?;
        signal.soac(offer).await?;
        peer.emit_state("waitingFirstFrame", None);
        Ok::<_, String>((peer, candidate_rx, session_id, tools))
    }
    .await;
    match result {
        Ok((peer, candidate_rx, session_id, tools)) => {
            opening.0 = None;
            let signal = opening.1.take().unwrap();
            let signal_closed = signal.closed();
            if peer.capture_type == 1 { peer.set_audio_muted(options.audio_muted); }
            let (tx, rx) = mpsc::channel(64);
            let task = tokio::spawn(run_session(signal, peer.clone(), candidate_rx, rx));
            Ok(SessionHandle {
                tx,
                task: Some(task),
                snapshot: SessionSnapshot {
                    phase: "waitingFirstFrame".into(),
                    session_id,
                    generation,
                    resource_epoch: 0,
                    target_id: options.target_id,
                    target_name: options.target_name,
                    view_only: options.view_only,
                    first_frame_received: false,
                    error: None,
                    video_width: shape.width,
                    video_height: shape.height,
                },
                tools,
                peer,
                signal_closed,
            })
        }
        Err(error) => {
            opening.close().await;
            Err(error)
        }
    }
}

async fn run_session(
    mut signal: Signal,
    peer: Arc<Peer>,
    mut candidates: mpsc::Receiver<Value>,
    mut commands: mpsc::Receiver<SessionCommand>,
) {
    let mut heartbeat = tokio::time::interval(Duration::from_secs(1));
    let mut stats = tokio::time::interval(Duration::from_secs(2));
    let mut previous_stats = (Instant::now(), 0u64, 0u64);
    let ready_deadline = tokio::time::sleep(Duration::from_secs(30));
    let frame_deadline = tokio::time::sleep(Duration::from_secs(45));
    tokio::pin!(ready_deadline, frame_deadline);
    loop {
        tokio::select! {
            _ = peer.stopped.notified() => break,
            _ = &mut ready_deadline, if !peer.echo_received.load(Ordering::Acquire) => {
                peer.emit_state("ended", Some("CONTROL echo timed out"));
                break;
            }
            _ = &mut frame_deadline, if peer.capture_type == 1 && !peer.first_frame.load(Ordering::Acquire) => {
                peer.emit_state("ended", Some("First video frame timed out"));
                break;
            }
            candidate = candidates.recv() => {
                if let Some(candidate) = candidate {
                    if let Err(error) = signal.soac(candidate).await {
                        peer.emit_state("ended", Some(&error));
                        break;
                    }
                }
            }
            event = signal.event() => {
                match event {
                    Ok(event) => {
                        match event.get(0).and_then(Value::as_str) {
                            Some("soac") => {
                                if let Some(body) = event.get(1) {
                                    if let Err(error) = peer.receive(body).await {
                                        peer.emit_state("ended", Some(&error));
                                        break;
                                    }
                                }
                            }
                            Some("released" | "left" | "leave" | "publisher_disconnect") => {
                                // leave/publisher_disconnect terminate this private namespace, not a routed peer.
                                let matches=matches!(event.get(0).and_then(Value::as_str),Some("leave" | "publisher_disconnect"))
                                    || peer.matches_route(event.get(1).unwrap_or(&Value::Null));
                                crate::harmony::event(&peer.events, "signalRelease", json!({"captureType":peer.capture_type,
                                    "matched":matches,"event":event.get(0).and_then(Value::as_str)}));
                                if matches {
                                    signal.released();
                                    peer.emit_state("ended", Some("remote session released"));
                                    break;
                                }
                            }
                            _ => {}
                        }
                    }
                    Err(error) => {
                        peer.emit_state("ended", Some(&error));
                        break;
                    }
                }
            }
            command = commands.recv() => {
                match command {
                    Some(SessionCommand::Input(text)) => {
                        if let Err(error) = peer.handle_input(&text).await {
                            peer.report_input_error();
                            log::warn!("input rejected: {error}");
                        }
                    }
                    Some(SessionCommand::Gamepad(state)) => {
                        if peer.handle_gamepad(state).await.is_err() { peer.report_input_error(); }
                    }
                    Some(SessionCommand::Text(text)) => {
                        if !peer.view_only.load(Ordering::Acquire) {
                            if let Err(error) = peer.send_text_input(&text).await {
                                peer.report_input_error();
                                log::warn!("text input rejected: {error}");
                            }
                        }
                    }
                    Some(SessionCommand::Release) => peer.release_all().await,
                    Some(SessionCommand::Rendered) => {
                        if !peer.first_frame.swap(true, Ordering::AcqRel) {
                            event(&peer.events, "firstFrame", json!({"generation": peer.generation, "sessionId": peer.session_id}));
                            peer.emit_state(if peer.view_only.load(Ordering::Acquire) { "viewOnly" } else { "playing" }, None);
                        }
                    },
                    Some(SessionCommand::ViewOnly(value)) => {
                        peer.view_only.store(value, Ordering::Release);
                        if let Ok(mut input) = peer.input.lock() {
                            input.set_view_only(value);
                        }
                        if value {
                            peer.fail_remote_unlock(remote_unlock::Failure::Cancelled);
                            peer.release_all().await;
                        }
                        peer.emit_state(if value { "viewOnly" } else if peer.first_frame.load(Ordering::Acquire) { "playing" } else { "waitingFirstFrame" }, None);
                    }
                    Some(SessionCommand::Resize(width, height)) => {
                        if width > 0 && height > 0 {
                            // Kept for future surface-driven input mapping; the
                            // Peer fields are read-only to avoid torn sizes.
                            log::info!("surface size {width}x{height}");
                        }
                    }
                    Some(SessionCommand::VideoSettings(video)) => {
                        if let Err(error) = peer.apply_video_settings(video).await {
                            log::warn!("video settings rejected: {error}");
                            peer.report_video_settings_error("画面设置发送失败，请重试。");
                        }
                    }
                    Some(SessionCommand::TouchMode(mode)) => {
                        let released = match peer.input.lock() {
                            Ok(mut input) => input.set_touch_mode(mode),
                            Err(_) => Vec::new(),
                        };
                        for action in released {
                            let _ = peer.send_input(&action).await;
                        }
                    }
                    Some(SessionCommand::AudioMuted(muted)) => {
                        peer.set_audio_muted(muted);
                    }
                    Some(SessionCommand::Clipboard(text)) => {
                        let result = if peer.view_only.load(Ordering::Acquire) {
                            Err("当前会话为只读模式")
                        } else {
                            peer.clipboard.lock().map_err(|_| "Clipboard state unavailable")
                                .and_then(|mut state| state.local(text))
                        };
                        let mut error = None;
                        match result {
                            Ok(Some(messages)) => for message in messages {
                                if peer.send_text_bytes(message).await.is_err() { error = Some("剪贴板发送失败"); break; }
                            },
                            Ok(None) => {},
                            Err(message) => error = Some(message),
                        }
                        event(&peer.events, "operationResult", json!({
                            "operation": "clipboard", "success": error.is_none(), "error": error,
                            "generation": peer.generation
                        }));
                    }
                    Some(SessionCommand::RemoteAction(action)) => {
                        let mut error = None;
                        for message in action.messages(peer.control_seq.fetch_add(2, Ordering::Relaxed)) {
                            if peer.send_control_bytes(message).await.is_err() { error = Some("远端操作发送失败"); break; }
                        }
                        event(&peer.events, "operationResult", json!({
                            "operation": "remoteAction", "success": error.is_none(), "error": error,
                            "generation": peer.generation
                        }));
                    }
                    Some(SessionCommand::UnlockRemote(id, password)) => peer.request_remote_unlock(id, password).await,
                    Some(SessionCommand::Close) | None => break,
                }
            }
            _ = heartbeat.tick() => {
                peer.expire_remote_unlock();
                if peer.control.ready_state() == webrtc::data_channel::data_channel_state::RTCDataChannelState::Open {
                    let _ = peer.send_control_bytes(crate::viewer::input::Input::heartbeat().to_string().into_bytes()).await;
                }
            }
            _ = stats.tick(), if peer.capture_type == 1 => {
                use webrtc::stats::StatsReportType as T;
                let report = peer.pc.get_stats().await;
                let pair = report.reports.values().filter_map(|item| match item {
                    T::CandidatePair(value) if value.nominated => Some(value), _ => None,
                }).max_by_key(|value| value.bytes_received);
                let bytes = pair.map_or(previous_stats.1, |value| value.bytes_received);
                let rtt = pair.and_then(|value| (value.current_round_trip_time > 0.0)
                    .then(|| (value.current_round_trip_time * 1000.0).round() as u32));
                let relay = pair.is_some_and(|value| [&value.local_candidate_id, &value.remote_candidate_id]
                    .iter().any(|id| match report.reports.get(*id) {
                        Some(T::LocalCandidate(candidate)) | Some(T::RemoteCandidate(candidate)) =>
                            candidate.candidate_type == webrtc::ice::candidate::CandidateType::Relay,
                        _ => false,
                    }));
                let frames = peer.frames.load(Ordering::Relaxed);
                let seconds = previous_stats.0.elapsed().as_secs_f64().max(0.001);
                event(&peer.events, "stats", json!({
                    "mediaPackets": peer.media_packets.load(Ordering::Relaxed),
                    "submittedFrames": peer.frames.load(Ordering::Relaxed),
                    "inputCommands": peer.input_commands.load(Ordering::Relaxed),
                    "inputMessages": peer.input_messages.load(Ordering::Relaxed),
                    "generation": peer.generation,
                    "audioFrames": peer.audio_frames.load(Ordering::Relaxed),
                    "audioPackets": peer.audio_packets.load(Ordering::Relaxed),
                    "rttMs": rtt,
                    "route": if pair.is_none() { "" } else if relay { "relay" } else { "direct" },
                    "fps": (frames.saturating_sub(previous_stats.2) as f64 / seconds).round() as u32,
                    "kbps": bytes.saturating_sub(previous_stats.1) as f64 * 8.0 / seconds / 1000.0
                }));
                previous_stats = (Instant::now(), bytes, frames);
            }
        }
    }
    commands.close();
    while let Ok(command) = commands.try_recv() {
        if let SessionCommand::UnlockRemote(id, _) = command {
            remote_unlock::result(&peer.events, peer.generation, id, Some(remote_unlock::Failure::Cancelled));
        }
    }
    // Retire input/capture before leave; RTC teardown must not delay room release.
    // Interop lifecycle: openuuyc a87b8e7 signal/mod.rs, graceful_close before peer.close.
    peer.stop().await;
    let report=signal.close().await;
    event(&peer.events, "signalCleanup", json!({"captureType":peer.capture_type,"generation":peer.generation,"report":report}));
    let _ = peer.pc.close().await;
    if peer.capture_type == 1 {
        event(&peer.events, "sessionState", serde_json::to_value(peer.snapshot("ended", report.result().err().as_deref())).unwrap_or(Value::Null));
    }
}

#[cfg(test)]
#[path = "session_tests.rs"]
mod tests;
