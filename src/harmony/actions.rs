//! Actions evidenced by the upstream viewer power and control-center implementations.
use crate::viewer::wire;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum RemoteAction { Reboot, Shutdown, AutoLock(bool), HostMute(bool) }

impl RemoteAction {
    pub fn parse(name: &str, enabled: bool) -> Result<Self, &'static str> {
        match name {
            "reboot" => Ok(Self::Reboot), "shutdown" => Ok(Self::Shutdown),
            "autoLock" => Ok(Self::AutoLock(enabled)), "hostMute" => Ok(Self::HostMute(enabled)),
            _ => Err("Unknown remote action"),
        }
    }
    pub fn messages(self, seq: u64) -> Vec<Vec<u8>> {
        match self {
            Self::Reboot => vec![wire::simple_action(seq, 9, None)],
            Self::Shutdown => vec![wire::simple_action(seq, 12, None)],
            Self::AutoLock(enabled) => vec![wire::simple_action(seq, 19, Some(if enabled { 2 } else { 1 }))],
            Self::HostMute(true) => vec![wire::simple_action(seq, 14, None), wire::simple_action(seq + 1, 18, None)],
            Self::HostMute(false) => vec![wire::simple_action(seq, 16, None)],
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::harmony::tools::{blob, uint};
    #[test]
    fn upstream_action_numbers_and_boolean_values() {
        for (name, enabled, numbers) in [
            ("reboot", false, vec![9]), ("shutdown", false, vec![12]),
            ("autoLock", true, vec![19]), ("autoLock", false, vec![19]),
            ("hostMute", true, vec![14, 18]), ("hostMute", false, vec![16])
        ] {
            let messages = RemoteAction::parse(name, enabled).unwrap().messages(7);
            assert_eq!(messages.len(), numbers.len());
            for (message, number) in messages.iter().zip(numbers) {
                let action = blob(message, 3).unwrap();
                assert_eq!(uint(action, 1), number);
                if name == "autoLock" { assert_eq!(uint(action, 5), if enabled { 2 } else { 1 }); }
            }
        }
        assert!(RemoteAction::parse("unverified", true).is_err());
    }
}
