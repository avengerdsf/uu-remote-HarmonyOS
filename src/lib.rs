//! UU Remote protocol core shared by the Linux binaries and the HarmonyOS app.
//!
//! The Linux host and viewer keep using the same module files. The HarmonyOS
//! application links this crate as `libuu_core.a` and talks to it through the
//! versioned C ABI in [`harmony::abi`]. This crate must not link X11, GTK, SDL,
//! PAM, PulseAudio or other Linux desktop libraries.

pub mod auth;
pub mod config;
pub mod i18n;
pub mod protocol;
pub mod clipboard_protocol;
pub mod clipboard_rich;
mod ws_transport;

#[cfg(test)]
#[path = "hevc.rs"]
pub mod hevc;

pub mod harmony;

/// Reused controller protocol pieces. Path attributes keep the existing viewer
/// files authoritative instead of forking copies for HarmonyOS.
pub mod viewer {
    #[path = "api.rs"]
    pub mod api;
    #[path = "clipboard_state.rs"]
    pub(crate) mod clipboard_state;
    #[path = "cursor.rs"]
    pub mod cursor;
    #[path = "input.rs"]
    pub mod input;
    #[path = "native_gamepad.rs"]
    pub mod native_gamepad;
    #[path = "native_rumble.rs"]
    pub mod native_rumble;
    #[path = "media.rs"]
    pub mod media;
    #[path = "signal.rs"]
    pub mod signal;
    #[path = "wire.rs"]
    pub mod wire;

    /// Field readers shared by the control protocol tests. The full tool module
    /// depends on the desktop RTC peer and stays out of the HarmonyOS core; the
    /// HarmonyOS tool chain lives in [`crate::harmony::tools`].
    pub mod tools {
        use crate::protocol::{decode_wire, WireValue};

        pub fn uint(data: &[u8], field: u32) -> u64 {
            decode_wire(data)
                .ok()
                .and_then(|fields| {
                    fields.into_iter().find_map(|item| {
                        if item.number == field {
                            if let WireValue::Varint(value) = item.value {
                                return Some(value);
                            }
                        }
                        None
                    })
                })
                .unwrap_or(0)
        }

        pub fn blob(data: &[u8], field: u32) -> Option<&[u8]> {
            decode_wire(data).ok().and_then(|fields| {
                fields.into_iter().find_map(|item| {
                    if item.number == field {
                        if let WireValue::Bytes(value) = item.value {
                            return Some(value);
                        }
                    }
                    None
                })
            })
        }
    }
}
