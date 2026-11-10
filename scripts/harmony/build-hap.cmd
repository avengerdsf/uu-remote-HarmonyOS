@echo off
rem Build the HarmonyOS HAP from a Windows DevEco Studio installation.
rem Run scripts\harmony\build-native.ps1 first to stage libuu_core.a.
setlocal
if not defined DEVECO_HOME (
  for %%D in (
    "%ProgramFiles%\Huawei\DevEco Studio"
    "%LOCALAPPDATA%\Huawei\DevEco Studio"
  ) do (
    if exist "%%~D\tools\hvigor\bin\hvigorw.bat" if not defined DEVECO_HOME set "DEVECO_HOME=%%~D"
  )
)
if not defined DEVECO_SDK_HOME if defined DEVECO_HOME set "DEVECO_SDK_HOME=%DEVECO_HOME%\sdk"
if not defined DEVECO_SDK_HOME (
  echo Set DEVECO_HOME to DevEco Studio or DEVECO_SDK_HOME to the HarmonyOS SDK.
  exit /b 2
)
set "HVIGORW=%~dp0..\..\harmony\hvigorw.bat"
if not exist "%HVIGORW%" (
  echo Missing project hvigor wrapper: %HVIGORW%
  exit /b 2
)
cd /d "%~dp0..\..\harmony"
if not exist "oh_modules" (
  if defined DEVECO_HOME if exist "%DEVECO_HOME%\tools\ohpm\bin\ohpm.bat" (
    call "%DEVECO_HOME%\tools\ohpm\bin\ohpm.bat" install --all
    if errorlevel 1 exit /b %errorlevel%
  )
)
call "%HVIGORW%" clean assembleHap --mode module -p product=default -p buildMode=release --no-daemon
if errorlevel 1 exit /b %errorlevel%
echo HAP built under harmony\entry\build\default\outputs\default
