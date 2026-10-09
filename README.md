# PCHH — PC Health Check

A **minimal, bootable diagnostic operating system** for x86_64 PCs. Flash it to a
USB stick, boot any machine from it, and it runs entirely **from RAM** — it never
writes to the host disks except when you explicitly save a result.

It boots to a GRUB menu (with a verbose and a live-shell option) and presents an
interactive diagnostics menu. Each check prints colored `[ OK ] / [WARN] / [FAIL]`
output and, for "Diagnose all", assembles one consolidated timestamped report.

## Menu

```
QUICK CHECKS
  1) Diagnose all        2) Identify system
  3) Component overview  4) RAM test
  5) CPU / thermal test  6) GPU diagnostics
  7) USB write test

HARDWARE DETAIL
  8) Storage / SSD       9) Temperatures / fans
 10) BIOS / firmware     11) Manufacturers
 12) PCIe                13) ECC / machine checks
 14) Battery             15) Network / peripherals
 16) Read-only storage   17) Settings
 18) Live shell

 r) Reboot        s) Power off
```

The status line shows the active settings: `CPU <n>s | RAM <mode> | Verbose <on/off>`.

## Checks

| # | Check | What it reports | Sources |
|---|-------|-----------------|---------|
| 1 | Diagnose all | every check below in one consolidated report, saved to `/tmp` and — if a PCHH_DATA USB is present — copied there | `pchh-report` |
| 2 | Identify system | brief host fingerprint (vendor, product, CPU, kernel) | `dmidecode`, `lscpu` |
| 3 | Component overview | CPU, memory, block/PCI/USB devices, kernel errors | `lscpu`, `lsblk`, `lspci`, `lsusb`, `dmesg` |
| 4 | RAM test | capacity, per-DIMM size/type/speed/manufacturer/part, live memtester or stress-ng pressure | `dmidecode`, `/proc/meminfo`, `memtester`/`stress-ng` |
| 5 | CPU / thermal test | timed CPU workload plus new machine-check or thermal messages | `stress-ng`, `sensors`, `dmesg` |
| 6 | GPU diagnostics | graphics devices, driver binding, connector modes, color/shader renders, temps, kernel errors | `lspci`, DRM, `modetest`, `kmscube`, `sensors`, `dmesg` |
| 7 | USB write test | write, read-back, sync, and cleanup against the PCHH_DATA partition | `cp`, `cmp`, `sync` |
| 8 | Storage / SSD | SMART pass/wear, reallocated/pending sectors, NVMe life & media errors | `smartctl`, `nvme` |
| 9 | Temperatures / fans | sensor chips, ACPI thermal zones, NVMe temps | `sensors`, sysfs |
| 10 | BIOS / firmware | vendor, version, release date, UEFI vs legacy | `dmidecode` |
| 11 | Manufacturers | system, motherboard, chassis, CPU, DIMMs, disks, chipset | `dmidecode`, `lscpu`, `lsblk`, `lspci` |
| 12 | PCIe | device inventory, link state, PCIe error state, kernel errors | `lspci`, `dmesg` |
| 13 | ECC / machine checks | EDAC corrected/uncorrected errors, kernel machine-check events | sysfs, `dmesg` |
| 14 | Battery | charge capacity, wear, cycle count, status, AC power | sysfs |
| 15 | Network / peripherals | interfaces, carrier, speed, driver, RX/TX errors; USB topology + ALSA devices | `ip`, sysfs, `lsusb`, `aplay`, `arecord` |
| 16 | Read-only storage | filesystem checks and kernel I/O errors — **no repair, no writes** | `fsck`, `lsblk`, `dmesg` |
| 17 | Settings | change boot-time options for this session | in-menu editor |

`pchh-config` (a configuration/environment audit) also runs automatically as the
first step of any "Diagnose all" report but is not exposed as a top-level menu item.

## How it works

```
GRUB (BIOS + UEFI) → Linux kernel (vmlinuz) → initramfs (Alpine/busybox) → /init → pchh menu
```

The initramfs is a small Alpine userspace (busybox + diagnostic tools). `/init`
mounts the virtual filesystems, loads storage/sensor/display kernel modules, then
launches the interactive menu. The whole thing is packaged into a hybrid ISO by
`grub-mkrescue`, so it boots on both legacy BIOS and modern UEFI machines.

## Settings

Settings are stored in `/run/pchh/settings.conf` for the current boot only (RAM is
discarded on reboot). They can be changed from menu item **17** or preset before the
menu appears:

