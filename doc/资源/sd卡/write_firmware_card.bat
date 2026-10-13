@echo off
rem One-click full-auto: burn final r5 firmware SD image via write_card.ps1 -FirmwareAuto
rem Prereq: SD test card inserted as drive E: (script defaults to E:)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0write_card.ps1\" -FirmwareAuto'"
