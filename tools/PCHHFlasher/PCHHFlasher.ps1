# PCHH USB Flasher
# Elegant Windows tool to download and flash PCHH recovery image to USB

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Configuration
$ImageUrl = "https://github.com/Someonethatyouusedtoknow/pchhdiagnosticefi/releases/latest/download/pchh-usb.img"
$TempPath = "$env:TEMP\pchh-usb.img"

# Create main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "PCHH USB Flasher"
$form.Size = New-Object System.Drawing.Size(600, 450)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

# Header panel
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Size = New-Object System.Drawing.Size(600, 80)
$headerPanel.Location = New-Object System.Drawing.Point(0, 0)
$headerPanel.BackColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
$form.Controls.Add($headerPanel)

# Title label
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "PCHH Recovery USB Creator"
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(248, 250, 252)
$titleLabel.Location = New-Object System.Drawing.Point(30, 20)
$titleLabel.Size = New-Object System.Drawing.Size(540, 40)
$headerPanel.Controls.Add($titleLabel)

# Status label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Select a USB drive to create bootable PCHH recovery media"
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
$statusLabel.Location = New-Object System.Drawing.Point(30, 110)
$statusLabel.Size = New-Object System.Drawing.Size(540, 25)
$form.Controls.Add($statusLabel)

# USB drive dropdown
$usbLabel = New-Object System.Windows.Forms.Label
$usbLabel.Text = "Target USB Drive:"
$usbLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$usbLabel.ForeColor = [System.Drawing.Color]::FromArgb(248, 250, 252)
$usbLabel.Location = New-Object System.Drawing.Point(30, 150)
$usbLabel.Size = New-Object System.Drawing.Size(150, 25)
$form.Controls.Add($usbLabel)

# USB dropdown
$usbCombo = New-Object System.Windows.Forms.ComboBox
$usbCombo.Location = New-Object System.Drawing.Point(30, 180)
$usbCombo.Size = New-Object System.Drawing.Size(540, 25)
$usbCombo.DropDownStyle = "DropDownList"
$usbCombo.BackColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
$usbCombo.ForeColor = [System.Drawing.Color]::White
$usbCombo.FlatStyle = "Flat"
$form.Controls.Add($usbCombo)

# Progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(30, 230)
$progressBar.Size = New-Object System.Drawing.Size(540, 30)
$progressBar.Style = "Continuous"
$progressBar.Visible = $false
$form.Controls.Add($progressBar)

# Progress label
$progressLabel = New-Object System.Windows.Forms.Label
$progressLabel.Text = ""
$progressLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$progressLabel.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
$progressLabel.Location = New-Object System.Drawing.Point(30, 265)
$progressLabel.Size = New-Object System.Drawing.Size(540, 20)
$progressLabel.Visible = $false
$form.Controls.Add($progressLabel)

# Success icon
$successLabel = New-Object System.Windows.Forms.Label
$successLabel.Text = "USB drive created successfully!"
$successLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$successLabel.ForeColor = [System.Drawing.Color]::FromArgb(34, 211, 238)
$successLabel.Location = New-Object System.Drawing.Point(30, 230)
$successLabel.Size = New-Object System.Drawing.Size(540, 40)
$successLabel.TextAlign = "MiddleCenter"
$successLabel.Visible = $false
$form.Controls.Add($successLabel)

# Flash button
$flashButton = New-Object System.Windows.Forms.Button
$flashButton.Text = "Create Bootable USB"
$flashButton.Location = New-Object System.Drawing.Point(200, 320)
$flashButton.Size = New-Object System.Drawing.Size(200, 45)
$flashButton.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$flashButton.BackColor = [System.Drawing.Color]::FromArgb(56, 189, 248)
$flashButton.ForeColor = [System.Drawing.Color]::Black
$flashButton.FlatStyle = "Flat"
$flashButton.FlatAppearance.BorderSize = 0
$flashButton.Cursor = "Hand"
$form.Controls.Add($flashButton)

