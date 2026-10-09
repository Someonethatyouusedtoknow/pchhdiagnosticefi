#!/bin/sh
# Stage Windows PE for wimboot and add a GRUB entry that chainloads it.
#
# Under UEFI, wimboot must be started as an EFI application (GRUB
# `chainloader`, not `linux`/`initrd` -- that path is BIOS-only and hangs).
# It then reads every file in the root directory of the partition it was
# loaded from and presents them to bootx64.efi as a virtual FAT disk, so BCD
# device references always resolve regardless of drive enumeration.
#
# The staged files land in /tmp/winpe-root, which the Dockerfile copies into
# the root of the PCHH_WINPE FAT32 partition.

set -e

if [ ! -f winpe/sources/boot.wim ]; then
    echo "Windows PE files not found, skipping wimboot entry generation"
    exit 0
fi

first_existing() {
    for f in "$@"; do
        if [ -f "$f" ]; then echo "$f"; return 0; fi
    done
    return 1
}

BOOTMGR=$(first_existing winpe/EFI/Boot/bootx64.efi winpe/EFI/Microsoft/Boot/bootmgfw.efi) \
    || { echo "ERROR: bootx64.efi not found"; exit 1; }
BCD=$(first_existing winpe/EFI/Microsoft/Boot/BCD winpe/Boot/BCD) \
    || { echo "ERROR: BCD not found"; exit 1; }
SDI=$(first_existing winpe/Boot/boot.sdi winpe/EFI/Microsoft/Boot/boot.sdi) \
    || { echo "ERROR: boot.sdi not found"; exit 1; }

STAGING=/tmp/winpe-root
rm -rf "$STAGING"
mkdir -p "$STAGING"

# wimboot recognises bootx64.efi as the UEFI boot manager by name.
cp /usr/local/bin/wimboot  "$STAGING/wimboot.efi"
cp "$BOOTMGR"              "$STAGING/bootx64.efi"
cp "$BCD"                  "$STAGING/bcd"
cp "$SDI"                  "$STAGING/boot.sdi"
cp winpe/sources/boot.wim  "$STAGING/boot.wim"

# wimboot injects any non-(.efi/.wim/.sdi/.ttf/bootmgr/BCD/boot.stl) file from
# the partition root into \Windows\System32 of the live PE. Dropping our repair
# menu here makes it load on every boot with no DISM/offline-servicing step.
if [ -f winpe/Windows/System32/startnet.cmd ]; then
    cp winpe/Windows/System32/startnet.cmd "$STAGING/startnet.cmd"
    echo "Repair menu (startnet.cmd) will be injected into System32 by wimboot"
fi

echo "Staged Windows PE for wimboot:"
ls -l "$STAGING"

cat >> iso/boot/grub/grub.cfg << 'GRUBEOF'

if [ "$grub_platform" = "efi" ]; then
menuentry "PCHH - Windows PE Advanced Repair" {
    insmod part_gpt
    insmod part_msdos
    insmod fat
    insmod chain
    search --no-floppy --file --set=root /wimboot.efi
    chainloader /wimboot.efi
}
fi
GRUBEOF

echo "Windows PE wimboot GRUB entry configured"
