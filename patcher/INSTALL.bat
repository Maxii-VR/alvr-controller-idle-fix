@echo off
REM ALVR idle-hold patch - installer
REM Double-click this file. Windows will ask for permission; click Yes.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Patch-ALVR.ps1" -Mode Install
