# PCHH USB Flasher
# Elegant Windows tool to download and flash PCHH recovery image to USB

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Configuration
$ImageUrl = "https://github.com/Someonethatyouusedtoknow/pchhdiagnosticefi/releases/download/Beta/pchh-usb.img"
$TempPath = "$env:TEMP\pchh-usb.img"

# Shared palette and controls. Keep the script self-contained for terminal launches.
[System.Windows.Forms.Application]::EnableVisualStyles()
$colors = @{
    Background = [System.Drawing.ColorTranslator]::FromHtml("#10151F")
    Surface = [System.Drawing.ColorTranslator]::FromHtml("#1A2230")
    Border = [System.Drawing.ColorTranslator]::FromHtml("#334155")
    Text = [System.Drawing.ColorTranslator]::FromHtml("#F1F5F9")
    Muted = [System.Drawing.ColorTranslator]::FromHtml("#A8B6CA")
    Accent = [System.Drawing.ColorTranslator]::FromHtml("#67E8F9")
    Warning = [System.Drawing.ColorTranslator]::FromHtml("#FCD38A")
    Success = [System.Drawing.ColorTranslator]::FromHtml("#86EFAC")
}

function Add-Text {
    param($Parent, [string]$Text, [int]$X, [int]$Y, [int]$Width,
        [int]$Height = 24, [float]$Size = 10, $Color = $colors.Text,
        [switch]$Bold)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, $Height)
    $style = [System.Drawing.FontStyle]::Regular
    if ($Bold) { $style = [System.Drawing.FontStyle]::Bold }
    $label.Font = New-Object System.Drawing.Font("Segoe UI", $Size, $style)
    $label.ForeColor = $Color
    $Parent.Controls.Add($label)
    return $label
}

function Add-Button {
    param($Parent, [string]$Text, [int]$X, [int]$Y, [int]$Width, [switch]$Primary)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($Width, 44)
    $button.FlatStyle = "Flat"
    $button.FlatAppearance.BorderSize = 1
    $button.FlatAppearance.BorderColor = $colors.Border
    $button.BackColor = $colors.Surface
    $button.ForeColor = $colors.Text
    $button.FlatAppearance.MouseOverBackColor = [System.Drawing.ColorTranslator]::FromHtml("#29384C")
    $button.FlatAppearance.MouseDownBackColor = $colors.Border
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $button.Cursor = "Hand"
    $button.UseVisualStyleBackColor = $false
    if ($Primary) {
        $button.BackColor = $colors.Accent
        $button.ForeColor = $colors.Background
        $button.FlatAppearance.BorderSize = 0
        $button.FlatAppearance.MouseOverBackColor = [System.Drawing.ColorTranslator]::FromHtml("#A5F3FC")
        $button.FlatAppearance.MouseDownBackColor = [System.Drawing.ColorTranslator]::FromHtml("#22D3EE")
        $button.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    }
    $Parent.Controls.Add($button)
    return $button
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "PCHH USB Flasher"
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$form.AutoScaleMode = "Dpi"
$form.ClientSize = New-Object System.Drawing.Size(720, 678)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = $colors.Background
$form.ForeColor = $colors.Text
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

# Brand and introduction
$brandLabel = Add-Text $form "PCHH  /  RECOVERY TOOLS" 32 26 460 24 9 $colors.Accent -Bold
$titleLabel = Add-Text $form "Create your recovery USB" 32 58 656 46 25 $colors.Text -Bold
$subtitleLabel = Add-Text $form "A bootable PCHH toolkit, ready when you need it." 34 110 650 26 11 $colors.Muted

# Workflow overview: the current stage is highlighted throughout the operation.
$stepLabels = @(
    (Add-Text $form "01   SELECT USB" 34 160 208 26 9 $colors.Accent -Bold)
    (Add-Text $form "02   DOWNLOAD" 258 160 208 26 9 $colors.Muted -Bold)
    (Add-Text $form "03   WRITE IMAGE" 482 160 208 26 9 $colors.Muted -Bold)
)

$targetPanel = New-Object System.Windows.Forms.Panel
$targetPanel.Location = New-Object System.Drawing.Point(32, 202)
$targetPanel.Size = New-Object System.Drawing.Size(656, 148)
$targetPanel.BackColor = $colors.Surface
$form.Controls.Add($targetPanel)
$usbLabel = Add-Text $targetPanel "Target USB drive" 20 18 440 26 11 $colors.Text -Bold
$driveHint = Add-Text $targetPanel "Connect a USB drive, then choose it below." 20 48 606 24 9 $colors.Muted

$usbCombo = New-Object System.Windows.Forms.ComboBox
$usbCombo.Location = New-Object System.Drawing.Point(20, 88)
$usbCombo.Size = New-Object System.Drawing.Size(486, 32)
$usbCombo.Font = New-Object System.Drawing.Font("Segoe UI", 11)
$usbCombo.DropDownStyle = "DropDownList"
$usbCombo.BackColor = $colors.Background
$usbCombo.ForeColor = $colors.Text
$usbCombo.FlatStyle = "Flat"
$usbCombo.DropDownWidth = 610
$usbCombo.AccessibleName = "Target USB drive"
$usbCombo.TabIndex = 0
$targetPanel.Controls.Add($usbCombo)
$refreshButton = Add-Button $targetPanel "&Refresh" 518 82 118
$refreshButton.TabIndex = 1
$refreshButton.Add_Click({ Get-RemovableDisks })

# Persistent progress card avoids the layout jumping between states.
$progressPanel = New-Object System.Windows.Forms.Panel
$progressPanel.Location = New-Object System.Drawing.Point(32, 366)
$progressPanel.Size = New-Object System.Drawing.Size(656, 128)
$progressPanel.BackColor = $colors.Surface
$form.Controls.Add($progressPanel)
$statusLabel = Add-Text $progressPanel "Ready to create" 20 18 616 28 12 $colors.Text -Bold
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 58)
$progressBar.Size = New-Object System.Drawing.Size(616, 8)
$progressBar.Style = "Continuous"
$progressPanel.Controls.Add($progressBar)
$progressLabel = Add-Text $progressPanel "The recovery image will download automatically from GitHub." 20 82 616 28 9 $colors.Muted
$successLabel = Add-Text $progressPanel "Your PCHH recovery USB is ready to use." 20 78 616 32 11 $colors.Success -Bold
$successLabel.Visible = $false

