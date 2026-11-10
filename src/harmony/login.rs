//! QR sign-in for HarmonyOS. The protocol mirrors `src/login.rs` but the device
//! identity is supplied by the app (stable per installation, no /proc or /sys).

use crate::auth::{Credentials, QrRequestErrorKind, UUAuthClient, DEFAULT_SIGN_KEY};
use crate::harmony::{event, CoreConfig, EventQueue, LoginSnapshot};
use serde_json::{json, Value};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

const QR_EXPIRED: i64 = 1190;
const LONG_POLL: Duration = Duration::from_secs(60);

fn emit(events: &EventQueue, state: LoginSnapshot) {
    event(events, "loginState", serde_json::to_value(state).unwrap_or(Value::Null));
}

fn snapshot(phase: &str, status: &str, qr: Option<&str>, polling: bool, authenticated: bool,
            error: Option<&str>, generation: u64) -> LoginSnapshot {
    LoginSnapshot {
        phase: phase.into(),
        status_text: status.into(),
        qr_payload: qr.map(str::to_owned),
        polling_active: polling,
        authenticated,
        error: error.map(str::to_owned),
        generation,
    }
}

fn qr_data<'a>(status: u16, body: &'a Value) -> Option<&'a Value> {
    let code = body.get("code").and_then(Value::as_i64);
    (status == 200 && code == Some(0)).then(|| body.get("data").unwrap_or(&Value::Null))
}

fn csrf_from_token(token: &str) -> Option<String> {
    use base64::Engine;
    let payload = token.split('.').nth(1)?;
    let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(payload.trim_end_matches('='))
        .ok()?;
    serde_json::from_slice::<Value>(&bytes).ok()?.get("csrf")?.as_str().map(str::to_owned)
}

async fn ensure_device(config: &CoreConfig, creds: &mut Credentials) -> Result<(), String> {
    if !creds.device_id.is_empty() {
        return Ok(());
    }
    let client = UUAuthClient::new(creds.clone());
    let body = json!({
        "name": config.display_name(),
        "client_id": creds.client_id,
        "system_id": creds.system_id,
        "machine_guid": config.machine_guid,
        "os": if config.os_full_name.is_empty() { "HarmonyOS" } else { config.os_full_name.as_str() },
        "base_board": config.model,
        "cpu": config.model,
        "video": ["HarmonyOS"],
        "mac": "",
        "memory": 0,
        "screen": "1920x1080"
    });
    let (status, response) = client
        .post_json("/api/v1/device/windows/init", &body)
        .await
        .map_err(|_| "device initialization failed".to_string())?;
    let data = qr_data(status, &response).ok_or_else(|| "device initialization rejected".to_string())?;
    let id = data
        .get("device_id")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| "device initialization returned no device_id".to_string())?;
    creds.device_id = id.to_owned();
    Ok(())
}

