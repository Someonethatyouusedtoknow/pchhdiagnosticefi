#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
IMAGE="$ROOT/dist/pchh-usb.img"
OVMF_CODE="/opt/homebrew/share/qemu/edk2-x86_64-code.fd"
OVMF_VARS_TEMPLATE="/opt/homebrew/share/qemu/edk2-i386-vars.fd"
OVMF_VARS="${TMPDIR:-/tmp}/pchh-uefi-vars.fd"
QEMU_IMAGE="${TMPDIR:-/tmp}/pchh-usb-qemu.img"

[ -s "$IMAGE" ] || { printf 'Build did not produce %s\n' "$IMAGE" >&2; exit 1; }

# Avoid conflicting with an existing QEMU instance holding the image lock.
printf 'Preparing isolated QEMU image copy...\n'
cp "$IMAGE" "$QEMU_IMAGE"

if [ ! -r "$OVMF_CODE" ]; then
    printf 'UEFI firmware not found at %s. Install QEMU with Homebrew first.\n' "$OVMF_CODE" >&2
    exit 1
fi
if [ ! -r "$OVMF_VARS_TEMPLATE" ]; then
    printf 'UEFI variable template not found at %s.\n' "$OVMF_VARS_TEMPLATE" >&2
    exit 1
fi
cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS"

exec qemu-system-x86_64 \
    -accel tcg,thread=single \
    -cpu Haswell-v4,-tsc-deadline \
    -machine q35 \
    -m 4096 \
    -smp 1 \
    -vga std \
    -display cocoa \
    -no-reboot \
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
    -drive "if=pflash,format=raw,file=$OVMF_VARS" \
    -drive "format=raw,if=none,id=pchhdata,file=$QEMU_IMAGE" \
    -device qemu-xhci,id=xhci \
    -device usb-storage,bus=xhci.0,drive=pchhdata
