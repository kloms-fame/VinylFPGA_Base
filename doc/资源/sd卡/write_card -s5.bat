@echo off
chcp 65001 >nul
rem Run this file as Administrator to write the verified VISUAL_S3 image.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0write_card.ps1" -ReleaseName "VISUAL_S3_r2" -ImagePath "D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA_backups\visual_resources_20261015_r2\card_VISUAL_S3.img" -ExpectedSha256 "75719aed3726bf2a263a4dfc34f6a08a10e0f46c78ef4b05a333687ac5a874f1"
exit /b %ERRORLEVEL%
