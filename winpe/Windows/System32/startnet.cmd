@echo off
REM ===========================================================================
REM  PCHH - Windows PE Advanced Repair Environment
REM  Auto-launched by winpeshl -> cmd -> startnet.cmd on every PE boot.
REM
REM  Built for Windows PE amd64 build 26100 (Win11 24H2). Uses ONLY tools
REM  confirmed present in this PE image. Deliberately avoids: bootrec, wmic,
REM  systeminfo, powershell, timeout, choice, tasklist/taskkill, shutdown.
REM  GUI jobs stream output and exchange prompts through per-job files.
REM ===========================================================================

setlocal enabledelayedexpansion
if /i "%~1"=="/gui" goto GUI_DISPATCH
REM Tool windows keep their own interactive stdin and reuse initialized PE.
if /i "%~1"=="/tool" (
    set "choice=%~2"
    set "WINPART="
    call :DETECT_WINDOWS
    goto MENU_DISPATCH
)
title PCHH Windows PE - Advanced Repair Environment
color 0B
mode con: cols=100 lines=48

REM --- Initialize PE -----------------------------------------------------------
echo.
echo   Initializing Windows PE environment, please wait...
wpeinit >nul 2>&1
REM Bring up networking in the background so the menu is not blocked.
start "" /min wpeutil InitializeNetwork >nul 2>&1

REM --- Bring storage up and detect Windows ------------------------------------
set "WINPART="
set "ESPVOL="
call :STORAGE_INIT
call :DETECT_WINDOWS

REM Check for PCHH_GUI_CHILD flag - if set, we are being called FROM the GUI
REM to run a specific menu item, not launching the GUI itself.
if defined PCHH_GUI_CHILD (
    REM The GUI sent us a menu key via stdin - read and execute it
    call :PCHH_READ choice ""
    goto MENU_DISPATCH
)

REM GUI ONLY - no text fallback
echo.
echo   Checking for GUI support...
if not exist %SystemRoot%\System32\mshta.exe (
    echo   ERROR: mshta.exe not found - HTA support missing
    echo   The WinPE image was not prepared with prepare-winpe-gui.cmd
    call :PCHH_PAUSE
    exit /b 1
)
if not exist %SystemRoot%\System32\pchh-gui.hta (
    echo   ERROR: pchh-gui.hta not found
    call :PCHH_PAUSE
    exit /b 1
)
REM HTA alone can render the splash without executing any JavaScript.
if not exist %SystemRoot%\System32\jscript.dll goto GUI_SCRIPTING_MISSING
reg query HKCR\JScript\CLSID >nul 2>&1
if errorlevel 1 goto GUI_SCRIPTING_MISSING
reg query HKCR\WScript.Shell\CLSID >nul 2>&1
if errorlevel 1 goto GUI_SCRIPTING_MISSING
echo   Starting PCHH GUI...
set "PCHH_INITIALIZED=1"
start "PCHH Recovery" /max %SystemRoot%\System32\mshta.exe %SystemRoot%\System32\pchh-gui.hta
exit /b

:GUI_SCRIPTING_MISSING
echo.
echo   ERROR: WinPE-Scripting is missing or not registered.
echo   The recovery GUI requires both WinPE-Scripting and WinPE-HTA.
echo   Run prepare-winpe-gui.cmd on Windows using the matching ADK,
echo   copy the prepared boot.wim to winpe\sources\boot.wim, and rebuild.
call :PCHH_PAUSE
exit /b 1

:MAINMENU
if defined PCHH_JOB exit /b 0
REM Closing a tool returns the user to the recovery GUI underneath it.
exit /b

:MENU_DISPATCH
if defined PCHH_JOB exit /b 0
REM Dispatcher for GUI menu keys
if "!choice!"=="0" goto MENU_STORAGE
if /i "!choice!"=="A" goto MENU_DISK
if /i "!choice!"=="B" goto MENU_BOOT
if /i "!choice!"=="C" goto MENU_SFC
if /i "!choice!"=="D" goto MENU_REG
if /i "!choice!"=="E" goto MENU_DRV
if /i "!choice!"=="F" goto MENU_DATA
if /i "!choice!"=="G" goto MENU_NET
if /i "!choice!"=="H" goto MENU_DIAG
if /i "!choice!"=="I" goto MENU_UTIL
if /i "!choice!"=="J" goto MENU_BOOTMODE
if /i "!choice!"=="X" goto DO_EXIT
if /i "!choice!"=="R" goto DO_REBOOT
if /i "!choice!"=="S" goto DO_SHUTDOWN
exit /b

REM =============================================================================
REM  Helpers
REM =============================================================================
:DELAY
REM %1 = seconds
ping -n %~1 127.0.0.1 >nul 2>&1
goto :eof

:DETECT_WINDOWS
set "WINPART="
call :BITLOCKER_STATUS
for %%d in (A B C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist %%d:\Windows\System32\ntoskrnl.exe (
        if not defined WINPART set "WINPART=%%d:"
    )
)
goto :eof

:BITLOCKER_STATUS
echo.
echo   --- BitLocker volume status ---
if not exist "%SystemRoot%\System32\manage-bde.exe" (
    echo   [WARN] BitLocker detection is unavailable in this Windows PE image.
    echo   Add WinPE-WMI and WinPE-SecureStartup with prepare-winpe-gui.cmd.
    echo   An undetected Windows volume may still be BitLocker-locked.
    goto :eof
)
REM Use native output instead of parsing localized status strings. This lists
REM encryption and lock status even when Windows files cannot be read.
manage-bde -status
if errorlevel 1 (
    echo   [WARN] BitLocker status could not be read; this does not mean no encryption.
    echo   Check storage drivers, volume letters and WinPE BitLocker support.
)
echo.
echo   A locked volume cannot be searched for Windows until it is unlocked.
echo   In Utilities - Run commands, use your volume letter and recovery key:
echo     manage-bde -unlock D: -RecoveryPassword YOUR-48-DIGIT-RECOVERY-KEY
echo   Then run Storage Setup - Rescan disks and detect Windows again.
echo   Unlocking requires your key; it does not disable BitLocker encryption.
goto :eof

:STOR_BITLOCKER
call :BITLOCKER_STATUS
call :PCHH_PAUSE
goto MENU_STORAGE

:STORAGE_INIT
REM Drivers in the RAM image remain accessible even when the USB data volume is not.
echo   Initializing storage services and devices...
net start vds
if exist "%SystemRoot%\System32\pnputil.exe" pnputil /scan-devices
call :STOR_RESCAN
if exist "%SystemDrive%\PCHH\Drivers\" call :STOR_LOAD_FOLDER "%SystemDrive%\PCHH\Drivers"
for %%d in (A B C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist "%%d:\drivers\" call :STOR_LOAD_FOLDER "%%d:\drivers"
)
if exist "%SystemRoot%\System32\pnputil.exe" pnputil /scan-devices
call :STOR_RESCAN
echo.
echo   Physical disks and volumes after driver loading:
diskpart /s "%TEMP%\pchh-list.txt"
echo   If a physical disk is absent, inspect controller devices below and load its matching driver.
pnputil /enum-devices /connected /class SCSIAdapter
pnputil /enum-devices /problem
echo   Driver installation details: %SystemRoot%\inf\setupapi.dev.log
goto :eof

:STOR_LOAD_FOLDER
echo   Loading storage drivers from %~1
for /r "%~1" %%i in (*.inf) do (
    echo   Driver: %%i
    drvload "%%i"
)
goto :eof

:STOR_RESCAN
REM SELECT does not accept NOERR. Selecting nonexistent volume numbers aborts scripts.
REM Enumerate existing volumes first, then assign only those actual volume numbers.
> "%TEMP%\pchh-rescan.txt" (
    echo san policy=OnlineAll
    echo automount enable
    echo rescan
    echo list disk
    echo list volume
    echo exit
)
mountvol /e
diskpart /s "%TEMP%\pchh-rescan.txt"
> "%TEMP%\pchh-list.txt" (
    echo list disk
    echo list volume
    echo exit
)
diskpart /s "%TEMP%\pchh-list.txt" > "%TEMP%\pchh-volumes.txt" 2>&1
> "%TEMP%\pchh-assign.txt" (
    for /f "tokens=2" %%v in ('findstr /r /c:"^[ ]*Volume [0-9]" "%TEMP%\pchh-volumes.txt"') do (
        echo select volume %%v
        echo assign noerr
    )
    echo exit
)
diskpart /s "%TEMP%\pchh-assign.txt"
goto :eof

:NEEDWIN
REM Ensure WINPART is set, prompt if not. Returns with WINPART defined or empty.
if defined WINPART goto :eof
echo.
echo   No Windows installation was auto-detected.
call :BITLOCKER_STATUS
echo   If the Windows volume is locked, unlock it and rescan before repairing.
call :PCHH_READ WINPART "  Enter the Windows drive letter (e.g. C:) or leave blank to cancel: "
goto :eof

:LOCATE_BCD
REM Find the installed Windows boot store (ESP \EFI\... for UEFI, \Boot\ for BIOS).
REM Sets BCDSTORE to the full path, or leaves it empty / prompts.
set "BCDSTORE="
for %%d in (A B C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if not defined BCDSTORE if exist %%d:\EFI\Microsoft\Boot\BCD set "BCDSTORE=%%d:\EFI\Microsoft\Boot\BCD"
)
if not defined BCDSTORE for %%d in (A B C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if not defined BCDSTORE if exist %%d:\Boot\BCD set "BCDSTORE=%%d:\Boot\BCD"
)
if defined BCDSTORE (
    echo   Using boot store: !BCDSTORE!
    goto :eof
)
echo.
echo   Could not auto-locate a boot store. On UEFI the BCD lives on the EFI
echo   System Partition, which usually has no drive letter -- assign one first
echo   via the Boot Repair menu ^(Recreate ESP assigns S:^) or Disk - Assign.
call :PCHH_READ BCDSTORE "  Full path to the BCD file (blank to cancel): "
goto :eof

