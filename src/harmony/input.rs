//! Complete CONTROL input field mapping for the HarmonyOS controller.
//!
//! The wire shapes are the ones the original viewer and the official clients use
//! (`src/control_protocol.rs`): `kbd_press`/`kbd_release`/`kbd_click` with `key`,
//! `mouse_move_absolute` with `abs_x`/`abs_y`, `mouse_move_relative` and
//! `mouse_scroll` with integer `delta_x`/`delta_y`, `mouse_press`/`mouse_release`/
//! `mouse_click` with `button` (1 left, 2 right, 4 middle) and `text_input` with
//! `content`. ArkTS sends canonical scan codes plus normalized touch samples; this
//! module performs validation, gesture recognition and the final wire encoding so
//! the behaviour can be tested without a device.

use crate::viewer::input::Input;
use serde_json::{json, Value};

/// A press must move farther than this before it becomes a drag instead of a tap.
const TOUCH_SLOP_PX: f64 = 12.0;
/// A still press this long becomes a right click (same threshold as the host gesture).
const TOUCH_HOLD_MS: u64 = 450;
/// One wheel notch is 120 wire units; a 100 px two-finger drag is one notch.
const SCROLL_UNITS_PER_PX: f64 = 1.2;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TouchMode {
    Trackpad,
    Direct,
}

