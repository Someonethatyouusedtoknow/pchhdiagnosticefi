# PCHH — PC Health Check

A **minimal, bootable diagnostic operating system** for x86_64 PCs. Flash it to a
USB stick, boot any machine from it, and it runs entirely **in RAM** — it never
touches the host disks unless you explicitly tell it to.

It boots to a menu (with a live shell option) and reports:

| Check | What it shows | Tools used |
|-------|---------------|------------|
| **Diagnose all** | all diagnostic scans, saved to a detected USB drive and `/tmp` | — |
| **Component overview** | CPU, memory, block/PCI/USB devices, kernel errors | `lscpu`, `lsblk`, `lspci`, `lsusb`, `dmesg` |
| **Storage / SSD health** | SMART pass/fail, wear, reallocated/pending sectors, NVMe life & media errors | `smartctl`, `nvme` |
| **RAM** | capacity, per-DIMM size/type/speed/manufacturer/part | `dmidecode`, `/proc/meminfo` |
| **BIOS / firmware** | vendor, version, release date, UEFI vs legacy | `dmidecode` |
| **Manufacturers** | system, motherboard, chassis, CPU, DIMMs, disks, chipset | `dmidecode`, `lscpu`, `lsblk`, `lspci` |
| **Temperatures / fans** | sensor chips, ACPI thermal zones, NVMe temps | `sensors`, sysfs, `nvme` |
| **ECC / machine-check** | EDAC corrected/uncorrected errors and kernel machine-check events | sysfs, `dmesg` |
| **Battery health** | charge capacity, wear, cycle count, status, AC power | sysfs |
| **PCIe diagnostics** | device inventory, link state, PCIe error state and kernel errors | `lspci`, `dmesg` |
| **BIOS / firmware audit** | boot mode, Secure Boot, TPM, SMBIOS data, UEFI variables | `dmidecode`, sysfs |
| **CPU load / thermal test** | timed CPU workload and new machine-check or thermal messages | `stress-ng`, `sensors`, `dmesg` |
| **GPU diagnostics** | graphics devices, driver binding, temperatures, GPU error messages | `lspci`, DRM, `sensors`, `dmesg` |
| **Read-only storage checks** | filesystem checks and kernel I/O errors without repair or writes | `fsck`, `lsblk`, `dmesg` |
| **Network diagnostics** | interfaces, carrier, speed, driver, RX/TX errors | sysfs, `ip` |
| **USB / audio peripherals** | USB topology/errors and ALSA playback/capture devices | `lsusb`, `aplay`, `arecord` |
| **Memtest86+** | thorough bit-level RAM test (boot-menu entry, BIOS/CSM) | `memtest86+` |

## How it works

```
GRUB (BIOS + UEFI)  →  Linux kernel (vmlinuz)  →  initramfs  →  /init  →  pchh menu
```

The initramfs is a small Alpine userspace containing busybox plus the diagnostic
tools above. `/init` mounts the virtual filesystems, loads storage/sensor kernel
modules, then launches the interactive menu. The whole thing is packaged into a
hybrid ISO by `grub-mkrescue`, so it boots on both legacy BIOS and modern UEFI
machines.

## Project layout

```
PCHH/
├── Makefile                       # build / test / clean
├── build/Dockerfile               # reproducible build (Alpine rootfs + Debian/GRUB ISO)
├── iso/
│   ├── grub.cfg                   # boot menu (BIOS + UEFI), memtest entry
│   └── rootfs/                    # contents of the initramfs
│       ├── init                   # first userspace process
│       └── usr/local/
│           ├── bin/               # pchh (menu) + pchh-* diagnostic scripts
│           └── lib/pchh/common.sh # shared helpers
└── dist/pchh.iso                  # ISO output (git-ignored)
  dist/pchh-usb.img              # USB image with writable report partition
```

## Requirements

- **Docker Desktop** (for building). On Apple Silicon the build runs under
  `linux/amd64` emulation automatically.
- Optional: **QEMU** (`brew install qemu`) to test-boot the ISO.

## Build

```sh
make iso          # produces dist/pchh.iso and dist/pchh-usb.img
```

Or directly:

```sh
docker build --platform linux/amd64 -f build/Dockerfile \
    --target artifact --output type=local,dest=dist .
```

## Test in a VM

```sh
make test         # legacy BIOS boot in QEMU
```

The QEMU test uses the modern `q35` machine model. This avoids an IO-APIC timer
compatibility problem seen with the legacy QEMU `pc` model; it does not change
the ISO's APIC behavior when booted on physical hardware. Override it with
`make test QEMU_MACHINE=pc` if needed.

To boot the USB image, including its writable report partition, run:

```sh
make test-usb
```

Note: `dmidecode`, `sensors` and SMART data are limited or absent under
virtualization — the OS boots and the menu works, but for meaningful hardware
results, test on real hardware.

## Flash to a USB stick

Find your USB device, then write the USB image (this **erases** the stick):

```sh
# macOS / Linux — identify the disk first (diskutil list / lsblk)
sudo dd if=dist/pchh-usb.img of=/dev/rdiskN bs=4m status=progress # macOS
sudo dd if=dist/pchh-usb.img of=/dev/sdX     bs=4M status=progress # Linux
sync
```

Then boot the target PC from the USB (choose it in the firmware boot menu).

For UEFI systems, disable **Secure Boot** unless you have enrolled a trusted
PCHH signing key. The bundled GRUB EFI loader is not Microsoft-signed, so some
firmware will hide the USB or refuse to launch it while Secure Boot is enabled.
Use the firmware's UEFI boot entry for the USB, not a legacy/CSM-only entry.

## Using it

1. Boot the USB → the GRUB menu appears → pick **PCHH - PC Health Check**.
2. Choose a check from the menu, or **17) Live shell** to poke around manually.
3. **1) Diagnose all** runs the checks, saves a timestamped report to `/tmp`,
  and copies it to the first detected writable USB partition. The USB is
  unmounted automatically when PCHH mounted it.

The CPU load test is the only standard menu check that intentionally creates
load. It runs for 30 seconds by default during Diagnose all and can be adjusted
with `PCHH_CPU_SECONDS`. Storage checks are read-only. Network and audio checks only
inspect devices; they do not generate traffic or sound automatically.

## Adding your own check

1. Create `iso/rootfs/usr/local/bin/pchh-mycheck` (start with
   `. /usr/local/lib/pchh/common.sh` and use `header`/`section`/`kv`/`ok`/`warn`/`bad`).
2. Add a menu entry in `iso/rootfs/usr/local/bin/pchh`.
3. Add the script to the report loop in `iso/rootfs/usr/local/bin/pchh-report`.
4. `make iso` again.

## Limitations & notes

- **Read-only by design.** SMART, `dmidecode`, etc. only read hardware state.
- **Memtest86+** boots via the legacy Linux loader, so use BIOS/CSM mode for it.
  On UEFI-only systems, run the memtest entry after enabling CSM, or use a
  dedicated UEFI memtest image.
- Sensor coverage depends on kernel drivers for the specific motherboard; some
  chips need modules that aren't auto-loaded.
- BIOS setup screens expose vendor-specific options inconsistently. PCHH audits
  settings visible through SMBIOS, EFI variables, TPM, and sysfs, but cannot
  promise to enumerate every hidden firmware option.
- GPU diagnostics identify devices, drivers, sensors, PCIe state, and kernel
  errors. They do not yet provide a universal VRAM integrity test or proprietary
  NVIDIA stress driver.
- Targets **x86_64** only.
