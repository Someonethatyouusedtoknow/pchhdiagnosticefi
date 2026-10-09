@echo off
REM ===========================================================================
REM  PCHH - Windows PE Advanced Repair Environment
REM  Auto-launched by winpeshl -> cmd -> startnet.cmd on every PE boot.
REM
REM  Built for Windows PE amd64 build 26100 (Win11 24H2). Uses ONLY tools
REM  confirmed present in this PE image. Deliberately avoids: bootrec, wmic,
REM  systeminfo, powershell, timeout, choice, tasklist/taskkill, shutdown.
REM  Delays use ping; waits use pause; prompts use set /p.
REM ===========================================================================

setlocal enabledelayedexpansion
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

REM First-run guidance: if no Windows is visible, send the user to Storage Setup
REM instead of the full menu, so they can rescan / online / assign / load drivers.
if not defined WINPART goto MENU_STORAGE
goto MAINMENU

REM =============================================================================
REM  Helpers
REM =============================================================================
:DELAY
REM %1 = seconds
ping -n %~1 127.0.0.1 >nul 2>&1
goto :eof

:DETECT_WINDOWS
set "WINPART="
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist %%d:\Windows\System32\ntoskrnl.exe (
        if not defined WINPART set "WINPART=%%d:"
    )
)
goto :eof

:STORAGE_INIT
REM 1) First pass: mount what is already visible (incl. this USB and its
REM    \drivers\ folder) and give every volume a drive letter.
echo   Scanning disks and bringing volumes online...
call :STOR_RESCAN
REM 2) Auto-load storage drivers from any \drivers\ folder. The USB stays
REM    readable even when a RAID/Intel VMD NVMe is invisible, so loading its
REM    driver here makes the hidden disk appear - no menu digging required.
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist %%d:\drivers\ (
        for /r "%%d:\drivers" %%i in (*.inf) do drvload "%%i" >nul 2>&1
    )
)
REM 3) Second pass: re-enumerate so disks revealed by the new drivers mount
REM    and receive drive letters too.
call :STOR_RESCAN
goto :eof

:STOR_RESCAN
REM rescan + automount + assign a letter to every mountable volume (0..31).
REM All non-destructive; 'noerr' keeps the diskpart script going past gaps.
> "%TEMP%\pchh_stor.txt" (
    echo rescan
    echo automount enable
    for /L %%v in (0,1,31) do (
        echo select volume %%v noerr
        echo assign noerr
    )
    echo exit
)
diskpart /s "%TEMP%\pchh_stor.txt" >nul 2>&1
del "%TEMP%\pchh_stor.txt" >nul 2>&1
goto :eof

:NEEDWIN
REM Ensure WINPART is set, prompt if not. Returns with WINPART defined or empty.
if defined WINPART goto :eof
echo.
echo   No Windows installation was auto-detected.
set /p "WINPART=  Enter the Windows drive letter (e.g. C:) or leave blank to cancel: "
goto :eof

:LOCATE_BCD
REM Find the installed Windows boot store (ESP \EFI\... for UEFI, \Boot\ for BIOS).
REM Sets BCDSTORE to the full path, or leaves it empty / prompts.
set "BCDSTORE="
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if not defined BCDSTORE if exist %%d:\EFI\Microsoft\Boot\BCD set "BCDSTORE=%%d:\EFI\Microsoft\Boot\BCD"
)
if not defined BCDSTORE for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
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
set /p "BCDSTORE=  Full path to the BCD file (blank to cancel): "
goto :eof

REM =============================================================================
REM  MAIN MENU
REM =============================================================================
:MAINMENU
cls
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
set /p "choice=  Select a category: "
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
cls
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
set /p "d=  Select: "
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
cls
echo  ===== DISKS =====
(echo list disk) | diskpart
echo.
echo  ===== VOLUMES =====
(echo list volume) | diskpart
echo.
pause
goto MENU_DISK

:DISK_ASSIGN
cls
(echo list volume) | diskpart
echo.
set /p "v=  Volume number to assign: "
set /p "l=  Drive letter to assign (e.g. E): "
(echo select volume !v! ^& echo assign letter=!l! ^& echo exit) | diskpart
echo.
pause
goto MENU_DISK

:DISK_REMOVE
cls
(echo list volume) | diskpart
echo.
set /p "v=  Volume number: "
set /p "l=  Drive letter to remove (e.g. E): "
(echo select volume !v! ^& echo remove letter=!l! ^& echo exit) | diskpart
echo.
pause
goto MENU_DISK

