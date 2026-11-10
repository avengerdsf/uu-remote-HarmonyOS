//! Framing/ack evidence: internal viewer-evidence-20261016.md section 3.
//! Raw Engine.IO4 attachments and legacy SDK 0x04 framing are explicit alternatives.
use base64::Engine as _;
use futures_util::{SinkExt, StreamExt};
use serde_json::Value;
use tokio_tungstenite::tungstenite::{client::IntoClientRequest, Message};
use std::{collections::VecDeque,time::Duration};

#[derive(Clone,Default)]
pub struct CleanupBarrier(std::sync::Arc<std::sync::Mutex<Vec<tokio::sync::watch::Receiver<Option<CloseReport>>>>>);
impl CleanupBarrier {
    pub fn detach(&self,closed:&tokio::sync::watch::Receiver<Option<CloseReport>>) {
        if let Ok(mut pending)=self.0.lock() {pending.retain(|receiver|!receiver.same_channel(closed));}
    }
    pub async fn wait(&self)->Result<(),String> {
        let pending={std::mem::take(&mut *self.0.lock().map_err(|_|"信令清理失败，远端会话释放尚未确认")?)};
        let mut result=Ok(());
        for mut closed in pending {
            let report=loop {
                if let Some(report)=closed.borrow_and_update().as_ref() {break report.result()}
                if closed.changed().await.is_err() {break Err("信令清理失败，远端会话释放尚未确认".into())}
            };
            result=report.and(result);
        }
        result
    }
}

