@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem Run this file from an elevated Deployment and Imaging Tools Environment.
set "ROOT=%~dp0"
set "WIM=%ROOT%WinPE_amd64\media\sources\boot.wim"
set "MOUNT=%ROOT%WinPE_amd64\mount"
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

rem BitLocker status/unlock needs SecureStartup and its WMI dependency.
for %%p in (WinPE-WMI WinPE-SecureStartup) do (
  if not exist "%ADK%\%%p.cab" (
    echo ERROR: %%p.cab missing - install the matching Windows PE add-on.
    exit /b 1
  )
  if not exist "%ADK%\en-us\%%p_en-us.cab" (
    echo ERROR: %%p language package missing.
    exit /b 1
  )
)

if not exist "%MOUNT%" mkdir "%MOUNT%"

echo Mounting WinPE image...
dism /Mount-Image /ImageFile:"%WIM%" /Index:1 /MountDir:"%MOUNT%"
if errorlevel 1 goto :fail
set "MOUNTED=1"

echo Adding BitLocker support...
for %%p in (WinPE-WMI WinPE-SecureStartup) do (
  dism /Image:"%MOUNT%" /Add-Package /PackagePath:"%ADK%\%%p.cab"
  if errorlevel 1 goto :fail
  dism /Image:"%MOUNT%" /Add-Package /PackagePath:"%ADK%\en-us\%%p_en-us.cab"
  if errorlevel 1 goto :fail
)
if not exist "%MOUNT%\Windows\System32\manage-bde.exe" (
  echo ERROR: BitLocker tool missing after adding WinPE-SecureStartup.
  goto :fail
)

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

echo Installing PCHH startup files...
copy /y "%ROOT%winpe\Windows\System32\startnet.cmd" "%MOUNT%\Windows\System32\startnet.cmd" >nul
if errorlevel 1 goto :fail
copy /y "%ROOT%winpe\Windows\System32\pchh-gui.hta" "%MOUNT%\Windows\System32\pchh-gui.hta" >nul
if errorlevel 1 goto :fail
copy /y "%ROOT%winpe\Windows\System32\pchh-logo.png" "%MOUNT%\Windows\System32\pchh-logo.png" >nul
if errorlevel 1 goto :fail
copy /y "%ROOT%winpe\Windows\System32\winpeshl.ini" "%MOUNT%\Windows\System32\winpeshl.ini" >nul
if errorlevel 1 goto :fail

echo Saving WinPE image...
dism /Unmount-Image /MountDir:"%MOUNT%" /Commit
if errorlevel 1 goto :fail
set "MOUNTED=0"
echo.
echo GUI-enabled WinPE image is ready:
echo   "%WIM%"
echo Rebuild the PCHH ISO or USB image after this completes.
exit /b 0

:fail
echo.
echo ERROR: WinPE GUI preparation failed.
if "%MOUNTED%"=="1" dism /Unmount-Image /MountDir:"%MOUNT%" /Discard
exit /b 1