# Close button
$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = "Close"
$closeButton.Location = New-Object System.Drawing.Point(410, 320)
$closeButton.Size = New-Object System.Drawing.Size(160, 45)
$closeButton.Font = New-Object System.Drawing.Font("Segoe UI", 11)
$closeButton.BackColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
$closeButton.ForeColor = [System.Drawing.Color]::White
$closeButton.FlatStyle = "Flat"
$closeButton.FlatAppearance.BorderSize = 0
$closeButton.Cursor = "Hand"
$closeButton.Add_Click({ $form.Close() })
$form.Controls.Add($closeButton)

# Warning label
$warningLabel = New-Object System.Windows.Forms.Label
$warningLabel.Text = "WARNING: All data on the selected USB drive will be erased"
$warningLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$warningLabel.ForeColor = [System.Drawing.Color]::FromArgb(251, 146, 60)
$warningLabel.Location = New-Object System.Drawing.Point(30, 380)
$warningLabel.Size = New-Object System.Drawing.Size(540, 20)
$warningLabel.TextAlign = "MiddleCenter"
$form.Controls.Add($warningLabel)

# Function to get removable USB drives
function Get-RemovableDisks {
    try {
        $disks = Get-Disk | Where-Object { $_.BusType -eq 'USB' }
        $usbCombo.Items.Clear()

        foreach ($disk in $disks) {
            $sizeGB = [math]::Round($disk.Size / 1GB, 2)
            $friendlyName = $disk.FriendlyName
            if ([string]::IsNullOrWhiteSpace($friendlyName)) {
                $friendlyName = "USB Drive"
            }
            $itemText = "Disk " + $disk.Number + ": " + $friendlyName + " (" + $sizeGB + " GB)"
            $usbCombo.Items.Add($itemText) | Out-Null
        }

        if ($usbCombo.Items.Count -eq 0) {
            $usbCombo.Items.Add("No USB drives detected") | Out-Null
            $flashButton.Enabled = $false
        } else {
            $usbCombo.SelectedIndex = 0
            $flashButton.Enabled = $true
        }
    } catch {
        $usbCombo.Items.Clear()
        $usbCombo.Items.Add("Error: " + $_.Exception.Message) | Out-Null
        $flashButton.Enabled = $false
    }
}

# Function to download image
function Download-Image {
    param([string]$Url, [string]$Destination)

    $progressBar.Visible = $true
    $progressBar.Style = "Continuous"
    $progressBar.Value = 0
    $progressLabel.Visible = $true
    $progressLabel.Text = "Downloading PCHH recovery image..."
    $statusLabel.Text = "Downloading from GitHub..."
    $form.Refresh()

    $webClient = $null
    $partialPath = $Destination + ".part"
    $downloadState = @{ Completed = $false; Error = $null; Cancelled = $false }
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.add_DownloadProgressChanged({
            param($sender, $e)
            $progressBar.Value = $e.ProgressPercentage
            $mbReceived = [math]::Round($e.BytesReceived / 1MB, 2)
            $mbTotal = [math]::Round($e.TotalBytesToReceive / 1MB, 2)
            $pct = $e.ProgressPercentage
            $progressLabel.Text = "Downloaded $mbReceived MB / $mbTotal MB ($pct percent)"
            $form.Refresh()
        })
        $webClient.add_DownloadFileCompleted({
            param($sender, $e)
            $downloadState.Error = $e.Error
            $downloadState.Cancelled = $e.Cancelled
            $downloadState.Completed = $true
        })

        $webClient.DownloadFileAsync([uri]$Url, $partialPath)
        while (-not $downloadState.Completed) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }
        if ($downloadState.Error) {
            throw $downloadState.Error
        }
        if ($downloadState.Cancelled) {
            throw "The image download was cancelled."
        }
        if (-not (Test-Path -LiteralPath $partialPath -PathType Leaf)) {
            throw "The download did not create an image file."
        }
        if ((Get-Item -LiteralPath $partialPath -ErrorAction Stop).Length -le 0) {
            throw "The downloaded image is empty."
        }
        Move-Item -LiteralPath $partialPath -Destination $Destination -Force -ErrorAction Stop
        return $true
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show(
            "Failed to download image: " + $_.Exception.Message,
            "Download Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return $false
    } finally {
        if ($null -ne $webClient) {
            $webClient.Dispose()
        }
        Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
    }
}