pub struct Signal {
    ws: Option<crate::ws_transport::Socket>,
    next_ack:u64,
    pending:VecDeque<Value>,
    legacy_prefix:bool,
    binary:Option<BinaryPacket>,
    namespace_connected:bool,
    closed:tokio::sync::watch::Sender<Option<CloseReport>>,
}
struct BinaryPacket { ack:Option<u64>, event_ack:Option<u64>, count:usize, value:Value, attachments:Vec<String> }
#[derive(Clone,Default,serde::Serialize)]
#[serde(rename_all="camelCase")]
pub struct CloseReport {
    namespace_connected:bool,
    leave_sent:bool,
    namespace_sent:bool,
    close_sent:bool,
    close_received:bool,
    timed_out:bool,
    failed:bool,
}
impl CloseReport {
    pub fn result(&self)->Result<(),String> {
        if self.timed_out {Err("信令清理超时，远端会话释放尚未确认".into())}
        else if self.failed {Err("信令清理失败，远端会话释放尚未确认".into())}
        else {Ok(())}
    }
}
impl Drop for Signal {
    fn drop(&mut self) {
        if let Some(ws)=self.ws.take() {
            let connected=self.namespace_connected;
            if let Ok(runtime)=tokio::runtime::Handle::try_current() {
                runtime.spawn(Self::close_socket(ws,connected,self.closed.clone()));
            }
        }
    }
}
impl BinaryPacket {
    fn finish(mut self)->Packet {
        fn fill(value:&mut Value,attachments:&[String]) {
            match value {
                Value::Object(o) if o.get("_placeholder")==Some(&Value::Bool(true))=>{
                    if let Some(s)=o.get("num").and_then(Value::as_u64).and_then(|n|attachments.get(n as usize)) {*value=Value::String(s.clone());}
                }
                Value::Object(o)=>for x in o.values_mut(){fill(x,attachments)},
                Value::Array(a)=>for x in a{fill(x,attachments)},
                _=>{},
            }
        }
        fill(&mut self.value,&self.attachments);
        match self.ack {Some(id)=>Packet::Ack(id,self.value),None=>Packet::Event(self.value)}
    }
}
impl Signal {
    pub async fn connect(urls:&[String], token:&str, timeout:Duration, legacy_prefix:bool)->Result<Self,String> {
        Self::connect_tracked(urls,token,timeout,legacy_prefix,None).await
    }
    pub async fn connect_tracked(urls:&[String], token:&str, timeout:Duration, legacy_prefix:bool, cleanup:Option<&CleanupBarrier>)->Result<Self,String> {
        for url in urls {
            if let Ok(signal)=Self::one(url,token,legacy_prefix,timeout,cleanup).await {return Ok(signal)}
        }
        Err("Signaling connection failed (details omitted)".into())
    }
    async fn one(url:&str,token:&str,legacy_prefix:bool,timeout:Duration,cleanup:Option<&CleanupBarrier>)->Result<Self,String> {
        let mut request=format!("{}/socket.io/?transport=websocket&EIO=4",url.trim_end_matches('/')).into_client_request().map_err(|_|"Invalid signaling endpoint")?;
        request.headers_mut().insert("X-NRD-AUTH",token.parse().map_err(|_|"Invalid room authentication header")?);
        request.headers_mut().insert("X-NRD-CONTROLLING","0".parse().unwrap());
        let ws=crate::ws_transport::connect(request,timeout).await?;
        let mut s=Self{ws:Some(ws),next_ack:10,pending:VecDeque::new(),legacy_prefix,binary:None,namespace_connected:false,
            closed:tokio::sync::watch::channel(None).0};
        if let Some(cleanup)=cleanup {cleanup.0.lock().map_err(|_|"Signaling cleanup unavailable")?.push(s.closed());}
        let mut opened=false;
        let result=tokio::time::timeout(timeout,async {
        loop {
            match s.ws.as_mut().unwrap().next().await {
                Some(Ok(Message::Text(t))) if t.starts_with('0') && !opened => {
                    serde_json::from_str::<Value>(&t[1..]).map_err(|_|"Invalid Engine.IO open")?;
                    opened=true;s.send(Message::Text("40".into())).await?;
                }
                Some(Ok(Message::Text(t))) if t.starts_with("40") && opened =>{s.namespace_connected=true;return s.login_room().await},
                Some(Ok(Message::Text(t))) if t.starts_with('2')=>s.send(Message::Text(format!("3{}",&t[1..]))).await?,
                Some(Ok(Message::Ping(b)))=>s.send(Message::Pong(b)).await?,
                _=>return Err("Signaling handshake failed".into()),
            }
        }
        }).await.unwrap_or_else(|_|Err("Signaling handshake timed out".into()));
        match result {Ok(())=>Ok(s),Err(error)=>{s.close().await;Err(error)}}
    }
    // Interop evidence: openuuyc a87b8e7 signal/mod.rs login_room.
    async fn login_room(&mut self)->Result<(),String> {
        self.send(Message::Text(r#"421["room_info"]"#.into())).await?;
        loop {
            match self.packet().await? {
                Packet::Ack(1,value)=>return if value.get(0).and_then(Value::as_object).is_some_and(|info|!info.is_empty()) {
                    Ok(())
                } else {Err("Invalid room information acknowledgement".into())},
                Packet::Event(value)=>{
                    if self.pending.len()>=64 {return Err("Too many pre-control signaling events".into())}
                    self.pending.push_back(value);
                }
                _=>{},
            }
        }
    }
    async fn send(&mut self,message:Message)->Result<(),String> {self.ws.as_mut().ok_or("Signaling closed")?.send(message).await.map_err(|_|"Signaling send failed".into())}
    pub async fn control(&mut self, header:Value, app_data:Vec<u8>, timeout:Duration)->Result<Value,String> {
        self.next_ack+=1;let id=self.next_ack;
        self.send(Message::Text(format!("451-{id}{}",serde_json::json!(["control",header])))).await?;
        let mut attachment=Vec::new();if self.legacy_prefix {attachment.push(4)} attachment.extend(app_data);
        self.send(Message::Binary(attachment)).await?;
        tokio::time::timeout(timeout,async {
            loop {
                match self.packet().await? {
                    Packet::Ack(ack,value) if ack==id=> {
                        let a=value.as_array().ok_or("Invalid control acknowledgement")?;
                        if a.len()!=2 || a[0].as_str()!=Some("success") || !a[1].is_object() {return Err("Control refused or malformed acknowledgement".into())}
                        if a[1].get("code").is_some_and(|code|code.as_i64()!=Some(0)) {return Err("Control refused or malformed acknowledgement".into())}
                        if a[1].get("ice_id").and_then(Value::as_str).filter(|id|!id.is_empty()&&id.len()<=128).is_none() {
                            return Err("Control acknowledgement missing ICE route".into())
                        }
                        if a[1].get("client_id").and_then(Value::as_str).filter(|id|!id.is_empty()).is_none() {
                            return Err("control acknowledgement missing peer route".into())
                        }
                        return Ok(a[1].clone());
                    }
                    Packet::Event(value)=> {
                        if self.pending.len()>=64 {return Err("Too many pre-control signaling events".into())}
                        self.pending.push_back(value);
                    }
                    _=>{},
                }
            }
        }).await.map_err(|_|"Control acknowledgement timed out")?
    }
    async fn packet(&mut self)->Result<Packet,String> {
        loop {
            match self.ws.as_mut().ok_or("Signaling closed")?.next().await {
                Some(Ok(Message::Text(t))) if t.starts_with('2')=>self.send(Message::Text(format!("3{}",&t[1..]))).await?,
                Some(Ok(Message::Ping(b)))=>self.send(Message::Pong(b)).await?,
                Some(Ok(Message::Text(t))) if t.starts_with("43")=> {
                    let begin=t.find('[').ok_or("Malformed signaling acknowledgement")?;
                    let id=t[2..begin].parse().map_err(|_|"Malformed signaling acknowledgement id")?;
                    let value=serde_json::from_str(&t[begin..]).map_err(|_|"Malformed signaling acknowledgement body")?;
                    return Ok(Packet::Ack(id,value))
                }
                Some(Ok(Message::Text(t))) if t.starts_with("42")=> {
                    let begin=t.find('[').ok_or("Malformed signaling event")?;
                    let value=serde_json::from_str(&t[begin..]).map_err(|_|"Malformed signaling event body")?;
                    if begin>2 {
                        let id:u64=t[2..begin].parse().map_err(|_|"Malformed signaling event id")?;
                        self.send(Message::Text(format!("43{id}[]"))).await?;
                    }
                    return Ok(Packet::Event(value))
                }
                // Socket.IO binary event (45N-[...] / 46N-[...] ack) followed by N attachment frames.
                // The official host sends its answer this way (binary gzip_sdp); attachments are
                // substituted as base64 strings so the existing gzip_sdp decoder applies.
                Some(Ok(Message::Text(t))) if t.starts_with("45") || t.starts_with("46")=> {
                    let dash=t.find('-').ok_or("Malformed binary signaling packet")?;
                    let count:usize=t[2..dash].parse().map_err(|_|"Malformed binary attachment count")?;
                    if count>8 {return Err("Too many signaling attachments".into())}
                    let begin=t.find('[').ok_or("Malformed binary signaling packet")?;
                    if self.binary.is_some() {return Err("Interleaved binary signaling packets".into())}
                    let value:Value=serde_json::from_str(&t[begin..]).map_err(|_|"Malformed binary signaling body")?;
                    let ack=if t.starts_with("46") {Some(t[dash+1..begin].parse().map_err(|_|"Malformed binary acknowledgement id")?)}else{None};
                    let event_ack=if t.starts_with("45") && begin>dash+1 {Some(t[dash+1..begin].parse().map_err(|_|"Malformed binary event id")?)}else{None};
                    let packet=BinaryPacket{ack,event_ack,count,value,attachments:Vec::with_capacity(count)};
                    if count==0 {
                        if let Some(id)=packet.event_ack {self.send(Message::Text(format!("43{id}[]"))).await?;}
                        return Ok(packet.finish())
                    }
                    // select! may drop packet() between frames. Keep the header and
                    // every attachment on Signal so the next event() resumes them.
                    self.binary=Some(packet);
                }
                Some(Ok(Message::Binary(mut b))) if self.binary.is_some()=>{
                    if b.len()>2 && b[0]==4 && b[1]==0x1f {b.remove(0);}
                    if b.len()>4*1024*1024 {return Err("Signaling attachment too large".into())}
                    let packet=self.binary.as_mut().unwrap();
                    packet.attachments.push(base64::engine::general_purpose::STANDARD.encode(&b));
                    if packet.attachments.len()==packet.count {
                        let packet=self.binary.take().unwrap();
                        if let Some(id)=packet.event_ack {self.send(Message::Text(format!("43{id}[]"))).await?;}
                        return Ok(packet.finish())
                    }
                }
                Some(Ok(Message::Text(t))) if t=="41" || t=="1"=>{self.namespace_connected=false;return Err("Signaling room closed".into())},
                Some(Ok(Message::Close(_)))|None|Some(Err(_))=>{self.namespace_connected=false;return Err("Signaling disconnected".into())},
                // Type, short prefix and length only, to see what else the room delivers.
                Some(Ok(Message::Text(t)))=>log::info!("Viewer signaling frame ignored: text prefix={} bytes={}",t.chars().take(3).collect::<String>(),t.len()),
                Some(Ok(Message::Binary(b)))=>log::info!("Viewer signaling frame ignored: binary bytes={}",b.len()),
                _=>{},
            }
        }
    }
    pub async fn event(&mut self)->Result<Value,String> {
        if let Some(v)=self.pending.pop_front(){return Ok(v)}
        loop {if let Packet::Event(v)=self.packet().await?{return Ok(v)}}
    }
    pub async fn soac(&mut self, value:Value)->Result<(),String> {self.send(Message::Text(format!("42{}",serde_json::json!(["soac",value])))).await}
    pub fn released(&mut self) {self.namespace_connected=false;}
    pub fn closed(&self)->tokio::sync::watch::Receiver<Option<CloseReport>> {self.closed.subscribe()}
    pub async fn close(&mut self)->CloseReport {
        if let Some(ws)=self.ws.take() {
            let connected=std::mem::replace(&mut self.namespace_connected,false);
            let report=tokio::spawn(Self::close_socket(ws,connected,self.closed.clone())).await
                .unwrap_or_else(|_|CloseReport{failed:true,..Default::default()});
            self.closed.send_replace(Some(report.clone()));
            return report;
        }
        CloseReport::default()
    }
    async fn close_socket(mut ws:crate::ws_transport::Socket,connected:bool,closed:tokio::sync::watch::Sender<Option<CloseReport>>)->CloseReport {
        // UU controller close: openuuyc a87b8e7 transport.rs close_socket.
        // Business leave precedes namespace disconnect; a released viewer must not leave again.
        let mut report=CloseReport{namespace_connected:connected,..Default::default()};
        let result=tokio::time::timeout(Duration::from_millis(750),async {
            if connected {
                ws.send(Message::Text(r#"42["leave"]"#.into())).await.ok()?;
                report.leave_sent=true;
                ws.send(Message::Text("41".into())).await.ok()?;
                report.namespace_sent=true;
            }
            ws.close(Some(tokio_tungstenite::tungstenite::protocol::CloseFrame{
                code:tokio_tungstenite::tungstenite::protocol::frame::coding::CloseCode::Normal,reason:"".into()
            })).await.ok()?;
            report.close_sent=true;
            while let Some(message)=ws.next().await {
                match message {
                    Ok(Message::Close(_))=>{report.close_received=true;break},
                    Err(_)=>return None,
                    _=>{},
                }
            }
            report.close_received.then_some(())
        }).await;
        report.timed_out=result.is_err();
        report.failed=matches!(result,Ok(None));
        closed.send_replace(Some(report.clone()));
        report
    }
}
enum Packet { Ack(u64,Value), Event(Value) }

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn cancelled_open_cleanup_barrier_waits_for_the_close_report() {
        tokio::time::timeout(Duration::from_secs(4),async {
            let listener=tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let url=format!("ws://{}",listener.local_addr().unwrap());
            let(ready_tx,ready_rx)=tokio::sync::oneshot::channel();
            let(seen_tx,seen_rx)=tokio::sync::oneshot::channel();
            let(release_tx,release_rx)=tokio::sync::oneshot::channel();
            let server=tokio::spawn(async move {
                let mut ws=tokio_tungstenite::accept_async(listener.accept().await.unwrap().0).await.unwrap();
                ws.send(Message::Text("0{}".into())).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text("40".into()));
                ws.send(Message::Text("40{}".into())).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text(r#"421["room_info"]"#.into()));
                ready_tx.send(()).unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text(r#"42["leave"]"#.into()));
                assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text("41".into()));
                assert!(matches!(ws.next().await,Some(Ok(Message::Close(_)))));
                seen_tx.send(()).unwrap();
                release_rx.await.unwrap();
                ws.flush().await.unwrap();
            });
            let cleanup=CleanupBarrier::default();
            let tracked=cleanup.clone();
            let connecting=tokio::spawn(async move {
                Signal::connect_tracked(&[url],"synthetic",Duration::from_secs(2),true,Some(&tracked)).await
            });
            ready_rx.await.unwrap();
            connecting.abort();let _=connecting.await;
            seen_rx.await.unwrap();
            let waiting=tokio::spawn(async move {cleanup.wait().await});
            tokio::task::yield_now().await;
            let returned_early=waiting.is_finished();
            release_tx.send(()).unwrap();
            waiting.await.unwrap().unwrap();server.await.unwrap();
            assert!(!returned_early,"cancelled opening acknowledged cleanup before the close handshake");
        }).await.expect("cancelled opening cleanup stalled");
    }

    #[tokio::test]
    async fn control_ack_rejects_unusable_cloud_routes() {
        tokio::time::timeout(Duration::from_secs(8),async {
            let valid=serde_json::json!({"code":0,"client_id":"synthetic-peer","ice_id":"synthetic-ice","iceServers":[]});
            let mut cases=Vec::new();
            for field in ["ice_id","client_id"] {
                for value in [Value::Null,Value::String(String::new()),Value::Bool(true)] {
                    let mut ack=valid.clone();ack[field]=value;cases.push((ack,false));
                }
            }
            let mut long=valid.clone();long["ice_id"]=Value::String("i".repeat(129));cases.push((long,false));
            let mut refused=valid.clone();refused["code"]=Value::from(2002);cases.push((refused,false));
            cases.push((valid,true));
            for(ack,usable)in cases {
                let listener=tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
                let url=format!("ws://{}",listener.local_addr().unwrap());
                let server=tokio::spawn(async move {
                    let mut ws=tokio_tungstenite::accept_async(listener.accept().await.unwrap().0).await.unwrap();
                    ws.send(Message::Text("0{}".into())).await.unwrap();
                    assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text("40".into()));
                    ws.send(Message::Text("40{}".into())).await.unwrap();
                    assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text(r#"421["room_info"]"#.into()));
                    ws.send(Message::Text(r#"431[{"participants_info":[]}]"#.into())).await.unwrap();
                    let control=ws.next().await.unwrap().unwrap().into_text().unwrap();
                    let id=&control[4..control.find('[').unwrap()];
                    assert!(matches!(ws.next().await,Some(Ok(Message::Binary(_)))));
                    ws.send(Message::Text(format!("43{id}{}",serde_json::json!(["success",ack])))).await.unwrap();
                    assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text(r#"42["leave"]"#.into()));
                    assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text("41".into()));
                    assert!(matches!(ws.next().await,Some(Ok(Message::Close(_)))));
                    ws.flush().await.unwrap();
                });
                let mut signal=Signal::connect(&[url],"synthetic",Duration::from_secs(1),true).await.unwrap();
                let result=signal.control(serde_json::json!({}),Vec::new(),Duration::from_secs(1)).await;
                signal.close().await;server.await.unwrap();
                assert_eq!(result.is_ok(),usable,"unusable ACK must not produce an offer route");
            }
        }).await.expect("control ACK route validation timed out");
    }
    #[tokio::test]
    async fn failed_cancelled_and_dropped_signals_leave_the_room() {
        tokio::time::timeout(Duration::from_secs(6),async {
            for mode in 0..4 {
                let listener=tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
                let url=format!("ws://{}",listener.local_addr().unwrap());
                let(ready_tx,ready_rx)=tokio::sync::oneshot::channel();
                let server=tokio::spawn(async move {
                    let mut ws=tokio_tungstenite::accept_async(listener.accept().await.unwrap().0).await.unwrap();
                    ws.send(Message::Text("0{}".into())).await.unwrap();
                    assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text("40".into()));
                    ws.send(Message::Text("40{}".into())).await.unwrap();
                    assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text(r#"421["room_info"]"#.into()));
                    let _=ready_tx.send(());
                    if mode==0 {ws.send(Message::Text("431[{}]".into())).await.unwrap();}
                    if mode==2 {ws.send(Message::Text(r#"431[{"participants_info":[]}]"#.into())).await.unwrap();}
                    assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text(r#"42["leave"]"#.into()));
                    assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text("41".into()));
                    assert!(matches!(ws.next().await,Some(Ok(Message::Close(_)))));
                    ws.flush().await.unwrap();
                });
                let connecting=tokio::spawn(async move {Signal::connect(&[url],"synthetic",Duration::from_millis(300),true).await});
                ready_rx.await.unwrap();
                if mode==1 {connecting.abort();assert!(matches!(connecting.await,Err(error) if error.is_cancelled()));}
                else if mode==2 {drop(connecting.await.unwrap().unwrap());}
                else {assert!(connecting.await.unwrap().is_err());}
                server.await.unwrap();
            }
        }).await.expect("signal cleanup timed out");
    }
    #[tokio::test]
    async fn connection_logs_into_room_before_returning() {
        tokio::time::timeout(Duration::from_secs(5),async {
            let listener=tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let url=format!("ws://{}",listener.local_addr().unwrap());
            let server=tokio::spawn(async move {
                let mut ws=tokio_tungstenite::accept_hdr_async(listener.accept().await.unwrap().0,
                    |request:&tokio_tungstenite::tungstenite::handshake::server::Request,response| {
                        assert_eq!(request.headers().get("X-NRD-CONTROLLING").and_then(|value|value.to_str().ok()),Some("0"));
                        Ok(response)
                    }).await.unwrap();
                ws.send(Message::Text("0{}".into())).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text("40".into()));
                ws.send(Message::Text("40{}".into())).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text(r#"421["room_info"]"#.into()));
                ws.send(Message::Text(r#"427["notice",{}]"#.into())).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text("437[]".into()));
                ws.send(Message::Text(r#"431[{"participants_info":[]}]"#.into())).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text(r#"42["leave"]"#.into()));
                assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text("41".into()));
                assert!(matches!(ws.next().await,Some(Ok(Message::Close(_)))));
                ws.flush().await.unwrap();
            });
            let mut signal=Signal::connect(&[url],"synthetic",Duration::from_secs(1),true).await.unwrap();
            assert_eq!(signal.event().await.unwrap(),serde_json::json!(["notice",{}]));
            signal.close().await;server.await.unwrap();
        }).await.expect("room login timed out");
    }
    #[tokio::test]
    async fn close_disconnects_the_namespace_and_waits_for_transport_ack() {
        tokio::time::timeout(Duration::from_secs(5), async {
            let listener=tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let url=format!("ws://{}",listener.local_addr().unwrap());
            let(seen_tx,seen_rx)=tokio::sync::oneshot::channel();
            let(release_tx,release_rx)=tokio::sync::oneshot::channel();
            let server=tokio::spawn(async move {
                let mut ws=tokio_tungstenite::accept_async(listener.accept().await.unwrap().0).await.unwrap();
                ws.send(Message::Text("0{}".into())).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text("40".into()));
                ws.send(Message::Text("40{}".into())).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text(r#"421["room_info"]"#.into()));
                ws.send(Message::Text(r#"431[{"participants_info":[]}]"#.into())).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text(r#"42["leave"]"#.into()));
                assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text("41".into()));
                assert!(matches!(ws.next().await,Some(Ok(Message::Close(Some(frame))))
                    if frame.code==tokio_tungstenite::tungstenite::protocol::frame::coding::CloseCode::Normal));
                seen_tx.send(()).unwrap();
                release_rx.await.unwrap();
                ws.flush().await.unwrap();
            });
            let mut signal=Signal::connect(&[url],"synthetic",Duration::from_secs(2),true).await.unwrap();
            let closing=tokio::spawn(async move {signal.close().await});
            seen_rx.await.unwrap();
            assert!(!closing.is_finished(),"close must wait for the remote transport acknowledgement");
            release_tx.send(()).unwrap();
            let report=closing.await.unwrap();server.await.unwrap();
            assert!(report.namespace_connected && report.leave_sent && report.namespace_sent);
            assert!(report.close_sent && report.close_received && !report.timed_out && !report.failed);
        }).await.expect("graceful close timed out");
    }
    #[tokio::test]
    async fn released_namespace_does_not_send_leave_again() {
        tokio::time::timeout(Duration::from_secs(5), async {
            let listener=tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let url=format!("ws://{}",listener.local_addr().unwrap());
            let server=tokio::spawn(async move {
                let mut ws=tokio_tungstenite::accept_async(listener.accept().await.unwrap().0).await.unwrap();
                ws.send(Message::Text("0{}".into())).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text("40".into()));
                ws.send(Message::Text("40{}".into())).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text(r#"421["room_info"]"#.into()));
                ws.send(Message::Text(r#"431[{"participants_info":[]}]"#.into())).await.unwrap();
                ws.send(Message::Text(r#"427["leave"]"#.into())).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text("437[]".into()));
                assert!(matches!(ws.next().await,Some(Ok(Message::Close(_)))));
                ws.flush().await.unwrap();
            });
            let mut signal=Signal::connect(&[url],"synthetic",Duration::from_secs(2),true).await.unwrap();
            assert_eq!(signal.event().await.unwrap(),serde_json::json!(["leave"]));
            signal.released();signal.close().await;server.await.unwrap();
        }).await.expect("released close timed out");
    }
    #[tokio::test]
    async fn binary_attachments_survive_cancelled_event_reads() {
        tokio::time::timeout(Duration::from_secs(5), async {
            let listener=tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let url=format!("ws://{}",listener.local_addr().unwrap());
            let(first_tx,first_rx)=tokio::sync::oneshot::channel();
            let(second_tx,second_rx)=tokio::sync::oneshot::channel();
            let server=tokio::spawn(async move {
                let mut ws=tokio_tungstenite::accept_async(listener.accept().await.unwrap().0).await.unwrap();
                ws.send(Message::Text("0{}".into())).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text("40".into()));
                ws.send(Message::Text("40{}".into())).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text(r#"421["room_info"]"#.into()));
                ws.send(Message::Text(r#"431[{"participants_info":[]}]"#.into())).await.unwrap();
                ws.send(Message::Text(r#"452-9["soac",{"first":{"_placeholder":true,"num":0},"second":{"_placeholder":true,"num":1}}]"#.into())).await.unwrap();
                first_rx.await.unwrap();
                ws.send(Message::Binary(vec![1,2,3])).await.unwrap();
                ws.send(Message::Text("2probe".into())).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text("3probe".into()));
                second_rx.await.unwrap();
                ws.send(Message::Binary(vec![4,5,6])).await.unwrap();
                assert_eq!(ws.next().await.unwrap().unwrap(),Message::Text("439[]".into()));
            });
            let mut signal=Signal::connect(&[url],"synthetic",Duration::from_secs(2),true).await.unwrap();
            assert!(tokio::time::timeout(Duration::from_millis(50),signal.event()).await.is_err());
            first_tx.send(()).unwrap();
            assert!(tokio::time::timeout(Duration::from_millis(50),signal.event()).await.is_err());
            second_tx.send(()).unwrap();
            let event=signal.event().await.unwrap();
            assert_eq!(event,serde_json::json!(["soac",{"first":"AQID","second":"BAUG"}]));
            server.await.unwrap();
            signal.close().await;
        }).await.expect("binary cancellation regression timed out");
    }
}
