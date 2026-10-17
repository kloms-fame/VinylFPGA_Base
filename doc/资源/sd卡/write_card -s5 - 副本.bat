@echo off
chcp 65001 >nul
rem Run this file as Administrator to write the verified VISUAL_S3 r4 image.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0write_card.ps1" -ReleaseName "VISUAL_S3_r4" -ImagePath "D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA_backups\visual_resources_20261015_r4\card_VISUAL_S3.img" -ExpectedSha256 "eca36eac55736ef8b6ac4edfe6d1daa3eaaea98bbbc9883c393a51054d4a214b"
exit /b %ERRORLEVEL%
