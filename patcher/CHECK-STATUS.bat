@echo off
REM ALVR idle-hold patch - shows whether the patch is currently installed.
REM Read-only: this never changes anything. No admin needed.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Patch-ALVR.ps1" -Mode Status
