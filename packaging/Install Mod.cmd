@echo off
setlocal
title MotionBridge Fallen Doll Playtest Mod Installer

echo MotionBridge Fallen Doll Playtest Mod Installer
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Install-Mod.ps1" -Edition Playtest -Interactive
set "installerExitCode=%ERRORLEVEL%"

echo.
if not "%installerExitCode%"=="0" (
    echo Installation failed. See the message above and Install-Mod.log.
) else (
    echo Installation finished. You may close this window.
)
echo.
pause
exit /b %installerExitCode%