| Variable | Default | Description |
|----------|---------|-------------|
| `PCHH_CPU_SECONDS` | `30` | Duration of the CPU/thermal load test (10–300). |
| `PCHH_AUTO_USB_REPORT` | `1` | When on, "Diagnose all" and "Identify system" auto-copy their
report to the PCHH_DATA USB if present. |
| `PCHH_GPU_VISUAL` | `1` | Run the display color/shader renders in GPU diagnostics. |
| `PCHH_VERBOSE` | `0` | Show full check output inline instead of a spin-and-summarize run. |
| `PCHH_RAM_MODE` | `live` | `live` (in-RAM memtester/stress-ng) or `memtest` (advises booting
the Memtest86+ GRUB entry for a thorough bit-level test). |

## Project layout

```
PCHH/
├── Makefile                       # build / test / clean
├── build/Dockerfile               # reproducible build (Alpine rootfs + Debian/GRUB ISO)
├── iso/
│   ├── grub.cfg                   # GRUB boot menu (BIOS + UEFI), memtest entry, reboot/poweroff
│   └── rootfs/                    # contents of the initramfs
│       ├── init                   # first userspace process
│       └── usr/local/
│           ├── bin/               # pchh (menu) + pchh-* diagnostic scripts
│           └── lib/pchh/common.sh # shared helpers (formatting, settings, USB save)
└── dist/                          # ISO output (git-ignored)
    ├── pchh.iso                   # hybrid BIOS/UEFI image
    └── pchh-usb.img               # ISO + 512 MiB PCHH_DATA report partition
```

The `dist/pchh-usb.img` image carries an extra MBR partition (`PCHH_DATA`,
VFAT, 512 MiB) that the checks use to save reports and run USB write tests. The
menu and "Diagnose all" detect this partition automatically when an ISO USB is
flashed to a stick.

## Requirements

- **Docker Desktop** (for building). On Apple Silicon the build runs under
  `linux/amd64` emulation automatically.
- Optional: **QEMU** (`brew install qemu`) to test-boot the ISO locally.
- Optional on Linux: **OVMF** packages to test the UEFI boot path with `make test-uefi`.

## Build

```sh
make iso          # produces dist/pchh.iso and dist/pchh-usb.img
```

### Optional WinPE integration

An official Microsoft ADK `WinPE_amd64` tree can be included as a second boot
environment. Stage it before building:

```sh
make prepare-winpe WINPE_DIR=/path/to/WinPE_amd64
make iso
```

The tree must contain `EFI/Microsoft/Boot/bootmgfw.efi` and
`sources/boot.wim`. The build adds a `PCHH - Windows PE (ADK)` GRUB entry;
Windows-native tools such as `bcdboot`, `bcdedit`, DISM, SFC, and Startup
Repair then run in their supported environment. The staged `winpe/` contents
are local build input and are not committed to this repository.

Or directly:

```sh
docker build --platform linux/amd64 -f build/Dockerfile \
    --target artifact --output type=local,dest=dist .
```

The build is reproducible and multi-stage: an Alpine rootfs stage packs the
initramfs and kernel, a Debian/GRUB stage lays out the ISO tree, then a scratch
artifact stage emits only `pchh.iso` and `pchh-usb.img` (delivered via
`docker build --output`).

## Test in a VM

```sh
make test         # legacy BIOS boot in QEMU
```

The QEMU test uses the modern `q35` machine model, which avoids an
IO-APIC timer compatibility issue seen with the legacy QEMU `pc` model; it does
not change the ISO's APIC behavior when booted on physical hardware. Override it
with `make test QEMU_MACHINE=pc` if needed.

```sh
make test-usb     # boot the PCHH_DATA USB image in QEMU (q35 + xHCI)
make test-uefi    # UEFI boot via OVMF (Linux hosts with OVMF installed)
make test-pe-uefi # UEFI boot with optimized settings for x86 emulation on Apple Silicon
```

### Testing Windows PE integration

When a WinPE tree has been staged and built into the image:

```sh
make test-usb-winpe   # boot USB image with GRUB → Windows PE menu option
```

This target uses optimized QEMU settings for Apple Silicon hosts:
- Single-threaded TCG emulation (`-accel tcg,thread=single`)
- Conservative CPU profile (`-cpu Haswell-v4,-tsc-deadline`)
- Single core (`-smp 1`) to avoid AP initialization races
- 2GB RAM for Windows PE's in-memory boot.wim
- VGA display for Windows Boot Manager's graphical output

**Expected behavior:** GRUB displays the menu including "PCHH - Windows PE (ADK)". 
Selecting it searches for the `PCHH_WINPE` FAT32 partition and chainloads 
`bootx64.efi` from it. Boot takes 3–7 minutes under TCG translation on Apple Silicon.

Note: `dmidecode`, `sensors` and SMART data are limited or absent under
virtualization — the OS boots and the menu works, but for meaningful hardware
results, test on real hardware.

## Flash to a USB stick