REM =============================================================================
REM  MAIN MENU
REM =============================================================================
:MAINMENU
if defined PCHH_JOB exit /b 0
if not defined PCHH_JOB cls
echo  ==========================================================================
echo    PCHH - Professional Computer Hardware Helper
echo    Windows PE Advanced Repair Environment        [Win11 24H2 / build 26100]
echo  ==========================================================================
if defined WINPART (
    echo    Detected Windows: !WINPART!\Windows
) else (
    echo    Detected Windows: NONE - run [0] Storage Setup if a disk is installed
)
echo  --------------------------------------------------------------------------
echo.
echo    [0]  Storage Setup / Detect Disks   ^(run first if disks are missing^)
echo.
echo    [A]  Disk ^& Partition Management
echo    [B]  Boot Repair  ^(UEFI ^& Legacy BIOS^)
echo    [C]  System File ^& Image Repair  ^(SFC / DISM / ChkDsk^)
echo    [D]  Registry ^& User Accounts
echo    [E]  Driver Management
echo    [F]  Data Recovery, Copy ^& Permissions
echo    [G]  Network Tools
echo    [H]  Diagnostics ^& System Info
echo    [I]  Utilities  ^(CMD / Notepad / Task Manager^)
echo    [J]  Startup Settings ^& Recovery Environment  ^(Safe Mode / WinRE^)
echo.
echo    [R]  Reboot        [S]  Shut Down        [X]  Exit to Command Prompt
echo.
echo  ==========================================================================
set "choice="
call :PCHH_READ choice "  Select a category: "
if "!choice!"=="0" goto MENU_STORAGE
if /i "!choice!"=="A" goto MENU_DISK
if /i "!choice!"=="B" goto MENU_BOOT
if /i "!choice!"=="C" goto MENU_SFC
if /i "!choice!"=="D" goto MENU_REG
if /i "!choice!"=="E" goto MENU_DRV
if /i "!choice!"=="F" goto MENU_DATA
if /i "!choice!"=="G" goto MENU_NET
if /i "!choice!"=="H" goto MENU_DIAG
if /i "!choice!"=="I" goto MENU_UTIL
if /i "!choice!"=="J" goto MENU_BOOTMODE
if /i "!choice!"=="R" goto DO_REBOOT
if /i "!choice!"=="S" goto DO_SHUTDOWN
if /i "!choice!"=="X" goto DO_EXIT
goto MAINMENU

REM =============================================================================
REM  A. DISK & PARTITION
REM =============================================================================
:MENU_DISK
if defined PCHH_JOB exit /b 0
if not defined PCHH_JOB cls
echo  ===================  DISK ^& PARTITION MANAGEMENT  ========================
echo.
echo    [1]  DiskPart ^(interactive^)
echo    [2]  List all disks ^& volumes  ^(quick^)
echo    [3]  Assign a drive letter
echo    [4]  Remove a drive letter
echo    [5]  Format a volume
echo    [6]  Clean ^& repartition a disk  ^(guided - DESTRUCTIVE^)
echo    [7]  Check disk for errors  ^(ChkDsk^)
echo    [8]  Volume info / dirty bit  ^(FSUtil^)
echo    [9]  DiskRaid ^(advanced RAID/virtual disk^)
echo.
echo    [0]  Back to main menu
echo  --------------------------------------------------------------------------
set "d="
call :PCHH_READ d "  Select: "
if "!d!"=="1" ( cls & echo Type 'list disk', 'list volume', 'exit' to return.& echo. & diskpart & goto MENU_DISK )
if "!d!"=="2" goto DISK_LIST
if "!d!"=="3" goto DISK_ASSIGN
if "!d!"=="4" goto DISK_REMOVE
if "!d!"=="5" goto DISK_FORMAT
if "!d!"=="6" goto DISK_CLEAN
if "!d!"=="7" goto DISK_CHKDSK
if "!d!"=="8" goto DISK_FSUTIL
if "!d!"=="9" ( cls & diskraid & goto MENU_DISK )
if "!d!"=="0" goto MAINMENU
goto MENU_DISK

:DISK_LIST
if not defined PCHH_JOB cls
echo  ===== DISKS =====
(echo list disk) | diskpart
echo.
echo  ===== VOLUMES =====
(echo list volume) | diskpart
echo.
call :PCHH_PAUSE
goto MENU_DISK

:DISK_ASSIGN
if not defined PCHH_JOB cls
(echo list volume) | diskpart
echo.
call :PCHH_READ v "  Volume number to assign: "
call :PCHH_READ l "  Drive letter to assign (e.g. E): "
(echo select volume !v! ^& echo assign letter=!l! ^& echo exit) | diskpart
echo.
call :PCHH_PAUSE
goto MENU_DISK

:DISK_REMOVE
if not defined PCHH_JOB cls
(echo list volume) | diskpart
echo.
call :PCHH_READ v "  Volume number: "
call :PCHH_READ l "  Drive letter to remove (e.g. E): "
(echo select volume !v! ^& echo remove letter=!l! ^& echo exit) | diskpart
echo.
call :PCHH_PAUSE
goto MENU_DISK

:DISK_FORMAT
if not defined PCHH_JOB cls
(echo list volume) | diskpart
echo.
call :PCHH_READ v "  Volume number to FORMAT (blank to cancel): "
if "!v!"=="" goto MENU_DISK
call :PCHH_READ fs "  Filesystem [NTFS/FAT32/exFAT] (default NTFS): "
if "!fs!"=="" set "fs=NTFS"
call :PCHH_READ lbl "  Volume label (optional): "
echo.
echo   WARNING: This ERASES ALL DATA on volume !v!.
call :PCHH_READ ok "  Type YES to confirm: "
if /i not "!ok!"=="YES" goto MENU_DISK
(echo select volume !v! ^& echo format fs=!fs! label="!lbl!" quick ^& echo exit) | diskpart
echo.
call :PCHH_PAUSE
goto MENU_DISK

:DISK_CLEAN
if not defined PCHH_JOB cls
echo  GUIDED CLEAN + REPARTITION  (DESTROYS the selected disk)
echo.
(echo list disk) | diskpart
echo.
call :PCHH_READ dk "  Disk number to wipe (blank to cancel): "
if "!dk!"=="" goto MENU_DISK
echo.
echo   Choose new layout:
echo     [1] GPT  (UEFI)  - creates 100MB EFI + MSR + Windows NTFS
echo     [2] MBR  (Legacy BIOS) - single active NTFS partition
call :PCHH_READ ly "  Layout: "
echo.
echo   WARNING: ALL DATA on disk !dk! will be destroyed.
call :PCHH_READ ok "  Type ERASE to confirm: "
if /i not "!ok!"=="ERASE" goto MENU_DISK
if "!ly!"=="1" (
    (echo select disk !dk! ^& echo clean ^& echo convert gpt ^& echo create partition efi size=100 ^& echo format fs=fat32 quick label=SYSTEM ^& echo assign letter=S ^& echo create partition msr size=16 ^& echo create partition primary ^& echo format fs=ntfs quick label=Windows ^& echo assign letter=W ^& echo exit) | diskpart
    echo.
    echo   Created ESP=S:  Windows=W:  -- use Boot Repair next to install a bootloader.
) else (
    (echo select disk !dk! ^& echo clean ^& echo convert mbr ^& echo create partition primary ^& echo format fs=ntfs quick label=Windows ^& echo assign letter=W ^& echo active ^& echo exit) | diskpart
    echo.
    echo   Created active Windows=W:  -- use Boot Repair next to install a bootloader.
)
echo.
call :PCHH_PAUSE
goto MENU_DISK

:DISK_CHKDSK
if not defined PCHH_JOB cls
(echo list volume) | diskpart
echo.
call :PCHH_READ l "  Drive letter to check (e.g. C): "
echo.
echo    [1] Read-only scan        [2] Fix errors (/F)
echo    [3] Fix + recover sectors (/F /R)     [4] Force dismount (/F /X)
call :PCHH_READ m "  Mode: "
echo.
if "!m!"=="1" chkdsk !l!:
if "!m!"=="2" chkdsk !l!: /F
if "!m!"=="3" chkdsk !l!: /F /R
if "!m!"=="4" chkdsk !l!: /F /X
echo.
call :PCHH_PAUSE
goto MENU_DISK

:DISK_FSUTIL
if not defined PCHH_JOB cls
call :PCHH_READ l "  Drive letter (e.g. C): "
echo.
echo  --- Volume information ---
fsutil fsinfo volumeinfo !l!:
echo.
echo  --- Dirty bit ---
fsutil dirty query !l!:
echo.
call :PCHH_PAUSE
goto MENU_DISK

REM =============================================================================
REM  B. BOOT REPAIR
REM =============================================================================
:MENU_BOOT
if defined PCHH_JOB exit /b 0
if not defined PCHH_JOB cls
echo  =========================  BOOT REPAIR  ==================================
echo.
echo    [1]  AUTO repair boot  ^(detect Windows + rebuild - recommended^)
echo    [2]  Rebuild UEFI boot files to an EFI partition  ^(bcdboot /f UEFI^)
echo    [3]  Rebuild Legacy BIOS boot  ^(bootsect + bcdboot /f BIOS^)
echo    [4]  Recreate / repair the EFI System Partition  ^(guided^)
echo    [5]  View / edit BCD store  ^(bcdedit^)
echo    [6]  Write boot code to volume  ^(bootsect /nt60^)
echo.
echo    [0]  Back to main menu
echo  --------------------------------------------------------------------------
set "b="
call :PCHH_READ b "  Select: "
if "!b!"=="1" goto BOOT_AUTO
if "!b!"=="2" goto BOOT_UEFI
if "!b!"=="3" goto BOOT_BIOS
if "!b!"=="4" goto BOOT_ESP
if "!b!"=="5" goto BOOT_BCDEDIT
if "!b!"=="6" goto BOOT_SECT
if "!b!"=="0" goto MAINMENU
goto MENU_BOOT

:BOOT_AUTO
if not defined PCHH_JOB cls
echo  AUTOMATIC BOOT REPAIR
echo.
call :DETECT_WINDOWS
call :NEEDWIN
if not defined WINPART goto MENU_BOOT
echo   Using Windows at: !WINPART!\Windows
echo.
echo   Looking for an EFI System Partition...
set "ESP="
(echo list volume) | diskpart | find /i "FAT32 System"
echo.
call :PCHH_READ ESP "  Enter the drive letter of the EFI/System partition, or blank for Legacy BIOS: "
echo.
if defined ESP (
    echo   Writing UEFI boot files to !ESP! ...
    bcdboot !WINPART!\Windows /s !ESP! /f UEFI
) else (
    echo   Writing Legacy BIOS boot files...
    for %%d in (!WINPART!) do bootsect /nt60 %%d /force /mbr
    bcdboot !WINPART!\Windows /s !WINPART! /f BIOS
)
echo.
echo   Done. If Windows still will not start, try option [4] to recreate the ESP.
echo.
call :PCHH_PAUSE
goto MENU_BOOT

:BOOT_UEFI
if not defined PCHH_JOB cls
call :NEEDWIN
if not defined WINPART goto MENU_BOOT
echo.
echo   The EFI partition is usually ~100MB FAT32. Assign it a letter first
echo   (Disk menu - Assign) if it has none.
call :PCHH_READ ESP "  EFI/System partition drive letter (e.g. S): "
echo.
bcdboot !WINPART!\Windows /s !ESP!: /f UEFI
echo.
call :PCHH_PAUSE
goto MENU_BOOT

