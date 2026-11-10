//! HarmonyOS controller core: QR login, device list, signaling, WebRTC and input.
//!
//! Video access units and audio PCM leave this module only through the native
//! platform callbacks. No frame is converted to RGB or passed through ArkTS.

pub mod abi;
pub mod actions;
pub mod input;
pub mod login;
pub mod platform;
pub mod service;
pub mod session;
pub mod tools;
mod text_stream;
pub mod video;

use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CoreConfig {
    #[serde(default)]
    pub device_id: String,
    #[serde(default)]
    pub client_id: String,
    #[serde(default)]
    pub system_id: String,
    #[serde(default)]
    pub machine_guid: String,
    #[serde(default)]
    pub locale: String,
    #[serde(default)]
    pub model: String,
    #[serde(default)]
    pub os_full_name: String,
    #[serde(default)]
    pub sdk_api_version: String,
    #[serde(default)]
    pub device_type: String,
    #[serde(default = "default_platform")]
    pub platform: u32,
    #[serde(default = "default_timeout")]
    pub signaling_timeout_ms: u32,
}

fn default_platform() -> u32 {
    3
}

fn default_timeout() -> u32 {
    12_000
}

impl CoreConfig {
    pub fn display_name(&self) -> String {
        if self.model.is_empty() {
            "HarmonyOS".into()
        } else {
            self.model.clone()
        }
    }

    pub fn is_pc(&self) -> bool {
        self.device_type.eq_ignore_ascii_case("2in1") || self.device_type.eq_ignore_ascii_case("pc")
    }
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginSnapshot {
    pub phase: String,
    pub status_text: String,
    pub qr_payload: Option<String>,
    pub polling_active: bool,
    pub authenticated: bool,
    pub error: Option<String>,
    pub generation: u64,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceItem {
    pub id: String,
    pub name: String,
    pub platform: String,
    pub online: bool,
    pub status_text: String,
    pub capabilities: Vec<String>,
    pub connect_label: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub busy: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub controlled: Option<bool>,
    pub shared: bool,
    #[serde(skip)]
    pub grouped_only: bool,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DevicesSnapshot {
    pub phase: String,
    pub devices: Vec<DeviceItem>,
    pub error: Option<String>,
    pub generation: u64,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionSnapshot {
    pub phase: String,
    pub session_id: String,
    pub generation: u64,
    pub resource_epoch: u64,
    pub target_id: String,
    pub target_name: String,
    pub view_only: bool,
    pub first_frame_received: bool,
    pub error: Option<String>,
    pub video_width: u32,
    pub video_height: u32,
}

impl SessionSnapshot {
    pub fn ended() -> Self {
        Self {
            phase: "ended".into(),
            session_id: String::new(),
            generation: 0,
            resource_epoch: 0,
            target_id: String::new(),
            target_name: String::new(),
            view_only: false,
            first_frame_received: false,
            error: None,
            video_width: 0,
            video_height: 0,
        }
    }
}

pub type EventQueue = Arc<Mutex<VecDeque<String>>>;

pub fn event(queue: &EventQueue, kind: &str, data: serde_json::Value) {
    let payload = data.to_string();
    let envelope = serde_json::json!({"type": kind, "data": payload});
    if let Ok(mut queue) = queue.lock() {
        if kind == "remoteCursor" { queue.retain(|item| !item.contains("\"type\":\"remoteCursor\"")); }
        if queue.len() >= 1024 {
            queue.pop_front();
        }
        queue.push_back(envelope.to_string());
    }
}

pub fn log_error(message: &str) {
    // No credentials, QR payloads or input contents in diagnostics.
    log::error!("{message}");
}
