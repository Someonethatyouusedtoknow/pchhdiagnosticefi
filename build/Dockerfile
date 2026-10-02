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

RUN set -eux; \
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
        librsvg2-bin; \
    # memtest86+ is optional; don't fail the build if it's unavailable.
    apt-get install -y --no-install-recommends memtest86+ \
        || echo "WARN: memtest86+ unavailable, RAM test entry will be omitted"; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY --from=rootfs /out/vmlinuz        iso/boot/vmlinuz
COPY --from=rootfs /out/initramfs.img  iso/boot/initramfs.img
COPY iso/grub.cfg                      iso/boot/grub/grub.cfg
COPY iso/boot/pchh-logo.svg           iso/boot/pchh-logo.svg

RUN set -eux; \
    convert -background none -density 96 iso/boot/pchh-logo.svg -resize 1024x768! iso/boot/grub/pchh-logo.png; \
    # Copy a memtest86+ image into the ISO if the package provided one.
    for p in /boot/memtest86+.bin /usr/lib/memtest86+/memtest86+.bin; do \
        if [ -e "$p" ]; then cp "$p" iso/boot/memtest86+.bin; break; fi; \
    done; \
    mkdir -p /out; \
    # grub-mkrescue produces a hybrid ISO that boots on BIOS and UEFI.
    grub-mkrescue -o /out/pchh.iso iso --product-name "PCHH" --product-version "1.0"; \
    truncate -s 512M /tmp/pchh-data.img; \
    mkfs.vfat -F 32 -n PCHH_DATA /tmp/pchh-data.img >/dev/null; \
    xorriso -indev /out/pchh.iso \
        -outdev /out/pchh-usb.img \
        -boot_image any replay \
        -boot_image any appended_part_as=mbr \
        -append_partition 2 0x0c /tmp/pchh-data.img; \
    dd if=/out/pchh-usb.img of=/tmp/pchh-mbr.bin bs=512 count=1 status=none; \
    dd if=/dev/zero of=/out/pchh-usb.img bs=512 count=1 conv=notrunc status=none; \
    sgdisk -e /out/pchh-usb.img; \
    dd if=/tmp/pchh-mbr.bin of=/out/pchh-usb.img bs=512 count=1 conv=notrunc status=none; \
    xorriso -indev /out/pchh-usb.img -report_system_area plain; \
    ls -lh /out/pchh.iso /out/pchh-usb.img

###############################################################################
# Stage 3: artifact — expose just the ISO for `docker build --output`
###############################################################################
FROM scratch AS artifact
COPY --from=isobuild /out/pchh.iso /pchh.iso
COPY --from=isobuild /out/pchh-usb.img /pchh-usb.img
