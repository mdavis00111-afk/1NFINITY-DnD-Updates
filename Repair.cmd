@echo off
setlocal
cd /d "%~dp0"
echo Close all running 1NFINITY windows before continuing.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update.ps1" -InstallRoot "%~dp0." -Repair
if errorlevel 1 pause
