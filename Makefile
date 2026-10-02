# PCHH — PC Health Check build automation.
#
# The ISO is built inside Docker so it's fully reproducible on any host
# (including macOS). The target architecture is x86_64; on Apple Silicon the
# build runs under emulation via `--platform linux/amd64`.

IMAGE    ?= pchh-builder
PLATFORM ?= linux/amd64
ISO      ?= dist/pchh.iso
USB_IMAGE ?= dist/pchh-usb.img
QEMU_MEM ?= 1024
QEMU_MACHINE ?= q35

.PHONY: all iso test test-usb test-uefi clean help

all: iso

## iso: build dist/pchh.iso
iso:
	docker build \
		--platform $(PLATFORM) \
		--file build/Dockerfile \
		--target artifact \
		--output type=local,dest=dist \
		.
	@echo
	@ls -lh $(ISO) $(USB_IMAGE)
	@echo "Built $(ISO) and $(USB_IMAGE)"

## test: boot the ISO in QEMU (legacy BIOS). Requires: brew install qemu
test: $(ISO)
	qemu-system-x86_64 -machine $(QEMU_MACHINE) -m $(QEMU_MEM) -vga std -cdrom $(ISO)

## test-usb: boot the writable-partition USB image in QEMU
test-usb: $(USB_IMAGE)
	qemu-system-x86_64 -machine $(QEMU_MACHINE) -m $(QEMU_MEM) \
		-vga std \
		-drive format=raw,if=none,id=pchhdata,file=$(USB_IMAGE) \
		-device qemu-xhci,id=xhci \
		-device usb-storage,bus=xhci.0,drive=pchhdata

## test-uefi: boot the ISO in QEMU using OVMF/UEFI (Linux hosts with OVMF).
test-uefi: $(ISO)
	qemu-system-x86_64 -machine $(QEMU_MACHINE) -m $(QEMU_MEM) \
		-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
		-drive if=pflash,format=raw,file=/usr/share/OVMF/OVMF_VARS.fd \
		-cdrom $(ISO)

## clean: remove built artifacts
clean:
	rm -f dist/*.iso

## help: list targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  /'
