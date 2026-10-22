@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem Run this file from an elevated Deployment and Imaging Tools Environment.
rem This version copies the GUI files into the mount directory directly.

set "ROOT=%~dp0"
set "WIM=%ROOT%WinPE_amd64\media\sources\boot.wim"
set "MOUNT=C:\PCHH_MOUNT"
set "ADK=%ProgramFiles(x86)%\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs"
set "SCRIPTING=%ADK%\WinPE-Scripting.cab"
set "SCRIPTING_LANG=%ADK%\en-us\WinPE-Scripting_en-us.cab"
set "HTA=%ADK%\WinPE-HTA.cab"
set "LANG=%ADK%\en-us\WinPE-HTA_en-us.cab"
set "MOUNTED=0"

if not exist "%WIM%" (
  echo ERROR: WinPE boot image not found:
  echo   "%WIM%"
  exit /b 1
)
if not exist "%SCRIPTING%" (
  echo ERROR: WinPE-Scripting.cab not found - install the matching Windows PE add-on.
  exit /b 1
)
if not exist "%SCRIPTING_LANG%" (
  echo ERROR: WinPE-Scripting language package not found.
  exit /b 1
)
if not exist "%HTA%" (
  echo ERROR: WinPE-HTA.cab not found:
  echo   "%HTA%"
  echo Install the matching Windows PE add-on for the ADK.
  exit /b 1
)
if not exist "%LANG%" (
  echo ERROR: WinPE-HTA language package not found:
  echo   "%LANG%"
  exit /b 1
)

if not exist "%MOUNT%" mkdir "%MOUNT%"

echo Mounting WinPE image...
dism /Mount-Image /ImageFile:"%WIM%" /Index:1 /MountDir:"%MOUNT%"
if errorlevel 1 goto :fail
set "MOUNTED=1"

rem HTA renders HTML; WinPE-Scripting supplies JScript and WScript.Shell.
echo Adding WinPE-Scripting...
dism /Image:"%MOUNT%" /Add-Package /PackagePath:"%SCRIPTING%"
if errorlevel 1 goto :fail
dism /Image:"%MOUNT%" /Add-Package /PackagePath:"%SCRIPTING_LANG%"
if errorlevel 1 goto :fail
if not exist "%MOUNT%\Windows\System32\jscript.dll" (
  echo ERROR: JScript engine missing after adding WinPE-Scripting.
  goto :fail
)

echo Adding WinPE-HTA...
dism /Image:"%MOUNT%" /Add-Package /PackagePath:"%HTA%"
if errorlevel 1 goto :fail
dism /Image:"%MOUNT%" /Add-Package /PackagePath:"%LANG%"
if errorlevel 1 goto :fail

echo Verifying mshta.exe was added...
if not exist "%MOUNT%\Windows\System32\mshta.exe" (
  echo ERROR: mshta.exe not found after adding HTA package!
  goto :fail
)
echo   OK: mshta.exe is present

echo Installing PCHH startup files...
echo   Source: %ROOT%winpe\Windows\System32\
echo   Target: %MOUNT%\Windows\System32\

if not exist "%ROOT%winpe\Windows\System32\startnet.cmd" (
  echo ERROR: Source startnet.cmd not found at:
  echo   "%ROOT%winpe\Windows\System32\startnet.cmd"
  goto :fail
)
if not exist "%ROOT%winpe\Windows\System32\pchh-gui.hta" (
  echo ERROR: Source pchh-gui.hta not found at:
  echo   "%ROOT%winpe\Windows\System32\pchh-gui.hta"
  goto :fail
)

copy /y "%ROOT%winpe\Windows\System32\startnet.cmd" "%MOUNT%\Windows\System32\startnet.cmd"
if errorlevel 1 (
  echo ERROR: Failed to copy startnet.cmd
  goto :fail
)
echo   Copied startnet.cmd

copy /y "%ROOT%winpe\Windows\System32\pchh-gui.hta" "%MOUNT%\Windows\System32\pchh-gui.hta"
if errorlevel 1 (
  echo ERROR: Failed to copy pchh-gui.hta
  goto :fail
)
echo   Copied pchh-gui.hta
copy /y "%ROOT%winpe\Windows\System32\pchh-logo.png" "%MOUNT%\Windows\System32\pchh-logo.png" >nul
if errorlevel 1 goto :fail
copy /y "%ROOT%winpe\Windows\System32\winpeshl.ini" "%MOUNT%\Windows\System32\winpeshl.ini" >nul
if errorlevel 1 goto :fail


echo Verifying files in mount...
dir "%MOUNT%\Windows\System32\mshta.exe" "%MOUNT%\Windows\System32\pchh-gui.hta" "%MOUNT%\Windows\System32\startnet.cmd"

echo Saving WinPE image...
dism /Unmount-Image /MountDir:"%MOUNT%" /Commit
if errorlevel 1 goto :fail
set "MOUNTED=0"
echo.
echo SUCCESS: GUI-enabled WinPE image is ready:
echo   "%WIM%"
echo.
echo Next step: On macOS, run these commands:
echo   cp WinPE_amd64/media/sources/boot.wim winpe/sources/boot.wim
echo   docker build --platform linux/amd64 --file build/Dockerfile --target artifact --output type=local,dest=dist .
exit /b 0

:fail
echo.
echo ERROR: WinPE GUI preparation failed.
if "%MOUNTED%"=="1" (
  echo Discarding changes and unmounting...
  dism /Unmount-Image /MountDir:"%MOUNT%" /Discard
)
exit /b 1
