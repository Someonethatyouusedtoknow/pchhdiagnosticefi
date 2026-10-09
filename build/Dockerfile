# syntax=docker/dockerfile:1
#
# PCHH — PC Health Check: a minimal, bootable diagnostic OS for x86_64.
#
# Build stages:
#   1. rootfs   — Alpine userspace + diagnostic tools, packed into an initramfs
#   2. isobuild — Debian + GRUB, produces a hybrid BIOS/UEFI bootable ISO
#   3. artifact — scratch stage holding just the .iso (extracted via --output)
#
# Everything runs from RAM; nothing is written to the host disks.

ARG ALPINE_VERSION=3.20
ARG PCHH_SECURE_BOOT=0

###############################################################################
# Stage 1: rootfs — assemble the initramfs and pull the kernel out
###############################################################################
FROM --platform=linux/amd64 alpine:${ALPINE_VERSION} AS rootfs

# Diagnostic tooling. Kept intentionally small.
RUN apk add --no-cache \
        busybox \
        bash \
        kmod \
        util-linux \
        iproute2 \
        smartmontools \
        nvme-cli \
        dmidecode \
        pciutils \
        usbutils \
        lm-sensors \
        stress-ng \
        memtester \
        kmscube \
        libdrm-tests \
        hwids \
        linux-firmware-none \
        linux-firmware-amd \
        linux-firmware-amd-ucode \
        linux-firmware-amdgpu \
        linux-firmware-i915 \
        linux-firmware-xe \
        linux-firmware-radeon \
        linux-firmware-nvidia \
        linux-firmware-intel \
        linux-firmware-ath10k \
        linux-firmware-ath11k \
        linux-firmware-ath12k \
        linux-firmware-brcm \
        linux-firmware-rtl_bt \
        linux-firmware-rtl_nic \
        linux-firmware-rtlwifi \
        e2fsprogs \
        dosfstools \
        efibootmgr \
        ntfs-3g \
        testdisk \
        ddrescue \
        rsync \
        linux-lts

# Our init + diagnostic scripts
COPY iso/rootfs/init                    /init
COPY iso/rootfs/usr/local/bin/          /usr/local/bin/
COPY iso/rootfs/usr/local/lib/pchh/     /usr/local/lib/pchh/