:BOOT_BIOS
if not defined PCHH_JOB cls
call :NEEDWIN
if not defined WINPART goto MENU_BOOT
echo.
echo   Writing NT60 boot code and BIOS BCD to !WINPART! ...
bootsect /nt60 !WINPART! /force /mbr
bcdboot !WINPART!\Windows /s !WINPART! /f BIOS
echo.
call :PCHH_PAUSE
goto MENU_BOOT

:BOOT_ESP
if not defined PCHH_JOB cls
echo  RECREATE / REPAIR EFI SYSTEM PARTITION
echo.
echo   This assigns letter S: to an existing EFI partition and reformats it,
echo   then reinstalls the UEFI bootloader. Your Windows partition is NOT touched.
echo.
(echo list volume) | diskpart
echo.
call :PCHH_READ ev "  Volume number of the EFI System Partition (blank to cancel): "
if "!ev!"=="" goto MENU_BOOT
call :NEEDWIN
if not defined WINPART goto MENU_BOOT
echo.
echo   WARNING: the EFI partition will be reformatted (FAT32).
call :PCHH_READ ok "  Type YES to confirm: "
if /i not "!ok!"=="YES" goto MENU_BOOT
(echo select volume !ev! ^& echo assign letter=S ^& echo format fs=fat32 quick ^& echo exit) | diskpart
bcdboot !WINPART!\Windows /s S: /f UEFI
echo.
echo   EFI partition rebuilt.
echo.
call :PCHH_PAUSE
goto MENU_BOOT

:BOOT_BCDEDIT
if not defined PCHH_JOB cls
echo  Current system BCD (if any):
bcdedit /enum >nul 2>&1 && bcdedit /enum
echo.
echo   You are now at a prompt. Examples:
echo     bcdedit /store S:\EFI\Microsoft\Boot\BCD /enum
echo     bcdedit /store ^<path^> /set {default} recoveryenabled No
echo   Type 'exit' to return.
echo.
cmd /k
goto MENU_BOOT

:BOOT_SECT
if not defined PCHH_JOB cls
echo   NT60 writes BOOTMGR-compatible boot code for Windows Vista and later.
echo   For UEFI boot files, use Rebuild UEFI boot files instead.
call :PCHH_READ l "  Target volume (e.g. C or C:, SYS, ALL; blank to cancel): "
if not defined l goto MENU_BOOT
call :NORMALIZE_BOOT_TARGET
if not defined BOOT_TARGET (
    echo   Invalid target. Enter a drive letter, SYS, or ALL.
    goto MENU_BOOT
)
bootsect /nt60 !BOOT_TARGET! /force
echo.
call :PCHH_PAUSE
goto MENU_BOOT

REM =============================================================================
REM  C. SYSTEM FILE & IMAGE REPAIR
REM =============================================================================
:MENU_SFC
if defined PCHH_JOB exit /b 0
if not defined PCHH_JOB cls
echo  ==============  SYSTEM FILE ^& IMAGE REPAIR  ==============================
echo.
echo    [1]  SFC - System File Checker  ^(offline scan ^& repair^)
echo    [2]  DISM - Check image health
echo    [3]  DISM - Scan image health
echo    [4]  DISM - Restore health  ^(online / Windows Update^)
echo    [5]  DISM - Restore health from a source WIM/ESD
echo    [6]  DISM - List installed packages
echo    [7]  ChkDsk the Windows volume
echo.
echo    [0]  Back to main menu
echo  --------------------------------------------------------------------------
set "c="
call :PCHH_READ c "  Select: "
if "!c!"=="1" goto SFC_RUN
if "!c!"=="2" goto DISM_CHECK
if "!c!"=="3" goto DISM_SCAN
if "!c!"=="4" goto DISM_RESTORE
if "!c!"=="5" goto DISM_SOURCE
if "!c!"=="6" goto DISM_PKGS
if "!c!"=="7" ( call :NEEDWIN & if defined WINPART ( chkdsk !WINPART! /F & call :PCHH_PAUSE ) & goto MENU_SFC )
if "!c!"=="0" goto MAINMENU
goto MENU_SFC

:SFC_RUN
if not defined PCHH_JOB cls
call :NEEDWIN
if not defined WINPART goto MENU_SFC
echo   Running SFC against !WINPART!\Windows  (this can take a while)...
echo.
sfc /scannow /offbootdir=!WINPART!\ /offwindir=!WINPART!\Windows
echo.
call :PCHH_PAUSE
goto MENU_SFC

:DISM_CHECK
if not defined PCHH_JOB cls
call :NEEDWIN
if not defined WINPART goto MENU_SFC
dism /Image:!WINPART!\ /Cleanup-Image /CheckHealth
echo.
call :PCHH_PAUSE
goto MENU_SFC

:DISM_SCAN
if not defined PCHH_JOB cls
call :NEEDWIN
if not defined WINPART goto MENU_SFC
dism /Image:!WINPART!\ /Cleanup-Image /ScanHealth
echo.
call :PCHH_PAUSE
goto MENU_SFC

:DISM_RESTORE
if not defined PCHH_JOB cls
call :NEEDWIN
if not defined WINPART goto MENU_SFC
echo   Attempting online RestoreHealth (needs network)...
dism /Image:!WINPART!\ /Cleanup-Image /RestoreHealth
echo.
call :PCHH_PAUSE
goto MENU_SFC

:DISM_SOURCE
if not defined PCHH_JOB cls
call :NEEDWIN
if not defined WINPART goto MENU_SFC
echo   Provide a source, e.g.  D:\sources\install.wim:1  or  esd:D:\sources\install.esd:1
call :PCHH_READ src "  Source: "
dism /Image:!WINPART!\ /Cleanup-Image /RestoreHealth /Source:!src! /LimitAccess
echo.
call :PCHH_PAUSE
goto MENU_SFC

:DISM_PKGS
if not defined PCHH_JOB cls
call :NEEDWIN
if not defined WINPART goto MENU_SFC
dism /Image:!WINPART!\ /Get-Packages
echo.
call :PCHH_PAUSE
goto MENU_SFC

REM =============================================================================
REM  D. REGISTRY & USER ACCOUNTS
REM =============================================================================
:MENU_REG
if defined PCHH_JOB exit /b 0
if not defined PCHH_JOB cls
echo  =================  REGISTRY ^& USER ACCOUNTS  ============================
echo.
echo    [1]  Load an offline registry hive, then open RegEdit
echo    [2]  Open RegEdit  ^(no hive pre-loaded^)
echo    [3]  Unload a previously loaded hive
echo    [4]  Reset a local account password  ^(Utilman swap method^)
echo    [5]  Restore Utilman after a password reset
echo.
echo    [0]  Back to main menu
echo  --------------------------------------------------------------------------
echo   Note: offline password reset here works by swapping Utilman.exe with
echo   cmd.exe so you get a SYSTEM prompt at the real Windows logon screen,
echo   then run:  net user ^<username^> ^<newpassword^>
echo  --------------------------------------------------------------------------
set "r="
call :PCHH_READ r "  Select: "
if "!r!"=="1" goto REG_LOAD
if "!r!"=="2" ( start "" %SystemRoot%\regedit.exe & goto MENU_REG )
if "!r!"=="3" goto REG_UNLOAD
if "!r!"=="4" goto PASS_RESET
if "!r!"=="5" goto PASS_RESTORE
if "!r!"=="0" goto MAINMENU
goto MENU_REG

:REG_LOAD
if not defined PCHH_JOB cls
call :NEEDWIN
if not defined WINPART goto MENU_REG
echo.
echo    Which hive?
echo     [1] SYSTEM     [2] SOFTWARE     [3] SAM     [4] SECURITY     [5] DEFAULT
call :PCHH_READ h "  Hive: "
set "HP="
if "!h!"=="1" (set "HP=!WINPART!\Windows\System32\config\SYSTEM"   & set "HN=OFF_SYSTEM")
if "!h!"=="2" (set "HP=!WINPART!\Windows\System32\config\SOFTWARE" & set "HN=OFF_SOFTWARE")
if "!h!"=="3" (set "HP=!WINPART!\Windows\System32\config\SAM"      & set "HN=OFF_SAM")
if "!h!"=="4" (set "HP=!WINPART!\Windows\System32\config\SECURITY" & set "HN=OFF_SECURITY")
if "!h!"=="5" (set "HP=!WINPART!\Windows\System32\config\DEFAULT"  & set "HN=OFF_DEFAULT")
if not defined HP goto MENU_REG
reg load HKLM\!HN! "!HP!"
if errorlevel 1 ( echo   Failed to load hive. & call :PCHH_PAUSE & goto MENU_REG )
echo.
echo   Loaded as HKLM\!HN!  -- edit it under that key in RegEdit.
echo   IMPORTANT: unload it (option 3) before rebooting, choosing key !HN!.
start "" %SystemRoot%\regedit.exe
call :PCHH_PAUSE
goto MENU_REG

:REG_UNLOAD
if not defined PCHH_JOB cls
echo   Loaded offline hives:
reg query HKLM 2>nul | find /i "OFF_"
echo.
call :PCHH_READ hn "  Hive key to unload (e.g. OFF_SYSTEM): "
if "!hn!"=="" goto MENU_REG
reg unload HKLM\!hn!
echo.
call :PCHH_PAUSE
goto MENU_REG

:PASS_RESET
if not defined PCHH_JOB cls
call :NEEDWIN
if not defined WINPART goto MENU_REG
echo.
echo   This backs up Utilman.exe and replaces it with cmd.exe on the offline
echo   Windows. At the Windows logon screen, click the Ease of Access button
echo   (bottom-right) to open a SYSTEM command prompt, then run:
echo         net user ^<username^> ^<newpassword^>
echo         net user ^<username^> *            (to be prompted, or set blank)
echo.
call :PCHH_READ ok "  Proceed with the swap on !WINPART!? Type YES: "
if /i not "!ok!"=="YES" goto MENU_REG
set "U=!WINPART!\Windows\System32\utilman.exe"
set "C=!WINPART!\Windows\System32\cmd.exe"
takeown /f "!U!" >nul 2>&1
icacls "!U!" /grant Administrators:F >nul 2>&1
if not exist "!U!.pchhbak" copy /y "!U!" "!U!.pchhbak" >nul
copy /y "!C!" "!U!" >nul
if errorlevel 1 ( echo   Swap failed - check the drive is writable. ) else ( echo   Done. Reboot into Windows and use the Ease of Access button. )
echo.
call :PCHH_PAUSE
goto MENU_REG

:PASS_RESTORE
if not defined PCHH_JOB cls
call :NEEDWIN
if not defined WINPART goto MENU_REG
set "U=!WINPART!\Windows\System32\utilman.exe"
if exist "!U!.pchhbak" (
    copy /y "!U!.pchhbak" "!U!" >nul
    del "!U!.pchhbak" >nul 2>&1
    echo   Utilman.exe restored.
) else (
    echo   No backup found at !U!.pchhbak
)
echo.
call :PCHH_PAUSE
goto MENU_REG

