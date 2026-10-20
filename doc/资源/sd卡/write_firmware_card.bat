@echo off
chcp 65001 >nul
echo 此脚本不会写 SD 卡，也不会给 FPGA 烧录固件。
echo 请使用 Anlogic TD 连接下载器，通过 JTAG/SRAM 下载以下匹配固件：
echo.
echo %~dp0release_20261020_manual_lyrics_4songs_4mvs_fullbleed\VinylFPGA_4songs_4mvs_manual_lyrics_fullbleed_20261020.bit
echo SHA-256: 26baebd9fcf9a051bd91b204fda325e40bf92f29985a21afce10a454ec3fe82e
echo.
echo SD 卡镜像请运行 write_card_manual_lyrics.bat；两者是独立操作。
pause
exit /b 0
