@echo off
setlocal
cd /d "%~dp0"
set "GAME=%~dp0game"
if exist "%~dp0active-game.txt" for /f "usebackq delims=" %%G in ("%~dp0active-game.txt") do if exist "%~dp0%%G\project.godot" set "GAME=%~dp0%%G"
"%~dp0Godot.exe" --path "%GAME%" --headless --editor --import --log-file "%~dp0test-import.log"
if errorlevel 1 goto failed
"%~dp0Godot.exe" --path "%GAME%" --headless --script res://tests/sqlite_smoke.gd --log-file "%~dp0test-sqlite.log"
if errorlevel 1 goto failed
"%~dp0Godot.exe" --path "%GAME%" --headless --script res://tests/character_smoke.gd --log-file "%~dp0test-characters.log"
if errorlevel 1 goto failed
"%~dp0Godot.exe" --path "%GAME%" --headless --script res://tests/layout_smoke.gd --log-file "%~dp0test-layout.log"
if errorlevel 1 goto failed
echo All smoke tests passed.
pause
exit /b 0
:failed
echo Test failed. See test-*.log files beside this launcher.
pause
exit /b 1