:DISK_FORMAT
cls
(echo list volume) | diskpart
echo.
set /p "v=  Volume number to FORMAT (blank to cancel): "
if "!v!"=="" goto MENU_DISK
set /p "fs=  Filesystem [NTFS/FAT32/exFAT] (default NTFS): "
if "!fs!"=="" set "fs=NTFS"
set /p "lbl=  Volume label (optional): "
echo.
echo   WARNING: This ERASES ALL DATA on volume !v!.
set /p "ok=  Type YES to confirm: "
if /i not "!ok!"=="YES" goto MENU_DISK
(echo select volume !v! ^& echo format fs=!fs! label="!lbl!" quick ^& echo exit) | diskpart
echo.
pause
goto MENU_DISK

:DISK_CLEAN
cls
echo  GUIDED CLEAN + REPARTITION  (DESTROYS the selected disk)
echo.
(echo list disk) | diskpart
echo.
set /p "dk=  Disk number to wipe (blank to cancel): "
if "!dk!"=="" goto MENU_DISK
echo.
echo   Choose new layout:
echo     [1] GPT  (UEFI)  - creates 100MB EFI + MSR + Windows NTFS
echo     [2] MBR  (Legacy BIOS) - single active NTFS partition
set /p "ly=  Layout: "
echo.
echo   WARNING: ALL DATA on disk !dk! will be destroyed.
set /p "ok=  Type ERASE to confirm: "
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
pause
goto MENU_DISK

:DISK_CHKDSK
cls
(echo list volume) | diskpart
echo.
set /p "l=  Drive letter to check (e.g. C): "
echo.
echo    [1] Read-only scan        [2] Fix errors (/F)
echo    [3] Fix + recover sectors (/F /R)     [4] Force dismount (/F /X)
set /p "m=  Mode: "
echo.
if "!m!"=="1" chkdsk !l!:
if "!m!"=="2" chkdsk !l!: /F
if "!m!"=="3" chkdsk !l!: /F /R
if "!m!"=="4" chkdsk !l!: /F /X
echo.
pause
goto MENU_DISK

:DISK_FSUTIL
cls
set /p "l=  Drive letter (e.g. C): "
echo.
echo  --- Volume information ---
fsutil fsinfo volumeinfo !l!:
echo.
echo  --- Dirty bit ---
fsutil dirty query !l!:
echo.
pause
goto MENU_DISK

REM =============================================================================
REM  B. BOOT REPAIR
REM =============================================================================
:MENU_BOOT
cls
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
set /p "b=  Select: "
if "!b!"=="1" goto BOOT_AUTO
if "!b!"=="2" goto BOOT_UEFI
if "!b!"=="3" goto BOOT_BIOS
if "!b!"=="4" goto BOOT_ESP
if "!b!"=="5" goto BOOT_BCDEDIT
if "!b!"=="6" goto BOOT_SECT
if "!b!"=="0" goto MAINMENU
goto MENU_BOOT

:BOOT_AUTO
cls
echo  AUTOMATIC BOOT REPAIR
echo.
call :DETECT_WINDOWS
call :NEEDWIN
if not defined WINPART goto MENU_BOOT
echo   Using Windows at: !WINPART!\Windows
echo.
echo   Looking for an EFI System Partition...
set "ESP="
(echo list volume) | diskpart | findstr /i "FAT32 System"
echo.
set /p "ESP=  Enter the drive letter of the EFI/System partition, or blank for Legacy BIOS: "
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
pause
goto MENU_BOOT

:BOOT_UEFI
cls
call :NEEDWIN
if not defined WINPART goto MENU_BOOT
echo.
echo   The EFI partition is usually ~100MB FAT32. Assign it a letter first
echo   (Disk menu - Assign) if it has none.
set /p "ESP=  EFI/System partition drive letter (e.g. S): "
echo.
bcdboot !WINPART!\Windows /s !ESP!: /f UEFI
echo.
pause
goto MENU_BOOT

:BOOT_BIOS
cls
call :NEEDWIN
if not defined WINPART goto MENU_BOOT
echo.
echo   Writing NT60 boot code and BIOS BCD to !WINPART! ...
bootsect /nt60 !WINPART! /force /mbr
bcdboot !WINPART!\Windows /s !WINPART! /f BIOS
echo.
pause
goto MENU_BOOT