Find your USB device (the drive to overwrite), then write the USB image
(this **erases** the stick):

```sh
# macOS — identify the disk first (diskutil list)
sudo dd if=dist/pchh-usb.img of=/dev/rdiskN bs=4m status=progress
sync

# Linux — identify the disk first (lsblk)
sudo dd if=dist/pchh-usb.img of=/dev/sdX bs=4M status=progress
sync
```

Then boot the target PC from the USB (choose it in the firmware boot menu).

For UEFI systems, the current image requires **Secure Boot to be disabled**.
The GRUB EFI loader produced by `grub-mkrescue` is unsigned, so firmware may
hide the USB or refuse to launch it before Linux starts. Use the firmware's
UEFI boot entry for the USB, not a legacy/CSM-only entry.

To boot with Secure Boot enabled, the image must be rebuilt as a signed boot
chain. There are two supported approaches:

1. **Shim path (best for general distribution):** install the distribution's
   `shim-signed` and `grub-efi-amd64-signed` packages in the ISO build stage,
   copy the signed `shimx64.efi` and GRUB modules into the EFI System
   Partition, and sign the PCHH kernel with a key trusted by that GRUB. The
   shim must be the vendor/Microsoft-signed build; an unsigned copy does not
   solve Secure Boot.
2. **Own-key path (best for private use):** generate a Platform Key/Key
   Exchange Key or a Machine Owner Key, sign GRUB, its modules, and the Linux
   kernel with `sbsigntool`, and enroll the public certificate in each target
   machine's firmware (or with `mokutil`). Firmware enrollment is a one-time
   step per machine and cannot be automated safely by this diagnostic ISO.

Signing only the kernel is insufficient: firmware first verifies the EFI
   loader, and GRUB then verifies the kernel and any modules it loads. BIOS
   boot remains unaffected because Secure Boot applies to UEFI.

## Using it

1. Boot the USB → the GRUB menu appears → pick **PCHH - PC Health Check**.
2. Choose a number from the menu, or **18) Live shell** to inspect manually.
3. **1) Diagnose all** runs every check, writes a timestamped report to
   `/tmp/pchh-report-*.txt`, and — when `PCHH_AUTO_USB_REPORT` is on and a
   `PCHH_DATA` USB is present — copies it to that USB partition (auto-unmounted
   when PCHH mounted it).
4. After any single check, press `Enter` to return, or `s` to save that check's
   last-screen result to the USB.

The CPU/thermal test is the only standard menu check that intentionally creates
load. Storage checks are read-only. Network and audio checks only inspect
devices; they do not generate traffic or play sound automatically. The USB write
test does write to (and clean up on) the designated `PCHH_DATA` partition only.

## Adding your own check

1. Create `iso/rootfs/usr/local/bin/pchh-mycheck` — start it with
   `. /usr/local/lib/pchh/common.sh` and use `header`/`section`/`kv`/`ok`/`warn`/`bad`.
2. Add a menu entry in `iso/rootfs/usr/local/bin/pchh`.
3. Add the script to the report loop in `iso/rootfs/usr/local/bin/pchh-report`
   (and to `report_step_name` in that file) so it is included in "Diagnose all".
4. `make iso` again.

## Limitations & notes

- **Windows boot repair:** menu item 19 inventories Windows volumes and EFI
  partitions, backs up the Microsoft EFI boot directory, recreates the UEFI
  firmware entry when `bootmgfw.efi` exists, and exports the BCD store for
  inspection. It can also generate a ready-to-run WinRE `.cmd` script that
  runs `bcdboot`, offline `sfc`, `chkdsk`, and Safe Mode `bcdedit` commands.
  These Microsoft tools run from Windows Recovery Environment, not Linux.
- **Windows disk safety:** BitLocker volumes must be unlocked in Windows
  Recovery Environment before offline access. Do not run filesystem repair on
  a failing drive before imaging it with `ddrescue`.

- **Read-only by design.** SMART, `dmidecode`, etc. only read hardware state.
- **Memtest86+** boots via the legacy Linux loader, so use BIOS/CSM mode for it.
  On UEFI-only systems, set `RAM mode` to `memtest` from Settings, or enable CSM
  and pick the GRUB "Memtest86+" entry.
- Sensor coverage depends on kernel drivers for the specific motherboard; some
  chips need modules that aren't auto-loaded.
- BIOS setup screens expose vendor-specific options inconsistently. PCHH audits
  settings visible through SMBIOS, EFI variables, TPM, and sysfs, but cannot
  promise to enumerate every hidden firmware option.
- GPU diagnostics identify devices, drivers, sensors, PCIe state, and kernel
  errors, and run automated color/shader renders — they do not yet provide a
  universal VRAM integrity test or proprietary NVIDIA stress driver.
- Targets **x86_64** only.
