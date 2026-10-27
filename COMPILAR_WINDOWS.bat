@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0COMPILAR_WINDOWS.ps1"
pause
