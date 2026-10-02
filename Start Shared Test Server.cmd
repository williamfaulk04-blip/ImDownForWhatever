@echo off
setlocal
cd /d "%~dp0"

if not exist ".tools\cloudflared.exe" (
  echo Cloudflare Tunnel is not installed yet. Installing the signed executable...
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install-cloudflared.ps1"
  if errorlevel 1 goto :error
)

rem Keep port 8000 available for the normal local-development server.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start-quick-tunnel.ps1" -Port 8010
if errorlevel 1 goto :error
exit /b 0

:error
echo.
echo The shared test server could not start. Review the message above.
pause
exit /b 1
