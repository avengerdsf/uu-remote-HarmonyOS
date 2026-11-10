use super::*;
use crate::harmony::platform::PlatformOps;
use webrtc::util::vnet::{net::{Net, NetConfig}, router::{Router, RouterConfig}};
use futures_util::{SinkExt, StreamExt};

#[tokio::test]
async fn rejected_and_cancelled_open_leave_the_room() {
    use tokio_tungstenite::tungstenite::Message;
    tokio::time::timeout(Duration::from_secs(8), async {
        for cancel in [false, true] {
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let url = format!("ws://{}", listener.local_addr().unwrap());
            let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
            let server = tokio::spawn(async move {
                let mut ws = tokio_tungstenite::accept_async(listener.accept().await.unwrap().0).await.unwrap();
                ws.send(Message::Text("0{}".into())).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text("40".into()));
                ws.send(Message::Text("40{}".into())).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text(r#"421["room_info"]"#.into()));
                ws.send(Message::Text(r#"431[{"participants_info":[]}]"#.into())).await.unwrap();
                let control = ws.next().await.unwrap().unwrap().into_text().unwrap();
                let id = &control[4..control.find('[').unwrap()];
                assert!(matches!(ws.next().await, Some(Ok(Message::Binary(_)))));
                ready_tx.send(()).unwrap();
                if !cancel { ws.send(Message::Text(format!(r#"43{id}["success",{{"ice_id":"synthetic-ice"}}]"#))).await.unwrap(); }
                assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text(r#"42["leave"]"#.into()));
                assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text("41".into()));
                assert!(matches!(ws.next().await, Some(Ok(Message::Close(_)))));
                ws.flush().await.unwrap();
            });
            let task = tokio::spawn(async move {
                let api = Api::new(crate::auth::UUAuthClient::new(Default::default()), "http://127.0.0.1:1");
                let room = serde_json::from_value(json!({"token":"synthetic", "signaling_list":[url],
                    "report_token":"", "report_url":""})).unwrap();
                let shape = serde_json::from_str(include_str!("../../tests/fixtures/viewer/shape.json")).unwrap();
                let platform = Platform::new(PlatformOps {
                    user: std::ptr::null_mut(), submit_video: None, submit_audio: None,
                    attach_surface: None, detach_surface: None, input_capability: None,
                    request_input_injection: None, submit_audio_packet: None, set_audio_muted: None,
                });
                open(&api, &room, &shape, "synthetic-device", "synthetic-client", OpenOptions {
                    target_id: "synthetic-target".into(), target_name: String::new(), mac: false, capture_cursor: false,
                    video: VideoSettings::default(), touch_mode: TouchMode::Direct, view_only: true, audio_muted: true,
                }, Default::default(), platform, 1, Duration::from_secs(2)).await
            });
            ready_rx.await.unwrap();
            if cancel { task.abort(); assert!(matches!(task.await, Err(error) if error.is_cancelled())); }
            else { assert_eq!(task.await.unwrap().err().unwrap(), "control acknowledgement missing peer route"); }
            server.await.unwrap();
        }
    }).await.expect("opening cleanup timed out");
}

#[tokio::test]
async fn cancelled_tool_readiness_keeps_the_opening_cleanup_barrier() {
    use tokio_tungstenite::tungstenite::Message;
    tokio::time::timeout(Duration::from_secs(6), async {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("ws://{}", listener.local_addr().unwrap());
        let (seen_tx, seen_rx) = tokio::sync::oneshot::channel();
        let (release_tx, release_rx) = tokio::sync::oneshot::channel();
        let server = tokio::spawn(async move {
            let mut ws = tokio_tungstenite::accept_async(listener.accept().await.unwrap().0).await.unwrap();
            ws.send(Message::Text("0{}".into())).await.unwrap();
            assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text("40".into()));
            ws.send(Message::Text("40{}".into())).await.unwrap();
            assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text(r#"421["room_info"]"#.into()));
            ws.send(Message::Text(r#"431[{"participants_info":[]}]"#.into())).await.unwrap();
            let control = ws.next().await.unwrap().unwrap().into_text().unwrap();
            let id = &control[4..control.find('[').unwrap()];
            assert!(matches!(ws.next().await, Some(Ok(Message::Binary(_)))));
            ws.send(Message::Text(format!(r#"43{id}["success",{{"ice_id":"synthetic-ice","client_id":"synthetic-peer","iceServers":[]}}]"#))).await.unwrap();
            loop { if ws.next().await.unwrap().unwrap() == Message::Text(r#"42["leave"]"#.into()) { break; } }
            assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text("41".into()));
            assert!(matches!(ws.next().await, Some(Ok(Message::Close(_)))));
            seen_tx.send(()).unwrap();
            release_rx.await.unwrap(); ws.flush().await.unwrap();
        });
        let api = Api::new(crate::auth::UUAuthClient::new(Default::default()), "http://127.0.0.1:1");
        let room = serde_json::from_value(json!({"token":"synthetic", "signaling_list":[url], "report_token":"", "report_url":""})).unwrap();
        let mut shape: Shape = serde_json::from_str(include_str!("../../tests/fixtures/viewer/shape.json")).unwrap();
        shape.capture_type = 5;
        let platform = Platform::new(PlatformOps { user: std::ptr::null_mut(), submit_video: None, submit_audio: None,
            attach_surface: None, detach_surface: None, input_capability: None,
            request_input_injection: None, submit_audio_packet: None, set_audio_muted: None });
        let cleanup = crate::viewer::signal::CleanupBarrier::default();
        let handle = open_tracked(&api, &room, &shape, "synthetic-device", "synthetic-client", OpenOptions {
            target_id: "synthetic-target".into(), target_name: String::new(), mac: false, capture_cursor: false,
            video: VideoSettings::default(), touch_mode: TouchMode::Direct, view_only: true, audio_muted: true,
        }, Default::default(), platform, 1, Duration::from_secs(2), Some(&cleanup)).await.unwrap();
        let readiness = tokio::spawn(async move { handle.wait_ready().await });
        tokio::task::yield_now().await;
        readiness.abort(); let _ = readiness.await;
        seen_rx.await.unwrap();
        let waiting = tokio::spawn(async move { cleanup.wait().await });
        tokio::task::yield_now().await;
        let returned_early = waiting.is_finished();
        release_tx.send(()).unwrap();
        waiting.await.unwrap().unwrap(); server.await.unwrap();
        assert!(!returned_early, "cancelled readiness lost the cleanup barrier before service adoption");
    }).await.expect("cancelled readiness cleanup stalled");
}

#[tokio::test]
async fn file_rpc_channels_match_windows_and_keep_terminal_replies_separate() {
    use crate::harmony::tools::{self, blob, ints, nested, rpc};
    let link = ToolLink::new(Vec::new());
    let (_, mut inbox) = link.attach();
    let reply = rpc(41, true, 7, &ints(&[(4, 1)]));
    link.forward(1, &reply);
    let (channel, packet) = inbox.recv().await.unwrap();
    assert_eq!(channel, tools::FILE, "Windows TEXT file replies must reach the file inbox");
    assert_eq!(packet, reply);
    link.forward(0, &reply);
    assert_eq!(inbox.recv().await.unwrap().0, tools::FILE);
    let request = rpc(42, false, 4, &ints(&[(2, 1)]));
    assert!(blob(blob(&request, 21).unwrap(), 8).is_some());
    link.forward(0, &request);
    assert_eq!(inbox.recv().await.unwrap().0, tools::FILE);
    let terminal = wire::envelope(43, 22, &nested(24, &[]));
    link.forward(0, &terminal);
    assert_eq!(inbox.recv().await.unwrap().0, tools::CONTROL);
    link.forward(1, &terminal);
    link.forward(1, &wire::envelope(44, 22, &nested(9, &[])));
    link.forward(1, b"not a protobuf message");
    assert!(inbox.try_recv().is_err(), "non-file TEXT messages must stay out of the tool inbox");
    link.forward(1, &wire::envelope(45, 27, &ints(&[(1, 2), (2, 3)])));
    assert_eq!(inbox.recv().await.unwrap().0, tools::FILE);
    for _ in 0..300 { link.forward(0, &wire::envelope(44, 13, &[])); }
    assert!(inbox.try_recv().is_err(), "unsolicited metrics must not fill the tool inbox");
    link.forward(tools::FILE, &reply);
    assert_eq!(inbox.recv().await.unwrap().0, tools::FILE);
}

async fn input_peer(settings: SettingEngine) -> Peer {
    input_peer_with_api(APIBuilder::new().with_setting_engine(settings).build()).await
}

async fn input_peer_with_api(api: webrtc::api::API) -> Peer {
    let pc = Arc::new(api.new_peer_connection(RTCConfiguration::default()).await.unwrap());
    let mut channels = Vec::new();
    for label in &CHANNELS[..2] {
        channels.push(pc.create_data_channel(label, Some(RTCDataChannelInit {
            ordered: Some(true), ..Default::default()
        })).await.unwrap());
    }
    Peer {
        capture_type: 1,
        cursor: Default::default(),
        capture_cursor: false,
        cursor_capture: Mutex::new((None, false)),
        remote_unlock: Mutex::new(remote_unlock::State::default()),
        control: channels[0].clone(), text: channels[1].clone(),
        tools: ToolLink::new(channels), pc,
        clipboard: Mutex::new(SyncState::default()),
        input: Mutex::new(InputTranslator::new(false, TouchMode::Direct, false)),
        gamepad: Mutex::new(Default::default()),
        input_error_reported: AtomicBool::new(false),
        input_commands: AtomicU64::new(0), input_messages: AtomicU64::new(0),
        view_only: AtomicBool::new(false), audio_muted: AtomicBool::new(false),
        video: tokio::sync::Mutex::new(VideoDelivery::new(VideoSettings::default())),
        answered: AtomicBool::new(false),
        early: Mutex::new(Vec::new()),
        app_id: "synthetic-app".into(), ice_id: "synthetic-ice".into(),
        remote_client: "synthetic-host".into(), echo_received: AtomicBool::new(false),
        first_frame: AtomicBool::new(false), video_size: Mutex::new((1920, 1080)),
        events: Default::default(), generation: 7, session_id: "synthetic-session".into(),
        target_id: "synthetic-target".into(), target_name: String::new(),
        media_packets: AtomicU64::new(0), audio_packets: AtomicU64::new(0),
        audio_frames: AtomicU64::new(0), frames: AtomicU64::new(0), control_seq: AtomicU64::new(0),
        ended: Mutex::new(false), stopped: tokio::sync::Notify::new(),
        platform: Platform::new(PlatformOps {
            user: std::ptr::null_mut(), submit_video: None, submit_audio: None,
            attach_surface: None, detach_surface: None, input_capability: None,
            request_input_injection: None, submit_audio_packet: None, set_audio_muted: None,
        }),
    }
}

#[tokio::test]
async fn capture_sync_updates_the_decoder_size_without_accepting_empty_dimensions() {
    let peer = input_peer(SettingEngine::default()).await;
    let mut sync = Vec::new();
    for (field, value) in [(1, 30), (5, 2560), (6, 1440)] { wire::int(field, value, &mut sync); }
    peer.receive_video_sync(&wire::envelope(7, 25, &sync));
    let actual = peer.snapshot("connected", None);
    let mut invalid = Vec::new();
    wire::int(5, 640, &mut invalid);
    peer.receive_video_sync(&wire::envelope(8, 25, &invalid));
    let after_empty = peer.snapshot("connected", None);
    peer.pc.close().await.unwrap();
    assert_eq!((actual.video_width, actual.video_height), (2560, 1440));
    assert_eq!((after_empty.video_width, after_empty.video_height), (2560, 1440));
}

#[tokio::test]
async fn video_settings_wait_for_echo_and_text_channel() {
    let peer = input_peer(SettingEngine::default()).await;
    let next = VideoSettings { resolution: video::Resolution::Size(1280, 720), ..Default::default() };
    assert_eq!(peer.apply_video_settings(next).await, Ok(()));
    peer.echo_received.store(true, Ordering::Release);
    assert_eq!(peer.apply_video_settings(next).await, Ok(()));
    let video = peer.video.lock().await;
    assert_eq!(video.requested, next);
    assert!(video.sent.is_none());
    drop(video);
    peer.pc.close().await.unwrap();
}

#[tokio::test]
async fn frontend_input_including_touchscreen_double_tap_reaches_control_channel_in_order() {
    tokio::time::timeout(Duration::from_secs(15), async {
        // The same in-memory network used by the original viewer's RTC tests.
        let router = Arc::new(tokio::sync::Mutex::new(Router::new(RouterConfig {
            cidr: "192.0.2.0/24".into(), ..Default::default()
        }).unwrap()));
        let mut settings = Vec::new();
        for address in ["192.0.2.10", "192.0.2.11"] {
            let net = Arc::new(Net::new(Some(NetConfig {
                static_ips: vec![address.into()], ..Default::default()
            })));
            let nic = net.get_nic().unwrap();
            router.lock().await.add_net(nic.clone()).await.unwrap();
            nic.lock().await.set_router(router.clone()).await.unwrap();
            let mut setting = SettingEngine::default();
            setting.set_vnet(Some(net));
            setting.set_network_types(vec![webrtc::ice::network_type::NetworkType::Udp4]);
            settings.push(setting);
        }
        router.lock().await.start().await.unwrap();
        let host = APIBuilder::new().with_setting_engine(settings.pop().unwrap()).build()
            .new_peer_connection(RTCConfiguration::default()).await.unwrap();
        let peer = input_peer(settings.pop().unwrap()).await;
        let (tx, mut received) = mpsc::channel(64);
        host.on_data_channel(Box::new(move |channel| {
            let tx = tx.clone();
            Box::pin(async move {
                let label = channel.label().to_owned();
                channel.on_message(Box::new(move |message| {
                    let (tx, label) = (tx.clone(), label.clone());
                    Box::pin(async move { tx.send((label, message.is_string, message.data)).await.unwrap(); })
                }));
            })
        }));
        let mut gathered = peer.pc.gathering_complete_promise().await;
        let offer = peer.pc.create_offer(None).await.unwrap();
        peer.pc.set_local_description(offer).await.unwrap(); gathered.recv().await;
        host.set_remote_description(peer.pc.local_description().await.unwrap()).await.unwrap();
        let mut gathered = host.gathering_complete_promise().await;
        let answer = host.create_answer(None).await.unwrap();
        host.set_local_description(answer).await.unwrap(); gathered.recv().await;
        peer.pc.set_remote_description(host.local_description().await.unwrap()).await.unwrap();
        while peer.control.ready_state() != webrtc::data_channel::data_channel_state::RTCDataChannelState::Open {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        let samples = [
            json!({"action":"touch_down","abs_x":0.25,"abs_y":0.5,"at_ms":1000}),
            json!({"action":"touch_up","abs_x":0.25,"abs_y":0.5,"at_ms":1080}),
            json!({"action":"touch_down","abs_x":0.252,"abs_y":0.5,"at_ms":1220}),
            json!({"action":"touch_up","abs_x":0.252,"abs_y":0.5,"at_ms":1300}),
            json!({"action":"mouse_move_absolute","abs_x":0.75,"abs_y":0.25}),
            json!({"action":"mouse_press","button":2}),
            json!({"action":"mouse_release","button":2}),
            json!({"action":"touch_down","abs_x":0.25,"abs_y":0.5,"at_ms":2000}),
            json!({"action":"touch_move","abs_x":0.5,"abs_y":0.5,"at_ms":2020}),
            json!({"action":"touch_up","abs_x":0.5,"abs_y":0.5,"at_ms":2080}),
            json!({"action":"key","scan":4,"down":true}),
            json!({"action":"key","scan":4,"down":false}),
        ];
        for sample in samples { peer.handle_input(&sample.to_string()).await.unwrap(); }
        peer.send_text_input("synthetic").await.unwrap();
        let expected = [
            json!({"action":"mouse_move_absolute","abs_x":0.25,"abs_y":0.5}),
            json!({"action":"mouse_press","button":1}),
            json!({"action":"mouse_release","button":1}),
            json!({"action":"mouse_move_absolute","abs_x":0.252,"abs_y":0.5}),
            json!({"action":"mouse_press","button":1}),
            json!({"action":"mouse_release","button":1}),
            json!({"action":"mouse_move_absolute","abs_x":0.75,"abs_y":0.25}),
            json!({"action":"mouse_press","button":2}),
            json!({"action":"mouse_release","button":2}),
            json!({"action":"mouse_move_absolute","abs_x":0.25,"abs_y":0.5}),
            json!({"action":"mouse_press","button":1}),
            json!({"action":"mouse_move_absolute","abs_x":0.5,"abs_y":0.5}),
            json!({"action":"mouse_release","button":1}),
            json!({"action":"kbd_press","key":65}),
            json!({"action":"kbd_release","key":65}),
            json!({"action":"text_input","content":"synthetic"}),
        ];
        for expected in expected {
            let (label, is_string, data) = received.recv().await.unwrap();
            assert_eq!(label, CHANNELS[0]); assert!(!is_string);
            assert_eq!(serde_json::from_slice::<Value>(&data).unwrap(), expected);
        }
        peer.view_only.store(true, Ordering::Release);
        peer.handle_input(r#"{"action":"mouse_move_absolute","abs_x":0.5,"abs_y":0.5}"#).await.unwrap();
        peer.send_text_input("synthetic").await.unwrap();
        assert!(tokio::time::timeout(Duration::from_millis(100), received.recv()).await.is_err());
        assert_eq!(peer.input_commands.load(Ordering::Relaxed), 13);
        assert_eq!(peer.input_messages.load(Ordering::Relaxed), 16);
        peer.stop().await;
        let (label, is_string, data) = received.recv().await.unwrap();
        assert_eq!(label, CHANNELS[1]); assert!(!is_string);
        let action = crate::harmony::tools::blob(&data, 3).expect("disconnect must send a SimpleAction");
        assert_eq!(crate::harmony::tools::uint(action, 1), 7, "disconnect must only stop capture, never reboot or shut down the remote computer");
        let args = crate::harmony::tools::blob(action, 2).unwrap();
        assert_eq!(serde_json::from_slice::<Value>(args).unwrap(), json!({"screen_id":-1}));
        assert!(tokio::time::timeout(Duration::from_millis(100), received.recv()).await.is_err(),
            "disconnect must not send additional system or input commands");
        peer.pc.close().await.unwrap(); host.close().await.unwrap();
        router.lock().await.stop().await.unwrap();
    }).await.expect("native CONTROL input regression timed out");
}

#[tokio::test]
async fn input_failure_is_reported_once_without_input_contents() {
    let peer = input_peer(SettingEngine::default()).await;
    assert!(peer.handle_input(r#"{"action":"mouse_press","button":1}"#).await.is_err());
    assert_eq!(peer.input_commands.load(Ordering::Relaxed), 1);
    assert_eq!(peer.input_messages.load(Ordering::Relaxed), 0);
    peer.report_input_error(); peer.report_input_error();
    let events = peer.events.lock().unwrap().clone();
    assert_eq!(events.len(), 1);
    let event: Value = serde_json::from_str(&events[0]).unwrap();
    assert_eq!(event["type"], "inputError");
    let data: Value = serde_json::from_str(event["data"].as_str().unwrap()).unwrap();
    assert_eq!(data["generation"], 7); assert!(data["message"].is_string());
    assert_eq!(data.as_object().unwrap().len(), 2);
    peer.pc.close().await.unwrap();
}

#[tokio::test]
async fn ended_session_cannot_emit_active_or_duplicate_terminal_states() {
    let peer = input_peer(SettingEngine::default()).await;
    peer.emit_state("ended", Some("remote session released"));
    peer.emit_state("viewOnly", None);
    peer.emit_state("playing", None);
    peer.emit_state("ended", Some("peer connection closed"));
    let events = peer.events.lock().unwrap().clone();
    assert_eq!(events.len(), 1);
    let envelope: Value = serde_json::from_str(&events[0]).unwrap();
    let state: Value = serde_json::from_str(envelope["data"].as_str().unwrap()).unwrap();
    assert_eq!(state["phase"], "ended");
    assert_eq!(state["error"], "remote session released");
    peer.pc.close().await.unwrap();
}

struct DelayedVideoRead {
    reader: Arc<dyn webrtc::interceptor::RTPReader + Send + Sync>,
    sequence: Option<u16>,
    consumed: mpsc::UnboundedSender<u16>,
    release: Arc<tokio::sync::Notify>,
}

#[async_trait::async_trait]
impl webrtc::interceptor::RTPReader for DelayedVideoRead {
    async fn read(&self, buf: &mut [u8], attributes: &webrtc::interceptor::Attributes)
        -> Result<(webrtc::rtp::packet::Packet, webrtc::interceptor::Attributes), webrtc::interceptor::Error> {
        let packet = self.reader.read(buf, attributes).await?;
        if Some(packet.0.header.sequence_number) == self.sequence {
            let _ = self.consumed.send(packet.0.header.sequence_number);
            self.release.notified().await;
        }
        Ok(packet)
    }
}

struct VideoFixture {
    peer: Arc<Peer>,
    host: RTCPeerConnection,
    video: Arc<webrtc::track::track_local::track_local_static_rtp::TrackLocalStaticRTP>,
    router: Arc<tokio::sync::Mutex<Router>>,
    frames: mpsc::UnboundedReceiver<(i64, Vec<u8>)>,
    consumed: mpsc::UnboundedReceiver<u16>,
    release: Arc<tokio::sync::Notify>,
    submitted: Box<mpsc::UnboundedSender<(i64, Vec<u8>)>>,
    reader_tasks: Arc<Mutex<Vec<tokio::task::JoinHandle<()>>>>,
}

impl VideoFixture {
    async fn new(delayed_sequence: Option<u16>) -> Self {
        use webrtc::interceptor::{mock::{mock_builder::MockBuilder, mock_interceptor::MockInterceptor}, registry::Registry};
        use webrtc::track::track_local::{track_local_static_rtp::TrackLocalStaticRTP, TrackLocal};
        let router = Arc::new(tokio::sync::Mutex::new(Router::new(RouterConfig {
            cidr: "192.0.2.0/24".into(), ..Default::default()
        }).unwrap()));
        let mut settings = Vec::new();
        for address in ["192.0.2.10", "192.0.2.11"] {
            let net = Arc::new(Net::new(Some(NetConfig { static_ips: vec![address.into()], ..Default::default() })));
            let nic = net.get_nic().unwrap();
            router.lock().await.add_net(nic.clone()).await.unwrap();
            nic.lock().await.set_router(router.clone()).await.unwrap();
            let mut setting = SettingEngine::default();
            setting.set_vnet(Some(net));
            setting.set_network_types(vec![webrtc::ice::network_type::NetworkType::Udp4]);
            settings.push(setting);
        }
        router.lock().await.start().await.unwrap();
        let mut engine = MediaEngine::default(); engine.register_default_codecs().unwrap();
        let host = APIBuilder::new().with_media_engine(engine).with_setting_engine(settings.pop().unwrap())
            .build().new_peer_connection(RTCConfiguration::default()).await.unwrap();
        let video = Arc::new(TrackLocalStaticRTP::new(RTCRtpCodecCapability {
            mime_type: "video/H264".into(), clock_rate: 90000,
            sdp_fmtp_line: "level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f".into(),
            ..Default::default()
        }, "synthetic-video".into(), "synthetic-stream".into()));
        host.add_track(video.clone() as Arc<dyn TrackLocal + Send + Sync>).await.unwrap();
        let (consumed_tx, consumed) = mpsc::unbounded_channel();
        let release = Arc::new(tokio::sync::Notify::new());
        let mut registry = Registry::new();
        let gate = release.clone();
        registry.add(Box::new(MockBuilder::new(move |_| {
            let (consumed, release) = (consumed_tx.clone(), gate.clone());
            Ok(Arc::new(MockInterceptor {
                bind_remote_stream_fn: Some(Box::new(move |_, reader| {
                    let (consumed, release) = (consumed.clone(), release.clone());
                    Box::pin(async move { Arc::new(DelayedVideoRead {
                        reader, sequence: delayed_sequence, consumed, release,
                    }) as Arc<dyn webrtc::interceptor::RTPReader + Send + Sync> })
                })), ..Default::default()
            }))
        })));
        let mut engine = MediaEngine::default(); engine.register_default_codecs().unwrap();
        let mut peer = input_peer_with_api(APIBuilder::new().with_media_engine(engine)
            .with_setting_engine(settings.pop().unwrap()).with_interceptor_registry(registry).build()).await;
        peer.pc.add_transceiver_from_kind(RTPCodecType::Video, Some(RTCRtpTransceiverInit {
            direction: RTCRtpTransceiverDirection::Recvonly, send_encodings: Vec::new(),
        })).await.unwrap();
        let (submitted_tx, frames) = mpsc::unbounded_channel();
        let mut submitted = Box::new(submitted_tx);
        unsafe extern "C" fn capture(user: *mut std::ffi::c_void, _: i32, _: i32, _: i32,
            pts: i64, data: *const u8, len: usize) -> i32 {
            let sender = &*(user as *const mpsc::UnboundedSender<(i64, Vec<u8>)>);
            let _ = sender.send((pts, std::slice::from_raw_parts(data, len).to_vec()));
            0
        }
        peer.platform = Platform::new(PlatformOps {
            user: (&mut *submitted as *mut mpsc::UnboundedSender<(i64, Vec<u8>)>).cast(),
            submit_video: Some(capture), submit_audio: None, attach_surface: None, detach_surface: None,
            input_capability: None, request_input_injection: None, submit_audio_packet: None, set_audio_muted: None,
        });
        let peer = Arc::new(peer);
        install_handlers(&peer);
        let reader_tasks = Arc::new(Mutex::new(Vec::new()));
        let (weak, tasks) = (Arc::downgrade(&peer), reader_tasks.clone());
        peer.pc.on_track(Box::new(move |track, _, _| {
            let (weak, tasks) = (weak.clone(), tasks.clone());
            Box::pin(async move {
                if let Some(peer) = weak.upgrade() {
                    tasks.lock().unwrap().push(tokio::spawn(peer.run_video(track)));
                }
            })
        }));
        let mut gathered = peer.pc.gathering_complete_promise().await;
        let offer = peer.pc.create_offer(None).await.unwrap();
        peer.pc.set_local_description(offer).await.unwrap(); gathered.recv().await;
        host.set_remote_description(peer.pc.local_description().await.unwrap()).await.unwrap();
        let mut gathered = host.gathering_complete_promise().await;
        let answer = host.create_answer(None).await.unwrap();
        host.set_local_description(answer).await.unwrap(); gathered.recv().await;
        peer.pc.set_remote_description(host.local_description().await.unwrap()).await.unwrap();
        while peer.pc.connection_state() != RTCPeerConnectionState::Connected {
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
        Self { peer, host, video, router, frames, consumed, release, submitted, reader_tasks }
    }

    async fn send(&self, seq: u16, timestamp: u32) {
        self.send_payload(seq, timestamp, vec![0x65, seq as u8]).await;
    }

    async fn send_payload(&self, seq: u16, timestamp: u32, payload: Vec<u8>) {
        use webrtc::track::track_local::TrackLocalWriter;
        self.video.write_rtp(&webrtc::rtp::packet::Packet {
            header: webrtc::rtp::header::Header { version: 2, sequence_number: seq, timestamp,
                marker: true, ..Default::default() },
            payload: bytes::Bytes::from(payload),
        }).await.unwrap();
    }

    async fn next_frame(&mut self) -> Option<(i64, Vec<u8>)> {
        tokio::time::timeout(Duration::from_millis(500), self.frames.recv()).await.ok().flatten()
    }

    async fn close(self) {
        self.release.notify_waiters();
        self.peer.pc.close().await.unwrap();
        self.host.close().await.unwrap();
        let tasks = std::mem::take(&mut *self.reader_tasks.lock().unwrap());
        for task in tasks { task.await.unwrap(); }
        self.router.lock().await.stop().await.unwrap();
        drop(self.submitted);
    }
}

#[tokio::test]
async fn video_recovery_request_survives_pli_throttling_without_further_packets() {
    tokio::time::timeout(Duration::from_secs(10), async {
        let mut fixture = VideoFixture::new(None).await;
        fixture.send(0, 0).await;
        assert!(fixture.next_frame().await.is_some());
        let sender = fixture.host.get_senders().await.into_iter().next().unwrap();
        fixture.send_payload(1, 9000, vec![0xff]).await;
        let first = tokio::time::timeout(Duration::from_secs(1), sender.read_rtcp()).await.unwrap().unwrap();
        assert!(first.0.iter().any(|packet| packet.as_any().is::<PictureLossIndication>()));
        tokio::time::sleep(Duration::from_millis(60)).await;
        fixture.send_payload(2, 18000, vec![0xff]).await;
        let second = tokio::time::timeout(Duration::from_secs(1), sender.read_rtcp()).await;
        fixture.close().await;
        assert!(second.is_ok(), "a throttled recovery request was lost when no further packets arrived");
        assert!(second.unwrap().unwrap().0.iter().any(|packet| packet.as_any().is::<PictureLossIndication>()));
    }).await.expect("synthetic PLI throttle test timed out");
}

#[tokio::test]
async fn video_reader_keeps_consumed_packet_across_timer_ticks() {
    tokio::time::timeout(Duration::from_secs(15), async {
        let mut fixture = VideoFixture::new(Some(2)).await;
        fixture.send(1, 90000).await;
        let first = fixture.next_frame().await;
        fixture.send(2, 180000).await;
        assert_eq!(tokio::time::timeout(Duration::from_secs(1), fixture.consumed.recv()).await.unwrap(), Some(2));
        // The packet has left SRTP, but its read future remains pending through several expiry ticks.
        tokio::time::sleep(Duration::from_millis(130)).await;
        fixture.release.notify_one();
        let second = fixture.next_frame().await;
        fixture.close().await;
        assert_eq!(first, Some((1_000_000, vec![0, 0, 0, 1, 0x65, 1])));
        assert_eq!(second, Some((2_000_000, vec![0, 0, 0, 1, 0x65, 2])));
    }).await.expect("in-memory delayed video reader timed out");
}

#[tokio::test]
async fn reordered_video_units_keep_their_own_presentation_timestamps() {
    tokio::time::timeout(Duration::from_secs(15), async {
        let mut fixture = VideoFixture::new(None).await;
        fixture.send(1, 90000).await;
        let first = fixture.next_frame().await;
        fixture.send(3, 270000).await;
        while fixture.peer.media_packets.load(Ordering::Acquire) < 2 { tokio::task::yield_now().await; }
        fixture.send(2, 180000).await;
        let second = fixture.next_frame().await;
        let third = fixture.next_frame().await;
        fixture.close().await;
        assert_eq!(first, Some((1_000_000, vec![0, 0, 0, 1, 0x65, 1])));
        assert_eq!(second, Some((2_000_000, vec![0, 0, 0, 1, 0x65, 2])));
        assert_eq!(third, Some((3_000_000, vec![0, 0, 0, 1, 0x65, 3])));
    }).await.expect("in-memory reordered video reader timed out");
}

#[tokio::test]
async fn namespace_release_ends_its_session_without_leaving_again() {
    use tokio_tungstenite::tungstenite::Message;
    tokio::time::timeout(Duration::from_secs(6), async {
        for name in ["leave", "publisher_disconnect"] {
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let url = format!("ws://{}", listener.local_addr().unwrap());
            let server = tokio::spawn(async move {
                let mut ws = tokio_tungstenite::accept_async(listener.accept().await.unwrap().0).await.unwrap();
                ws.send(Message::Text("0{}".into())).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text("40".into()));
                ws.send(Message::Text("40{}".into())).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text(r#"421["room_info"]"#.into()));
                ws.send(Message::Text(r#"431[{"participants_info":[]}]"#.into())).await.unwrap();
                ws.send(Message::Text(r#"42["released",{"client_id":"another-peer"}]"#.into())).await.unwrap();
                ws.send(Message::Text("2probe".into())).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text("3probe".into()));
                ws.send(Message::Text(format!("42{}", serde_json::json!([name,{"client_id":"local-controller","ice_id":"other-route"}])))).await.unwrap();
                let next = tokio::time::timeout(Duration::from_millis(500), ws.next()).await;
                let closed = matches!(next, Ok(Some(Ok(Message::Close(_)))));
                if closed { ws.flush().await.unwrap(); }
                closed
            });
            let signal = Signal::connect(&[url], "synthetic", Duration::from_secs(1), true).await.unwrap();
            let peer = input_peer(SettingEngine::default()).await;
            peer.echo_received.store(true, Ordering::Release);
            let peer = Arc::new(peer);
            let (_candidate_tx, candidates) = mpsc::channel(1);
            let (_tx, commands) = mpsc::channel(1);
            run_session(signal, peer.clone(), candidates, commands).await;
            assert!(server.await.unwrap(), "namespace release was ignored or sent a duplicate leave");
            let events = peer.events.lock().unwrap();
            assert!(events.iter().any(|event| event.contains("remote session released")));
        }
    }).await.expect("namespace release cleanup timed out");
}

#[tokio::test]
async fn session_leaves_signaling_before_waiting_for_rtc_close() {
    use tokio_tungstenite::tungstenite::Message;
    tokio::time::timeout(Duration::from_secs(6), async {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("ws://{}", listener.local_addr().unwrap());
        let leave_seen = Arc::new(AtomicBool::new(false));
        let seen = leave_seen.clone();
        let server = tokio::spawn(async move {
            let mut ws = tokio_tungstenite::accept_async(listener.accept().await.unwrap().0).await.unwrap();
            ws.send(Message::Text("0{}".into())).await.unwrap();
            assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text("40".into()));
            ws.send(Message::Text("40{}".into())).await.unwrap();
            assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text(r#"421["room_info"]"#.into()));
            ws.send(Message::Text(r#"431[{"participants_info":[]}]"#.into())).await.unwrap();
            assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text(r#"42["leave"]"#.into()));
            seen.store(true, Ordering::Release);
            assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text("41".into()));
            assert!(matches!(ws.next().await, Some(Ok(Message::Close(_)))));
            ws.flush().await.unwrap();
        });
        let signal = Signal::connect(&[url], "synthetic", Duration::from_secs(1), true).await.unwrap();
        let mut peer = input_peer(SettingEngine::default()).await;
        peer.capture_type = 5;
        let peer = Arc::new(peer);
        let resume = Arc::new(tokio::sync::Notify::new());
        let release = resume.clone();
        let (closed_tx, mut closed_rx) = mpsc::channel(1);
        peer.pc.on_peer_connection_state_change(Box::new(move |state| {
            let sender = closed_tx.clone();
            let seen = leave_seen.clone();
            let release = release.clone();
            Box::pin(async move {
                if state == RTCPeerConnectionState::Closed {
                    sender.send(seen.load(Ordering::Acquire)).await.unwrap();
                    release.notified().await;
                }
            })
        }));
        let (_candidate_tx, candidates) = mpsc::channel(1);
        let (tx, commands) = mpsc::channel(1);
        tx.send(SessionCommand::Close).await.unwrap();
        let task = tokio::spawn(run_session(signal, peer, candidates, commands));
        let leave_preceded_rtc_close = closed_rx.recv().await.unwrap();
        resume.notify_one();
        task.await.unwrap();
        server.await.unwrap();
        assert!(leave_preceded_rtc_close, "RTC shutdown blocked the business leave signal");
    }).await.expect("signal-before-RTC cleanup timed out");
}

#[tokio::test]
async fn session_close_preserves_signaling_timeout_and_defers_local_ended() {
    use tokio_tungstenite::tungstenite::Message;
    tokio::time::timeout(Duration::from_secs(6), async {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("ws://{}", listener.local_addr().unwrap());
        let (seen_tx, seen_rx) = tokio::sync::oneshot::channel();
        let (release_tx, release_rx) = tokio::sync::oneshot::channel();
        let server = tokio::spawn(async move {
            let mut ws = tokio_tungstenite::accept_async(listener.accept().await.unwrap().0).await.unwrap();
            ws.send(Message::Text("0{}".into())).await.unwrap();
            assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text("40".into()));
            ws.send(Message::Text("40{}".into())).await.unwrap();
            assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text(r#"421["room_info"]"#.into()));
            ws.send(Message::Text(r#"431[{"participants_info":[]}]"#.into())).await.unwrap();
            assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text(r#"42["leave"]"#.into()));
            assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text("41".into()));
            assert!(matches!(ws.next().await, Some(Ok(Message::Close(_)))));
            seen_tx.send(()).unwrap();
            let _ = release_rx.await;
        });
        let signal = Signal::connect(&[url], "synthetic", Duration::from_secs(1), true).await.unwrap();
        let signal_closed = signal.closed();
        let mut peer = input_peer(SettingEngine::default()).await;
        peer.capture_type = 1;
        let peer = Arc::new(peer);
        let events = peer.events.clone();
        let (tx, commands) = mpsc::channel(1);
        let (_candidate_tx, candidates) = mpsc::channel(1);
        let task = tokio::spawn(run_session(signal, peer.clone(), candidates, commands));
        let handle = SessionHandle { tx, task: Some(task), snapshot: peer.snapshot("waitingFirstFrame", None),
            tools: peer.tools.clone(), peer, signal_closed };
        let closing = tokio::spawn(handle.close());
        seen_rx.await.unwrap();
        let early_ended = events.lock().unwrap().iter().any(|raw| {
            let value: Value = serde_json::from_str(raw).unwrap();
            value["type"] == "sessionState" && value["data"].as_str().is_some_and(|data| data.contains("ended"))
        });
        let result = serde_json::to_value(closing.await.unwrap()).unwrap();
        let _ = release_tx.send(());
        server.await.unwrap();
        assert!(result.get("Err").is_some(), "signaling timeout was reported as a successful local close: {result}");
        assert!(!early_ended, "local ended was published before signaling cleanup completed");
    }).await.expect("signaling timeout regression stalled");
}

#[tokio::test]
async fn forced_session_close_waits_for_dropped_signal_cleanup() {
    use tokio_tungstenite::tungstenite::Message;
    tokio::time::timeout(Duration::from_secs(6), async {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("ws://{}", listener.local_addr().unwrap());
        let (seen_tx, seen_rx) = tokio::sync::oneshot::channel();
        let (release_tx, release_rx) = tokio::sync::oneshot::channel();
        let server = tokio::spawn(async move {
            let mut ws = tokio_tungstenite::accept_async(listener.accept().await.unwrap().0).await.unwrap();
            ws.send(Message::Text("0{}".into())).await.unwrap();
            assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text("40".into()));
            ws.send(Message::Text("40{}".into())).await.unwrap();
            assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text(r#"421["room_info"]"#.into()));
            ws.send(Message::Text(r#"431[{"participants_info":[]}]"#.into())).await.unwrap();
            assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text(r#"42["leave"]"#.into()));
            assert_eq!(ws.next().await.unwrap().unwrap(), Message::Text("41".into()));
            assert!(matches!(ws.next().await, Some(Ok(Message::Close(_)))));
            seen_tx.send(()).unwrap();
            release_rx.await.unwrap();
            ws.flush().await.unwrap();
        });
        let signal = Signal::connect(&[url], "synthetic", Duration::from_secs(1), true).await.unwrap();
        let signal_closed = signal.closed();
        let mut peer = input_peer(SettingEngine::default()).await;
        peer.capture_type = 5;
        let peer = Arc::new(peer);
        let rtc_resume = Arc::new(tokio::sync::Notify::new());
        let resume = rtc_resume.clone();
        peer.pc.on_peer_connection_state_change(Box::new(move |state| {
            let resume = resume.clone();
            Box::pin(async move { if state == RTCPeerConnectionState::Closed { resume.notified().await; } })
        }));
        let (tx, _rx) = mpsc::channel(1);
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
        let task = tokio::spawn(async move {
            let _signal = signal;
            ready_tx.send(()).unwrap();
            std::future::pending::<()>().await;
        });
        ready_rx.await.unwrap();
        let handle = SessionHandle {
            tx, task: Some(task), snapshot: peer.snapshot("waitingFirstFrame", None),
            tools: peer.tools.clone(), peer, signal_closed,
        };
        let closing = tokio::spawn(handle.close());
        seen_rx.await.unwrap();
        tokio::task::yield_now().await;
        let returned_before_signal_cleanup = closing.is_finished();
        release_tx.send(()).unwrap();
        rtc_resume.notify_one();
        closing.await.unwrap().unwrap(); server.await.unwrap();
        assert!(!returned_before_signal_cleanup, "disconnect returned before its dropped signal completed cleanup");
    }).await.expect("forced signal cleanup timed out");
}

#[tokio::test]
async fn cancelled_session_close_still_reaps_its_task_when_command_queue_is_full() {
    tokio::time::timeout(Duration::from_secs(8), async {
        struct Dropped(Arc<AtomicBool>);
        impl Drop for Dropped {
            fn drop(&mut self) { self.0.store(true, Ordering::Release); }
        }
        let peer = Arc::new(input_peer(SettingEngine::default()).await);
        let (tx, rx) = mpsc::channel(1);
        assert!(tx.try_send(SessionCommand::Rendered).is_ok());
        let dropped = Arc::new(AtomicBool::new(false));
        let flag = dropped.clone();
        let (started, ready) = tokio::sync::oneshot::channel();
        let task = tokio::spawn(async move {
            let _guard = Dropped(flag);
            let _ = started.send(());
            std::future::pending::<()>().await;
            drop(rx);
        });
        let abort = task.abort_handle();
        ready.await.unwrap();
        let handle = SessionHandle {
            tx, task: Some(task), snapshot: peer.snapshot("waitingFirstFrame", None),
            tools: peer.tools.clone(), peer: peer.clone(), signal_closed: tokio::sync::watch::channel(Some(Default::default())).1,
        };
        assert!(tokio::time::timeout(Duration::from_millis(20), handle.close()).await.is_err());
        let cleaned = tokio::time::timeout(Duration::from_millis(2500), async {
            while !dropped.load(Ordering::Acquire) { tokio::time::sleep(Duration::from_millis(10)).await; }
        }).await.is_ok();
        // Reap the deliberately stalled task even when testing the broken close implementation.
        abort.abort();
        while !dropped.load(Ordering::Acquire) { tokio::task::yield_now().await; }
        peer.pc.close().await.unwrap();
        assert!(cleaned, "cancelling close detached the session task without its cleanup owner");
    }).await.expect("synthetic cancelled session close timed out");
}

#[tokio::test]
async fn ended_video_session_never_submits_late_packets_to_the_native_decoder() {
    tokio::time::timeout(Duration::from_secs(15), async {
        let mut fixture = VideoFixture::new(None).await;
        fixture.send(1, 90000).await;
        let first = fixture.next_frame().await;
        fixture.peer.emit_state("ended", Some("synthetic remote release"));
        fixture.send(2, 180000).await;
        let received = tokio::time::timeout(Duration::from_secs(1), async {
            while fixture.peer.media_packets.load(Ordering::Acquire) < 2 { tokio::task::yield_now().await; }
        }).await.is_ok();
        let late_frame = fixture.next_frame().await;
        fixture.close().await;
        assert_eq!(first, Some((1_000_000, vec![0, 0, 0, 1, 0x65, 1])));
        assert!(received, "the terminal gate must be tested after a late packet reaches run_video");
        assert_eq!(late_frame, None);
    }).await.expect("in-memory ended video gate timed out");
}

#[tokio::test]
async fn video_presentation_timestamps_remain_continuous_across_rtp_rollover() {
    tokio::time::timeout(Duration::from_secs(15), async {
        let mut fixture = VideoFixture::new(None).await;
        let before_wrap = u32::MAX - 89999;
        fixture.send(1, before_wrap).await;
        let first = fixture.next_frame().await;
        fixture.send(2, 0).await;
        let second = fixture.next_frame().await;
        fixture.send(3, 90000).await;
        let third = fixture.next_frame().await;
        fixture.close().await;
        let cycle = i64::from(u32::MAX) + 1;
        assert_eq!(first, Some((i64::from(before_wrap) * 1_000_000 / 90000, vec![0, 0, 0, 1, 0x65, 1])));
        assert_eq!(second, Some((cycle * 1_000_000 / 90000, vec![0, 0, 0, 1, 0x65, 2])));
        assert_eq!(third, Some(((cycle + 90000) * 1_000_000 / 90000, vec![0, 0, 0, 1, 0x65, 3])));
    }).await.expect("in-memory RTP rollover timed out");
}

#[tokio::test]
async fn closing_a_desktop_session_stops_audio_without_tool_sessions_muting_it() {
    tokio::time::timeout(Duration::from_secs(5), async {
        unsafe extern "C" fn mute(user: *mut std::ffi::c_void, muted: i32) -> i32 {
            let calls = &*(user as *const [AtomicU64; 2]);
            calls[usize::from(muted == 1)].fetch_add(1, Ordering::Relaxed);
            0
        }
        let calls = Box::new([AtomicU64::new(0), AtomicU64::new(0)]);
        let platform = Platform::new(PlatformOps {
            user: (&*calls as *const [AtomicU64; 2]).cast_mut().cast(),
            submit_video: None, submit_audio: None, attach_surface: None, detach_surface: None,
            input_capability: None, request_input_injection: None, submit_audio_packet: None,
            set_audio_muted: Some(mute),
        });
        let mut desktop = input_peer(SettingEngine::default()).await;
        desktop.platform = platform;
        desktop.close().await;
        let after_desktop = calls[1].load(Ordering::Relaxed);
        let mut tool = input_peer(SettingEngine::default()).await;
        tool.capture_type = 5;
        tool.platform = platform;
        tool.close().await;
        let after_tool = calls[1].load(Ordering::Relaxed);
        assert_eq!(after_desktop, 1, "desktop close must stop its native audio renderer");
        assert_eq!(after_tool, after_desktop, "tool close must leave desktop audio untouched");
        assert_eq!(calls[0].load(Ordering::Relaxed), 0, "closing sessions must never restart native audio");
    }).await.expect("synthetic audio close timed out");
}

