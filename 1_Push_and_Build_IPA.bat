@echo off
title Stark App Store // 1-Click Push & Build IPA on Codemagic M2
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0_stark_builder.ps1" -Mode push
echo.
pause
