@echo off
rem S0 entry: interactive device diagnosis and explicit disk confirmation.
call "%~dp0write_card.bat"
exit /b %ERRORLEVEL%
