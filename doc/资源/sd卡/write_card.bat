@echo off
rem 双击我即可：自动弹 UAC 提权，调用同目录 write_card.ps1
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0write_card.ps1\"'"
