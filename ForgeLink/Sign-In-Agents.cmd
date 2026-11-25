@echo off
setlocal
echo ForgeLink - TrueNAS agent sign-in
echo.
echo 1. Sign in to Claude Code
echo 2. Sign in to Antigravity
echo 3. Check both login states and test Antigravity in plan mode
echo 4. Show the ForgeLink pairing token privately in this terminal
echo 5. Test Claude in plan mode (after sign-in)
echo.
set /p CHOICE=Choose 1, 2, 3, 4 or 5: 
if "%CHOICE%"=="1" ssh -tt truenas "sudo -n docker exec -it -w /workspace/Stark_IPA_Builder forgelink-bridge claude auth login"
if "%CHOICE%"=="2" ssh -tt truenas "sudo -n docker exec -it -w /workspace/Stark_IPA_Builder forgelink-bridge agy"
if "%CHOICE%"=="3" ssh -tt truenas "sudo -n docker exec forgelink-bridge claude auth status & sudo -n docker exec forgelink-bridge agy -p 'Reply only READY' --mode plan --print-timeout 30s"
if "%CHOICE%"=="4" ssh -tt truenas "sudo -n grep '^FORGELINK_TOKEN=' /mnt/storage_pool/apps/forgelink/.env"
if "%CHOICE%"=="5" ssh -tt truenas "sudo -n docker exec -it -w /workspace/Stark_IPA_Builder forgelink-bridge claude -p 'Reply only READY' --output-format text --permission-mode plan"
echo.
echo Bridge address in ForgeLink: http://100.64.0.4:8789
echo Your iPhone must be connected to your private Tailscale network.
echo Keep login codes and pairing tokens in this terminal, not in chat. Close Antigravity after login with Ctrl+C.
pause
