@echo off
:: Sleep Network - one-click installer. Double-click me.
:: Downloads the current installer from the public sleep-network-install repo and runs it.
:: SLEEPNET_PAUSE_ON_ERROR keeps the window open on failure (install.ps1 also pauses).
setlocal
set SLEEPNET_PAUSE_ON_ERROR=1
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/tooltim/sleep-network-install/main/install.ps1'); exit 0 } catch { Write-Host ''; Write-Host '============================================================' -ForegroundColor Red; Write-Host '  FAIL  Sleep Network install did not finish' -ForegroundColor Red; Write-Host '============================================================' -ForegroundColor Red; Write-Host $_; Write-Host ''; Write-Host '  Screenshot this window and send it to Tim.' -ForegroundColor Yellow; try { Write-Host '  Press Enter to close this window...'; [void][Console]::ReadLine() } catch { }; exit 1 }"
set ERR=%ERRORLEVEL%
if not "%ERR%"=="0" (
  echo.
  echo Something did not work. Send a screenshot of this window to Tim.
  pause
  exit /b %ERR%
)