$warningLabel = Add-Text $form "All data on the selected USB drive will be erased. Back up your files first." 34 514 652 44 10 $colors.Warning
$footerLabel = Add-Text $form "PCHH USB FLASHER" 34 622 300 22 8 $colors.Muted
$closeButton = Add-Button $form "&Close" 336 600 112
$closeButton.TabIndex = 3
$closeButton.Add_Click({ $form.Close() })
$flashButton = Add-Button $form "&Create bootable USB" 460 600 228 -Primary
$flashButton.TabIndex = 2

function Set-FlasherStage {
    param([int]$Stage)
    for ($i = 0; $i -lt $stepLabels.Count; $i++) {
        $stepLabels[$i].ForeColor = $colors.Muted
        if ($i -lt $Stage) { $stepLabels[$i].ForeColor = $colors.Success }
        if ($i -eq $Stage) { $stepLabels[$i].ForeColor = $colors.Accent }
    }
}

function Reset-FlasherPresentation {
    $successLabel.Visible = $false
    $progressLabel.Visible = $true
    $warningLabel.Visible = $true
    $statusLabel.ForeColor = $colors.Text
    $progressBar.Value = 0
    $closeButton.Text = "&Close"
    $statusLabel.Text = "Ready to create"
    $progressLabel.Text = "The recovery image will download automatically from GitHub."
    Set-FlasherStage 0
}

# Function to get removable USB drives
function Get-RemovableDisks {
    Reset-FlasherPresentation
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
            $usbCombo.SelectedIndex = 0
            $statusLabel.Text = "Connect a USB drive"
            $progressLabel.Text = "No USB drives found. Connect your drive and select Refresh."
        } else {
            $usbCombo.SelectedIndex = 0
            $flashButton.Enabled = $true
            $statusLabel.Text = "Ready to create"
            $progressLabel.Text = "The recovery image will download automatically from GitHub."
        }
    } catch {
        $usbCombo.Items.Clear()
        $usbCombo.Items.Add("Unable to scan USB drives") | Out-Null
        $usbCombo.SelectedIndex = 0
        $statusLabel.Text = "Drive scan failed"
        $progressLabel.Text = "Run as Administrator, then select Refresh to try again."
        $flashButton.Enabled = $false
    }
}

