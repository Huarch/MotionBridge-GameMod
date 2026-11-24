@echo off
setlocal
title MotionBridge Community 0.9.0b Compatibility Installer
echo Install the base Mod 0.18.1 first. Keep the game closed.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0CommunityCompatibility\Install-Compatibility.ps1" -Interactive
set "installerExitCode=%ERRORLEVEL%"
echo.
pause
exit /b %installerExitCode%
