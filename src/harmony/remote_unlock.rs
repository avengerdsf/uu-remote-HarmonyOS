use crate::harmony::{event, EventQueue};
use crate::protocol::{decode_wire, WireField, WireValue};
use crate::viewer::{tools::blob, wire};
use serde::Serialize;
use serde_json::json;
use std::time::{Duration, Instant};

const UNLOCK_DEADLINE: Duration = Duration::from_secs(15);
const MAX_PASSWORD_BYTES: usize = 1024;

#[derive(Clone, Copy)]
pub enum Failure {
    Unavailable,
    Pending,
    Rejected,
    TimedOut,
    Cancelled,
}

impl Failure {
    fn message(self) -> &'static str {
        use crate::i18n::s;
        match self {
            Self::Unavailable => s("当前会话不可自动解锁。", "Automatic unlock is unavailable for this session."),
            Self::Pending => s("正在等待被控端解锁。", "An unlock request is already pending."),
            Self::Rejected => s("被控端自动解锁失败。", "The remote computer could not unlock."),
            Self::TimedOut => s("被控端自动解锁超时。", "The remote unlock request timed out."),
            Self::Cancelled => s("远程解锁已取消。", "Remote unlock was cancelled."),
        }
    }
}

pub fn result(events: &EventQueue, generation: u64, request_id: u64, failure: Option<Failure>) {
    event(events, "operationResult", json!({
        "operation":"unlockRemote", "generation":generation, "requestId":request_id,
        "success":failure.is_none(), "error":failure.map(Failure::message)
    }));
}

/// Owns sensitive buffers until the command is dropped or WebRTC releases the packet.
pub struct Secret(Vec<u8>);

impl Secret {
    pub(super) fn password(&self) -> Option<&str> {
        let value = std::str::from_utf8(&self.0).ok()?;
        (!value.is_empty() && value.len() <= MAX_PASSWORD_BYTES && !value.contains('\0')).then_some(value)
    }
}

impl From<String> for Secret {
    fn from(value: String) -> Self { Self(value.into_bytes()) }
}

impl AsRef<[u8]> for Secret {
    fn as_ref(&self) -> &[u8] { &self.0 }
}

impl Drop for Secret {
    fn drop(&mut self) {
        for byte in &mut self.0 {
            // Volatile stores survive dead-store elimination when the buffer is freed.
            unsafe { std::ptr::write_volatile(byte, 0); }
        }
        std::sync::atomic::compiler_fence(std::sync::atomic::Ordering::SeqCst);
    }
}

pub(super) fn unlock_packet(sequence: u64, password: Secret) -> Option<bytes::Bytes> {
    #[derive(Serialize)]
    struct Args<'a> { key: &'a str }

    let key = password.password()?;
    let mut args = Secret(Vec::with_capacity(key.len() * 6 + 10));
    serde_json::to_writer(&mut args.0, &Args { key }).ok()?;
    let mut action = Secret(Vec::with_capacity(args.0.len() + 8));
    wire::int(1, 15, &mut action.0);
    wire::bytes(2, args.as_ref(), &mut action.0);
    Some(bytes::Bytes::from_owner(Secret(wire::envelope(sequence, 3, action.as_ref()))))
}