REM =============================================================================
REM  E. DRIVER MANAGEMENT
REM =============================================================================
:MENU_DRV
if defined PCHH_JOB exit /b 0
if not defined PCHH_JOB cls
echo  ====================  DRIVER MANAGEMENT  ================================
echo.
echo    [1]  Load a driver into THIS PE now  ^(drvload - for disk/NIC access^)
echo    [2]  Inject driver(s) into offline Windows  ^(dism /Add-Driver^)
echo    [3]  Export drivers FROM offline Windows  ^(dism /Export-Driver^)
echo    [4]  List drivers in offline Windows  ^(dism /Get-Drivers^)
echo    [5]  pnputil - list PE driver store
echo.
echo    [0]  Back to main menu
echo  --------------------------------------------------------------------------
set "e="
call :PCHH_READ e "  Select: "
if "!e!"=="1" ( call :PCHH_READ inf "  Path to .inf: " & drvload "!inf!" & call :PCHH_PAUSE & goto MENU_DRV )
if "!e!"=="2" goto DRV_ADD
if "!e!"=="3" goto DRV_EXPORT
if "!e!"=="4" ( call :NEEDWIN & if defined WINPART ( dism /Image:!WINPART!\ /Get-Drivers & call :PCHH_PAUSE ) & goto MENU_DRV )
if "!e!"=="5" ( pnputil /enum-drivers & call :PCHH_PAUSE & goto MENU_DRV )
if "!e!"=="0" goto MAINMENU
goto MENU_DRV

:DRV_ADD
if not defined PCHH_JOB cls
call :NEEDWIN
if not defined WINPART goto MENU_DRV
call :PCHH_READ dp "  Folder containing drivers (searched recursively): "
dism /Image:!WINPART!\ /Add-Driver /Driver:"!dp!" /Recurse /ForceUnsigned
echo.
call :PCHH_PAUSE
goto MENU_DRV

:DRV_EXPORT
if not defined PCHH_JOB cls
call :NEEDWIN
if not defined WINPART goto MENU_DRV
call :PCHH_READ dp "  Destination folder for exported drivers: "
if not exist "!dp!" md "!dp!"
dism /Image:!WINPART!\ /Export-Driver /Destination:"!dp!"
echo.
call :PCHH_PAUSE
goto MENU_DRV

REM =============================================================================
REM  F. DATA RECOVERY, COPY & PERMISSIONS
REM =============================================================================
:MENU_DATA
if defined PCHH_JOB exit /b 0
if not defined PCHH_JOB cls
echo  =============  DATA RECOVERY, COPY ^& PERMISSIONS  =======================
echo.
echo    [1]  RoboCopy  ^(robust copy with retries^)
echo    [2]  XCopy     ^(simple recursive copy^)
echo    [3]  Mirror a folder  ^(RoboCopy /MIR - deletes extras in dest^)
echo    [4]  Rescue copy  ^(skip unreadable files, keep going^)
echo    [5]  Take ownership + grant full control  ^(takeown + icacls^)
echo    [6]  Show / clear file attributes  ^(attrib^)
echo    [7]  Open Notepad  ^(browse/open files via File - Open^)
echo.
echo    [0]  Back to main menu
echo  --------------------------------------------------------------------------
set "f="
call :PCHH_READ f "  Select: "
if "!f!"=="1" goto DATA_ROBO
if "!f!"=="2" goto DATA_XCOPY
if "!f!"=="3" goto DATA_MIRROR
if "!f!"=="4" goto DATA_RESCUE
if "!f!"=="5" goto DATA_OWN
if "!f!"=="6" goto DATA_ATTRIB
if "!f!"=="7" ( start "" notepad.exe & goto MENU_DATA )
if "!f!"=="0" goto MAINMENU
goto MENU_DATA

:DATA_ROBO
if not defined PCHH_JOB cls
call :PCHH_READ s "  Source folder: "
call :PCHH_READ d "  Destination folder: "
robocopy "!s!" "!d!" /E /COPY:DAT /R:2 /W:5 /TEE
echo.
call :PCHH_PAUSE
goto MENU_DATA

:DATA_XCOPY
if not defined PCHH_JOB cls
call :PCHH_READ s "  Source: "
call :PCHH_READ d "  Destination: "
xcopy "!s!" "!d!" /E /H /C /I /Y
echo.
call :PCHH_PAUSE
goto MENU_DATA

:DATA_MIRROR
if not defined PCHH_JOB cls
echo   WARNING: /MIR deletes files in the destination that are not in source.
call :PCHH_READ s "  Source folder: "
call :PCHH_READ d "  Destination folder: "
call :PCHH_READ ok "  Type YES to mirror: "
if /i not "!ok!"=="YES" goto MENU_DATA
robocopy "!s!" "!d!" /MIR /R:2 /W:5 /TEE
echo.
call :PCHH_PAUSE
goto MENU_DATA

:DATA_RESCUE
if not defined PCHH_JOB cls
echo   Rescue mode: copies everything readable, skips bad files, lots of retries.
call :PCHH_READ s "  Source (failing drive) folder: "
call :PCHH_READ d "  Destination (good drive) folder: "
robocopy "!s!" "!d!" /E /COPY:DAT /R:1 /W:1 /XJ /NP /TEE /LOG:X:\pchh-rescue.log
echo.
echo   Log saved to X:\pchh-rescue.log
echo.
call :PCHH_PAUSE
goto MENU_DATA

:DATA_OWN
if not defined PCHH_JOB cls
call :PCHH_READ p "  File or folder path: "
takeown /f "!p!" /r /d y
icacls "!p!" /grant Administrators:F /t /c
echo.
call :PCHH_PAUSE
goto MENU_DATA

:DATA_ATTRIB
if not defined PCHH_JOB cls
call :PCHH_READ p "  File or folder path: "
echo.
echo    [1] Show attributes   [2] Clear hidden+system (unhide)   [3] Set hidden+system
call :PCHH_READ m "  Mode: "
if "!m!"=="1" attrib "!p!"
if "!m!"=="2" attrib -h -s "!p!" /s /d
if "!m!"=="3" attrib +h +s "!p!" /s /d
echo.
call :PCHH_PAUSE
goto MENU_DATA

REM =============================================================================
REM  G. NETWORK TOOLS
REM =============================================================================
:MENU_NET
if defined PCHH_JOB exit /b 0
if not defined PCHH_JOB cls
echo  =======================  NETWORK TOOLS  =================================
echo.
echo    [1]  Initialize / restart networking  ^(wpeutil^)
echo    [2]  Show IP configuration  ^(ipconfig /all^)
echo    [3]  Ping a host
echo    [4]  Trace route to a host
echo    [5]  Map a network share  ^(net use^)
echo    [6]  Set a static IP address  ^(netsh^)
echo    [7]  Reset DHCP / renew address
echo.
echo    [0]  Back to main menu
echo  --------------------------------------------------------------------------
set "g="
call :PCHH_READ g "  Select: "
if "!g!"=="1" ( wpeutil InitializeNetwork & echo. & call :PCHH_PAUSE & goto MENU_NET )
if "!g!"=="2" ( ipconfig /all & echo. & call :PCHH_PAUSE & goto MENU_NET )
if "!g!"=="3" ( call :PCHH_READ h "  Host to ping: " & ping !h! & echo. & call :PCHH_PAUSE & goto MENU_NET )
if "!g!"=="4" ( call :PCHH_READ h "  Host to trace: " & tracert !h! & echo. & call :PCHH_PAUSE & goto MENU_NET )
if "!g!"=="5" goto NET_MAP
if "!g!"=="6" goto NET_STATIC
if "!g!"=="7" goto NET_DHCP
if "!g!"=="0" goto MAINMENU
goto MENU_NET

:NET_MAP
if not defined PCHH_JOB cls
call :PCHH_READ unc "  Share path (e.g. \\server\share): "
call :PCHH_READ dl "  Drive letter to map (e.g. Z): "
call :PCHH_READ us "  Username (blank for none): "
if defined us call :PCHH_READ password "Password for the network share: "
if "!us!"=="" ( net use !dl!: "!unc!" ) else ( net use !dl!: "!unc!" "!password!" /user:"!us!" )
set "password="
echo.
call :PCHH_PAUSE
goto MENU_NET

:NET_STATIC
if not defined PCHH_JOB cls
echo   Available interfaces:
netsh interface show interface
echo.
call :PCHH_READ nm "  Interface name (e.g. Ethernet): "
call :PCHH_READ ip "  IP address: "
call :PCHH_READ mk "  Subnet mask: "
call :PCHH_READ gw "  Gateway: "
netsh interface ip set address name="!nm!" static !ip! !mk! !gw!
call :PCHH_READ dns "  DNS server (blank to skip): "
if not "!dns!"=="" netsh interface ip set dns name="!nm!" static !dns!
echo.
call :PCHH_PAUSE
goto MENU_NET

:NET_DHCP
if not defined PCHH_JOB cls
echo   Available interfaces:
netsh interface show interface
echo.
call :PCHH_READ nm "  Interface name (e.g. Ethernet): "
netsh interface ip set address name="!nm!" dhcp
netsh interface ip set dns name="!nm!" dhcp
ipconfig /renew
echo.
call :PCHH_PAUSE
goto MENU_NET

REM =============================================================================
REM  H. DIAGNOSTICS & SYSTEM INFO
REM =============================================================================
:MENU_DIAG
if defined PCHH_JOB exit /b 0
if not defined PCHH_JOB cls
echo  ===================  DIAGNOSTICS ^& SYSTEM INFO  =========================
echo.
echo    [1]  System summary  ^(CPU / BIOS / board from registry^)
echo    [2]  Disk overview  ^(diskpart^)
echo    [3]  Network summary  ^(ipconfig^)
echo    [4]  Windows Event Log query  ^(wevtutil^)
echo    [5]  Installed driver list  ^(driverquery^)
echo    [6]  Open Task Manager
echo    [7]  Diagnose persistent recovery error ^(0xc000... / BCD / winload^)
echo    [8]  Read Startup Repair log and propose a repair
echo.
echo    [0]  Back to main menu
echo  --------------------------------------------------------------------------
set "h="
call :PCHH_READ h "  Select: "
if "!h!"=="1" goto DIAG_SYS
if "!h!"=="2" ( cls & (echo list disk ^& echo list volume) | diskpart & echo. & call :PCHH_PAUSE & goto MENU_DIAG )
if "!h!"=="3" ( cls & ipconfig /all & echo. & call :PCHH_PAUSE & goto MENU_DIAG )
if "!h!"=="4" goto DIAG_EVT
if "!h!"=="5" ( cls & driverquery & echo. & call :PCHH_PAUSE & goto MENU_DIAG )
if "!h!"=="6" ( start "" taskmgr.exe & goto MENU_DIAG )
if "!h!"=="7" goto DIAG_RECOVERY
if "!h!"=="8" goto DIAG_SRT
if "!h!"=="0" goto MAINMENU
goto MENU_DIAG