impl TouchMode {
    pub fn parse(value: &str) -> Self {
        if value.eq_ignore_ascii_case("direct") {
            Self::Direct
        } else {
            Self::Trackpad
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum TouchAction {
    MoveAbsolute { x: f64, y: f64 },
    Relative { dx: f64, dy: f64 },
    Press(i32),
    Release(i32),
    Click(i32),
    Scroll { dx: i32, dy: i32 },
}

#[derive(Clone, Copy)]
struct Active {
    last: (f64, f64),
    started_ms: u64,
    pointers: u8,
    pressed: bool,
    moved: bool,
    scrolling: bool,
    travelled: f64,
}

/// Recognizes the two controller touch modes. Coordinates are normalized to the
/// visible video rectangle; black-bar touches are rejected by the caller and by
/// the `0..=1` check here instead of being clamped onto the remote edge.
pub struct TouchMapper {
    mode: TouchMode,
    active: Option<Active>,
    scroll_x: f64,
    scroll_y: f64,
}

impl TouchMapper {
    pub fn new(mode: TouchMode) -> Self {
        Self { mode, active: None, scroll_x: 0.0, scroll_y: 0.0 }
    }

    pub fn set_mode(&mut self, mode: TouchMode) -> bool {
        if self.mode == mode {
            return false;
        }
        self.mode = mode;
        self.active = None;
        self.scroll_x = 0.0;
        self.scroll_y = 0.0;
        true
    }

    fn valid(x: f64, y: f64) -> bool {
        x.is_finite() && y.is_finite() && (0.0..=1.0).contains(&x) && (0.0..=1.0).contains(&y)
    }

    pub fn down(&mut self, x: f64, y: f64, pointers: u8, at_ms: u64, _screen: (u32, u32)) -> Vec<TouchAction> {
        if !Self::valid(x, y) {
            return Vec::new();
        }
        if let Some(active) = self.active.as_mut() {
            // A second finger joins a trackpad gesture and turns it into scrolling.
            if pointers >= 2 {
                active.pointers = pointers;
                active.scrolling = true;
                active.moved = true;
            }
            return Vec::new();
        }
        self.active = Some(Active {
            last: (x, y),
            started_ms: at_ms,
            pointers,
            pressed: false,
            moved: false,
            scrolling: self.mode == TouchMode::Trackpad && pointers >= 2,
            travelled: 0.0,
        });
        match self.mode {
            TouchMode::Direct => vec![TouchAction::MoveAbsolute { x, y }],
            TouchMode::Trackpad => Vec::new(),
        }
    }

    pub fn move_to(
        &mut self,
        x: f64,
        y: f64,
        pointers: u8,
        at_ms: u64,
        screen: (u32, u32),
    ) -> Vec<TouchAction> {
        if !Self::valid(x, y) {
            return Vec::new();
        }
        let Some(active) = self.active.as_mut() else {
            return Vec::new();
        };
        let dx_px = (x - active.last.0) * f64::from(screen.0.max(1));
        let dy_px = (y - active.last.1) * f64::from(screen.1.max(1));
        active.last = (x, y);
        active.pointers = active.pointers.max(pointers);
        active.travelled += dx_px.hypot(dy_px);
        if active.travelled > TOUCH_SLOP_PX {
            active.moved = true;
        }
        let _ = at_ms;
        match self.mode {
            TouchMode::Direct => {
                let mut actions = Vec::new();
                if !active.pressed && active.travelled > TOUCH_SLOP_PX {
                    active.pressed = true;
                    actions.push(TouchAction::Press(1));
                }
                actions.push(TouchAction::MoveAbsolute { x, y });
                actions
            }
            TouchMode::Trackpad => {
                if pointers >= 2 {
                    active.scrolling = true;
                    active.moved = true;
                }
                if active.scrolling {
                    self.scroll_x += dx_px * SCROLL_UNITS_PER_PX;
                    self.scroll_y += dy_px * SCROLL_UNITS_PER_PX;
                    let dx = self.scroll_x.trunc();
                    let dy = self.scroll_y.trunc();
                    if dx != 0.0 || dy != 0.0 {
                        self.scroll_x -= dx;
                        self.scroll_y -= dy;
                        vec![TouchAction::Scroll { dx: dx as i32, dy: dy as i32 }]
                    } else {
                        Vec::new()
                    }
                } else if dx_px != 0.0 || dy_px != 0.0 {
                    vec![TouchAction::Relative { dx: dx_px, dy: dy_px }]
                } else {
                    Vec::new()
                }
            }
        }
    }

    pub fn up(&mut self, x: f64, y: f64, pointers: u8, at_ms: u64) -> Vec<TouchAction> {
        let _ = x;
        let _ = y;
        let Some(active) = self.active.take() else {
            return Vec::new();
        };
        self.scroll_x = 0.0;
        self.scroll_y = 0.0;
        match self.mode {
            TouchMode::Direct => {
                if active.pressed {
                    vec![TouchAction::Release(1)]
                } else if at_ms.saturating_sub(active.started_ms) >= TOUCH_HOLD_MS {
                    vec![TouchAction::Click(2)]
                } else {
                    vec![TouchAction::Click(1)]
                }
            }
            TouchMode::Trackpad => {
                let _ = pointers;
                if active.scrolling || active.moved {
                    Vec::new()
                } else if at_ms.saturating_sub(active.started_ms) >= TOUCH_HOLD_MS {
                    vec![TouchAction::Click(2)]
                } else {
                    vec![TouchAction::Click(1)]
                }
            }
        }
    }

    pub fn cancel(&mut self) -> Vec<TouchAction> {
        let Some(active) = self.active.take() else {
            return Vec::new();
        };
        self.scroll_x = 0.0;
        self.scroll_y = 0.0;
        if self.mode == TouchMode::Direct && active.pressed {
            vec![TouchAction::Release(1)]
        } else {
            Vec::new()
        }
    }
}

/// Stateful translator from the ArkTS `sendInput` JSON to CONTROL messages.
pub struct InputTranslator {
    input: Input,
    touch: TouchMapper,
    relative_x: f64,
    relative_y: f64,
    screen: (u32, u32),
}

impl InputTranslator {
    pub fn new(view_only: bool, touch_mode: TouchMode, mac: bool) -> Self {
        let mut input = Input::new(view_only);
        input.set_mac(mac);
        Self {
            input,
            touch: TouchMapper::new(touch_mode),
            relative_x: 0.0,
            relative_y: 0.0,
            screen: (1920, 1080),
        }
    }

    pub fn set_view_only(&mut self, view_only: bool) {
        self.input.set_view_only(view_only);
    }

    pub fn set_mac(&mut self, mac: bool) {
        self.input.set_mac(mac);
    }

    /// Switching modes releases every held key/button, as the settings page promises.
    pub fn set_touch_mode(&mut self, mode: TouchMode) -> Vec<Value> {
        self.relative_x = 0.0;
        self.relative_y = 0.0;
        if self.touch.set_mode(mode) {
            self.input.release_all()
        } else {
            Vec::new()
        }
    }

    /// The remote size used to turn normalized touch deltas into pointer pixels.
    pub fn set_screen(&mut self, width: u32, height: u32) {
        if width > 0 && height > 0 {
            self.screen = (width, height);
        }
    }

    pub fn release_all(&mut self) -> Vec<Value> {
        let _ = self.touch.cancel();
        self.relative_x = 0.0;
        self.relative_y = 0.0;
        self.input.release_all()
    }

    fn relative(&mut self, dx: f64, dy: f64) -> Option<Value> {
        if !dx.is_finite() || !dy.is_finite() {
            return None;
        }
        self.relative_x = (self.relative_x + dx).clamp(-65535.0, 65535.0);
        self.relative_y = (self.relative_y + dy).clamp(-65535.0, 65535.0);
        let dx = self.relative_x.trunc();
        let dy = self.relative_y.trunc();
        if dx == 0.0 && dy == 0.0 {
            return None;
        }
        self.relative_x -= dx;
        self.relative_y -= dy;
        Some(json!({"action": "mouse_move_relative", "delta_x": dx as i64, "delta_y": dy as i64}))
    }

    fn touch_actions(&mut self, actions: Vec<TouchAction>) -> Vec<Value> {
        let mut out = Vec::new();
        for action in actions {
            match action {
                TouchAction::MoveAbsolute { x, y } => {
                    out.push(json!({"action": "mouse_move_absolute", "abs_x": x.clamp(0.0, 1.0), "abs_y": y.clamp(0.0, 1.0)}));
                }
                TouchAction::Relative { dx, dy } => {
                    if let Some(value) = self.relative(dx, dy) {
                        out.push(value);
                    }
                }
                TouchAction::Press(button) => {
                    if let Some(value) = self.input.button(button, true) {
                        out.push(value);
                    }
                }
                TouchAction::Release(button) => {
                    if let Some(value) = self.input.button(button, false) {
                        out.push(value);
                    }
                }
                TouchAction::Click(button) => {
                    // Match the original desktop viewer's press/release sequence.
                    if let Some(press) = self.input.button(button, true) {
                        out.push(press);
                        out.extend(self.input.button(button, false));
                    }
                }
                TouchAction::Scroll { dx, dy } => {
                    if dx != 0 || dy != 0 {
                        out.push(json!({"action": "mouse_scroll", "delta_x": dx, "delta_y": dy}));
                    }
                }
            }
        }
        out
    }

    /// Handles one `sendInput` payload. Unknown actions are ignored so a newer UI
    /// can talk to an older core; malformed known actions return an error.
    pub fn handle(&mut self, text: &str) -> Result<Vec<Value>, String> {
        let value: Value = serde_json::from_str(text).map_err(|_| "invalid input json")?;
        let action = value.get("action").and_then(Value::as_str).unwrap_or("");
        match action {
            "key" => {
                let scan = value.get("scan").and_then(Value::as_i64).unwrap_or(-1);
                let down = value.get("down").and_then(Value::as_bool).unwrap_or(false);
                if !(0..=512).contains(&scan) {
                    return Ok(Vec::new());
                }
                Ok(self.input.key(scan as i32, down).into_iter().collect())
            }
            "key_click" => {
                let scan = value.get("scan").and_then(Value::as_i64).unwrap_or(-1);
                if !(0..=512).contains(&scan) {
                    return Ok(Vec::new());
                }
                Ok(self.input.key_click(scan as i32).into_iter().collect())
            }
            "mouse_move_absolute" => {
                let x = finite(&value, "abs_x")?;
                let y = finite(&value, "abs_y")?;
                Ok(vec![json!({"action": "mouse_move_absolute", "abs_x": x.clamp(0.0, 1.0), "abs_y": y.clamp(0.0, 1.0)})])
            }
            "mouse_move_relative" => {
                let dx = finite(&value, "delta_x")?;
                let dy = finite(&value, "delta_y")?;
                Ok(self.relative(dx, dy).into_iter().collect())
            }
            "mouse_press" | "mouse_release" => {
                let button = integer(&value, "button")?;
                Ok(self.input.button(button, action == "mouse_press").into_iter().collect())
            }
            "mouse_click" => {
                let button = integer(&value, "button")?;
                // Live Windows interoperability uses the same down/up pair as touch clicks.
                let mut outgoing = Vec::new();
                if let Some(press) = self.input.button(button, true) {
                    outgoing.push(press);
                    outgoing.extend(self.input.button(button, false));
                }
                Ok(outgoing)
            }
            "mouse_scroll" => {
                let dx = integer(&value, "delta_x")?;
                let dy = integer(&value, "delta_y")?;
                if dx.abs() > 12_000 || dy.abs() > 12_000 {
                    return Err("mouse_scroll delta out of range".into());
                }
                if dx == 0 && dy == 0 {
                    return Ok(Vec::new());
                }
                Ok(vec![json!({"action": "mouse_scroll", "delta_x": dx, "delta_y": dy})])
            }
            "text_input" => {
                let content = value
                    .get("content")
                    .and_then(Value::as_str)
                    .ok_or("text_input content must be a string")?;
                if content.len() > 16 * 1024 {
                    return Err("text_input content exceeds 16 KiB".into());
                }
                Ok(vec![json!({"action": "text_input", "content": content})])
            }
            "touch_down" | "touch_move" | "touch_up" | "touch_cancel" => {
                if !self.input.enabled() {
                    return Ok(Vec::new());
                }
                let mut cursor = None;
                let mut actions = match action {
                    "touch_cancel" => self.touch.cancel(),
                    _ => {
                        let x = finite(&value, "abs_x")?;
                        let y = finite(&value, "abs_y")?;
                        if self.touch.mode == TouchMode::Trackpad &&
                            (value.get("cursor_x").is_some() || value.get("cursor_y").is_some()) {
                            let point = (finite(&value, "cursor_x")?.clamp(0.0, 1.0), finite(&value, "cursor_y")?.clamp(0.0, 1.0));
                            if TouchMapper::valid(x, y) { cursor = Some(point); }
                        }
                        let pointers = value
                            .get("pointers")
                            .and_then(Value::as_u64)
                            .unwrap_or(1)
                            .clamp(1, 10) as u8;
                        let at_ms = value.get("at_ms").and_then(Value::as_u64).unwrap_or(0);
                        match action {
                            "touch_down" => self.touch.down(x, y, pointers, at_ms, self.screen),
                            "touch_move" => self.touch.move_to(x, y, pointers, at_ms, self.screen),
                            _ => self.touch.up(x, y, pointers, at_ms),
                        }
                    }
                };
                // The optional ArkTS cursor anchor shares the displayed pointer's
                // normalized position. Only official absolute-motion fields go on wire.
                if let Some((x, y)) = cursor {
                    for mapped in &mut actions {
                        if matches!(mapped, TouchAction::Relative { .. }) { *mapped = TouchAction::MoveAbsolute { x, y }; }
                    }
                    if action == "touch_down" { actions.insert(0, TouchAction::MoveAbsolute { x, y }); }
                }
                Ok(self.touch_actions(actions))
            }
            _ => Ok(Vec::new()),
        }
    }
}

fn finite(value: &Value, key: &str) -> Result<f64, String> {
    value
        .get(key)
        .and_then(Value::as_f64)
        .filter(|number| number.is_finite())
        .ok_or_else(|| format!("input field {key} must be a finite number"))
}

fn integer(value: &Value, key: &str) -> Result<i32, String> {
    value
        .get(key)
        .and_then(Value::as_i64)
        .and_then(|number| i32::try_from(number).ok())
        .ok_or_else(|| format!("input field {key} must be an i32 integer"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn translator(mode: TouchMode) -> InputTranslator {
        let mut translator = InputTranslator::new(false, mode, false);
        translator.set_screen(1920, 1080);
        translator
    }

    fn actions(values: &[Value]) -> Vec<(&str, &Value)> {
        values
            .iter()
            .map(|value| (value["action"].as_str().unwrap(), value))
            .collect()
    }

    #[test]
    fn trackpad_cursor_anchor_matches_the_visible_pointer_without_relative_drift() {
        let mut input = translator(TouchMode::Trackpad);
        let down = input.handle(r#"{"action":"touch_down","abs_x":0.2,"abs_y":0.4,"cursor_x":0.5,"cursor_y":0.6,"at_ms":1000}"#).unwrap();
        assert_eq!(down, vec![json!({"action":"mouse_move_absolute","abs_x":0.5,"abs_y":0.6})]);
        let moved = input.handle(r#"{"action":"touch_move","abs_x":0.3,"abs_y":0.5,"cursor_x":0.6,"cursor_y":0.7,"at_ms":1100}"#).unwrap();
        assert_eq!(moved, vec![json!({"action":"mouse_move_absolute","abs_x":0.6,"abs_y":0.7})]);
        assert!(input.handle(r#"{"action":"touch_up","abs_x":0.3,"abs_y":0.5,"cursor_x":0.6,"cursor_y":0.7,"at_ms":1200}"#).unwrap().is_empty());
        input.set_view_only(true);
        assert!(input.handle(r#"{"action":"touch_down","abs_x":0.2,"abs_y":0.4,"cursor_x":0.5,"cursor_y":0.6}"#).unwrap().is_empty());
    }

    #[test]
    fn cursor_anchor_validation_keeps_scroll_and_legacy_touch_behavior() {
        let mut input = translator(TouchMode::Trackpad);
        assert!(input.handle(r#"{"action":"touch_down","abs_x":0.2,"abs_y":0.4,"cursor_x":0.5}"#).is_err());
        assert!(input.handle(r#"{"action":"touch_move","abs_x":0.3,"abs_y":0.5,"cursor_x":0.6,"cursor_y":0.7}"#).unwrap().is_empty());
        assert!(input.handle(r#"{"action":"touch_down","abs_x":-1,"abs_y":0.4,"cursor_x":0.5,"cursor_y":0.6}"#).unwrap().is_empty());
        input.handle(r#"{"action":"touch_down","abs_x":0.2,"abs_y":0.4,"cursor_x":0.5,"cursor_y":0.6,"pointers":2}"#).unwrap();
        let scroll = input.handle(r#"{"action":"touch_move","abs_x":0.3,"abs_y":0.5,"cursor_x":0.5,"cursor_y":0.6,"pointers":2}"#).unwrap();
        assert_eq!(scroll.len(), 1); assert_eq!(scroll[0]["action"], "mouse_scroll");
        input.release_all();
        assert!(input.handle(r#"{"action":"touch_down","abs_x":0.2,"abs_y":0.4}"#).unwrap().is_empty());
        assert_eq!(input.handle(r#"{"action":"touch_move","abs_x":0.3,"abs_y":0.5}"#).unwrap()[0]["action"], "mouse_move_relative");
    }

    #[test]
    fn touch_clicks_match_the_original_viewer_press_release_sequence() {
        for mode in [TouchMode::Direct, TouchMode::Trackpad] {
            for (held_ms, button) in [(80, 1), (500, 2)] {
                let mut input = translator(mode);
                input.handle(r#"{"action":"touch_down","abs_x":0.25,"abs_y":0.5,"at_ms":1000}"#).unwrap();
                let outgoing = input.handle(&json!({
                    "action": "touch_up", "abs_x": 0.25, "abs_y": 0.5,
                    "at_ms": 1000 + held_ms
                }).to_string()).unwrap();
                // Upstream src/viewer/sdl.rs sends Input::button for down/up.
                let mut original = Input::new(false);
                let expected = vec![original.button(button, true).unwrap(), original.button(button, false).unwrap()];
                assert_eq!(outgoing, expected, "mode={mode:?}, button={button}");
                assert!(input.release_all().is_empty());
            }
        }
    }

    #[test]
    fn release_all_cancels_a_pending_touch_after_focus_loss() {
        for mode in [TouchMode::Direct, TouchMode::Trackpad] {
            let mut input = translator(mode);
            input.handle(r#"{"action":"touch_down","abs_x":0.25,"abs_y":0.5,"at_ms":1000}"#).unwrap();
            input.release_all();
            assert!(input.handle(r#"{"action":"touch_up","abs_x":0.25,"abs_y":0.5,"at_ms":1080}"#).unwrap().is_empty());
        }
    }

    #[test]
    fn direct_tap_clicks_left_at_the_touched_position() {
        let mut input = translator(TouchMode::Direct);
        let down = input.handle(r#"{"action":"touch_down","abs_x":0.25,"abs_y":0.5,"pointers":1,"at_ms":1000}"#).unwrap();
        assert_eq!(actions(&down), vec![("mouse_move_absolute", &json!({"action":"mouse_move_absolute","abs_x":0.25,"abs_y":0.5}))]);
        let up = input.handle(r#"{"action":"touch_up","abs_x":0.25,"abs_y":0.5,"pointers":1,"at_ms":1080}"#).unwrap();
        assert_eq!(up, vec![json!({"action":"mouse_press","button":1}), json!({"action":"mouse_release","button":1})]);
    }

    #[test]
    fn direct_long_press_clicks_right_and_drag_holds_left() {
        let mut input = translator(TouchMode::Direct);
        input.handle(r#"{"action":"touch_down","abs_x":0.5,"abs_y":0.5,"at_ms":0}"#).unwrap();
        let held = input.handle(r#"{"action":"touch_up","abs_x":0.5,"abs_y":0.5,"at_ms":450}"#).unwrap();
        assert_eq!(held, vec![json!({"action":"mouse_press","button":2}), json!({"action":"mouse_release","button":2})]);

        input.handle(r#"{"action":"touch_down","abs_x":0.1,"abs_y":0.1,"at_ms":1000}"#).unwrap();
        let first_move = input.handle(r#"{"action":"touch_move","abs_x":0.12,"abs_y":0.1,"at_ms":1020}"#).unwrap();
        assert_eq!(first_move[0], json!({"action":"mouse_press","button":1}));
        assert_eq!(first_move[1]["action"], "mouse_move_absolute");
        let up = input.handle(r#"{"action":"touch_up","abs_x":0.2,"abs_y":0.1,"at_ms":1100}"#).unwrap();
        assert_eq!(up, vec![json!({"action":"mouse_release","button":1})]);
    }

    #[test]
    fn direct_cancel_releases_a_held_drag_only() {
        let mut input = translator(TouchMode::Direct);
        input.handle(r#"{"action":"touch_down","abs_x":0.1,"abs_y":0.1,"at_ms":0}"#).unwrap();
        input.handle(r#"{"action":"touch_move","abs_x":0.2,"abs_y":0.1,"at_ms":10}"#).unwrap();
        assert_eq!(input.handle(r#"{"action":"touch_cancel"}"#).unwrap(), vec![json!({"action":"mouse_release","button":1})]);
        assert!(input.handle(r#"{"action":"touch_cancel"}"#).unwrap().is_empty());
    }

    #[test]
    fn trackpad_tap_clicks_and_move_sends_integer_relative_deltas() {
        let mut input = translator(TouchMode::Trackpad);
        input.handle(r#"{"action":"touch_down","abs_x":0.5,"abs_y":0.5,"at_ms":0}"#).unwrap();
        let moved = input.handle(r#"{"action":"touch_move","abs_x":0.51,"abs_y":0.5,"at_ms":20}"#).unwrap();
        assert_eq!(moved[0]["action"], "mouse_move_relative");
        assert!(moved[0]["delta_x"].is_i64());
        assert!(moved[0]["delta_y"].is_i64());
        assert!(input.handle(r#"{"action":"touch_up","abs_x":0.51,"abs_y":0.5,"at_ms":60}"#).unwrap().is_empty());

        input.handle(r#"{"action":"touch_down","abs_x":0.5,"abs_y":0.5,"at_ms":1000}"#).unwrap();
        let tap = input.handle(r#"{"action":"touch_up","abs_x":0.5,"abs_y":0.5,"at_ms":1050}"#).unwrap();
        assert_eq!(tap, vec![json!({"action":"mouse_press","button":1}), json!({"action":"mouse_release","button":1})]);
    }

    #[test]
    fn two_finger_drag_scrolls_with_wire_integers() {
        let mut input = translator(TouchMode::Trackpad);
        input.handle(r#"{"action":"touch_down","abs_x":0.5,"abs_y":0.5,"pointers":1,"at_ms":0}"#).unwrap();
        input.handle(r#"{"action":"touch_down","abs_x":0.5,"abs_y":0.5,"pointers":2,"at_ms":10}"#).unwrap();
        let scroll = input.handle(r#"{"action":"touch_move","abs_x":0.5,"abs_y":0.55,"pointers":2,"at_ms":30}"#).unwrap();
        assert_eq!(scroll[0]["action"], "mouse_scroll");
        assert!(scroll[0]["delta_y"].as_i64().unwrap() != 0);
        assert!(scroll[0]["delta_x"].as_i64().unwrap() == 0);
        assert!(input.handle(r#"{"action":"touch_up","abs_x":0.5,"abs_y":0.55,"pointers":1,"at_ms":60}"#).unwrap().is_empty());
    }

    #[test]
    fn black_bar_and_invalid_coordinates_are_ignored_not_clamped() {
        let mut input = translator(TouchMode::Direct);
        assert!(input.handle(r#"{"action":"touch_down","abs_x":1.2,"abs_y":0.5}"#).unwrap().is_empty());
        assert!(input.handle(r#"{"action":"touch_down","abs_x":-0.1,"abs_y":0.5}"#).unwrap().is_empty());
        assert!(input.handle(r#"{"action":"touch_down","abs_x":"NaN","abs_y":0.5}"#).is_err());
        assert!(input.handle(r#"{"action":"mouse_move_absolute","abs_x":2.0,"abs_y":-1.0}"#).unwrap()
            == vec![json!({"action":"mouse_move_absolute","abs_x":1.0,"abs_y":0.0})]);
    }

    #[test]
    fn keyboard_fields_cover_press_release_and_click_with_held_deduplication() {
        let mut input = translator(TouchMode::Trackpad);
        assert_eq!(
            input.handle(r#"{"action":"key","scan":4,"down":true}"#).unwrap(),
            vec![json!({"action":"kbd_press","key":65})]
        );
        assert!(input.handle(r#"{"action":"key","scan":4,"down":true}"#).unwrap().is_empty());
        assert_eq!(
            input.handle(r#"{"action":"key","scan":4,"down":false}"#).unwrap(),
            vec![json!({"action":"kbd_release","key":65})]
        );
        assert_eq!(
            input.handle(r#"{"action":"key_click","scan":30}"#).unwrap(),
            vec![json!({"action":"kbd_click","key":49})]
        );
    }

    #[test]
    fn mouse_click_uses_the_windows_compatible_button_pair_without_releasing_a_held_button() {
        let mut input = translator(TouchMode::Direct);
        for button in [1, 2, 4] {
            let click = json!({"action":"mouse_click","button":button}).to_string();
            assert_eq!(input.handle(&click).unwrap(), vec![
                json!({"action":"mouse_press","button":button}),
                json!({"action":"mouse_release","button":button}),
            ]);
            input.handle(&json!({"action":"mouse_press","button":button}).to_string()).unwrap();
            assert!(input.handle(&click).unwrap().is_empty());
            assert_eq!(input.release_all(), vec![json!({"action":"mouse_release","button":button})]);
        }
        assert!(input.handle(r#"{"action":"mouse_click","button":3}"#).unwrap().is_empty());
        input.set_view_only(true);
        assert!(input.handle(r#"{"action":"mouse_click","button":2}"#).unwrap().is_empty());
    }

    #[test]
    fn mouse_fields_match_control_protocol_integer_requirements() {
        let mut input = translator(TouchMode::Trackpad);
        assert_eq!(
            input.handle(r#"{"action":"mouse_press","button":2}"#).unwrap(),
            vec![json!({"action":"mouse_press","button":2})]
        );
        assert_eq!(
            input.handle(r#"{"action":"mouse_release","button":2}"#).unwrap(),
            vec![json!({"action":"mouse_release","button":2})]
        );
        assert_eq!(
            input.handle(r#"{"action":"mouse_click","button":4}"#).unwrap(),
            vec![json!({"action":"mouse_press","button":4}), json!({"action":"mouse_release","button":4})]
        );
        assert_eq!(
            input.handle(r#"{"action":"mouse_scroll","delta_x":-120,"delta_y":240}"#).unwrap(),
            vec![json!({"action":"mouse_scroll","delta_x":-120,"delta_y":240})]
        );
        // The official parser requires i32: a fractional field must fail, not be truncated.
        assert!(input.handle(r#"{"action":"mouse_scroll","delta_x":1.5,"delta_y":0}"#).is_err());
        assert!(input.handle(r#"{"action":"mouse_move_relative","delta_x":0.6,"delta_y":0}"#).unwrap().is_empty());
        assert_eq!(
            input.handle(r#"{"action":"mouse_move_relative","delta_x":0.6,"delta_y":0}"#).unwrap(),
            vec![json!({"action":"mouse_move_relative","delta_x":1,"delta_y":0})]
        );
    }

    #[test]
    fn text_input_uses_the_official_content_field_and_limits_bytes() {
        let mut input = translator(TouchMode::Trackpad);
        assert_eq!(
            input.handle(r#"{"action":"text_input","content":"你好 a"}"#).unwrap(),
            vec![json!({"action":"text_input","content":"你好 a"})]
        );
        let too_long = format!(r#"{{"action":"text_input","content":"{}"}}"#, "a".repeat(16 * 1024 + 1));
        assert!(input.handle(&too_long).is_err());
        assert!(input.handle(r#"{"action":"text_input"}"#).is_err());
    }

    #[test]
    fn view_only_blocks_every_input_path_and_release_all_clears_held_state() {
        let mut input = translator(TouchMode::Direct);
        input.handle(r#"{"action":"key","scan":4,"down":true}"#).unwrap();
        input.handle(r#"{"action":"mouse_press","button":1}"#).unwrap();
        input.set_view_only(true);
        assert!(input.handle(r#"{"action":"touch_down","abs_x":0.5,"abs_y":0.5}"#).unwrap().is_empty());
        assert!(input.handle(r#"{"action":"mouse_press","button":1}"#).unwrap().is_empty());
        input.set_view_only(false);
        let release = input.release_all();
        assert_eq!(release.len(), 2);
        assert!(release.iter().all(|value| value["action"].as_str().unwrap().ends_with("release")));
    }

    #[test]
    fn switching_touch_mode_drops_the_active_gesture_and_releases_held_buttons() {
        let mut input = translator(TouchMode::Direct);
        input.handle(r#"{"action":"touch_down","abs_x":0.2,"abs_y":0.2,"at_ms":0}"#).unwrap();
        input.handle(r#"{"action":"touch_move","abs_x":0.3,"abs_y":0.2,"at_ms":20}"#).unwrap();
        assert_eq!(
            input.set_touch_mode(TouchMode::Trackpad),
            vec![json!({"action":"mouse_release","button":1})]
        );
        assert!(input.handle(r#"{"action":"touch_up","abs_x":0.3,"abs_y":0.2,"at_ms":500}"#).unwrap().is_empty());
    }
}
