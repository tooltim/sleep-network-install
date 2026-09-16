@echo off
:: Sleep Network - one-click installer. Double-click me.
:: Downloads the current installer from the public sleep-network-install repo and runs it.
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/tooltim/sleep-network-install/main/install.ps1 | iex"
if errorlevel 1 (
  echo.
  echo Something did not work. Send a screenshot of this window to Tim.
  pause
)