:BOOT_ESP
cls
echo  RECREATE / REPAIR EFI SYSTEM PARTITION
echo.
echo   This assigns letter S: to an existing EFI partition and reformats it,
echo   then reinstalls the UEFI bootloader. Your Windows partition is NOT touched.
echo.
(echo list volume) | diskpart
echo.
set /p "ev=  Volume number of the EFI System Partition (blank to cancel): "
if "!ev!"=="" goto MENU_BOOT
call :NEEDWIN
if not defined WINPART goto MENU_BOOT
echo.
echo   WARNING: the EFI partition will be reformatted (FAT32).
set /p "ok=  Type YES to confirm: "
if /i not "!ok!"=="YES" goto MENU_BOOT
(echo select volume !ev! ^& echo assign letter=S ^& echo format fs=fat32 quick ^& echo exit) | diskpart
bcdboot !WINPART!\Windows /s S: /f UEFI
echo.
echo   EFI partition rebuilt.
echo.
pause
goto MENU_BOOT

:BOOT_BCDEDIT
cls
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
cls
set /p "l=  Volume to write NT60 boot code to (e.g. C or ALL): "
bootsect /nt60 !l! /force
echo.
pause
goto MENU_BOOT

REM =============================================================================
REM  C. SYSTEM FILE & IMAGE REPAIR
REM =============================================================================
:MENU_SFC
cls
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
set /p "c=  Select: "
if "!c!"=="1" goto SFC_RUN
if "!c!"=="2" goto DISM_CHECK
if "!c!"=="3" goto DISM_SCAN
if "!c!"=="4" goto DISM_RESTORE
if "!c!"=="5" goto DISM_SOURCE
if "!c!"=="6" goto DISM_PKGS
if "!c!"=="7" ( call :NEEDWIN & if defined WINPART ( chkdsk !WINPART! /F & pause ) & goto MENU_SFC )
if "!c!"=="0" goto MAINMENU
goto MENU_SFC

:SFC_RUN
cls
call :NEEDWIN
if not defined WINPART goto MENU_SFC
echo   Running SFC against !WINPART!\Windows  (this can take a while)...
echo.
sfc /scannow /offbootdir=!WINPART!\ /offwindir=!WINPART!\Windows
echo.
pause
goto MENU_SFC

:DISM_CHECK
cls
call :NEEDWIN
if not defined WINPART goto MENU_SFC
dism /Image:!WINPART!\ /Cleanup-Image /CheckHealth
echo.
pause
goto MENU_SFC

:DISM_SCAN
cls
call :NEEDWIN
if not defined WINPART goto MENU_SFC
dism /Image:!WINPART!\ /Cleanup-Image /ScanHealth
echo.
pause
goto MENU_SFC

:DISM_RESTORE
cls
call :NEEDWIN
if not defined WINPART goto MENU_SFC
echo   Attempting online RestoreHealth (needs network)...
dism /Image:!WINPART!\ /Cleanup-Image /RestoreHealth
echo.
pause
goto MENU_SFC

:DISM_SOURCE
cls
call :NEEDWIN
if not defined WINPART goto MENU_SFC
echo   Provide a source, e.g.  D:\sources\install.wim:1  or  esd:D:\sources\install.esd:1
set /p "src=  Source: "
dism /Image:!WINPART!\ /Cleanup-Image /RestoreHealth /Source:!src! /LimitAccess
echo.
pause
goto MENU_SFC

:DISM_PKGS
cls
call :NEEDWIN
if not defined WINPART goto MENU_SFC
dism /Image:!WINPART!\ /Get-Packages
echo.
pause
goto MENU_SFC

REM =============================================================================
REM  D. REGISTRY & USER ACCOUNTS
REM =============================================================================
:MENU_REG
cls
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
set /p "r=  Select: "
if "!r!"=="1" goto REG_LOAD
if "!r!"=="2" ( start "" %SystemRoot%\regedit.exe & goto MENU_REG )
if "!r!"=="3" goto REG_UNLOAD
if "!r!"=="4" goto PASS_RESET
if "!r!"=="5" goto PASS_RESTORE
if "!r!"=="0" goto MAINMENU
goto MENU_REG