# Function to download image
function Download-Image {
    param([string]$Url, [string]$Destination)

    Set-FlasherStage 1
    $flashButton.Text = "Downloading..."
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
        # Windows PowerShell may default to TLS versions GitHub no longer accepts.
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
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
        $downloadError = $_.Exception.GetBaseException().Message
        [void][System.Windows.Forms.MessageBox]::Show(
            "Failed to download image: " + $downloadError + "`r`n`r`nURL: " + $Url,
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

    Set-FlasherStage 2
    $flashButton.Text = "Writing image..."
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
        $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
        if ($disk.BusType -ne 'USB' -or $disk.IsBoot -or $disk.IsSystem) {
            throw "The selected disk must be a USB drive and cannot be a boot or system disk."
        }
        if ($totalBytes -gt $disk.Size) {
            throw "The image is larger than the selected USB drive."
        }
        $sectorSize = [int]$disk.LogicalSectorSize
        if ($sectorSize -le 0 -or (4MB % $sectorSize) -ne 0) {
            throw "The USB drive reports an unsupported sector size."
        }
        if (($totalBytes % $sectorSize) -ne 0) {
            throw "The image size is not aligned to this USB drive's $sectorSize-byte sectors. Use a USB drive with 512-byte logical sectors."
        }
        Clear-Disk -Number $DiskNumber -RemoveData -Confirm:$false -ErrorAction Stop
        $progressLabel.Text = "Writing image data..."
        $form.Refresh()

        $diskPath = "\\.\PhysicalDrive" + $DiskNumber
        # Physical disks must be opened as existing devices. OpenWrite uses
        # OpenOrCreate, which Windows can reject with ERROR_INVALID_PARAMETER.
        $targetFile = New-Object System.IO.FileStream(
            $diskPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite,
            4MB,
            [System.IO.FileOptions]::WriteThrough
        )
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
            "Failed to write image: " + $_.Exception.GetBaseException().Message,
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
        "This will ERASE all data on:`r`n`r`n$($usbCombo.SelectedItem)`r`n`r`nCreate a PCHH recovery USB on this drive?",
        "Confirm",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    Reset-FlasherPresentation
    $flashButton.Enabled = $false
    $usbCombo.Enabled = $false
    $refreshButton.Enabled = $false
    $closeButton.Enabled = $false
    $form.ControlBox = $false

    $selection = $usbCombo.SelectedItem.ToString()
    $diskNumber = [int]($selection -replace '^Disk (\d+):.*', '$1')

    $flashed = $false
    $downloaded = Download-Image -Url $ImageUrl -Destination $TempPath

    if ($downloaded -eq $true) {
        $flashed = Flash-USB -DiskNumber $diskNumber -ImagePath $TempPath

        if ($flashed -eq $true) {
            Set-FlasherStage 3
            $progressBar.Value = 100
            $progressLabel.Visible = $false
            $successLabel.Visible = $true
            $statusLabel.Text = "Recovery USB created"
            $statusLabel.ForeColor = $colors.Success
            $warningLabel.Visible = $false
            $closeButton.Text = "&Done"
            Remove-Item $TempPath -ErrorAction SilentlyContinue
            $form.Refresh()
        }
    }

    if (-not $flashed) {
        $progressBar.Style = "Continuous"
        $statusLabel.Text = "Creation did not complete"
        $statusLabel.ForeColor = $colors.Warning
        $progressLabel.Text = "Review the error and try again. A failed write may leave the USB unbootable."
        Set-FlasherStage 0
    }
    $flashButton.Text = "&Create bootable USB"
    $flashButton.Enabled = $true
    $usbCombo.Enabled = $true
    $refreshButton.Enabled = $true
    $closeButton.Enabled = $true
    $form.ControlBox = $true
})

$usbCombo.Add_SelectedIndexChanged({
    if ($usbCombo.Enabled -and $successLabel.Visible) { Reset-FlasherPresentation }
})

# Initial load
Get-RemovableDisks

# Show form
[void]$form.ShowDialog()
