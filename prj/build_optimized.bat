@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\tools\build_optimized_project.ps1"
set "VINYL_BUILD_EXIT=%ERRORLEVEL%"
pause
exit /b %VINYL_BUILD_EXIT%
