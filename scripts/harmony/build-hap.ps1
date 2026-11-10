param(
    [string]$DevEcoHome = $env:DEVECO_HOME,
    [ValidateSet('debug', 'release')][string]$BuildMode = 'debug',
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $DevEcoHome) { throw 'Set DEVECO_HOME to the installed DevEco Studio directory.' }
if (-not (Get-Command devecocli -ErrorAction SilentlyContinue)) { throw 'Install DevEco CLI before building.' }
$env:DEVECO_HOME = $DevEcoHome; $env:DEVECO_PATH = $DevEcoHome
if (-not $env:DEVECO_SDK_HOME) { $env:DEVECO_SDK_HOME = Join-Path $DevEcoHome 'sdk' }
$env:JAVA_HOME = Join-Path $DevEcoHome 'jbr'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
if (-not $env:UU_TMP_DIR) { $env:UU_TMP_DIR = Join-Path $Root 'tmp' }
New-Item -ItemType Directory -Force -Path $env:UU_TMP_DIR | Out-Null
$env:TEMP = $env:UU_TMP_DIR; $env:TMP = $env:UU_TMP_DIR
$env:HVIGOR_USER_HOME = Join-Path $env:UU_TMP_DIR 'hvigor'
$env:OHPM_HOME = Join-Path $env:UU_TMP_DIR 'ohpm'
$env:npm_config_cache = Join-Path $env:UU_TMP_DIR 'npm'
if (-not $SkipNative) { & (Join-Path $PSScriptRoot 'build-native.ps1') }
Push-Location (Join-Path $Root 'harmony')
try {
    & devecocli build --modules entry --build-mode $BuildMode
    if ($LASTEXITCODE -ne 0) { throw 'devecocli build failed' }
    Write-Host 'HAP output: harmony\entry\build\default\outputs\default'
} finally { Pop-Location }
