@echo off
title CarbPrep // Test-only Codemagic M2 IPA build
if not exist "%~dp0_stark_builder.ps1" (
  echo Place this file beside your existing _stark_builder.ps1.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0_stark_builder.ps1" -Mode push -CommitMessage "CarbPrep signing-only test: desktop native unsigned build"
set "BUILD_EXIT=%ERRORLEVEL%"
echo.
echo The push is not proof of a completed build. Check Codemagic for the unsigned IPA artifact.
pause
exit /b %BUILD_EXIT%