:REG_LOAD
cls
call :NEEDWIN
if not defined WINPART goto MENU_REG
echo.
echo    Which hive?
echo     [1] SYSTEM     [2] SOFTWARE     [3] SAM     [4] SECURITY     [5] DEFAULT
set /p "h=  Hive: "
set "HP="
if "!h!"=="1" set "HP=!WINPART!\Windows\System32\config\SYSTEM"   & set "HN=OFF_SYSTEM"
if "!h!"=="2" set "HP=!WINPART!\Windows\System32\config\SOFTWARE" & set "HN=OFF_SOFTWARE"
if "!h!"=="3" set "HP=!WINPART!\Windows\System32\config\SAM"      & set "HN=OFF_SAM"
if "!h!"=="4" set "HP=!WINPART!\Windows\System32\config\SECURITY" & set "HN=OFF_SECURITY"
if "!h!"=="5" set "HP=!WINPART!\Windows\System32\config\DEFAULT"  & set "HN=OFF_DEFAULT"
if not defined HP goto MENU_REG
reg load HKLM\!HN! "!HP!"
if errorlevel 1 ( echo   Failed to load hive. & pause & goto MENU_REG )
echo.
echo   Loaded as HKLM\!HN!  -- edit it under that key in RegEdit.
echo   IMPORTANT: unload it (option 3) before rebooting, choosing key !HN!.
start "" %SystemRoot%\regedit.exe
pause
goto MENU_REG

:REG_UNLOAD
cls
echo   Loaded offline hives:
reg query HKLM 2>nul | findstr /i "OFF_"
echo.
set /p "hn=  Hive key to unload (e.g. OFF_SYSTEM): "
if "!hn!"=="" goto MENU_REG
reg unload HKLM\!hn!
echo.
pause
goto MENU_REG

:PASS_RESET
cls
call :NEEDWIN
if not defined WINPART goto MENU_REG
echo.
echo   This backs up Utilman.exe and replaces it with cmd.exe on the offline
echo   Windows. At the Windows logon screen, click the Ease of Access button
echo   (bottom-right) to open a SYSTEM command prompt, then run:
echo         net user ^<username^> ^<newpassword^>
echo         net user ^<username^> *            (to be prompted, or set blank)
echo.
set /p "ok=  Proceed with the swap on !WINPART!? Type YES: "
if /i not "!ok!"=="YES" goto MENU_REG
set "U=!WINPART!\Windows\System32\utilman.exe"
set "C=!WINPART!\Windows\System32\cmd.exe"
takeown /f "!U!" >nul 2>&1
icacls "!U!" /grant Administrators:F >nul 2>&1
if not exist "!U!.pchhbak" copy /y "!U!" "!U!.pchhbak" >nul
copy /y "!C!" "!U!" >nul
if errorlevel 1 ( echo   Swap failed - check the drive is writable. ) else ( echo   Done. Reboot into Windows and use the Ease of Access button. )
echo.
pause
goto MENU_REG

:PASS_RESTORE
cls
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
pause
goto MENU_REG

REM =============================================================================
REM  E. DRIVER MANAGEMENT
REM =============================================================================
:MENU_DRV
cls
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
set /p "e=  Select: "
if "!e!"=="1" ( set /p "inf=  Path to .inf: " & drvload "!inf!" & pause & goto MENU_DRV )
if "!e!"=="2" goto DRV_ADD
if "!e!"=="3" goto DRV_EXPORT
if "!e!"=="4" ( call :NEEDWIN & if defined WINPART ( dism /Image:!WINPART!\ /Get-Drivers & pause ) & goto MENU_DRV )
if "!e!"=="5" ( pnputil /enum-drivers & pause & goto MENU_DRV )
if "!e!"=="0" goto MAINMENU
goto MENU_DRV

:DRV_ADD
cls
call :NEEDWIN
if not defined WINPART goto MENU_DRV
set /p "dp=  Folder containing drivers (searched recursively): "
dism /Image:!WINPART!\ /Add-Driver /Driver:"!dp!" /Recurse /ForceUnsigned
echo.
pause
goto MENU_DRV

:DRV_EXPORT
cls
call :NEEDWIN
if not defined WINPART goto MENU_DRV
set /p "dp=  Destination folder for exported drivers: "
if not exist "!dp!" md "!dp!"
dism /Image:!WINPART!\ /Export-Driver /Destination:"!dp!"
echo.
pause
goto MENU_DRV