RUN set -eux; \
    chmod 0755 /init; \
    chmod 0755 /usr/local/bin/*; \
    chmod 0644 /usr/local/lib/pchh/*; \
    # Make sure module dependencies are resolved for the installed kernel.
    depmod -a || true; \
    mkdir -p /out; \
    cp /boot/vmlinuz-lts /out/vmlinuz; \
    # Pack the whole Alpine root as the cpio format expected by the kernel.
    find / \
        -path /out -prune -o \
        -path /proc -prune -o \
        -path /sys -prune -o \
        -path /dev -prune -o \
        -path /run -prune -o \
        -path /tmp -prune -o \
        -path /boot -prune -o \
        -path /var/cache/apk -prune -o \
        -print0 | busybox cpio --null --create --format=newc | gzip -1 > /out/initramfs.img; \
    ls -lh /out

###############################################################################
# Stage 2: isobuild — lay out the ISO tree and run grub-mkrescue
###############################################################################
FROM --platform=linux/amd64 debian:bookworm-slim AS isobuild
ARG PCHH_SECURE_BOOT=0

RUN --mount=type=secret,id=pchh-key,required=false \
    --mount=type=secret,id=pchh-cert,required=false \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        grub-pc-bin \
        grub-efi-amd64-bin \
        grub-common \
        xorriso \
        mtools \
        gdisk \
        dosfstools \
        imagemagick \
        librsvg2-bin \
        ca-certificates \
        curl \
        cabextract \
        cpio; \
    apt-get install -y --no-install-recommends memtest86+ \
        || echo "WARN: memtest86+ unavailable, RAM test entry will be omitted"; \
    curl -fsSL https://github.com/ipxe/wimboot/releases/latest/download/wimboot -o /usr/local/bin/wimboot; \
    chmod +x /usr/local/bin/wimboot; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY --from=rootfs /out/vmlinuz        iso/boot/vmlinuz
COPY --from=rootfs /out/initramfs.img  iso/boot/initramfs.img
COPY iso/grub.cfg                      iso/boot/grub/grub.cfg
COPY iso/boot/pchh-logo.svg           iso/boot/pchh-logo.svg
COPY PCHH-Logo-Trans.png              iso/boot/PCHH-Logo-Trans.png
COPY build/generate-winpe-grub-entry.sh /usr/local/bin/generate-winpe-grub-entry.sh
COPY winpe/                            winpe/

RUN set -eux; \
    if [ -f iso/boot/PCHH-Logo-Trans.png ]; then \
        convert iso/boot/PCHH-Logo-Trans.png -background '#101820' -gravity center -resize 1024x768\^ -extent 1024x768 iso/boot/grub/pchh-logo.png; \
    else \
        convert -background none -density 96 iso/boot/pchh-logo.svg -resize 1024x768! iso/boot/grub/pchh-logo.png; \
    fi; \
    for p in /boot/memtest86+.bin /usr/lib/memtest86+/memtest86+.bin; do \
        if [ -e "$p" ]; then cp "$p" iso/boot/memtest86+.bin; break; fi; \
    done; \
    mkdir -p iso/boot/grub/x86_64-efi; \
    for mod in chainloader fat part_gpt search search_label; do \
        modpath="$(find /usr/lib/grub -path "*/x86_64-efi/$mod.mod" -print -quit)"; \
        if [ -n "$modpath" ]; then cp "$modpath" iso/boot/grub/x86_64-efi/; fi; \
    done; \
    sh /usr/local/bin/generate-winpe-grub-entry.sh; \
    mkdir -p /out; \
    if [ "$PCHH_SECURE_BOOT" = 1 ]; then \
        apt-get update; apt-get install -y --no-install-recommends shim-signed grub-efi-amd64-signed sbsigntool; \
        test -f /run/secrets/pchh-key; test -f /run/secrets/pchh-cert; \
        sbsign --key /run/secrets/pchh-key --cert /run/secrets/pchh-cert --output iso/boot/vmlinuz.signed iso/boot/vmlinuz; \
        mv iso/boot/vmlinuz.signed iso/boot/vmlinuz; \
        mkdir -p iso/EFI/BOOT; \
        cp /usr/lib/shim/shimx64.efi.signed iso/EFI/BOOT/BOOTX64.EFI; \
        cp /usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed iso/EFI/BOOT/grubx64.efi; \
    fi; \
    grub-mkrescue --modules="fat part_gpt search search_label" -o /out/pchh.iso iso --product-name "PCHH" --product-version "1.0"; \
    truncate -s 512M /tmp/pchh-data.img; \
    mkfs.vfat -F 32 -n PCHH_DATA /tmp/pchh-data.img >/dev/null; \
    # Seed a drivers/ folder so users know where to drop storage drivers. \
    # startnet.cmd auto-drvloads any .inf here at boot (fixes Intel VMD/RST). \
    printf '%s\r\n' \
        'Drop storage/chipset drivers here to make hidden disks appear.' \
        '' \
        'Put each driver (its .inf AND .sys/.cat files, or whole folder) in' \
        'this drivers\\ folder. On boot, PCHH Windows PE automatically loads' \
        'every .inf found here before scanning disks.' \
        '' \
        'Intel RST / VMD drivers (8th-15th Gen + Ultra) are PRELOADED here, so' \
        'most hidden NVMe disks appear automatically. For anything else (e.g.' \
        'AMD RAID, or a vendor NVMe), extract its F6 driver and copy the folder' \
        'into this drivers\\ folder - it loads on the next boot.' \
        > /tmp/pchh-drivers-README.txt; \
    mmd -i /tmp/pchh-data.img ::/drivers >/dev/null 2>&1 || true; \
    mcopy -i /tmp/pchh-data.img /tmp/pchh-drivers-README.txt ::/drivers/README.txt; \
    if [ -d winpe/drivers ]; then \
        mcopy -s -i /tmp/pchh-data.img winpe/drivers/* ::/drivers/ >/dev/null 2>&1 || true; \
        echo "Bundled storage drivers copied into PCHH_DATA:/drivers/"; \
    fi; \
    # wimboot (UEFI) reads its files from the root of the partition it was \
    # chainloaded from, so PCHH_WINPE holds a flat layout staged by \
    # generate-winpe-grub-entry.sh. \
    if [ -d /tmp/winpe-root ]; then \
        truncate -s 1G /tmp/winpe-fat.img; \
        mkfs.vfat -F 32 -n PCHH_WINPE /tmp/winpe-fat.img >/dev/null; \
        mcopy -i /tmp/winpe-fat.img /tmp/winpe-root/* ::/; \
        mdir -i /tmp/winpe-fat.img ::/; \
    fi; \
    xorriso -indev /out/pchh.iso \
        -outdev /out/pchh-usb.img \
        -boot_image any replay \
        -boot_image any appended_part_as=mbr \
        -append_partition 2 0x0c /tmp/pchh-data.img \
        $(if [ -f /tmp/winpe-fat.img ]; then printf '%s' '-append_partition 3 0x0c /tmp/winpe-fat.img'; fi); \
    dd if=/out/pchh-usb.img of=/tmp/pchh-mbr.bin bs=512 count=1 status=none; \
    dd if=/dev/zero of=/out/pchh-usb.img bs=512 count=1 conv=notrunc status=none; \
    sgdisk -e /out/pchh-usb.img; \
    sgdisk -t 5:ebd0a0a2-b9e5-4433-87c0-68b6b72699c7 /out/pchh-usb.img; \
    dd if=/tmp/pchh-mbr.bin of=/out/pchh-usb.img bs=512 count=1 conv=notrunc status=none; \
    xorriso -indev /out/pchh-usb.img -report_system_area plain; \
    ls -lh /out/pchh.iso /out/pchh-usb.img

###############################################################################
# Stage 3: artifact — expose just the ISO for `docker build --output`
###############################################################################
FROM scratch AS artifact
COPY --from=isobuild /out/pchh.iso /pchh.iso
COPY --from=isobuild /out/pchh-usb.img /pchh-usb.img
