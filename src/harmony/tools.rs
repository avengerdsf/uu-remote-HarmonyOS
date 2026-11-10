//! HarmonyOS tool transport.
//!
//! The protocol implementations are the same files used by the desktop
//! viewer (`src/viewer/tools/{files,terminal,portmap}.rs`). This module only
//! supplies their common transport, envelope helpers and channel constants;
//! the desktop RTC peer, CLI and Unix terminal IPC are intentionally absent.

#[path = "../viewer/tools/files.rs"]
pub mod files;
#[path = "../viewer/tools/portmap.rs"]
pub mod portmap;
#[path = "../viewer/tools/terminal.rs"]
pub mod terminal;

use crate::protocol::{decode_wire, WireValue};
use crate::viewer::wire;
use std::{
    sync::{Arc, Mutex},
    time::Duration,
};
use tokio::sync::mpsc;

pub const CONTROL: usize = 0;
pub const FILE: usize = 3;
pub const BINARY: usize = 4;
pub type Packet = (usize, Vec<u8>);
pub const TIMEOUT: Duration = Duration::from_secs(30);

#[async_trait::async_trait]
pub trait Send: std::marker::Send + Sync {
    async fn send(&self, channel: usize, data: Vec<u8>) -> Result<(), String>;
}

#[derive(Clone)]
pub struct Transport(pub Arc<dyn Send>);

impl Transport {
    pub async fn send(&self, channel: usize, data: Vec<u8>) -> Result<(), String> {
        tokio::time::timeout(TIMEOUT, self.0.send(channel, data))
            .await
            .map_err(|_| "Tool send timeout")?
    }
}

struct Rtc(Vec<Arc<webrtc::data_channel::RTCDataChannel>>);

#[async_trait::async_trait]
impl Send for Rtc {
    async fn send(&self, channel: usize, data: Vec<u8>) -> Result<(), String> {
        let dc = self.0.get(channel).ok_or("Unknown tool channel")?;
        while dc.buffered_amount().await > 1024 * 1024 {
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
        dc.send(&bytes::Bytes::from(data))
            .await
            .map_err(|_| "Tool data channel send failed")?;
        Ok(())
    }
}

pub fn channel_transport(channels: Vec<Arc<webrtc::data_channel::RTCDataChannel>>) -> Transport {
    Transport(Arc::new(Rtc(channels)))
}

pub fn uint(data: &[u8], n: u32) -> u64 {
    decode_wire(data)
        .ok()
        .and_then(|fields| {
            fields.into_iter().find_map(|field| match (field.number, field.value) {
                (k, WireValue::Varint(v)) if k == n => Some(v),
                _ => None,
            })
        })
        .unwrap_or(0)
}

pub fn blob(data: &[u8], n: u32) -> Option<&[u8]> {
    decode_wire(data).ok()?.into_iter().find_map(|field| match (field.number, field.value) {
        (k, WireValue::Bytes(v)) if k == n => Some(v),
        _ => None,
    })
}

pub fn text(data: &[u8], n: u32) -> Result<String, String> {
    String::from_utf8(blob(data, n).unwrap_or_default().to_vec())
        .map_err(|_| "Invalid UTF-8 field".into())
}

pub fn ints(fields: &[(u32, u64)]) -> Vec<u8> {
    let mut bytes = Vec::new();
    for &(number, value) in fields {
        wire::int(number, value, &mut bytes);
    }
    bytes
}

pub fn nested(n: u32, body: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    wire::bytes(n, body, &mut out);
    out
}

pub fn rpc(id: u64, response: bool, case: u32, body: &[u8]) -> Vec<u8> {
    let mut bytes = nested(1, &ints(&[(1, id)]));
    wire::bytes(
        if response { 4 } else { 8 },
        &nested(case, body),
        &mut bytes,
    );
    wire::envelope(id, if response { 22 } else { 21 }, &bytes)
}

pub async fn receive(rx: &mut mpsc::Receiver<Packet>) -> Result<Packet, String> {
    tokio::time::timeout(TIMEOUT, rx.recv())
        .await
        .map_err(|_| "Tool response timeout")?
        .ok_or("Tool transport closed".into())
}