REM =============================================================================
REM  F. DATA RECOVERY, COPY & PERMISSIONS
REM =============================================================================
:MENU_DATA
cls
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
set /p "f=  Select: "
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
cls
set /p "s=  Source folder: "
set /p "d=  Destination folder: "
robocopy "!s!" "!d!" /E /COPY:DAT /R:2 /W:5 /TEE
echo.
pause
goto MENU_DATA

:DATA_XCOPY
cls
set /p "s=  Source: "
set /p "d=  Destination: "
xcopy "!s!" "!d!" /E /H /C /I /Y
echo.
pause
goto MENU_DATA

:DATA_MIRROR
cls
echo   WARNING: /MIR deletes files in the destination that are not in source.
set /p "s=  Source folder: "
set /p "d=  Destination folder: "
set /p "ok=  Type YES to mirror: "
if /i not "!ok!"=="YES" goto MENU_DATA
robocopy "!s!" "!d!" /MIR /R:2 /W:5 /TEE
echo.
pause
goto MENU_DATA

:DATA_RESCUE
cls
echo   Rescue mode: copies everything readable, skips bad files, lots of retries.
set /p "s=  Source (failing drive) folder: "
set /p "d=  Destination (good drive) folder: "
robocopy "!s!" "!d!" /E /COPY:DAT /R:1 /W:1 /XJ /NP /TEE /LOG:X:\pchh-rescue.log
echo.
echo   Log saved to X:\pchh-rescue.log
echo.
pause
goto MENU_DATA

:DATA_OWN
cls
set /p "p=  File or folder path: "
takeown /f "!p!" /r /d y
icacls "!p!" /grant Administrators:F /t /c
echo.
pause
goto MENU_DATA

:DATA_ATTRIB
cls
set /p "p=  File or folder path: "
echo.
echo    [1] Show attributes   [2] Clear hidden+system (unhide)   [3] Set hidden+system
set /p "m=  Mode: "
if "!m!"=="1" attrib "!p!"
if "!m!"=="2" attrib -h -s "!p!" /s /d
if "!m!"=="3" attrib +h +s "!p!" /s /d
echo.
pause
goto MENU_DATA

REM =============================================================================
REM  G. NETWORK TOOLS
REM =============================================================================
:MENU_NET
cls
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
set /p "g=  Select: "
if "!g!"=="1" ( wpeutil InitializeNetwork & echo. & pause & goto MENU_NET )
if "!g!"=="2" ( ipconfig /all & echo. & pause & goto MENU_NET )
if "!g!"=="3" ( set /p "h=  Host to ping: " & ping !h! & echo. & pause & goto MENU_NET )
if "!g!"=="4" ( set /p "h=  Host to trace: " & tracert !h! & echo. & pause & goto MENU_NET )
if "!g!"=="5" goto NET_MAP
if "!g!"=="6" goto NET_STATIC
if "!g!"=="7" goto NET_DHCP
if "!g!"=="0" goto MAINMENU
goto MENU_NET

:NET_MAP
cls
set /p "unc=  Share path (e.g. \\server\share): "
set /p "dl=  Drive letter to map (e.g. Z): "
set /p "us=  Username (blank for none): "
if "!us!"=="" ( net use !dl!: "!unc!" ) else ( net use !dl!: "!unc!" /user:!us! * )
echo.
pause
goto MENU_NET

:NET_STATIC
cls
echo   Available interfaces:
netsh interface show interface
echo.
set /p "nm=  Interface name (e.g. Ethernet): "
set /p "ip=  IP address: "
set /p "mk=  Subnet mask: "
set /p "gw=  Gateway: "
netsh interface ip set address name="!nm!" static !ip! !mk! !gw!
set /p "dns=  DNS server (blank to skip): "
if not "!dns!"=="" netsh interface ip set dns name="!nm!" static !dns!
echo.
pause
goto MENU_NET

:NET_DHCP
cls
echo   Available interfaces:
netsh interface show interface
echo.
set /p "nm=  Interface name (e.g. Ethernet): "
netsh interface ip set address name="!nm!" dhcp
netsh interface ip set dns name="!nm!" dhcp
ipconfig /renew
echo.
pause
goto MENU_NET