:DIAG_SRT
if not defined PCHH_JOB cls
echo  =================  STARTUP REPAIR LOG DIAGNOSIS  =========================
echo.
call :NEEDWIN
if not defined WINPART goto MENU_DIAG
set "SRTLOG=!WINPART!\Windows\System32\LogFiles\Srt\SrtTrail.txt"
if not exist "!SRTLOG!" (
    echo   SrtTrail.txt was not found at !SRTLOG!.
    echo   Run Startup Repair first, or use Diagnostics - Persistent Recovery.
    echo.
    call :PCHH_PAUSE
    goto MENU_DIAG
)
echo   Reading: !SRTLOG!
echo.
type "!SRTLOG!"
echo.
echo  --- Proposed next steps ---
find /i "boot critical file is corrupt" "!SRTLOG!" >nul 2>&1 && echo   [1] Boot file corruption: back up BCD, then use Boot Repair - Auto repair.
find /i "boot manager failed to find OS loader" "!SRTLOG!" >nul 2>&1 && echo   [2] OS loader missing: verify the Windows volume and run bcdboot to the EFI partition.
find /i "boot configuration data store" "!SRTLOG!" >nul 2>&1 && echo   [3] BCD problem: use Persistent Recovery diagnosis to inspect and back up the BCD.
find /i "root cause found" "!SRTLOG!" >nul 2>&1 && echo   [4] Startup Repair identified a root cause above; address that item before rebuilding blindly.
find /i "corrupt" "!SRTLOG!" >nul 2>&1 && echo   [5] Corruption reported: run read-only checks first, then ChkDsk only after backing up important data.
find /i "unknown bugcheck" "!SRTLOG!" >nul 2>&1 && echo   [6] Driver or update failure suspected: use System File Repair or remove the recent offline package.
echo.
echo   These are proposals based on log text; no repair was performed.
call :PCHH_PAUSE
goto MENU_DIAG

:DIAG_RECOVERY
if not defined PCHH_JOB cls
echo  ==============  WINDOWS RECOVERY CODE ASSISTANT  ========================
echo   For the persistent Your PC/Device needs to be repaired screen.
echo   A code is a clue, not a confirmed diagnosis. Scanning does not repair files.
set "rcode="
call :PCHH_READ rcode "  Recovery code, e.g. 0xc0000225 (optional): "
if defined rcode (
    >"%TEMP%\pchh-code.txt" echo(!rcode!
    findstr /r /i /x "0x[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]" "%TEMP%\pchh-code.txt" >nul
    if errorlevel 1 (echo   Invalid code. Use 0x followed by eight hexadecimal digits. & goto DIAG_RECOVERY)
)
set "rfile="
call :PCHH_READ rfile "  File named on screen (optional): "
echo   Readable Windows installations:
for %%d in (A B C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist "%%d:\Windows\System32\config\SYSTEM" echo     %%d:\Windows
)
echo   Check the list and BitLocker status above. Select the installation to scan.
set "rdrive="
call :PCHH_READ rdrive "  Windows drive letter, e.g. D (blank to cancel): "
set "RTARGET="
for %%d in (A B C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if /i "!rdrive!"=="%%d" set "RTARGET=%%d:"
    if /i "!rdrive!"=="%%d:" set "RTARGET=%%d:"
)
if not defined RTARGET goto MENU_DIAG
if /i "!RTARGET!"=="%SystemDrive%" (echo   Refusing to target the recovery RAM drive. & exit /b 1)
if not exist "!RTARGET!\Windows\System32\config\SYSTEM" (
    echo   Windows SYSTEM hive unreadable. Check BitLocker and the drive letter.
    exit /b 1
)
set "WINPART=!RTARGET!"
set "RDIR=%TEMP%\PCHH-Recovery-!RANDOM!-!RANDOM!"
if defined PCHH_JOB set "RDIR=!PCHH_JOB!\recovery"
md "!RDIR!\scratch"
echo.
echo  --- Code guidance ---
set "RKNOWN="
for %%c in (0xc000000e 0xc000000f 0xc0000225 0xc0000098 0xc000014c) do if /i "!rcode!"=="%%c" set "RKNOWN=BOOT"
if defined RKNOWN echo   Boot device / loader / BCD family: inspect storage visibility and boot entries first.
if /i "!rcode!"=="0xc0000185" (set "RKNOWN=IO" & echo   I/O error: check connections and disk health before write repairs.)
if /i "!rcode!"=="0xc00000e9" (set "RKNOWN=IO" & echo   Unexpected I/O error: check peripherals, connections and storage health.)
if /i "!rcode!"=="0xc0000428" (set "RKNOWN=SIGNATURE" & echo   Signature failure: inspect the named file and recent drivers; verify system files.)
if /i "!rcode!"=="0xc000021a" (set "RKNOWN=SYSTEM" & echo   System process failure: investigate files, recent updates and drivers.)
if not defined RKNOWN echo   No specific rule for this code. General checks apply; do not infer a repair from the code alone.
echo   Screen file: !rfile!
echo   Target: !WINPART!\Windows
call :RECOVERY_SCAN

:RECOVERY_PLAN
echo.
echo  --- Findings and proposed solutions ---
echo   Review output above. A nonzero scan result may mean the tool could not run.
if not "!RDISKRC!"=="0" echo   [WARN] Filesystem check returned !RDISKRC!; review errors versus an unreadable volume.
if not "!RSFCRC!"=="0" echo   [WARN] SFC verification returned !RSFCRC!; review its findings before repair.
if not "!RDISMRC!"=="0" echo   [WARN] Image health query returned !RDISMRC!; component health may be unknown.
if not "!RBCDCOUNT!"=="1" echo   [WARN] Found !RBCDCOUNT! boot stores. Confirm the correct disk before boot repair.
if "!RLOADER!"=="missing" echo   [WARN] Windows loader missing. Repair system files before rebuilding boot files.
if /i "!RKNOWN!"=="IO" echo   [PRIORITY] Suspected hardware I/O: preserve files or image the disk before any write repair.
echo   [1] Rebuild UEFI boot files - for confirmed missing, unreadable or wrong BCD entries.
echo       Requires a verified EFI partition; existing boot files are backed up to PE RAM.
echo   [2] Repair Windows system files - for SFC corruption or a missing loader.
echo       Runs offline SFC /scannow. Does not change driver or security settings.
echo   [3] Repair component store - if DISM reports corruption or SFC cannot repair.
echo       Requires matching Windows WIM/ESD and image index, then reruns SFC.
echo   [4] Repair filesystem - for confirmed filesystem errors after a data backup.
echo       CHKDSK /f changes disk metadata. Avoid on failing hardware.
echo   [0] Finish without further repairs. No automatic reboot.
echo   Select only a solution supported by the findings. Each requires confirmation.
set "rchoice="
call :PCHH_READ rchoice "  Proposed solution 1-4, or 0 to finish: "
if "!rchoice!"=="1" goto RECOVERY_BOOT
if "!rchoice!"=="2" goto RECOVERY_SFC
if "!rchoice!"=="3" goto RECOVERY_IMAGE
if "!rchoice!"=="4" goto RECOVERY_DISK
if "!rchoice!"=="0" goto MENU_DIAG
if not defined rchoice goto MENU_DIAG
echo   Select one listed solution.
goto RECOVERY_PLAN

:RECOVERY_SCAN
REM No repair switches, offline hive loads or host-side backups during diagnosis.
echo.
echo  --- Scan: filesystem, Windows files, recorded image health and boot stores ---
echo   Logs and scratch files: !RDIR!
chkdsk !WINPART! >"!RDIR!\filesystem.txt" 2>&1
set "RDISKRC=!errorlevel!"
type "!RDIR!\filesystem.txt"
sfc /verifyonly /offbootdir=!WINPART!\ /offwindir=!WINPART!\Windows /offlogfile="!RDIR!\sfc-verify.txt"
set "RSFCRC=!errorlevel!"
REM CheckHealth queries recorded corruption; servicing repairs require approval.
dism /Image:!WINPART!\ /Cleanup-Image /CheckHealth /LogPath:"!RDIR!\dism-check.log" /ScratchDir:"!RDIR!\scratch"
set "RDISMRC=!errorlevel!"
set "RLOADER=found"
if not exist "!WINPART!\Windows\System32\winload.efi" if not exist "!WINPART!\Windows\System32\winload.exe" set "RLOADER=missing"
echo   Windows loader: !RLOADER!
if exist "!WINPART!\Windows\System32\LogFiles\Srt\SrtTrail.txt" type "!WINPART!\Windows\System32\LogFiles\Srt\SrtTrail.txt"
if exist "!WINPART!\Windows\System32\winevt\Logs\System.evtx" wevtutil qe "!WINPART!\Windows\System32\winevt\Logs\System.evtx" /lf:true /c:15 /rd:true /f:text /q:"*[System[(Level=1 or Level=2)]]"
set "RBCDCOUNT=0"
for %%d in (A B C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    for %%p in ("%%d:\EFI\Microsoft\Boot\BCD" "%%d:\Boot\BCD") do if exist "%%~p" (
        set /a RBCDCOUNT+=1
        echo   BCD candidate: %%~p - verify device/osdevice match !WINPART!.
        bcdedit /store "%%~p" /enum all
        if errorlevel 1 echo   [WARN] Boot store could not be read.
    )
)
echo   Unlettered or locked partitions need Storage Setup before they can be scanned.
exit /b 0

:RECOVERY_CONFIRM
echo.
echo   Proposed command: !RCOMMAND!
echo   Target: !WINPART!\Windows. Back up important files before repairs.
set "rconfirm="
call :PCHH_READ rconfirm "  Type REPAIR to approve this solution, or blank to return: "
if /i not "!rconfirm!"=="REPAIR" exit /b 1
exit /b 0

:RECOVERY_BOOT
echo   Select the EFI partition belonging to the Windows disk. Assign a letter in Storage Setup if needed.
echo   Legacy BIOS repairs are available separately under Boot Repair.
set "rboot="
call :PCHH_READ rboot "  EFI System Partition drive letter (blank to return): "
set "RESP="
for %%d in (A B C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if /i "!rboot!"=="%%d" set "RESP=%%d:"
    if /i "!rboot!"=="%%d:" set "RESP=%%d:"
)
if not defined RESP goto RECOVERY_PLAN
if /i "!RESP!"=="!WINPART!" (echo   Refusing to use the Windows volume as EFI. & goto RECOVERY_PLAN)
if /i "!RESP!"=="%SystemDrive%" (echo   Refusing to use the RAM drive. & goto RECOVERY_PLAN)
>"!RDIR!\efi-check.txt" (
    echo select volume !RESP!
    echo detail partition
    echo detail volume
    echo exit
)
diskpart /s "!RDIR!\efi-check.txt" >"!RDIR!\efi-detail.txt" 2>&1
type "!RDIR!\efi-detail.txt"
findstr /i /c:"c12a7328-f81f-11d2-ba4b-00a0c93ec93b" "!RDIR!\efi-detail.txt" >nul
if errorlevel 1 (echo   EFI partition type not verified. No boot files changed. & goto RECOVERY_PLAN)
set "RCOMMAND=bcdboot !WINPART!\Windows /s !RESP! /f UEFI"
call :RECOVERY_CONFIRM
if errorlevel 1 goto RECOVERY_PLAN
set "RBACKUP=!RDIR!\boot-backup-!RANDOM!-!RANDOM!"
if exist "!RESP!\EFI\Microsoft\Boot\" (
    xcopy "!RESP!\EFI\Microsoft\Boot\*" "!RBACKUP!\" /e /h /i /k /y
    if errorlevel 1 (echo   Boot backup failed. Repair stopped. & exit /b 1)
    echo   Boot backup: !RBACKUP! - save to persistent storage before restarting.
)
bcdboot !WINPART!\Windows /s !RESP! /f UEFI
set "RREPAIRRC=!errorlevel!"
if not "!RREPAIRRC!"=="0" goto RECOVERY_FAILED
bcdedit /store "!RESP!\EFI\Microsoft\Boot\BCD" /enum all
if errorlevel 1 (echo   New BCD could not be verified. Review backup and output. & exit /b 1)
echo   Boot files rebuilt. Verify device/osdevice, then test boot when ready.
goto RECOVERY_AFTER

