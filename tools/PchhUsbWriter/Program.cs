using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows.Forms;

namespace PchhUsbWriter;

internal sealed record UsbDisk(int Number, string Name, ulong Size, string BusType, bool IsBoot, bool IsSystem)
{
    public string Display => $"Disk {Number} | {Name} | {Size / 1024d / 1024 / 1024:0.0} GB | {BusType}";
}

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new WriterForm());
    }
}

internal sealed class WriterForm : Form
{
    private readonly TextBox imagePath = new() { Dock = DockStyle.Fill };
    private readonly ComboBox disks = new() { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly Button refresh = new() { Text = "Refresh disks", AutoSize = true };
    private readonly Button write = new() { Text = "Write image", AutoSize = true };
    private readonly ProgressBar progress = new() { Dock = DockStyle.Fill, Minimum = 0, Maximum = 100 };
    private readonly Label status = new() { Text = "Choose the PCHH .img file and a USB disk.", AutoSize = true };
    private List<UsbDisk> foundDisks = new();

    public WriterForm()
    {
        Text = "PCHH USB Writer";
        Width = 680;
        Height = 270;
        MinimumSize = new System.Drawing.Size(600, 250);
        StartPosition = FormStartPosition.CenterScreen;

        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(16), ColumnCount = 2, RowCount = 6 };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        layout.Controls.Add(new Label { Text = "PCHH disk image", AutoSize = true }, 0, 0);
        layout.SetColumnSpan(layout.GetControlFromPosition(0, 0)!, 2);
        layout.Controls.Add(imagePath, 0, 1);
        var browse = new Button { Text = "Browse...", AutoSize = true };
        browse.Click += (_, _) => BrowseImage();
        layout.Controls.Add(browse, 1, 1);
        layout.Controls.Add(disks, 0, 2);
        layout.SetColumnSpan(disks, 2);
        layout.Controls.Add(refresh, 0, 3);
        refresh.Click += async (_, _) => await RefreshDisks();
        layout.Controls.Add(status, 0, 4);
        layout.SetColumnSpan(status, 2);
        layout.Controls.Add(progress, 0, 5);
        layout.Controls.Add(write, 1, 5);
        write.Click += async (_, _) => await WriteImage();
        Controls.Add(layout);
        Shown += async (_, _) =>
        {
            var defaultImage = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "dist", "pchh-usb.img"));
            if (File.Exists(defaultImage)) imagePath.Text = defaultImage;
            await RefreshDisks();
        };
    }

    private void BrowseImage()
    {
        using var dialog = new OpenFileDialog { Filter = "PCHH disk image (*.img)|*.img|All files (*.*)|*.*", CheckFileExists = true };
        if (dialog.ShowDialog(this) == DialogResult.OK) imagePath.Text = dialog.FileName;
    }

    private async Task RefreshDisks()
    {
        SetBusy(true);
        status.Text = "Scanning USB disks...";
        try
        {
            foundDisks = await Task.Run(ReadUsbDisks);
            disks.DataSource = null;
            disks.DataSource = foundDisks;
            disks.DisplayMember = nameof(UsbDisk.Display);
            status.Text = foundDisks.Count == 0 ? "No eligible USB disks found. Connect the target USB and refresh." : "Select the USB disk to overwrite.";
        }
        catch (Exception ex) { status.Text = $"Disk scan failed: {ex.Message}"; }
        finally { SetBusy(false); }
    }

    private static List<UsbDisk> ReadUsbDisks()
    {
        const string command = "Get-Disk | Where-Object { $_.BusType -eq 'USB' -and -not $_.IsBoot -and -not $_.IsSystem } | Select-Object Number,FriendlyName,Size,BusType,IsBoot,IsSystem | ConvertTo-Json -Compress";
        var output = RunPowerShell(command);
        if (string.IsNullOrWhiteSpace(output)) return new List<UsbDisk>();
        using var document = JsonDocument.Parse(output);
        var rows = document.RootElement.ValueKind == JsonValueKind.Array
            ? document.RootElement.EnumerateArray().ToArray()
            : new[] { document.RootElement };
        return rows.Select(row => new UsbDisk(
            row.GetProperty("Number").GetInt32(),
            row.GetProperty("FriendlyName").GetString() ?? "USB disk",
            row.GetProperty("Size").GetUInt64(),
            row.GetProperty("BusType").GetString() ?? "USB",
            row.GetProperty("IsBoot").GetBoolean(),
            row.GetProperty("IsSystem").GetBoolean())).ToList();
    }

    private async Task WriteImage()
    {
        if (disks.SelectedItem is not UsbDisk disk) { MessageBox.Show(this, "Select a USB disk."); return; }
        if (!File.Exists(imagePath.Text)) { MessageBox.Show(this, "Select an existing .img file."); return; }
        var image = new FileInfo(imagePath.Text);
        if (disk.Size < (ulong)image.Length) { MessageBox.Show(this, "The selected USB disk is smaller than the image."); return; }
        var warning = $"This permanently erases all data on:\n\n{disk.Display}\n\nImage: {image.Name} ({image.Length / 1024d / 1024 / 1024:0.00} GB)\n\nContinue?";
        if (MessageBox.Show(this, warning, "Confirm USB erase", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
        var typed = Microsoft.VisualBasic.Interaction.InputBox($"To confirm, type ERASE DISK {disk.Number}:", "Final confirmation", "");
        if (!string.Equals(typed, $"ERASE DISK {disk.Number}", StringComparison.Ordinal)) return;

        SetBusy(true);
        progress.Value = 0;
        try
        {
            status.Text = "Taking the selected USB disk offline...";
            await Task.Run(() => SetDiskOffline(disk.Number, true));
            status.Text = "Writing and verifying the image. Do not unplug the USB.";
            await Task.Run(() => WriteAndVerify(image.FullName, disk, value =>
                BeginInvoke(() => progress.Value = Math.Clamp(value, 0, 100))));
            status.Text = "Image written and verified. Safely eject the USB before removing it.";
            MessageBox.Show(this, "The PCHH image was written and verified. Safely eject the USB drive.", "Complete", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            status.Text = $"Write failed: {ex.Message}";
            try { await Task.Run(() => SetDiskOffline(disk.Number, false)); } catch { }
            MessageBox.Show(this, $"The image could not be written or verified.\n\n{ex.Message}", "Write failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally { SetBusy(false); }
    }

    private static void SetDiskOffline(int number, bool offline)
    {
        var state = offline ? "$true" : "$false";
        RunPowerShell($"Set-Disk -Number {number} -IsOffline {state} -ErrorAction Stop");
    }

    private static void WriteAndVerify(string imagePath, UsbDisk disk, Action<int> reportProgress)
    {
        var device = $@"\\.\PhysicalDrive{disk.Number}";
        using (var input = new FileStream(imagePath, FileMode.Open, FileAccess.Read, FileShare.Read, 4 * 1024 * 1024, FileOptions.SequentialScan))
        using (var output = new FileStream(device, FileMode.Open, FileAccess.Write, FileShare.None, 4 * 1024 * 1024, FileOptions.WriteThrough))
        {
            var buffer = new byte[4 * 1024 * 1024];
            long done = 0;
            int read;
            while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
            {
                output.Write(buffer, 0, read);
                done += read;
                reportProgress((int)(100L * done / input.Length));
            }
            output.Flush(true);
        }

        using var expected = SHA256.Create();
        using var source = File.OpenRead(imagePath);
        var expectedHash = expected.ComputeHash(source);
        using var actual = SHA256.Create();
        using var target = new FileStream(device, FileMode.Open, FileAccess.Read, FileShare.Read, 4 * 1024 * 1024, FileOptions.SequentialScan);
        var actualHash = actual.ComputeHash(new LimitedStream(target, new FileInfo(imagePath).Length));
        if (!CryptographicOperations.FixedTimeEquals(expectedHash, actualHash)) throw new IOException("Read-back SHA-256 does not match the image.");
        reportProgress(100);
    }

    private static string RunPowerShell(string command)
    {
        using var process = Process.Start(new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command " + QuotePowerShell(command),
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        }) ?? throw new InvalidOperationException("Could not start Windows PowerShell.");
        var stdout = process.StandardOutput.ReadToEnd();
        var stderr = process.StandardError.ReadToEnd();
        process.WaitForExit();
        if (process.ExitCode != 0) throw new InvalidOperationException(string.IsNullOrWhiteSpace(stderr) ? "PowerShell disk operation failed." : stderr.Trim());
        return stdout.Trim();
    }

    private static string QuotePowerShell(string command) => "\"" + command.Replace("\"", "`\"") + "\"";

    private void SetBusy(bool busy)
    {
        refresh.Enabled = !busy;
        write.Enabled = !busy;
        disks.Enabled = !busy;
        imagePath.Enabled = !busy;
    }
}

internal sealed class LimitedStream(Stream inner, long limit) : Stream
{
    private long remaining = limit;
    public override bool CanRead => inner.CanRead;
    public override bool CanSeek => false;
    public override bool CanWrite => false;
    public override long Length => limit;
    public override long Position { get => limit - remaining; set => throw new NotSupportedException(); }
    public override int Read(byte[] buffer, int offset, int count)
    {
        if (remaining <= 0) return 0;
        var read = inner.Read(buffer, offset, (int)Math.Min(count, remaining));
        remaining -= read;
        return read;
    }
    public override void Flush() => throw new NotSupportedException();
    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    public override void SetLength(long value) => throw new NotSupportedException();
    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
}
