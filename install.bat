@echo off
chcp 65001 >nul
echo Installing iTaiwan auto-agree...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
echo.
echo ------------------------------------------
echo If you see red error text above, take a screenshot and send it to Claude.
echo.
pause
