@echo off
setlocal
cd /d "%~dp0"
if not exist "Godot.exe" (
  echo Missing Godot.exe
  pause
  exit /b 1
)
if not exist "game\project.godot" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update.ps1" -InstallRoot "%~dp0."
  if errorlevel 1 pause
  exit /b
)
if not exist "game\.godot\" (
  start "Godot import" /wait "%~dp0Godot.exe" --headless --path "%~dp0game" --editor --import
  if errorlevel 1 (
    echo Godot import failed.
    pause
    exit /b 1
  )
)
start "1NFINITY D&D" "%~dp0Godot.exe" --path "%~dp0game"
