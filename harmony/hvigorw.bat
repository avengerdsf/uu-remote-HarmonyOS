@echo off
rem Thin project wrapper for DevEco Studio 5.x, which ships hvigor under
rem <DevEco Studio>\tools\hvigor\bin instead of generating hvigorw.bat here.
setlocal EnableDelayedExpansion
if defined DEVECO_HOME if exist "%DEVECO_HOME%\tools\hvigor\bin\hvigorw.bat" (
  call "%DEVECO_HOME%\tools\hvigor\bin\hvigorw.bat" %*
  exit /b !errorlevel!
)
if defined DEVECO_SDK_HOME if exist "%DEVECO_SDK_HOME%\..\tools\hvigor\bin\hvigorw.bat" (
  call "%DEVECO_SDK_HOME%\..\tools\hvigor\bin\hvigorw.bat" %*
  exit /b !errorlevel!
)
if defined COMMAND_LINE_TOOLS if exist "%COMMAND_LINE_TOOLS%\hvigor\bin\hvigorw.bat" (
  call "%COMMAND_LINE_TOOLS%\hvigor\bin\hvigorw.bat" %*
  exit /b !errorlevel!
)
echo hvigorw.bat not found. Set DEVECO_HOME to the DevEco Studio install directory
echo (the one containing tools\hvigor\bin\hvigorw.bat) or install Command Line Tools.
exit /b 2
