@echo off
rem S0 baseline writer: right-click Run as administrator for physical writing.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0write_card.ps1"
exit /b %ERRORLEVEL%
