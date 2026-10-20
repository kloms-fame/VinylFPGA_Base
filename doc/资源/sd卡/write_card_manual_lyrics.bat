@echo off
setlocal
chcp 65001 >nul

rem Current release: four independent songs, full-length full-bleed MVs, calibrated lyrics.
rem Uses the verified 320x240 RGB565/10fps visual policy from build_visual_assets.py.
rem This wrapper reuses write_card.ps1 and its disk identity and full read-back checks.
set "IMAGE=%~dp0release_20261020_manual_lyrics_4songs_4mvs_fullbleed\VinylFPGA_SD_4SONGS_4MVS_MANUAL_LYRICS_FULLBLEED_20261020.img"
set "SHA256=3bf36c259d093b9f85fd538892e11c74275b1e68111ed366b8c77e58cd654654"

if not exist "%IMAGE%" (
    echo Missing card image:
    echo   %IMAGE%
    echo Keep the generated image in the release folder shown above.
    pause
    exit /b 2
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0write_card.ps1" -ReleaseName "S3_FULLBLEED_LYR" -ImagePath "%IMAGE%" -ExpectedSha256 "%SHA256%"
exit /b %ERRORLEVEL%
