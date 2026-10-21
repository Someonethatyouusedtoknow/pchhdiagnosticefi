@echo off
:: PCHH USB Flasher Launcher
:: Right-click and select "Run as Administrator"

NET SESSION >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo  This tool requires administrator privileges.
    echo  Please right-click and select "Run as Administrator"
    echo.
    pause
    exit /b 1
)

cd /d "%~dp0"
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0PCHHFlasher.ps1'"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo  PowerShell script failed with error code %ERRORLEVEL%
    echo.
    pause
)
exit /b %ERRORLEVEL%
