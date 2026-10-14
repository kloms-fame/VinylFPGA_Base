@echo off
rem Run this file as Administrator to write the verified S1 image.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0write_card.ps1" -ImagePath "D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA_backups\S1_media_20261014_r2\card_STAGE1.img" -ExpectedSha256 "f407b008e1b9641950fd123c012aceaabe20cd70ae67dfe6d4422614ca8d96f0"
exit /b %ERRORLEVEL%
