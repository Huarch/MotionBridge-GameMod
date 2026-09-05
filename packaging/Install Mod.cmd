@echo off
setlocal
chcp 65001 >nul
title MotionBridge Fallen Doll Demo Mod Installer

echo MotionBridge Fallen Doll Demo / Legacy 0.49 Mod Installer
echo MotionBridge Fallen Doll Demo / Legacy 0.49 Mod 安装器
echo.
echo [D] Demo Desktop
echo [V] Demo VR
echo [L] Legacy 0.49
echo.
choice /C DVL /N /M "Choose the installed game edition / 选择已安装的游戏版本: "
if errorlevel 3 goto selectLegacy
if errorlevel 2 goto selectVR
set "modEdition=DemoDesktop"
goto runInstaller

:selectVR
set "modEdition=DemoVR"
goto runInstaller

:selectLegacy
set "modEdition=Legacy049"

:runInstaller

echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Install-Mod.ps1" -Edition "%modEdition%" -Interactive
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