/// Message 16 QuerySystemState, with state id 1 for SecureDesktopState.
pub(super) fn query(sequence: u64) -> Vec<u8> {
    wire::envelope(sequence, 16, &[8, 1])
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct LockState {
    pub locked: bool,
    pub supported: bool,
}

pub(super) enum HostUpdate { Lock(LockState), Failure }

pub(super) fn host_update(data: &[u8]) -> Option<HostUpdate> {
    let fields = decode_wire(data).ok()?;
    for field in fields {
        let WireValue::Bytes(payload) = field.value else { continue };
        if field.number == 15 {
            let state = decode_wire(blob(payload, 1)?).ok()?;
            return Some(HostUpdate::Lock(LockState { locked: flag(&state, 1)?, supported: flag(&state, 5)? }));
        }
        if field.number == 12 {
            let error = decode_wire(payload).ok()?;
            return error.iter().rev().find(|field| field.number == 2)
                .filter(|field| field.value == WireValue::Varint(-5_i64 as u64))
                .map(|_| HostUpdate::Failure);
        }
    }
    None
}

fn flag(fields: &[WireField<'_>], number: u32) -> Option<bool> {
    match fields.iter().rev().find(|field| field.number == number).map(|field| &field.value) {
        None | Some(WireValue::Varint(0)) => Some(false),
        Some(WireValue::Varint(1)) => Some(true),
        _ => None,
    }
}

#[derive(Default)]
pub(super) struct State {
    lock: Option<LockState>,
    pending: Option<(u64, Instant)>,
}

impl State {
    pub fn begin(&mut self, request_id: u64, now: Instant) -> Result<bool, Failure> {
        if let Some((id, _)) = self.pending {
            return if id == request_id { Ok(false) } else { Err(Failure::Pending) };
        }
        if self.lock != Some(LockState { locked: true, supported: true }) {
            return Err(Failure::Unavailable);
        }
        self.pending = Some((request_id, now + UNLOCK_DEADLINE));
        Ok(true)
    }

    pub fn observe(&mut self, state: LockState) -> (bool, Option<u64>) {
        let changed = self.lock.replace(state) != Some(state);
        let completed = if state.locked { None } else { self.finish() };
        (changed, completed)
    }

    pub fn finish(&mut self) -> Option<u64> { self.pending.take().map(|(id, _)| id) }

    pub fn finish_request(&mut self, request_id: u64) -> Option<u64> {
        if self.pending.is_some_and(|(id, _)| id == request_id) { self.finish() } else { None }
    }

    pub fn expire(&mut self, now: Instant) -> Option<u64> {
        if self.pending.is_some_and(|(_, deadline)| now >= deadline) { self.finish() } else { None }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unlock_guard_requires_capability_and_reports_each_attempt_once() {
        let mut state = State::default();
        let now = Instant::now();
        assert!(matches!(state.begin(1, now), Err(Failure::Unavailable)));
        state.observe(LockState { locked: true, supported: false });
        assert!(matches!(state.begin(1, now), Err(Failure::Unavailable)));
        let locked = LockState { locked: true, supported: true };
        assert_eq!(state.observe(locked), (true, None));
        assert!(matches!(state.begin(1, now), Ok(true)));
        assert!(matches!(state.begin(1, now), Ok(false)));
        assert!(matches!(state.begin(2, now), Err(Failure::Pending)));
        assert_eq!(state.observe(locked), (false, None));
        assert_eq!(state.finish_request(2), None);
        assert_eq!(state.expire(now + Duration::from_secs(14)), None);
        assert_eq!(state.observe(LockState { locked: false, supported: true }), (true, Some(1)));
        assert_eq!(state.finish(), None);
        state.observe(locked);
        assert!(matches!(state.begin(2, now), Ok(true)));
        assert_eq!(state.expire(now + UNLOCK_DEADLINE), Some(2));
        assert_eq!(state.expire(now + UNLOCK_DEADLINE), None);
    }

    #[test]
    fn unlock_wire_checks_exact_host_state_and_failure_code() {
        let secure = |fields: &[u8]| {
            let mut change = Vec::new();
            wire::bytes(1, fields, &mut change);
            wire::envelope(1, 15, &change)
        };
        assert!(matches!(host_update(&secure(&[8, 1, 40, 1])),
            Some(HostUpdate::Lock(LockState { locked: true, supported: true }))));
        assert!(matches!(host_update(&secure(&[40, 1])),
            Some(HostUpdate::Lock(LockState { locked: false, supported: true }))));
        assert!(host_update(&secure(&[10, 0])).is_none());
        for code in [-5_i64, -7, 5] {
            let mut report = Vec::new();
            wire::int(2, code as u64, &mut report);
            wire::bytes(3, b"never forward this text", &mut report);
            assert_eq!(matches!(host_update(&wire::envelope(1, 12, &report)), Some(HostUpdate::Failure)), code == -5);
        }
        assert_eq!(blob(&query(1), 16), Some(&[8, 1][..]));
        let packet = unlock_packet(4, Secret::from("fake\"test\n".to_string())).unwrap();
        let action = blob(&packet, 3).unwrap();
        assert_eq!(decode_wire(action).unwrap()[0].value, WireValue::Varint(15));
        assert_eq!(serde_json::from_slice::<serde_json::Value>(blob(action, 2).unwrap()).unwrap(),
            json!({"key":"fake\"test\n"}));
        assert!(unlock_packet(5, Secret::from(String::new())).is_none());
    }
}