:RECOVERY_SFC
set "RCOMMAND=sfc /scannow /offbootdir=!WINPART!\ /offwindir=!WINPART!\Windows"
call :RECOVERY_CONFIRM
if errorlevel 1 goto RECOVERY_PLAN
sfc /scannow /offbootdir=!WINPART!\ /offwindir=!WINPART!\Windows /offlogfile="!RDIR!\sfc-repair.txt"
set "RREPAIRRC=!errorlevel!"
if not "!RREPAIRRC!"=="0" goto RECOVERY_FAILED
goto RECOVERY_AFTER

:RECOVERY_IMAGE
echo   Use Windows media matching the installed version, edition, architecture and language.
set "rsource="
call :PCHH_READ rsource "  Full path to install.wim or install.esd (blank to return): "
if not defined rsource goto RECOVERY_PLAN
if not exist "!rsource!" (echo   Source not found. & goto RECOVERY_PLAN)
set "RSOURCETYPE="
for %%f in ("!rsource!") do (
    if /i "%%~xf"==".wim" set "RSOURCETYPE=wim"
    if /i "%%~xf"==".esd" set "RSOURCETYPE=esd"
)
if not defined RSOURCETYPE (echo   Select a WIM or ESD file. & goto RECOVERY_PLAN)
dism /Get-WimInfo /WimFile:"!rsource!" /LogPath:"!RDIR!\source.log"
if errorlevel 1 (echo   Cannot read source image. & goto RECOVERY_PLAN)
set "rindex="
call :PCHH_READ rindex "  Matching image index (blank to return): "
if not defined rindex goto RECOVERY_PLAN
>"!RDIR!\index.txt" echo(!rindex!
findstr /r /x "[1-9][0-9]*" "!RDIR!\index.txt" >nul
if errorlevel 1 (echo   Invalid image index. & goto RECOVERY_PLAN)
set "RCOMMAND=DISM /RestoreHealth with !RSOURCETYPE!:!rsource!:!rindex! /LimitAccess, then offline SFC /scannow"
call :RECOVERY_CONFIRM
if errorlevel 1 goto RECOVERY_PLAN
dism /Image:!WINPART!\ /Cleanup-Image /RestoreHealth /Source:"!RSOURCETYPE!:!rsource!:!rindex!" /LimitAccess /LogPath:"!RDIR!\dism-repair.log" /ScratchDir:"!RDIR!\scratch"
set "RREPAIRRC=!errorlevel!"
if not "!RREPAIRRC!"=="0" goto RECOVERY_FAILED
sfc /scannow /offbootdir=!WINPART!\ /offwindir=!WINPART!\Windows /offlogfile="!RDIR!\sfc-after-dism.txt"
set "RREPAIRRC=!errorlevel!"
if not "!RREPAIRRC!"=="0" goto RECOVERY_FAILED
goto RECOVERY_AFTER

:RECOVERY_DISK
echo   CHKDSK /f writes metadata. Preserve data first; image failing drives before repair.
set "RCOMMAND=chkdsk !WINPART! /f"
call :RECOVERY_CONFIRM
if errorlevel 1 goto RECOVERY_PLAN
chkdsk !WINPART! /f
set "RREPAIRRC=!errorlevel!"
REM CHKDSK 1 means errors found and fixed. Other nonzero codes require review.
if "!RREPAIRRC!"=="1" goto RECOVERY_AFTER
if not "!RREPAIRRC!"=="0" goto RECOVERY_FAILED

:RECOVERY_AFTER
echo   Selected repair returned !RREPAIRRC!. Checking the result with fresh scans.
echo   Command completion alone does not prove Windows can boot.
call :RECOVERY_SCAN
goto RECOVERY_PLAN

:RECOVERY_FAILED
echo   [FAIL] Repair returned !RREPAIRRC!. No additional repair runs automatically.
echo   Save the operation log and review the error before another solution.
exit /b !RREPAIRRC!

:DIAG_SYS
if not defined PCHH_JOB cls
echo  ======================  SYSTEM SUMMARY  =================================
echo.
echo  --- Processor ---
reg query "HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\0" /v ProcessorNameString 2>nul | find /i "ProcessorNameString"
echo.
echo  --- System BIOS / Board ---
reg query "HKLM\HARDWARE\DESCRIPTION\System\BIOS" 2>nul
echo.
echo  --- Boot environment ---
if defined firmware_type echo   Firmware: %firmware_type%
echo   PE drive: %SystemDrive%    Windows found: !WINPART!
echo.
echo   (For RAM and running processes, use Task Manager - Diagnostics menu.)
echo.
call :PCHH_PAUSE
goto MENU_DIAG

:DIAG_EVT
if not defined PCHH_JOB cls
call :NEEDWIN
if not defined WINPART goto MENU_DIAG
echo   Querying the offline System event log for the 30 most recent errors...
echo.
wevtutil qe "!WINPART!\Windows\System32\winevt\Logs\System.evtx" /lf:true /c:30 /rd:true /f:text /q:"*[System[(Level=1 or Level=2)]]"
echo.
call :PCHH_PAUSE
goto MENU_DIAG

REM =============================================================================
REM  I. UTILITIES
REM =============================================================================
:MENU_UTIL
if defined PCHH_JOB exit /b 0
if not defined PCHH_JOB cls
echo  ========================  UTILITIES  ===================================
echo.
echo    [1]  New Command Prompt window
echo    [2]  Notepad
echo    [3]  Task Manager
echo    [4]  RegEdit
echo    [5]  Re-detect installed Windows
echo    [6]  Change screen size  ^(80x25 / 100x48 / 120x50^)
echo.
echo    [0]  Back to main menu
echo  --------------------------------------------------------------------------
set "u="
call :PCHH_READ u "  Select: "
if "!u!"=="1" ( start "PCHH CMD" cmd & goto MENU_UTIL )
if "!u!"=="2" ( start "" notepad.exe & goto MENU_UTIL )
if "!u!"=="3" ( start "" taskmgr.exe & goto MENU_UTIL )
if "!u!"=="4" ( start "" %SystemRoot%\regedit.exe & goto MENU_UTIL )
if "!u!"=="5" ( call :DETECT_WINDOWS & echo   Detected: !WINPART! & call :DELAY 2 & goto MENU_UTIL )
if "!u!"=="6" goto UTIL_SIZE
if "!u!"=="0" goto MAINMENU
goto MENU_UTIL

:UTIL_SIZE
if not defined PCHH_JOB cls
echo    [1] 80x25    [2] 100x48    [3] 120x50
call :PCHH_READ z "  Size: "
if "!z!"=="1" mode con: cols=80 lines=25
if "!z!"=="2" mode con: cols=100 lines=48
if "!z!"=="3" mode con: cols=120 lines=50
goto MENU_UTIL

REM =============================================================================
REM  J. STARTUP SETTINGS & RECOVERY ENVIRONMENT
REM     All options write to the INSTALLED Windows boot store (not this PE).
REM =============================================================================
:MENU_BOOTMODE
if defined PCHH_JOB exit /b 0
if not defined PCHH_JOB cls
echo  ============  STARTUP SETTINGS ^& RECOVERY ENVIRONMENT  ==================
echo.
echo   These change how the INSTALLED Windows next starts ^(like the F8 /
echo   "Startup Settings" screen^). They edit that PC's boot configuration.
echo  --------------------------------------------------------------------------
echo    [1]  Enable legacy F8 "Advanced Boot Options" menu at startup
echo    [2]  Boot into Safe Mode  ^(minimal^)
echo    [3]  Boot into Safe Mode with Networking
echo    [4]  Boot into Safe Mode with Command Prompt
echo    [5]  Enable boot logging  ^(ntbtlog.txt^)
echo    [6]  Enable low-resolution video  ^(640x480^)
echo    [7]  Disable driver signature enforcement
echo    [8]  Disable early-launch anti-malware  ^(ELAM^)
echo    [9]  Disable automatic restart on system failure  ^(see BSOD code^)
echo   [10]  RESET to a normal boot  ^(clear 1-9^)
echo.
echo   [11]  Boot the installed Windows RECOVERY ENVIRONMENT ^(WinRE^) next restart
echo   [12]  Show current boot settings
echo   [13]  Locate WinRE image on disk
echo.
echo    [0]  Back to main menu
echo  --------------------------------------------------------------------------
set "j="
call :PCHH_READ j "  Select: "
if "!j!"=="1" goto BM_F8
if "!j!"=="2" goto BM_SAFE_MIN
if "!j!"=="3" goto BM_SAFE_NET
if "!j!"=="4" goto BM_SAFE_CMD
if "!j!"=="5" goto BM_BOOTLOG
if "!j!"=="6" goto BM_VGA
if "!j!"=="7" goto BM_NOSIG
if "!j!"=="8" goto BM_NOELAM
if "!j!"=="9" goto BM_NORESTART
if "!j!"=="10" goto BM_RESET
if "!j!"=="11" goto BM_WINRE
if "!j!"=="12" goto BM_SHOW
if "!j!"=="13" goto BM_FINDRE
if "!j!"=="0" goto MAINMENU
goto MENU_BOOTMODE

:BM_F8
if not defined PCHH_JOB cls
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
bcdedit /store "!BCDSTORE!" /set {bootmgr} displaybootmenu Yes
bcdedit /store "!BCDSTORE!" /set {default} bootmenupolicy Legacy
echo.
echo   Legacy F8 menu enabled. Tap F8 right after power-on to pick a startup mode.
echo.
call :PCHH_PAUSE
goto MENU_BOOTMODE

:BM_SAFE_MIN
if not defined PCHH_JOB cls
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
bcdedit /store "!BCDSTORE!" /deletevalue {default} safebootalternateshell >nul 2>&1
bcdedit /store "!BCDSTORE!" /set {default} safeboot Minimal
echo.
echo   Next boot will enter Safe Mode. Use [10] to return to normal.
echo.
call :PCHH_PAUSE
goto MENU_BOOTMODE

:BM_SAFE_NET
if not defined PCHH_JOB cls
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
bcdedit /store "!BCDSTORE!" /deletevalue {default} safebootalternateshell >nul 2>&1
bcdedit /store "!BCDSTORE!" /set {default} safeboot Network
echo.
echo   Next boot will enter Safe Mode with Networking. Use [10] to undo.
echo.
call :PCHH_PAUSE
goto MENU_BOOTMODE

:BM_SAFE_CMD
if not defined PCHH_JOB cls
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
bcdedit /store "!BCDSTORE!" /set {default} safeboot Minimal
bcdedit /store "!BCDSTORE!" /set {default} safebootalternateshell Yes
echo.
echo   Next boot will enter Safe Mode with Command Prompt. Use [10] to undo.
echo.
call :PCHH_PAUSE
goto MENU_BOOTMODE

:BM_BOOTLOG
if not defined PCHH_JOB cls
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
bcdedit /store "!BCDSTORE!" /set {default} bootlog Yes
echo.
echo   Boot logging enabled -> %%SystemRoot%%\ntbtlog.txt after next boot.
echo.
call :PCHH_PAUSE
goto MENU_BOOTMODE

:BM_VGA
if not defined PCHH_JOB cls
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
bcdedit /store "!BCDSTORE!" /set {default} vga On
echo.
echo   Low-resolution video enabled for next boot. Use [10] to undo.
echo.
call :PCHH_PAUSE
goto MENU_BOOTMODE

:BM_NOSIG
if not defined PCHH_JOB cls
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
bcdedit /store "!BCDSTORE!" /set {default} nointegritychecks Yes
bcdedit /store "!BCDSTORE!" /set {default} loadoptions DDISABLE_INTEGRITY_CHECKS >nul 2>&1
echo.
echo   Driver signature enforcement disabled.
echo   NOTE: ignored while UEFI Secure Boot is ON - disable Secure Boot in
echo   firmware if unsigned drivers still refuse to load. Use [10] to undo.
echo.
call :PCHH_PAUSE
goto MENU_BOOTMODE

:BM_NOELAM
if not defined PCHH_JOB cls
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
bcdedit /store "!BCDSTORE!" /set {default} disableelamdrivers Yes
echo.
echo   Early-launch anti-malware drivers disabled for next boot. Use [10] to undo.
echo.
call :PCHH_PAUSE
goto MENU_BOOTMODE

:BM_NORESTART
if not defined PCHH_JOB cls
echo  DISABLE AUTOMATIC RESTART ON SYSTEM FAILURE
echo.
echo   This lets you read a STOP/BSOD code instead of the PC rebooting instantly.
echo   It is stored in the SYSTEM registry hive of the installed Windows.
call :NEEDWIN
if not defined WINPART goto MENU_BOOTMODE
reg load HKLM\OFF_SYS "!WINPART!\Windows\System32\config\SYSTEM" >nul 2>&1
if errorlevel 1 ( echo   Could not load SYSTEM hive. & call :PCHH_PAUSE & goto MENU_BOOTMODE )
reg add "HKLM\OFF_SYS\ControlSet001\Control\CrashControl" /v AutoReboot /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\OFF_SYS\ControlSet002\Control\CrashControl" /v AutoReboot /t REG_DWORD /d 0 /f >nul 2>&1
reg unload HKLM\OFF_SYS >nul 2>&1
echo.
echo   Automatic restart on failure disabled. The next BSOD will stay on screen.
echo.
call :PCHH_PAUSE
goto MENU_BOOTMODE

:BM_RESET
if not defined PCHH_JOB cls
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
bcdedit /store "!BCDSTORE!" /deletevalue {default} safeboot >nul 2>&1
bcdedit /store "!BCDSTORE!" /deletevalue {default} safebootalternateshell >nul 2>&1
bcdedit /store "!BCDSTORE!" /deletevalue {default} bootlog >nul 2>&1
bcdedit /store "!BCDSTORE!" /deletevalue {default} vga >nul 2>&1
bcdedit /store "!BCDSTORE!" /deletevalue {default} nointegritychecks >nul 2>&1
bcdedit /store "!BCDSTORE!" /deletevalue {default} loadoptions >nul 2>&1
bcdedit /store "!BCDSTORE!" /deletevalue {default} disableelamdrivers >nul 2>&1
bcdedit /store "!BCDSTORE!" /set {default} bootmenupolicy Standard >nul 2>&1
echo.
echo   Startup options cleared - the installed Windows will boot normally.
echo   ^(To re-enable auto-restart use [9]'s reverse: set AutoReboot=1 in RegEdit.^)
echo.
call :PCHH_PAUSE
goto MENU_BOOTMODE

:BM_WINRE
if not defined PCHH_JOB cls
echo  BOOT THE INSTALLED WINDOWS RECOVERY ENVIRONMENT (WinRE)
echo.
echo   This points the installed PC's boot manager at its own recovery image
echo   for the next restart, giving you Troubleshoot - Startup Repair,
echo   System Restore, Reset this PC, and the WinRE command prompt.
echo.
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
set "RSEQ="
for /f "tokens=1,*" %%a in ('bcdedit /store "!BCDSTORE!" /enum {default} 2^>nul ^| find /i "recoverysequence"') do set "RSEQ=%%b"
REM Trim spaces
for /f "tokens=* delims= " %%a in ("!RSEQ!") do set "RSEQ=%%a"
if not defined RSEQ (
    echo.
    echo   No recovery sequence is configured on this install - WinRE may be
    echo   disabled or missing. You can still use this menu's Boot Repair, SFC
    echo   and DISM options, which cover most of what Startup Repair does.
    echo.
    call :PCHH_PAUSE
    goto MENU_BOOTMODE
)
echo.
echo   Recovery entry: !RSEQ!
bcdedit /store "!BCDSTORE!" /set {bootmgr} bootsequence !RSEQ!
if errorlevel 1 (
    echo   Could not set the one-time boot sequence.
) else (
    echo.
    echo   Done. Reboot ^(main menu [R]^) and remove this USB - the PC will boot
    echo   straight into its Windows Recovery Environment once.
)
echo.
call :PCHH_PAUSE
goto MENU_BOOTMODE

:BM_SHOW
if not defined PCHH_JOB cls
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
echo  ===== {bootmgr} =====
bcdedit /store "!BCDSTORE!" /enum {bootmgr}
echo.
echo  ===== {default} OS loader =====
bcdedit /store "!BCDSTORE!" /enum {default}
echo.
call :PCHH_PAUSE
goto MENU_BOOTMODE

:BM_FINDRE
if not defined PCHH_JOB cls
echo  SEARCHING FOR WinRE IMAGES (Winre.wim) ...
echo.
for %%d in (A B C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist %%d:\Recovery\WindowsRE\Winre.wim echo   Found: %%d:\Recovery\WindowsRE\Winre.wim
    if exist %%d:\Windows\System32\Recovery\Winre.wim echo   Found: %%d:\Windows\System32\Recovery\Winre.wim
    if exist %%d:\Recovery\Winre.wim echo   Found: %%d:\Recovery\Winre.wim
)
echo.
echo   (Recovery partitions are often unlettered; assign a letter via the Disk
echo    menu to see their contents. Option [11] boots WinRE without needing this.)
echo.
call :PCHH_PAUSE
goto MENU_BOOTMODE

REM =============================================================================
REM  STORAGE SETUP / DISK DETECTION  (first-run + recovery from "no volumes")
REM =============================================================================
:MENU_STORAGE
if defined PCHH_JOB exit /b 0
if not defined PCHH_JOB cls
echo  =============  STORAGE SETUP  /  DISK DETECTION   (START HERE)  =========
echo.
echo   DISKS:
(echo list disk) | diskpart
echo.
echo   VOLUMES:
(echo list volume) | diskpart
echo.
call :DETECT_WINDOWS
if defined WINPART (
    echo   [ OK ]  Windows found at !WINPART!\Windows  -- choose [6] to continue.
) else (
    echo   [ !! ]  No Windows volume is visible yet. Try [1], then [2]/[3]; if NO
    echo           disks appear at all, use [4] or the BIOS tip below.
)
echo  --------------------------------------------------------------------------
echo    [1]  Rescan / refresh disks ^& auto-assign letters
echo    [2]  Bring an OFFLINE disk online  ^(+ clear read-only^)
echo    [3]  Assign a drive letter to one volume
echo    [4]  Load a storage driver now  ^(Intel VMD/RST, RAID, vendor NVMe^)
echo    [5]  Show full disk ^& volume details
echo    [6]  Continue to the main repair menu
echo    [7]  Show BitLocker encryption and lock status
echo.
echo   TIP: "No disks at all" almost always means Intel RST / VMD / RAID is ON
echo        in BIOS. Load its driver with [4] ^(iaStorVD.inf / iaStorAC.inf from
echo        another USB^), or in BIOS/UEFI set SATA or VMD mode to AHCI.
echo        Changing BIOS to AHCI can stop Windows booting until repaired -- the
echo        driver route is safer.
echo  --------------------------------------------------------------------------
set "s="
call :PCHH_READ s "  Select: "
if "!s!"=="1" ( call :STORAGE_INIT & goto MENU_STORAGE )
if "!s!"=="2" goto STOR_ONLINE
if "!s!"=="3" goto STOR_ASSIGN
if "!s!"=="4" goto STOR_DRIVER
if "!s!"=="5" goto STOR_DETAIL
if "!s!"=="6" goto MAINMENU
if "!s!"=="7" goto STOR_BITLOCKER
goto MENU_STORAGE

:STOR_ONLINE
if not defined PCHH_JOB cls
(echo list disk) | diskpart
echo.
call :PCHH_READ dk "  Disk number to bring ONLINE (blank to cancel): "
if "!dk!"=="" goto MENU_STORAGE
(echo select disk !dk! ^& echo online disk noerr ^& echo attributes disk clear readonly noerr ^& echo exit) | diskpart
echo.
echo   Done. Rescanning...
call :STORAGE_INIT
call :PCHH_PAUSE
goto MENU_STORAGE

:STOR_ASSIGN
if not defined PCHH_JOB cls
(echo list volume) | diskpart
echo.
call :PCHH_READ v "  Volume number (blank to cancel): "
if "!v!"=="" goto MENU_STORAGE
call :PCHH_READ l "  Drive letter to assign (e.g. C): "
(echo select volume !v! ^& echo assign letter=!l! noerr ^& echo exit) | diskpart
echo.
call :PCHH_PAUSE
goto MENU_STORAGE

:STOR_DRIVER
if not defined PCHH_JOB cls
echo  LOAD A STORAGE DRIVER INTO THIS PE
echo.
echo   Needed when the disk controller is in RAID / Intel RST / VMD mode and no
echo   disks appear. Put the extracted driver (its .inf + .sys) on another USB
echo   stick or the PCHH_DATA partition, then give the full path to the .inf.
echo.
echo   Current volumes (to find your driver's drive letter):
(echo list volume) | diskpart
echo.
call :PCHH_READ inf "  Full path to the .inf (blank to cancel): "
if "!inf!"=="" goto MENU_STORAGE
drvload "!inf!"
echo.
echo   Rescanning storage...
call :STORAGE_INIT
call :DETECT_WINDOWS
if defined WINPART ( echo   Success - Windows now visible at !WINPART! ) else ( echo   Still no Windows volume - check the driver matches this controller. )
echo.
call :PCHH_PAUSE
goto MENU_STORAGE

:STOR_DETAIL
if not defined PCHH_JOB cls
(echo list disk ^& echo list volume) | diskpart
echo.
call :PCHH_PAUSE
goto MENU_STORAGE

REM =============================================================================
REM  System actions
REM =============================================================================
:DO_REBOOT
if not defined PCHH_JOB cls
echo   Rebooting...
wpeutil reboot
goto :eof

:DO_SHUTDOWN
if not defined PCHH_JOB cls
echo   Shutting down...
wpeutil shutdown
goto :eof

:DO_EXIT
if not defined PCHH_JOB cls
echo  ==========================================================================
echo   Exiting to the command prompt.
echo   Type  menu  to relaunch the PCHH repair menu, or  exit  to close.
echo  ==========================================================================
echo.
doskey menu=startnet.cmd
cmd /k
goto :eof

:GUI_DISPATCH
set "PCHH_JOB=%~3"
set "PCHH_REQUEST=0"
call :DETECT_WINDOWS
if /i "%~2"=="BM_BOOTLOG" goto BM_BOOTLOG
if /i "%~2"=="BM_F8" goto BM_F8
if /i "%~2"=="BM_FINDRE" goto BM_FINDRE
if /i "%~2"=="BM_NOELAM" goto BM_NOELAM
if /i "%~2"=="BM_NORESTART" goto BM_NORESTART
if /i "%~2"=="BM_NOSIG" goto BM_NOSIG
if /i "%~2"=="BM_RESET" goto BM_RESET
if /i "%~2"=="BM_SAFE_CMD" goto BM_SAFE_CMD
if /i "%~2"=="BM_SAFE_MIN" goto BM_SAFE_MIN
if /i "%~2"=="BM_SAFE_NET" goto BM_SAFE_NET
if /i "%~2"=="BM_SHOW" goto BM_SHOW
if /i "%~2"=="BM_VGA" goto BM_VGA
if /i "%~2"=="BM_WINRE" goto BM_WINRE
if /i "%~2"=="BOOT_AUTO" goto BOOT_AUTO
if /i "%~2"=="BOOT_BIOS" goto BOOT_BIOS
if /i "%~2"=="BOOT_ESP" goto BOOT_ESP
if /i "%~2"=="BOOT_SECT" goto BOOT_SECT
if /i "%~2"=="BOOT_UEFI" goto BOOT_UEFI
if /i "%~2"=="DATA_ATTRIB" goto DATA_ATTRIB
if /i "%~2"=="DATA_MIRROR" goto DATA_MIRROR
if /i "%~2"=="DATA_OWN" goto DATA_OWN
if /i "%~2"=="DATA_RESCUE" goto DATA_RESCUE
if /i "%~2"=="DATA_ROBO" goto DATA_ROBO
if /i "%~2"=="DATA_XCOPY" goto DATA_XCOPY
if /i "%~2"=="DIAG_EVT" goto DIAG_EVT
if /i "%~2"=="DIAG_RECOVERY" goto DIAG_RECOVERY
if /i "%~2"=="DIAG_SRT" goto DIAG_SRT
if /i "%~2"=="DIAG_SYS" goto DIAG_SYS
if /i "%~2"=="DISK_ASSIGN" goto DISK_ASSIGN
if /i "%~2"=="DISK_CHKDSK" goto DISK_CHKDSK
if /i "%~2"=="DISK_CLEAN" goto DISK_CLEAN
if /i "%~2"=="DISK_FORMAT" goto DISK_FORMAT
if /i "%~2"=="DISK_FSUTIL" goto DISK_FSUTIL
if /i "%~2"=="DISK_LIST" goto DISK_LIST
if /i "%~2"=="DISK_REMOVE" goto DISK_REMOVE
if /i "%~2"=="DISM_CHECK" goto DISM_CHECK
if /i "%~2"=="DISM_PKGS" goto DISM_PKGS
if /i "%~2"=="DISM_RESTORE" goto DISM_RESTORE
if /i "%~2"=="DISM_SCAN" goto DISM_SCAN
if /i "%~2"=="DISM_SOURCE" goto DISM_SOURCE
if /i "%~2"=="DRV_ADD" goto DRV_ADD
if /i "%~2"=="DRV_EXPORT" goto DRV_EXPORT
if /i "%~2"=="GUI_CHKDSK" goto GUI_CHKDSK
if /i "%~2"=="GUI_DETECT" goto GUI_DETECT
if /i "%~2"=="GUI_DRIVERQUERY" goto GUI_DRIVERQUERY
if /i "%~2"=="GUI_DRIVERS" goto GUI_DRIVERS
if /i "%~2"=="GUI_INIT" goto GUI_INIT
if /i "%~2"=="GUI_IP" goto GUI_IP
if /i "%~2"=="GUI_NETWORK" goto GUI_NETWORK
if /i "%~2"=="GUI_NOTEPAD" goto GUI_NOTEPAD
if /i "%~2"=="GUI_PING" goto GUI_PING
if /i "%~2"=="GUI_PNPUTIL" goto GUI_PNPUTIL
if /i "%~2"=="GUI_REGEDIT" goto GUI_REGEDIT
if /i "%~2"=="GUI_SCAN" goto GUI_SCAN
if /i "%~2"=="GUI_TASKMGR" goto GUI_TASKMGR
if /i "%~2"=="GUI_TRACE" goto GUI_TRACE
if /i "%~2"=="NET_DHCP" goto NET_DHCP
if /i "%~2"=="NET_MAP" goto NET_MAP
if /i "%~2"=="NET_STATIC" goto NET_STATIC
if /i "%~2"=="PASS_RESET" goto PASS_RESET
if /i "%~2"=="PASS_RESTORE" goto PASS_RESTORE
if /i "%~2"=="REG_LOAD" goto REG_LOAD
if /i "%~2"=="REG_UNLOAD" goto REG_UNLOAD
if /i "%~2"=="SFC_RUN" goto SFC_RUN
if /i "%~2"=="STOR_ASSIGN" goto STOR_ASSIGN
if /i "%~2"=="STOR_DETAIL" goto STOR_DETAIL
if /i "%~2"=="STOR_BITLOCKER" goto STOR_BITLOCKER
if /i "%~2"=="STOR_DRIVER" goto STOR_DRIVER
if /i "%~2"=="STOR_ONLINE" goto STOR_ONLINE
echo Unknown recovery operation.
exit /b 2

:GUI_SCAN
call :STORAGE_INIT
call :DETECT_WINDOWS
echo Windows volume: !WINPART!
exit /b

:GUI_DETECT
call :DETECT_WINDOWS
echo Windows volume: !WINPART!
exit /b

:GUI_INIT
wpeinit
wpeutil InitializeNetwork
call :STORAGE_INIT
call :DETECT_WINDOWS
echo Windows volume: !WINPART!
exit /b

:GUI_CHKDSK
call :NEEDWIN
if defined WINPART chkdsk !WINPART! /F
exit /b

:GUI_DRIVERS
call :NEEDWIN
if defined WINPART dism /Image:!WINPART!\ /Get-Drivers
exit /b

:GUI_PNPUTIL
pnputil /enum-drivers
exit /b

:GUI_REGEDIT
start "" %SystemRoot%\regedit.exe
exit /b

:GUI_NOTEPAD
start "" notepad.exe
exit /b

:GUI_TASKMGR
start "" taskmgr.exe
exit /b

:GUI_IP
ipconfig /all
exit /b

:GUI_NETWORK
wpeutil InitializeNetwork
exit /b

:GUI_PING
call :PCHH_READ host "Host to ping: "
ping !host!
exit /b

:GUI_TRACE
call :PCHH_READ host "Host to trace: "
tracert !host!
exit /b

:PCHH_PAUSE
if defined PCHH_JOB exit /b
pause
exit /b

:PCHH_READ
if not defined PCHH_JOB (
    set /p "%~1=%~2"
    exit /b
)
set /a PCHH_REQUEST+=1
set "PCHH_PROMPT=%~2"
> "!PCHH_JOB!\request.tmp" echo !PCHH_REQUEST!
>> "!PCHH_JOB!\request.tmp" echo %~1
>> "!PCHH_JOB!\request.tmp" echo(!PCHH_PROMPT!
move /y "!PCHH_JOB!\request.tmp" "!PCHH_JOB!\request.txt" >nul
:PCHH_WAIT
if exist "!PCHH_JOB!\cancel" exit 1223
if not exist "!PCHH_JOB!\answer-!PCHH_REQUEST!.txt" (
    ping -n 2 127.0.0.1 >nul
    goto PCHH_WAIT
)
set "%~1="
< "!PCHH_JOB!\answer-!PCHH_REQUEST!.txt" set /p "%~1="
del "!PCHH_JOB!\answer-!PCHH_REQUEST!.txt" "!PCHH_JOB!\request.txt" >nul 2>&1
exit /b

:GUI_DRIVERQUERY
driverquery
exit /b

:NORMALIZE_BOOT_TARGET
set "BOOT_TARGET="
if /i "!l!"=="SYS" set "BOOT_TARGET=SYS"
if /i "!l!"=="ALL" set "BOOT_TARGET=ALL"
for %%d in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if /i "!l!"=="%%d" set "BOOT_TARGET=%%d:"
    if /i "!l!"=="%%d:" set "BOOT_TARGET=%%d:"
)
exit /b
