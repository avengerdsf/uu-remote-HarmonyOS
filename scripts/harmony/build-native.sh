#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export UU_TMP_DIR="${UU_TMP_DIR:-$ROOT/tmp}"
mkdir -p "$UU_TMP_DIR"
UU_TMP_DIR="$(cd "$UU_TMP_DIR" && pwd)"
export TMPDIR="$UU_TMP_DIR"
export CARGO_HOME="${CARGO_HOME:-$UU_TMP_DIR/cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-$UU_TMP_DIR/rustup}"
export CARGO_TARGET_DIR="$UU_TMP_DIR/rust-target"
export CARGO_PROFILE_RELEASE_DEBUG=0
export CC_SHELL_ESCAPED_FLAGS=1
export UU_CORE_ONLY=1
if [[ -z "${OHOS_NDK_HOME:-}" && -n "${DEVECO_SDK_HOME:-}" ]]; then
  for candidate in "$DEVECO_SDK_HOME/default/openharmony/native" "$DEVECO_SDK_HOME/native"; do
    if [[ -d "$candidate/sysroot" ]]; then OHOS_NDK_HOME="$candidate"; break; fi
  done
fi
: "${OHOS_NDK_HOME:?set OHOS_NDK_HOME to the HarmonyOS Native SDK}"
SYSROOT="$OHOS_NDK_HOME/sysroot"
[[ -d "$SYSROOT" ]] || { echo "missing SDK sysroot" >&2; exit 2; }
# cc-rs parses CFLAGS as shell words. Quote SDK paths, which commonly contain spaces.
for TARGET in ${UU_RUST_TARGETS:-aarch64-unknown-linux-ohos x86_64-unknown-linux-ohos}; do
  case "$TARGET" in
    aarch64-unknown-linux-ohos) ABI=arm64-v8a; CLANG_TARGET=aarch64-linux-ohos ;;
    x86_64-unknown-linux-ohos) ABI=x86_64; CLANG_TARGET=x86_64-linux-ohos ;;
    *) echo "unsupported target: $TARGET" >&2; exit 2 ;;
  esac
  KEY="${TARGET//-/_}"
  CC_KEY="CC_$KEY"; AR_KEY="AR_$KEY"; FLAGS_KEY="CFLAGS_$KEY"
  export "$CC_KEY=${!CC_KEY:-$OHOS_NDK_HOME/llvm/bin/clang}"
  export "$AR_KEY=${!AR_KEY:-$OHOS_NDK_HOME/llvm/bin/llvm-ar}"
  [[ -x "${!CC_KEY}" && -x "${!AR_KEY}" ]] || { echo "set $CC_KEY and $AR_KEY to native host tools" >&2; exit 2; }
  if [[ -z "${!FLAGS_KEY:-}" ]]; then
    export "$FLAGS_KEY=--target=$CLANG_TARGET --sysroot=\"$SYSROOT\" -isystem \"$SYSROOT/usr/include/$CLANG_TARGET\" -fPIC"
  fi
  SYSROOT_RUST="$(rustc --print sysroot)"
  [[ -d "$SYSROOT_RUST/lib/rustlib/$TARGET" ]] || { echo "install Rust target $TARGET into RUSTUP_HOME first" >&2; exit 2; }
  EXTRA=(); [[ "${UU_CARGO_OFFLINE:-0}" == 1 ]] && EXTRA+=(--offline)
  (cd "$ROOT" && cargo build --release --lib --features harmony --locked --target "$TARGET" "${EXTRA[@]}")
  mkdir -p "$ROOT/harmony/entry/src/main/cpp/libs/$ABI"
  cp "$CARGO_TARGET_DIR/$TARGET/release/libuu_core.a" "$ROOT/harmony/entry/src/main/cpp/libs/$ABI/libuu_core.a"
  echo "staged libuu_core.a ($ABI)"
done
