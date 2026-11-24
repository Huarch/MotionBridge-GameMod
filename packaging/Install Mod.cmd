@echo off
setlocal
title MotionBridge Community 0.9.0b Mod Installer
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Mod.ps1" -Interactive
set "result=%ERRORLEVEL%"
pause
exit /b %result%
