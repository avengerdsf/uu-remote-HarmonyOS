//! Video quality, frame rate and color settings for the HarmonyOS controller.
//!
//! The values mirror the original client's control center (`viewer/hud.rs`) and the
//! host-side capture-setting field map (`src/capture_setting.rs`):
//! quality 5 auto / 4 原画 20M / 3 超清 8M / 2 高清 2M, frame rate 30/60/90/144,
//! chroma 1 = 4:2:0 and 3 = 真彩 4:4:4. Requests travel as Message 21 RPC case 2
//! (`CaptureSettingRequest`) and the host reports the encoded result with Message 25
//! (`CaptureSettingSync`), which this module parses so the UI shows the actual stream
//! instead of echoing the requested values.

use crate::protocol::{decode_wire, WireField, WireValue};
use serde_json::Value;

pub const QUALITY_AUTO: u32 = 5;
pub const QUALITY_ORIGINAL: u32 = 4; // 原画 20M
pub const QUALITY_ULTRA: u32 = 3; // 超清 8M
pub const QUALITY_HD: u32 = 2; // 高清 2M
pub const QUALITY_MIN: u32 = QUALITY_HD;
pub const QUALITY_MAX: u32 = QUALITY_AUTO;

pub const CHROMA_420: u32 = 1;
pub const CHROMA_444: u32 = 3;

pub const FPS_OPTIONS: [u32; 4] = [30, 60, 90, 144];
const MAX_SCREEN_DIMENSION: u32 = 16_384;

#[derive(Default)]
pub struct RtpClock {
    last: Option<u32>,
    ticks: i64,
}