REM =============================================================================
REM  H. DIAGNOSTICS & SYSTEM INFO
REM =============================================================================
:MENU_DIAG
cls
echo  ===================  DIAGNOSTICS ^& SYSTEM INFO  =========================
echo.
echo    [1]  System summary  ^(CPU / BIOS / board from registry^)
echo    [2]  Disk overview  ^(diskpart^)
echo    [3]  Network summary  ^(ipconfig^)
echo    [4]  Windows Event Log query  ^(wevtutil^)
echo    [5]  Installed driver list  ^(driverquery^)
echo    [6]  Open Task Manager
echo.
echo    [0]  Back to main menu
echo  --------------------------------------------------------------------------
set "h="
set /p "h=  Select: "
if "!h!"=="1" goto DIAG_SYS
if "!h!"=="2" ( cls & (echo list disk ^& echo list volume) | diskpart & echo. & pause & goto MENU_DIAG )
if "!h!"=="3" ( cls & ipconfig /all & echo. & pause & goto MENU_DIAG )
if "!h!"=="4" goto DIAG_EVT
if "!h!"=="5" ( cls & driverquery & echo. & pause & goto MENU_DIAG )
if "!h!"=="6" ( start "" taskmgr.exe & goto MENU_DIAG )
if "!h!"=="0" goto MAINMENU
goto MENU_DIAG

:DIAG_SYS
cls
echo  ======================  SYSTEM SUMMARY  =================================
echo.
echo  --- Processor ---
reg query "HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\0" /v ProcessorNameString 2>nul | findstr /i "ProcessorNameString"
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
pause
goto MENU_DIAG

:DIAG_EVT
cls
call :NEEDWIN
if not defined WINPART goto MENU_DIAG
echo   Querying the offline System event log for the 30 most recent errors...
echo.
wevtutil qe "!WINPART!\Windows\System32\winevt\Logs\System.evtx" /lf:true /c:30 /rd:true /f:text /q:"*[System[(Level=1 or Level=2)]]"
echo.
pause
goto MENU_DIAG

REM =============================================================================
REM  I. UTILITIES
REM =============================================================================
:MENU_UTIL
cls
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
set /p "u=  Select: "
if "!u!"=="1" ( start "PCHH CMD" cmd & goto MENU_UTIL )
if "!u!"=="2" ( start "" notepad.exe & goto MENU_UTIL )
if "!u!"=="3" ( start "" taskmgr.exe & goto MENU_UTIL )
if "!u!"=="4" ( start "" %SystemRoot%\regedit.exe & goto MENU_UTIL )
if "!u!"=="5" ( call :DETECT_WINDOWS & echo   Detected: !WINPART! & call :DELAY 2 & goto MENU_UTIL )
if "!u!"=="6" goto UTIL_SIZE
if "!u!"=="0" goto MAINMENU
goto MENU_UTIL

:UTIL_SIZE
cls
echo    [1] 80x25    [2] 100x48    [3] 120x50
set /p "z=  Size: "
if "!z!"=="1" mode con: cols=80 lines=25
if "!z!"=="2" mode con: cols=100 lines=48
if "!z!"=="3" mode con: cols=120 lines=50
goto MENU_UTIL

REM =============================================================================
REM  J. STARTUP SETTINGS & RECOVERY ENVIRONMENT
REM     All options write to the INSTALLED Windows boot store (not this PE).
REM =============================================================================
:MENU_BOOTMODE
cls
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
set /p "j=  Select: "
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
cls
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
bcdedit /store "!BCDSTORE!" /set {bootmgr} displaybootmenu Yes
bcdedit /store "!BCDSTORE!" /set {default} bootmenupolicy Legacy
echo.
echo   Legacy F8 menu enabled. Tap F8 right after power-on to pick a startup mode.
echo.
pause
goto MENU_BOOTMODE

:BM_SAFE_MIN
cls
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
bcdedit /store "!BCDSTORE!" /deletevalue {default} safebootalternateshell >nul 2>&1
bcdedit /store "!BCDSTORE!" /set {default} safeboot Minimal
echo.
echo   Next boot will enter Safe Mode. Use [10] to return to normal.
echo.
pause
goto MENU_BOOTMODE

:BM_SAFE_NET
cls
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
bcdedit /store "!BCDSTORE!" /deletevalue {default} safebootalternateshell >nul 2>&1
bcdedit /store "!BCDSTORE!" /set {default} safeboot Network
echo.
echo   Next boot will enter Safe Mode with Networking. Use [10] to undo.
echo.
pause
goto MENU_BOOTMODE

