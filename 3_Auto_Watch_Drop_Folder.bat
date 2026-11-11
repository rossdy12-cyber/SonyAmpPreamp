@echo off
title Stark App Store // Auto-Watch Drop_App_Here Folder
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0_stark_builder.ps1" -Mode watch
pause
