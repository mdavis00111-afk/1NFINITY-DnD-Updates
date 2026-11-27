@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update.ps1" -InstallRoot "%~dp0." -LaunchOnly
if errorlevel 1 pause