:BM_SAFE_CMD
cls
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
bcdedit /store "!BCDSTORE!" /set {default} safeboot Minimal
bcdedit /store "!BCDSTORE!" /set {default} safebootalternateshell Yes
echo.
echo   Next boot will enter Safe Mode with Command Prompt. Use [10] to undo.
echo.
pause
goto MENU_BOOTMODE

:BM_BOOTLOG
cls
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
bcdedit /store "!BCDSTORE!" /set {default} bootlog Yes
echo.
echo   Boot logging enabled -> %%SystemRoot%%\ntbtlog.txt after next boot.
echo.
pause
goto MENU_BOOTMODE

:BM_VGA
cls
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
bcdedit /store "!BCDSTORE!" /set {default} vga On
echo.
echo   Low-resolution video enabled for next boot. Use [10] to undo.
echo.
pause
goto MENU_BOOTMODE

:BM_NOSIG
cls
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
bcdedit /store "!BCDSTORE!" /set {default} nointegritychecks Yes
bcdedit /store "!BCDSTORE!" /set {default} loadoptions DDISABLE_INTEGRITY_CHECKS >nul 2>&1
echo.
echo   Driver signature enforcement disabled.
echo   NOTE: ignored while UEFI Secure Boot is ON - disable Secure Boot in
echo   firmware if unsigned drivers still refuse to load. Use [10] to undo.
echo.
pause
goto MENU_BOOTMODE

:BM_NOELAM
cls
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
bcdedit /store "!BCDSTORE!" /set {default} disableelamdrivers Yes
echo.
echo   Early-launch anti-malware drivers disabled for next boot. Use [10] to undo.
echo.
pause
goto MENU_BOOTMODE

:BM_NORESTART
cls
echo  DISABLE AUTOMATIC RESTART ON SYSTEM FAILURE
echo.
echo   This lets you read a STOP/BSOD code instead of the PC rebooting instantly.
echo   It is stored in the SYSTEM registry hive of the installed Windows.
call :NEEDWIN
if not defined WINPART goto MENU_BOOTMODE
reg load HKLM\OFF_SYS "!WINPART!\Windows\System32\config\SYSTEM" >nul 2>&1
if errorlevel 1 ( echo   Could not load SYSTEM hive. & pause & goto MENU_BOOTMODE )
reg add "HKLM\OFF_SYS\ControlSet001\Control\CrashControl" /v AutoReboot /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\OFF_SYS\ControlSet002\Control\CrashControl" /v AutoReboot /t REG_DWORD /d 0 /f >nul 2>&1
reg unload HKLM\OFF_SYS >nul 2>&1
echo.
echo   Automatic restart on failure disabled. The next BSOD will stay on screen.
echo.
pause
goto MENU_BOOTMODE

:BM_RESET
cls
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
pause
goto MENU_BOOTMODE

:BM_WINRE
cls
echo  BOOT THE INSTALLED WINDOWS RECOVERY ENVIRONMENT (WinRE)
echo.
echo   This points the installed PC's boot manager at its own recovery image
echo   for the next restart, giving you Troubleshoot - Startup Repair,
echo   System Restore, Reset this PC, and the WinRE command prompt.
echo.
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
set "RSEQ="
for /f "tokens=1,*" %%a in ('bcdedit /store "!BCDSTORE!" /enum {default} 2^>nul ^| findstr /i "recoverysequence"') do set "RSEQ=%%b"
REM Trim spaces
for /f "tokens=* delims= " %%a in ("!RSEQ!") do set "RSEQ=%%a"
if not defined RSEQ (
    echo.
    echo   No recovery sequence is configured on this install - WinRE may be
    echo   disabled or missing. You can still use this menu's Boot Repair, SFC
    echo   and DISM options, which cover most of what Startup Repair does.
    echo.
    pause
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
pause
goto MENU_BOOTMODE

:BM_SHOW
cls
call :LOCATE_BCD
if not defined BCDSTORE goto MENU_BOOTMODE
echo  ===== {bootmgr} =====
bcdedit /store "!BCDSTORE!" /enum {bootmgr}
echo.
echo  ===== {default} OS loader =====
bcdedit /store "!BCDSTORE!" /enum {default}
echo.
pause
goto MENU_BOOTMODE

:BM_FINDRE
cls
echo  SEARCHING FOR WinRE IMAGES (Winre.wim) ...
echo.
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist %%d:\Recovery\WindowsRE\Winre.wim echo   Found: %%d:\Recovery\WindowsRE\Winre.wim
    if exist %%d:\Windows\System32\Recovery\Winre.wim echo   Found: %%d:\Windows\System32\Recovery\Winre.wim
    if exist %%d:\Recovery\Winre.wim echo   Found: %%d:\Recovery\Winre.wim
)
echo.
echo   (Recovery partitions are often unlettered; assign a letter via the Disk
echo    menu to see their contents. Option [11] boots WinRE without needing this.)
echo.
pause
goto MENU_BOOTMODE

