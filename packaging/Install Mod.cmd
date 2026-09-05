@echo off
setlocal
chcp 65001 >nul
title MotionBridge Fallen Doll Playtest Mod Installer

echo MotionBridge Fallen Doll Playtest Mod Installer
echo MotionBridge Fallen Doll Playtest Mod Installer / Fallen Doll Playtest Mod 安装器
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Install-Mod.ps1" -Edition Playtest -Interactive
set "installerExitCode=%ERRORLEVEL%"

echo.
if not "%installerExitCode%"=="0" (
    echo Installation failed. See the message above and Install-Mod.log.
    echo 安装失败。请查看上方提示和 Install-Mod.log。
) else (
    echo Installation finished. You may close this window.
    echo 安装完成，可以关闭此窗口。
)
echo.
pause
exit /b %installerExitCode%
