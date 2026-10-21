# PCHH USB Flasher

Elegant Windows tool to download and flash PCHH recovery image to USB drives.

## Features

- **Automatic Download**: Fetches the latest PCHH recovery image from GitHub
- **USB Detection**: Automatically detects all removable USB drives
- **Progress Animation**: Real-time download and write progress
- **Modern UI**: Clean dark theme with smooth animations
- **Safe Operation**: Confirms before erasing any data
- **Auto-Close**: Exits automatically after successful flash

## Requirements

- Windows 10 or later
- Administrator privileges
- USB drive (8GB+ recommended)
- Internet connection for downloading the image

## Usage

### Method 1: Command Launcher (Recommended)

1. **Right-click** `Launch-PCHHFlasher.cmd`
2. Select **"Run as Administrator"**
3. The GUI will open automatically

### Method 2: PowerShell Direct

1. Open **PowerShell as Administrator**
2. Navigate to this folder
3. Run: `.\PCHHFlasher.ps1`

### Method 3: Run from a terminal without downloading the script manually

Open **Windows PowerShell 5.1 as Administrator** (the Windows PowerShell profile
in Windows Terminal), then run:

```powershell
iex (Invoke-RestMethod 'https://raw.githubusercontent.com/Someonethatyouusedtoknow/pchhdiagnosticefi/main/tools/PCHHFlasher/PCHHFlasher.ps1')
```

This downloads and executes the script from `main`. Review the URL's script
before running it. The GUI still asks you to select a USB and confirm erasure.
The download requires a published GitHub release with an asset named
`pchh-usb.img`; committing the script alone does not publish that image.

### In the GUI

1. **Select your USB drive** from the dropdown
2. Click **"Refresh"** if your drive doesn't appear
3. Click **"Create Bootable USB"**
4. Confirm the warning (all data will be erased)
5. Wait for download and write to complete
6. Success! The drive is ready to use

## What It Does

1. **Downloads** the latest `pchh-usb.img` from GitHub releases
2. **Detects** all USB drives connected to your system
3. **Erases** the selected USB drive
4. **Writes** the PCHH recovery image byte-by-byte
5. **Verifies** the write completed successfully
6. **Cleans up** temporary files

## Configuration

Edit the `$ImageUrl` variable in `PCHHFlasher.ps1` to point to your release:

```powershell
$ImageUrl = "https://github.com/Someonethatyouusedtoknow/pchhdiagnosticefi/releases/latest/download/pchh-usb.img"
```

## Screenshots

The interface features:
- **Dark theme** matching PCHH branding
- **Live progress bars** for download and write operations
- **Clear warnings** before destructive operations
- **Success animation** with auto-close

## Troubleshooting

### "No USB drives detected"

- Ensure the USB drive is plugged in
- Click the **"Refresh"** button
- Try a different USB port
- Check if the drive appears in Windows Disk Management

### "Access Denied" errors

- Make sure you're running as **Administrator**
- Close any programs that might be accessing the USB drive
- Safely eject and re-insert the USB drive

### Download fails

- Check your internet connection
- Verify the `$ImageUrl` is correct
- Check if GitHub is accessible from your network

## Technical Details

- Uses **System.Net.WebClient** for HTTP downloads
- Writes raw disk images using **FileStream** to `\\.\PhysicalDrive#`
- Progress updates every 4MB chunk written
- Automatically cleans up temporary files after completion
- Built with **Windows Forms** for native Windows GUI

## License

Part of the PCHH Recovery Environment project.