# Function to flash USB
function Flash-USB {
    param([int]$DiskNumber, [string]$ImagePath)

    $statusLabel.Text = "Writing image to USB drive..."
    $progressLabel.Text = "Preparing disk..."
    $progressBar.Style = "Marquee"
    $form.Refresh()

    $sourceFile = $null
    $targetFile = $null
    try {
        # Open and validate the image before making any changes to the USB drive.
        $sourceFile = [System.IO.File]::OpenRead($ImagePath)
        $totalBytes = $sourceFile.Length
        if ($totalBytes -le 0) {
            throw "The image file is empty."
        }
        Clear-Disk -Number $DiskNumber -RemoveData -Confirm:$false -ErrorAction Stop
        $progressLabel.Text = "Writing image data..."
        $form.Refresh()

        $diskPath = "\\.\PhysicalDrive" + $DiskNumber
        $targetFile = [System.IO.File]::OpenWrite($diskPath)
        $buffer = New-Object byte[] (4MB)
        $bytesWritten = 0
        $progressBar.Style = "Continuous"
        $progressBar.Value = 0

        while (($bytesRead = $sourceFile.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $targetFile.Write($buffer, 0, $bytesRead)
            $bytesWritten += $bytesRead
            $percent = [math]::Round(($bytesWritten / $totalBytes) * 100)
            $progressBar.Value = [math]::Min($percent, 100)
            $mbWritten = [math]::Round($bytesWritten / 1MB, 2)
            $mbTotal = [math]::Round($totalBytes / 1MB, 2)
            $progressLabel.Text = "Written $mbWritten MB / $mbTotal MB ($percent percent)"
            $form.Refresh()
        }

        $targetFile.Flush()
        return $true
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show(
            "Failed to write image: " + $_.Exception.Message,
            "Write Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return $false
    } finally {
        if ($null -ne $targetFile) { $targetFile.Dispose() }
        if ($null -ne $sourceFile) { $sourceFile.Dispose() }
    }
}

# Flash button handler
$flashButton.Add_Click({
    if ($usbCombo.SelectedIndex -lt 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please select a USB drive",
            "No Drive Selected",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    $result = [System.Windows.Forms.MessageBox]::Show(
        "This will ERASE all data on the selected USB drive. Continue?",
        "Confirm",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    $flashButton.Enabled = $false
    $usbCombo.Enabled = $false
    $refreshButton.Enabled = $false
    $closeButton.Enabled = $false
    $form.ControlBox = $false

    $selection = $usbCombo.SelectedItem.ToString()
    $diskNumber = [int]($selection -replace '^Disk (\d+):.*', '$1')

    $downloaded = Download-Image -Url $ImageUrl -Destination $TempPath

    if ($downloaded -eq $true) {
        $flashed = Flash-USB -DiskNumber $diskNumber -ImagePath $TempPath

        if ($flashed -eq $true) {
            $progressBar.Visible = $false
            $progressLabel.Visible = $false
            $successLabel.Visible = $true
            $statusLabel.Text = "USB drive is ready to use!"
            $warningLabel.Visible = $false
            Remove-Item $TempPath -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            $form.Close()
        }
    }

    $flashButton.Enabled = $true
    $usbCombo.Enabled = $true
    $refreshButton.Enabled = $true
    $closeButton.Enabled = $true
    $form.ControlBox = $true
})

# Refresh button
$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = "Refresh Drives"
$refreshButton.Location = New-Object System.Drawing.Point(30, 320)
$refreshButton.Size = New-Object System.Drawing.Size(160, 45)
$refreshButton.Font = New-Object System.Drawing.Font("Segoe UI", 11)
$refreshButton.BackColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
$refreshButton.ForeColor = [System.Drawing.Color]::White
$refreshButton.FlatStyle = "Flat"
$refreshButton.FlatAppearance.BorderSize = 0
$refreshButton.Cursor = "Hand"
$refreshButton.Add_Click({ Get-RemovableDisks })
$form.Controls.Add($refreshButton)

# Initial load
Get-RemovableDisks

# Show form
[void]$form.ShowDialog()
