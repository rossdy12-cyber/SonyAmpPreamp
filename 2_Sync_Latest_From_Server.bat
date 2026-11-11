@echo off
title Stark App Store // Sync Latest Repo From TrueNAS
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0_stark_builder.ps1" -Mode sync
echo.
pause
