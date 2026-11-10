param(
    [string]$NdkHome = $env:OHOS_NDK_HOME,
    [ValidateSet('arm64-v8a', 'x86_64')][string[]]$Architectures = @('arm64-v8a', 'x86_64'),
    [switch]$Offline
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $env:UU_TMP_DIR) { $env:UU_TMP_DIR = Join-Path $Root 'tmp' }
New-Item -ItemType Directory -Force -Path $env:UU_TMP_DIR | Out-Null
$env:TEMP = $env:UU_TMP_DIR; $env:TMP = $env:UU_TMP_DIR
if (-not $env:CARGO_HOME) { $env:CARGO_HOME = Join-Path $env:UU_TMP_DIR 'cargo' }
if (-not $env:RUSTUP_HOME) { $env:RUSTUP_HOME = Join-Path $env:UU_TMP_DIR 'rustup' }
$env:CARGO_TARGET_DIR = Join-Path $env:UU_TMP_DIR 'rust-target'
$env:CARGO_PROFILE_RELEASE_DEBUG = '0'; $env:UU_CORE_ONLY = '1'
$env:CC_SHELL_ESCAPED_FLAGS = '1'
if (-not $NdkHome -and $env:DEVECO_SDK_HOME) {
    foreach ($candidate in @((Join-Path $env:DEVECO_SDK_HOME 'default\openharmony\native'), (Join-Path $env:DEVECO_SDK_HOME 'native'))) {
        if (Test-Path (Join-Path $candidate 'llvm\bin\clang.exe')) { $NdkHome = $candidate; break }
    }
}
if (-not $NdkHome) { throw 'Set OHOS_NDK_HOME or DEVECO_SDK_HOME.' }
$Clang = Join-Path $NdkHome 'llvm\bin\clang.exe'
$Ar = Join-Path $NdkHome 'llvm\bin\llvm-ar.exe'
$Sysroot = Join-Path $NdkHome 'sysroot'
if (-not (Test-Path $Clang) -or -not (Test-Path $Ar)) { throw 'Native SDK compiler not found.' }
Push-Location $Root
try {
    foreach ($abi in $Architectures) {
        $target = if ($abi -eq 'arm64-v8a') { 'aarch64-unknown-linux-ohos' } else { 'x86_64-unknown-linux-ohos' }
        $clangTarget = $target.Replace('-unknown', '')
        $key = $target.Replace('-', '_')
        $rustSysroot = & rustc --print sysroot
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $rustSysroot "lib\rustlib\$target"))) {
            throw "Install Rust target $target into the configured RUSTUP_HOME first."
        }
        Set-Item -Path "Env:CC_$key" -Value $Clang
        Set-Item -Path "Env:AR_$key" -Value $Ar
        Set-Item -Path "Env:CFLAGS_$key" -Value "--target=$clangTarget --sysroot=`"$Sysroot`" -isystem `"$Sysroot\usr\include\$clangTarget`" -fPIC"
        $extra = @(); if ($Offline) { $extra += '--offline' }
        & cargo build --release --lib --features harmony --locked --target $target @extra
        if ($LASTEXITCODE -ne 0) { throw "cargo build failed ($target)" }
        $out = Join-Path $Root "harmony\entry\src\main\cpp\libs\$abi"
        New-Item -ItemType Directory -Force -Path $out | Out-Null
        Copy-Item -LiteralPath (Join-Path $env:CARGO_TARGET_DIR "$target\release\libuu_core.a") -Destination (Join-Path $out 'libuu_core.a') -Force
        Write-Host "staged libuu_core.a ($abi)"
    }
} finally { Pop-Location }
