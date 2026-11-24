@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Compatibility.ps1" -Interactive
if errorlevel 1 echo Installation failed. Please keep this window for the error message.
pause