impl RtpClock {
    /// Extend the 90 kHz RTP clock through u32 rollover without replacing PTS
    /// with packet arrival time (reordering can deliver several AUs at once).
    pub fn micros(&mut self, timestamp: u32) -> i64 {
        self.ticks += self.last.map_or(i64::from(timestamp), |last| i64::from(timestamp.wrapping_sub(last) as i32));
        self.last = Some(timestamp);
        self.ticks * 1_000_000 / 90_000
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Resolution {
    /// Follow the remote desktop (CaptureSettingRequest field 10 = 3).
    Native,
    /// Follow the current local viewport, in physical pixels.
    Window(u32, u32),
    /// On a portrait phone, use the viewport width and the host screen's aspect ratio.
    WindowWidth { width: u32, decoder_size: (u32, u32) },
    /// Scale the stream below the native desktop size (fields 5/6 and 16/17).
    Size(u32, u32),
}

impl Resolution {
    pub fn parse(value: &str) -> Option<Self> {
        let value = value.trim().to_ascii_lowercase();
        if matches!(value.as_str(), "" | "auto" | "native" | "follow") {
            return Some(Self::Native);
        }
        if value == "window" { return Some(Self::Window(1280, 720)); }
        if let Some((width, height)) = value.split_once('x') {
            let (width, height) = (width.parse().ok()?, height.parse().ok()?);
            return valid_screen_size(width, height).then_some(Self::Size(width, height));
        }
        let base = value.split('p').next().unwrap_or("");
        let size = match base {
            "2160" | "4k" => (3840, 2160),
            "1440" | "2k" => (2560, 1440),
            "1080" | "fhd" => (1920, 1080),
            "720" | "hd" => (1280, 720),
            _ => return None,
        };
        Some(Self::Size(size.0, size.1))
    }

    pub(super) fn fields_for_screen(self, screen: Option<&ResolutionScreen>) -> Vec<(u32, u64)> {
        // ChooseResolutionType in the GameViewerServer 4.46 descriptor.
        let mut fields = Vec::new();
        if let Some(screen) = screen { fields.push((4, u64::from(screen.id))); }
        let (mode, dimensions) = match self {
            Self::Native => (3, screen.and_then(|screen| screen.initial)),
            Self::Window(width, height) => (2, Some(ScreenMode { logical: (width, height), physical: (width, height) })),
            Self::WindowWidth { width, decoder_size } => (2, Some(width_fitted_mode(width, decoder_size, screen))),
            Self::Size(width, height) => {
                let physical = (width, height);
                let dimensions = match screen {
                    Some(screen) if !screen.modes.is_empty() => {
                        let Some(mode) = screen.modes.iter().find(|mode| mode.physical == physical) else {
                            return Vec::new();
                        };
                        *mode
                    }
                    _ => ScreenMode { logical: physical, physical },
                };
                (4, Some(dimensions))
            }
        };
        fields.push((10, mode));
        if let Some(dimensions) = dimensions {
            let (width, height) = dimensions.logical;
            let (pixel_width, pixel_height) = dimensions.physical;
            fields.extend([(5, width.into()), (6, height.into()),
                (16, pixel_width.into()), (17, pixel_height.into())]);
        }
        fields
    }

    /// A capability ceiling for the connect Shape; None = advertise the 4K ceiling.
    pub fn size(self) -> (u32, u32) {
        match self {
            Self::Native => (3840, 2160),
            Self::Window(width, height) | Self::Size(width, height) => (width, height),
            Self::WindowWidth { width, decoder_size } => width_fitted_mode(width, decoder_size, None).physical,
        }
    }

    pub fn resized(self, width: u32, height: u32, phone: bool) -> Self {
        if !matches!(self, Self::Window(..) | Self::WindowWidth { .. }) || width < 2 || height < 2 {
            return self;
        }
        if phone && width < height {
            Self::WindowWidth { width, decoder_size: (3840, 2160) }
        } else {
            Self::Window(width.min(3840) & !1, height.min(2160) & !1)
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct VideoSettings {
    pub quality: u32,
    pub fps: u32,
    pub chroma: u32,
    pub resolution: Resolution,
}

/// Decoder ceiling reported by the platform. The default is deliberately the
/// pre-probe baseline (4:2:0, 60 fps): a missing or failed probe must never make
/// the host send a stream this device cannot decode.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DecoderCapabilities {
    pub max_fps: u32,
    pub chroma_444: bool,
    pub hevc: bool,
    pub max_width: u32,
    pub max_height: u32,
}

impl Default for DecoderCapabilities {
    fn default() -> Self {
        Self {
            max_fps: 60,
            chroma_444: false,
            hevc: false,
            max_width: 1920,
            max_height: 1080,
        }
    }
}

impl DecoderCapabilities {
    /// Snaps a probed frame-rate ceiling to one of the four wire options and
    /// keeps 4:4:4 opt-in (the public AVCodec capability API does not expose
    /// chroma sampling, so the native probe reports false until proven).
    pub fn sanitized(self) -> Self {
        let max_fps = match self.max_fps {
            0 => 60,
            1..=59 => 30,
            60..=89 => 60,
            90..=143 => 90,
            _ => 144,
        };
        Self {
            max_fps,
            chroma_444: self.chroma_444,
            hevc: self.hevc,
            max_width: self.max_width.clamp(640, 3840),
            max_height: self.max_height.clamp(480, 2160),
        }
    }
}

impl Default for VideoSettings {
    fn default() -> Self {
        Self {
            quality: QUALITY_AUTO,
            fps: 60,
            chroma: CHROMA_420,
            resolution: Resolution::Native,
        }
    }
}

/// Bitrate cap the official host applies to each preset (src/capture_setting.rs):
/// 高清 2M, 超清 8M, 原画 20M; 自动 keeps constant-quality encoding with no cap.
pub fn preset_max_kbps(quality: u32) -> Option<u32> {
    match quality {
        QUALITY_HD => Some(2_000),
        QUALITY_ULTRA => Some(8_000),
        QUALITY_ORIGINAL => Some(20_000),
        _ => None,
    }
}

/// Official GvPb_VideoQuality name mapping used by the settings UI.
pub fn quality_value(id: &str) -> Option<u32> {
    match id.trim().to_ascii_lowercase().as_str() {
        "auto" => Some(QUALITY_AUTO),
        "original" | "bluray" | "20m" => Some(QUALITY_ORIGINAL),
        "ultra" | "8m" => Some(QUALITY_ULTRA),
        "hd" | "2m" => Some(QUALITY_HD),
        other => other
            .parse::<u32>()
            .ok()
            .filter(|value| (QUALITY_MIN..=QUALITY_MAX).contains(value)),
    }
}

/// CaptureSettingRequest field 1 is the menu option index, field 18 the actual fps.
pub fn fps_option(fps: u32) -> u64 {
    match fps {
        30 => 1,
        60 => 2,
        90 => 3,
        _ => 4,
    }
}

impl VideoSettings {
    pub fn limited(mut self, caps: DecoderCapabilities) -> Self {
        let caps = caps.sanitized();
        self.fps = self.fps.min(caps.max_fps);
        if !caps.chroma_444 { self.chroma = CHROMA_420; }
        if let Resolution::WindowWidth { width, .. } = self.resolution {
            self.resolution = Resolution::WindowWidth { width, decoder_size: (caps.max_width, caps.max_height) };
        } else if !matches!(self.resolution, Resolution::Native) {
            let (width, height) = self.resolution.size();
            let ratio = (f64::from(caps.max_width) / f64::from(width))
                .min(f64::from(caps.max_height) / f64::from(height)).min(1.0);
            let width = ((f64::from(width) * ratio) as u32).max(2) & !1;
            let height = ((f64::from(height) * ratio) as u32).max(2) & !1;
            self.resolution = if matches!(self.resolution, Resolution::Window(..)) {
                Resolution::Window(width, height)
            } else { Resolution::Size(width, height) };
        }
        self
    }

    pub fn sanitized(mut self) -> Self {
        if !(QUALITY_MIN..=QUALITY_MAX).contains(&self.quality) {
            self.quality = QUALITY_AUTO;
        }
        if !FPS_OPTIONS.contains(&self.fps) {
            self.fps = 60;
        }
        if !matches!(self.chroma, CHROMA_420 | CHROMA_444) {
            self.chroma = CHROMA_420;
        }
        self
    }

    /// Applies the JSON keys sent by the ArkTS settings layer. Unknown or invalid
    /// values keep the previous setting; returns whether anything changed.
    pub fn apply_params(&mut self, params: &Value) -> bool {
        let before = *self;
        if let Some(quality) = params.get("quality").and_then(Value::as_str) {
            if let Some(value) = quality_value(quality) {
                self.quality = value;
            }
        } else if let Some(quality) = params.get("quality").and_then(Value::as_u64) {
            self.quality = quality as u32;
        }
        if let Some(fps) = params.get("fps").and_then(Value::as_u64) {
            self.fps = fps as u32;
        }
        if let Some(enabled) = params.get("trueColor").and_then(Value::as_bool) {
            self.chroma = if enabled { CHROMA_444 } else { CHROMA_420 };
        } else if let Some(chroma) = params.get("chroma").and_then(Value::as_u64) {
            self.chroma = chroma as u32;
        }
        if let Some(profile) = params
            .get("profile")
            .or_else(|| params.get("resolution"))
            .and_then(Value::as_str)
        {
            if let Some(resolution) = Resolution::parse(profile) {
                self.resolution = resolution;
            }
        }
        *self = self.sanitized();
        *self != before
    }

    #[cfg(test)]
    pub fn fields(self) -> Vec<(u32, u64)> {
        let mut fields = self.settings_fields(None);
        fields.extend(self.resolution.fields_for_screen(None));
        fields
    }

    #[cfg(test)]
    pub fn changes_from(self, previous: Self) -> Vec<(u32, u64)> {
        let mut fields = self.settings_fields(Some(previous));
        if self.resolution != previous.resolution {
            fields.extend(self.resolution.fields_for_screen(None));
        }
        fields
    }

    pub(super) fn settings_fields(self, previous: Option<Self>) -> Vec<(u32, u64)> {
        let mut fields = Vec::new();
        if previous.map(|value| value.quality) != Some(self.quality) {
            fields.push((2, u64::from(self.quality)));
        }
        if previous.map(|value| value.fps) != Some(self.fps) {
            fields.push((1, fps_option(self.fps)));
            fields.push((18, u64::from(self.fps)));
        }
        if previous.map(|value| value.chroma) != Some(self.chroma) {
            fields.push((7, u64::from(self.chroma)));
        }
        fields
    }
}

/// CaptureSettingSync (Message 25) as actually encoded by the host.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CaptureSync {
    pub fps: u32,
    pub quality: u32,
    pub chroma: u32,
    pub width: u32,
    pub height: u32,
}

fn number(fields: &[WireField], wanted: u32) -> Option<u64> {
    fields.iter().find_map(|field| match (field.number, &field.value) {
        (number, WireValue::Varint(value)) if number == wanted => Some(*value),
        _ => None,
    })
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct ScreenMode {
    logical: (u32, u32),
    pub physical: (u32, u32),
}

#[derive(Debug, PartialEq, Eq)]
pub(super) struct ResolutionScreen {
    pub id: u32,
    pub modes: Vec<ScreenMode>,
    pub initial: Option<ScreenMode>,
}

fn width_fitted_mode(width: u32, (max_width, max_height): (u32, u32), screen: Option<&ResolutionScreen>) -> ScreenMode {
    let reference = screen.and_then(|screen| screen.initial.or_else(|| screen.modes.iter()
        .max_by_key(|mode| mode.physical.0 * mode.physical.1).copied()));
    let (aspect_width, aspect_height) = reference.map_or((16, 9), |mode| mode.physical);
    let width_at_height_limit = (u64::from(max_height) * u64::from(aspect_width) / u64::from(aspect_height)) as u32;
    let width = width.min(max_width).min(width_at_height_limit.max(2)) & !1;
    let height = (u64::from(width) * u64::from(aspect_height) / u64::from(aspect_width)) as u32;
    let height = height.clamp(2, max_height) & !1;
    let ideal = ScreenMode { logical: (width, height), physical: (width, height) };
    // Physical Windows displays require an advertised size for the selected screen.
    screen.and_then(|screen| screen.modes.iter().copied().filter(|mode| {
        let (w, h) = mode.physical;
        w <= max_width && h <= max_height && w % 2 == 0 && h % 2 == 0
    }).min_by_key(|mode| {
        let (w, h) = mode.physical;
        (w.abs_diff(width) + h.abs_diff(height), w.abs_diff(width), w * h)
    })).unwrap_or(ideal)
}

fn valid_screen_size(width: u32, height: u32) -> bool {
    (1..=MAX_SCREEN_DIMENSION).contains(&width) && (1..=MAX_SCREEN_DIMENSION).contains(&height)
}

fn screen_mode(data: &[u8]) -> Option<ScreenMode> {
    let fields = decode_wire(data).ok()?;
    let pair = |w, h| {
        let width = u32::try_from(number(&fields, w)?).ok()?;
        let height = u32::try_from(number(&fields, h)?).ok()?;
        valid_screen_size(width, height).then_some((width, height))
    };
    let logical = pair(3, 4);
    let physical = pair(5, 6);
    Some(ScreenMode { logical: logical.or(physical)?, physical: physical.or(logical)? })
}

/// ScreenSources (Message 7). Only the active screen's advertised fixed modes are selectable.
pub(super) fn parse_resolution_screen(data: &[u8]) -> Option<ResolutionScreen> {
    use crate::viewer::tools::blob;
    if data.len() > 256 * 1024 { return None; }
    let inventory = decode_wire(blob(data, 7)?).ok()?;
    let active = number(&inventory, 2).unwrap_or(0);
    let mut best = None;
    for field in inventory.iter().filter(|field| field.number == 1).take(64) {
        let WireValue::Bytes(bytes) = field.value else { continue };
        let Ok(screen) = decode_wire(bytes) else { continue };
        let id = number(&screen, 1).unwrap_or(0);
        if id > i32::MAX as u64 { continue; }
        let rank = if id == active { 2 } else if number(&screen, 7) == Some(1) { 1 } else { 0 };
        if best.as_ref().is_some_and(|(previous, _)| rank <= *previous) { continue; }
        best = Some((rank, (id as u32, screen)));
        if rank == 2 { break; }
    }
    let (_, (id, screen)) = best?;
    let mut modes = screen.iter().filter(|field| field.number == 3).take(256)
        .filter_map(|field| match field.value {
            WireValue::Bytes(bytes) => screen_mode(bytes),
            _ => None,
        }).collect::<Vec<_>>();
    modes.sort_unstable_by_key(|mode| (mode.physical, mode.logical));
    modes.dedup_by_key(|mode| mode.physical);
    let initial = screen.iter().find_map(|field| match (field.number, &field.value) {
        (6, WireValue::Bytes(bytes)) => screen_mode(bytes),
        _ => None,
    });
    Some(ResolutionScreen { id, modes, initial })
}

fn width_height(fields: &[WireField]) -> (u32, u32) {
    let pair = |width_field, height_field| {
        let width = u32::try_from(number(fields, width_field)?).ok()?;
        let height = u32::try_from(number(fields, height_field)?).ok()?;
        (width > 0 && height > 0).then_some((width, height))
    };
    // CaptureSettingSync 9/10 are physical pixels and 5/6 are logical dimensions.
    pair(9, 10).or_else(|| pair(5, 6)).unwrap_or_default()
}

/// Message 22 / CaptureSettingResponse (case 2) carries repeated errors in field 1.
pub fn capture_setting_rejected(data: &[u8]) -> bool {
    use crate::viewer::tools::blob;
    blob(data, 22).and_then(|rpc| blob(rpc, 2)).and_then(|reply| decode_wire(reply).ok())
        .is_some_and(|fields| fields.iter().any(|field| match (field.number, &field.value) {
            (1, WireValue::Bytes(error)) => decode_wire(error).ok()
                .and_then(|fields| number(&fields, 1)).is_some_and(|code| code != 0),
            _ => false,
        }))
}

/// Parses a Message 25 envelope (`field 25` carries CaptureSettingSync).
pub fn parse_capture_sync(data: &[u8]) -> Option<CaptureSync> {
    let message = decode_wire(data).ok()?;
    let payload = message.iter().find_map(|field| match (field.number, &field.value) {
        (25, WireValue::Bytes(bytes)) => Some(*bytes),
        _ => None,
    })?;
    let sync = decode_wire(payload).ok()?;
    let (width, height) = width_height(&sync);
    Some(CaptureSync {
        fps: number(&sync, 1).unwrap_or(0).min(u64::from(u32::MAX)) as u32,
        quality: number(&sync, 2).unwrap_or(0).min(u64::from(u32::MAX)) as u32,
        chroma: number(&sync, 3).unwrap_or(0).min(u64::from(u32::MAX)) as u32,
        width,
        height,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rtp_clock_preserves_zero_and_extends_rollover() {
        let mut clock = RtpClock::default();
        assert_eq!(clock.micros(0), 0);
        assert_eq!(clock.micros(90000), 1_000_000);
        let mut clock = RtpClock::default();
        let before = u32::MAX - 44999;
        assert_eq!(clock.micros(before), i64::from(before) * 1_000_000 / 90000);
        assert_eq!(clock.micros(45000), (i64::from(before) + 90000) * 1_000_000 / 90000);
        // Preserve signed presentation deltas when decode and display order differ.
        assert_eq!(clock.micros(0), (i64::from(before) + 45000) * 1_000_000 / 90000);
    }
    use crate::viewer::wire;

    #[test]
    fn quality_presets_match_the_original_menu_and_bitrates() {
        // viewer/hud.rs labels: 自动 / 原画 20M / 超清 8M / 高清 2M.
        assert_eq!(quality_value("auto"), Some(QUALITY_AUTO));
        assert_eq!(quality_value("original"), Some(4));
        assert_eq!(quality_value("ultra"), Some(3));
        assert_eq!(quality_value("hd"), Some(2));
        assert_eq!(quality_value("20m"), Some(4));
        assert_eq!(quality_value("0"), None);
        assert_eq!(quality_value("6"), None);
        // Host caps for the same enum (src/capture_setting.rs::max_kbps).
        assert_eq!(preset_max_kbps(QUALITY_ORIGINAL), Some(20_000));
        assert_eq!(preset_max_kbps(QUALITY_ULTRA), Some(8_000));
        assert_eq!(preset_max_kbps(QUALITY_HD), Some(2_000));
        assert_eq!(preset_max_kbps(QUALITY_AUTO), None);
    }

    #[test]
    fn frame_rate_fields_cover_30_60_90_and_144() {
        for (fps, option) in [(30, 1), (60, 2), (90, 3), (144, 4)] {
            let settings = VideoSettings { fps, ..Default::default() };
            let previous = VideoSettings { fps: if fps == 60 { 30 } else { 60 }, ..settings };
            let fields = settings.changes_from(previous);
            assert_eq!(fields, vec![(1, option), (18, u64::from(fps))]);
        }
        assert_eq!(VideoSettings { fps: 75, ..Default::default() }.sanitized().fps, 60);
    }

    #[test]
    fn true_color_requests_chroma_444_and_keeps_the_other_fields() {
        let mut settings = VideoSettings::default();
        let params = serde_json::json!({"quality": "ultra", "fps": 90, "trueColor": true});
        assert!(settings.apply_params(&params));
        assert_eq!(settings, VideoSettings { quality: QUALITY_ULTRA, fps: 90, chroma: CHROMA_444, resolution: Resolution::Native });
        assert_eq!(settings.fields(), vec![(2, 3), (1, 3), (18, 90), (7, 3), (10, 3)]);
        assert!(settings.apply_params(&serde_json::json!({"trueColor": false})));
        assert_eq!(settings.changes_from(VideoSettings { chroma: CHROMA_444, ..settings }), vec![(7, 1)]);
    }

    #[test]
    fn changed_groups_are_sent_without_repeating_unrelated_fields() {
        let base = VideoSettings::default();
        assert!(base.changes_from(base).is_empty());
        assert_eq!(
            VideoSettings { quality: QUALITY_HD, ..base }.changes_from(base),
            vec![(2, 2)]
        );
        assert_eq!(
            VideoSettings { resolution: Resolution::Size(1920, 1080), ..base }.changes_from(base),
            vec![(10, 4), (5, 1920), (6, 1080), (16, 1920), (17, 1080)]
        );
    }

    #[test]
    fn resolution_profiles_keep_the_existing_ids_and_pixels() {
        for (id, size) in [
            ("auto", (3840, 2160)),
            ("2160p60", (3840, 2160)),
            ("1440p60", (2560, 1440)),
            ("1080p60", (1920, 1080)),
            ("720p30", (1280, 720)),
        ] {
            let resolution = Resolution::parse(id).unwrap();
            assert_eq!(resolution.size(), size);
        }
        assert_eq!(Resolution::parse("qhd"), None);
        assert_eq!(Resolution::parse("1600x900"), Some(Resolution::Size(1600, 900)));
        assert_eq!(Resolution::parse("0x900"), None);
        assert_eq!(Resolution::parse("1600x65536"), None);
    }

    #[test]
    fn screen_inventory_targets_selected_monitor_and_preserves_reported_dimensions() {
        let mut mode = Vec::new();
        for (field, value) in [(3, 1280), (4, 720), (5, 2560), (6, 1440)] {
            wire::int(field, value, &mut mode);
        }
        let mut selected = Vec::new();
        wire::int(1, 7, &mut selected);
        wire::bytes(3, &mode, &mut selected);
        wire::bytes(3, &mode, &mut selected);
        wire::bytes(4, &mode, &mut selected);
        let mut initial = Vec::new();
        for (field, value) in [(3, 1920), (4, 1080), (5, 3840), (6, 2160)] {
            wire::int(field, value, &mut initial);
        }
        wire::bytes(6, &initial, &mut selected);
        let mut primary = Vec::new();
        wire::int(1, 3, &mut primary);
        wire::int(7, 1, &mut primary);
        let mut inventory = Vec::new();
        wire::bytes(1, &primary, &mut inventory);
        wire::bytes(1, &selected, &mut inventory);
        let fallback = parse_resolution_screen(&wire::envelope(1, 7, &inventory)).unwrap();
        assert_eq!(fallback.id, 3);
        wire::int(2, 7, &mut inventory);
        let screen = parse_resolution_screen(&wire::envelope(2, 7, &inventory)).unwrap();
        assert_eq!(screen.id, 7);
        assert_eq!(screen.modes.len(), 1);
        assert_eq!(Resolution::Size(2560, 1440).fields_for_screen(Some(&screen)),
            vec![(4, 7), (10, 4), (5, 1280), (6, 720), (16, 2560), (17, 1440)]);
        assert!(Resolution::Size(3840, 2160).fields_for_screen(Some(&screen)).is_empty());
        assert_eq!(Resolution::Native.fields_for_screen(Some(&screen)),
            vec![(4, 7), (10, 3), (5, 1920), (6, 1080), (16, 3840), (17, 2160)]);
        assert_eq!(Resolution::Native.fields_for_screen(Some(&fallback)), vec![(4, 3), (10, 3)]);
    }

    #[test]
    fn capture_sync_reports_encoded_fps_quality_chroma_and_size() {
        let mut sync = Vec::new();
        for (field, value) in [(1u32, 90u64), (2, 4), (3, 3), (5, 1280), (6, 720), (9, 2560), (10, 1440)] {
            wire::int(field, value, &mut sync);
        }
        let message = wire::envelope(7, 25, &sync);
        assert_eq!(
            parse_capture_sync(&message),
            Some(CaptureSync { fps: 90, quality: 4, chroma: 3, width: 2560, height: 1440 })
        );
        // Use the logical pair when no complete pixel pair is available.
        let mut legacy = Vec::new();
        wire::int(5, 1920, &mut legacy);
        wire::int(6, 1080, &mut legacy);
        wire::int(9, 3840, &mut legacy);
        let parsed = parse_capture_sync(&wire::envelope(8, 25, &legacy)).unwrap();
        assert_eq!((parsed.width, parsed.height), (1920, 1080));
        assert_eq!(parse_capture_sync(&wire::envelope(9, 3, &[])), None);
    }

    #[test]
    fn generated_request_has_the_exact_capture_setting_fields() {
        let requested = VideoSettings {
            quality: QUALITY_ORIGINAL,
            fps: 144,
            chroma: CHROMA_444,
            resolution: Resolution::Size(1280, 720),
        };
        let message = wire::capture_setting(42, &requested.fields());
        let envelope = crate::protocol::decode_wire(&message).unwrap();
        let rpc = crate::viewer::tools::blob(&message, 21).expect("RpcRequest");
        assert!(envelope.iter().any(|field| field.number == 21));
        let rpc = crate::protocol::decode_wire(rpc).unwrap();
        let body = rpc.iter().find_map(|field| match (field.number, &field.value) {
            (2, crate::protocol::WireValue::Bytes(bytes)) => Some(*bytes),
            _ => None,
        }).expect("CaptureSettingRequest");
        let fields = crate::protocol::decode_wire(body).unwrap();
        let numbers: Vec<(u32, u64)> = fields.iter().filter_map(|field| match field.value {
            crate::protocol::WireValue::Varint(value) => Some((field.number, value)),
            _ => None,
        }).collect();
        assert_eq!(numbers, vec![(2, 4), (1, 4), (18, 144), (7, 3), (10, 4), (5, 1280), (6, 720), (16, 1280), (17, 720)]);
    }

    #[test]
    fn only_capture_setting_error_replies_report_rejection() {
        let mut errors = Vec::new();
        wire::bytes(1, &[8, 1], &mut errors);
        let response = |case, body: &[u8]| {
            let mut rpc = Vec::new();
            wire::bytes(case, body, &mut rpc);
            wire::envelope(7, 22, &rpc)
        };
        assert!(capture_setting_rejected(&response(2, &errors)));
        assert!(!capture_setting_rejected(&response(2, &[])));
        assert!(!capture_setting_rejected(&response(3, &errors)));
        let mut success = Vec::new();
        wire::bytes(1, &[8, 0], &mut success);
        assert!(!capture_setting_rejected(&response(2, &success)));
    }

    #[test]
    fn decoder_capabilities_snap_to_wire_options_and_default_to_conservative() {
        assert_eq!(
            DecoderCapabilities::default(),
            DecoderCapabilities { max_fps: 60, chroma_444: false, ..Default::default() }
        );
        assert_eq!(DecoderCapabilities { max_fps: 144, chroma_444: true, ..Default::default() }.sanitized().max_fps, 144);
        assert_eq!(DecoderCapabilities { max_fps: 120, chroma_444: false, ..Default::default() }.sanitized().max_fps, 90);
        assert_eq!(DecoderCapabilities { max_fps: 75, chroma_444: false, ..Default::default() }.sanitized().max_fps, 60);
        assert_eq!(DecoderCapabilities { max_fps: 0, chroma_444: false, ..Default::default() }.sanitized().max_fps, 60);
        assert_eq!(DecoderCapabilities { max_fps: 30, ..Default::default() }.sanitized().max_fps, 30);
        assert!(!DecoderCapabilities { max_fps: 144, chroma_444: false, ..Default::default() }.sanitized().chroma_444);
    }

    #[test]
    fn requests_never_exceed_the_probed_decoder() {
        let caps = DecoderCapabilities { max_fps: 30, max_width: 1280, max_height: 720, ..Default::default() };
        let requested = VideoSettings { fps: 144, chroma: CHROMA_444, resolution: Resolution::Size(3840, 2160), ..Default::default() };
        let actual = requested.limited(caps);
        assert_eq!((actual.fps, actual.chroma, actual.resolution), (30, CHROMA_420, Resolution::Size(1280, 720)));
    }

    #[test]
    fn native_resolution_keeps_follow_remote_and_window_resolution_tracks_even_pixels() {
        let native = VideoSettings::default().limited(DecoderCapabilities::default());
        assert!(native.fields().contains(&(10, 3)));
        assert!(!native.fields().iter().any(|(field, _)| *field == 5));
        let window = Resolution::parse("window").unwrap().resized(801, 601, true);
        assert_eq!(window, Resolution::Window(800, 600));
        assert_eq!(window.resized(0, 0, true), window);
        assert_eq!(Resolution::Native.resized(800, 600, true), Resolution::Native);
        assert_eq!(window.resized(800, 1000, false), Resolution::Window(800, 1000));
        let limited = VideoSettings { resolution: window.resized(3000, 2000, true), ..native }
            .limited(DecoderCapabilities::default());
        assert_eq!(limited.resolution, Resolution::Window(1620, 1080));
        assert!(limited.fields().contains(&(10, 2)));
        assert!(limited.fields().contains(&(16, 1620)));
    }

    #[test]
    fn portrait_window_uses_the_host_aspect_and_nearest_decodable_screen_mode() {
        let resolution = Resolution::parse("window").unwrap().resized(1260, 2800, true);
        let initial = ScreenMode { logical: (1600, 1200), physical: (1600, 1200) };
        let mut screen = ResolutionScreen { id: 7, modes: Vec::new(), initial: Some(initial) };
        assert_eq!(resolution.fields_for_screen(Some(&screen)),
            vec![(4, 7), (10, 2), (5, 1260), (6, 944), (16, 1260), (17, 944)]);
        screen.modes = vec![initial, ScreenMode { logical: (640, 480), physical: (1280, 960) },
            ScreenMode { logical: (1280, 900), physical: (1280, 900) }];
        let caps = DecoderCapabilities { max_width: 1280, max_height: 900, ..Default::default() };
        let limited = VideoSettings { resolution, ..Default::default() }.limited(caps);
        assert_eq!(limited.resolution.fields_for_screen(Some(&screen)),
            vec![(4, 7), (10, 2), (5, 1280), (6, 900), (16, 1280), (17, 900)]);
        assert_eq!(resolution.fields_for_screen(Some(&screen)),
            vec![(4, 7), (10, 2), (5, 640), (6, 480), (16, 1280), (17, 960)]);
    }
}
