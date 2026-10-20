@echo off
rem Current verified release: four songs, four full-bleed MVs, manual lyrics.
rem Right-click and run as administrator; the script still requires explicit disk confirmation.
call "%~dp0write_card_manual_lyrics.bat"
exit /b %ERRORLEVEL%