REM =============================================================================
REM  STORAGE SETUP / DISK DETECTION  (first-run + recovery from "no volumes")
REM =============================================================================
:MENU_STORAGE
cls
echo  =============  STORAGE SETUP  /  DISK DETECTION   (START HERE)  =========
echo.
echo   DISKS:
(echo list disk) | diskpart | findstr /i /c:"Disk "
echo.
echo   VOLUMES:
(echo list volume) | diskpart | findstr /i /c:"Volume "
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
echo.
echo   TIP: "No disks at all" almost always means Intel RST / VMD / RAID is ON
echo        in BIOS. Load its driver with [4] ^(iaStorVD.inf / iaStorAC.inf from
echo        another USB^), or in BIOS/UEFI set SATA or VMD mode to AHCI.
echo        Changing BIOS to AHCI can stop Windows booting until repaired -- the
echo        driver route is safer.
echo  --------------------------------------------------------------------------
set "s="
set /p "s=  Select: "
if "!s!"=="1" ( call :STORAGE_INIT & goto MENU_STORAGE )
if "!s!"=="2" goto STOR_ONLINE
if "!s!"=="3" goto STOR_ASSIGN
if "!s!"=="4" goto STOR_DRIVER
if "!s!"=="5" goto STOR_DETAIL
if "!s!"=="6" goto MAINMENU
goto MENU_STORAGE

:STOR_ONLINE
cls
(echo list disk) | diskpart
echo.
set /p "dk=  Disk number to bring ONLINE (blank to cancel): "
if "!dk!"=="" goto MENU_STORAGE
(echo select disk !dk! noerr ^& echo online disk noerr ^& echo attributes disk clear readonly noerr ^& echo exit) | diskpart
echo.
echo   Done. Rescanning...
call :STORAGE_INIT
pause
goto MENU_STORAGE

:STOR_ASSIGN
cls
(echo list volume) | diskpart
echo.
set /p "v=  Volume number (blank to cancel): "
if "!v!"=="" goto MENU_STORAGE
set /p "l=  Drive letter to assign (e.g. C): "
(echo select volume !v! noerr ^& echo assign letter=!l! noerr ^& echo exit) | diskpart
echo.
pause
goto MENU_STORAGE

:STOR_DRIVER
cls
echo  LOAD A STORAGE DRIVER INTO THIS PE
echo.
echo   Needed when the disk controller is in RAID / Intel RST / VMD mode and no
echo   disks appear. Put the extracted driver (its .inf + .sys) on another USB
echo   stick or the PCHH_DATA partition, then give the full path to the .inf.
echo.
echo   Current volumes (to find your driver's drive letter):
(echo list volume) | diskpart | findstr /i /c:"Volume "
echo.
set /p "inf=  Full path to the .inf (blank to cancel): "
if "!inf!"=="" goto MENU_STORAGE
drvload "!inf!"
echo.
echo   Rescanning storage...
call :STORAGE_INIT
call :DETECT_WINDOWS
if defined WINPART ( echo   Success - Windows now visible at !WINPART! ) else ( echo   Still no Windows volume - check the driver matches this controller. )
echo.
pause
goto MENU_STORAGE

:STOR_DETAIL
cls
(echo list disk ^& echo list volume) | diskpart
echo.
pause
goto MENU_STORAGE

REM =============================================================================
REM  System actions
REM =============================================================================
:DO_REBOOT
cls
echo   Rebooting...
wpeutil reboot
goto :eof

:DO_SHUTDOWN
cls
echo   Shutting down...
wpeutil shutdown
goto :eof

:DO_EXIT
cls
echo  ==========================================================================
echo   Exiting to the command prompt.
echo   Type  menu  to relaunch the PCHH repair menu, or  exit  to close.
echo  ==========================================================================
echo.
doskey menu=startnet.cmd
cmd /k
goto :eof
