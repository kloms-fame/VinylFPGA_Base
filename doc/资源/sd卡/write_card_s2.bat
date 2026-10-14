@echo off
rem Run this file as Administrator to write the verified S2 full-MV image.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0write_card.ps1" -ReleaseName "S2" -ImagePath "D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA_backups\S2_mv_20261014\card_STAGE2.img" -ExpectedSha256 "5061694a17e27063cd157d90944792eabc17973b99abec1fce9c1ebd81084948"
exit /b %ERRORLEVEL%
