@echo off
REM ALVR idle-hold patch - uninstaller (restores your original driver)
REM Double-click this file. Windows will ask for permission; click Yes.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Patch-ALVR.ps1" -Mode Uninstall
