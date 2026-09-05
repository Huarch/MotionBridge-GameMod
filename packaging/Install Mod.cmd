@echo off
setlocal
title MotionBridge Fallen Doll Demo Mod Installer

echo MotionBridge Fallen Doll Demo / Legacy 0.49 Mod Installer
echo.
echo [D] Demo Desktop
echo [V] Demo VR
echo [L] Legacy 0.49
echo.
choice /C DVL /N /M "Choose the installed game edition: "
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
) else (
    echo Installation finished. You may close this window.
)
echo.
pause
exit /b %installerExitCode%
