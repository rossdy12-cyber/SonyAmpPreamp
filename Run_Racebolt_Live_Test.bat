@echo off
title Racebolt // Live site test Codemagic M2 build
if not exist "%~dp0_stark_builder.ps1" (
  echo Place this file beside your existing _stark_builder.ps1.
  pause
  exit /b 1
)
REM Existing Jarvis/Nightfall guards recognize this legacy test prefix.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0_stark_builder.ps1" -Mode push -CommitMessage "CarbPrep signing-only test: Racebolt live site safety fix build 3"
set "BUILD_EXIT=%ERRORLEVEL%"
echo.
echo Open RaceboltTest iOS Unsigned IPA in Codemagic to download build 3.
echo This builds and exports only. NAS signing and store upload are separate.
echo A successful push alone is not proof that the build completed.
pause
exit /b %BUILD_EXIT%