pub async fn run(
    config: &CoreConfig,
    events: &EventQueue,
    generation: u64,
    cancel: Arc<AtomicBool>,
) -> Result<Credentials, String> {
    let mut creds = Credentials {
        client_id: config.client_id.clone(),
        system_id: config.system_id.clone(),
        device_id: config.device_id.clone(),
        sign_key: DEFAULT_SIGN_KEY.into(),
        ..Default::default()
    };
    ensure_device(config, &mut creds).await.map_err(|error| {
        emit(events, snapshot("failed", "无法初始化设备身份", None, false, false, Some(&error), generation));
        error
    })?;
    let client = UUAuthClient::new(creds.clone());
    loop {
        if cancel.load(Ordering::Acquire) {
            emit(events, snapshot("failed", "已取消登录", None, false, false, None, generation));
            return Err("cancelled".into());
        }
        emit(events, snapshot("loadingQr", "正在生成二维码…", None, true, false, None, generation));
        let (status, response) = match client
            .post_with_timeout("/api/v1/qrcode/gen/login", None, LONG_POLL)
            .await
        {
            Ok(result) => result,
            Err(error) => {
                let status = if error.kind == QrRequestErrorKind::Timeout {
                    "二维码生成超时"
                } else {
                    "二维码加载失败"
                };
                emit(events, snapshot("failed", status, None, false, false, None, generation));
                return Err("QR generation failed".into());
            }
        };
        let Some(data) = qr_data(status, &response) else {
            emit(events, snapshot("failed", "二维码加载失败", None, false, false, None, generation));
            return Err("QR generation rejected".into());
        };
        let url = data
            .get("qrcode_jump_url")
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .ok_or_else(|| "QR generation returned no payload".to_string())?
            .to_owned();
        let ticket = data
            .get("status_query_ticket")
            .or_else(|| data.get("token"))
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .ok_or_else(|| "QR generation returned no status ticket".to_string())?
            .to_owned();
        let mut login_status = 1i64;
        emit(events, snapshot("waitingScan", "请扫描二维码", Some(&url), true, false, None, generation));
        loop {
            if cancel.load(Ordering::Acquire) {
                emit(events, snapshot("failed", "已取消登录", None, false, false, None, generation));
                return Err("cancelled".into());
            }
            let query = json!({
                "token": ticket,
                "qrcode_jump_url": url,
                "login_status": login_status
            });
            let (status, response) = match client
                .post_with_timeout("/api/v1/qrcode/login/status", Some(&query), LONG_POLL)
                .await
            {
                Ok(result) => result,
                Err(error) => {
                    let text = if error.kind == QrRequestErrorKind::Timeout {
                        "二维码状态查询超时（不代表二维码已失效）"
                    } else {
                        "暂时无法查询扫码状态"
                    };
                    emit(events, snapshot("queryFailed", text, Some(&url), false, false, None, generation));
                    return Err("QR status query failed".into());
                }
            };
            if response.get("code").and_then(Value::as_i64) == Some(QR_EXPIRED) {
                emit(events, snapshot("expired", "二维码已过期", None, false, false, None, generation));
                return Err("QR expired".into());
            }
            let Some(data) = qr_data(status, &response) else {
                emit(events, snapshot("queryFailed", "暂时无法查询扫码状态", Some(&url), false, false, None, generation));
                return Err("QR status rejected".into());
            };
            match data.get("status").and_then(Value::as_i64) {
                Some(1) => {
                    login_status = 1;
                }
                Some(2) => {
                    login_status = 2;
                    emit(events, snapshot("waitingConfirm", "请在手机上确认", Some(&url), true, false, None, generation));
                }
                Some(0) => {
                    tokio::time::sleep(Duration::from_millis(350)).await;
                    break;
                }
                Some(3) => break,
                Some(4) => {
                    emit(events, snapshot("finalizing", "已确认，正在完成登录…", Some(&url), false, false, None, generation));
                    let body = json!({"token": ticket, "qrcode_jump_url": url});
                    let (status, response) = client
                        .post_with_timeout("/api/v1/login/by_qrcode", Some(&body), LONG_POLL)
                        .await
                        .map_err(|_| "login exchange failed".to_string())?;
                    let data = qr_data(status, &response)
                        .ok_or_else(|| "login was not granted".to_string())?;
                    let token = data
                        .get("token")
                        .and_then(Value::as_str)
                        .ok_or_else(|| "login returned no token".to_string())?
                        .to_owned();
                    let user = data
                        .get("user_id")
                        .and_then(Value::as_str)
                        .ok_or_else(|| "login returned no user_id".to_string())?
                        .to_owned();
                    creds.token = token.clone();
                    creds.user_id = user;
                    creds.csrf = csrf_from_token(&token).unwrap_or_default();
                    return Ok(creds);
                }
                _ => {
                    emit(events, snapshot("failed", "二维码状态响应异常", None, false, false, None, generation));
                    return Err("unexpected QR status".into());
                }
            }
        }
    }
}
