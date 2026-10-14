@echo off
rem Run this file as Administrator to write the verified S3 lyrics image.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0write_card.ps1" -ReleaseName "S3" -ImagePath "D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA_backups\S3_lyrics_20261014_r5\card_STAGE3.img" -ExpectedSha256 "f1a17b8a4c303e0aaf7c631baed36fd0b682d2c2ec6ce212641fe654aaadb544"
exit /b %ERRORLEVEL%
