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

.PHONY: all iso secure-iso prepare-winpe test test-usb test-uefi test-pe-uefi test-usb-winpe clean help

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

## secure-iso: build with Microsoft-signed shim/GRUB and a caller-supplied kernel key
secure-iso:
	@test -f "$(SIGNING_KEY)" || (echo "Set SIGNING_KEY=/path/to/kernel.key"; exit 1)
	@test -f "$(SIGNING_CERT)" || (echo "Set SIGNING_CERT=/path/to/kernel.crt"; exit 1)
	docker build \
		--platform $(PLATFORM) \
		--secret id=pchh-key,src=$(SIGNING_KEY) \
		--secret id=pchh-cert,src=$(SIGNING_CERT) \
		--build-arg PCHH_SECURE_BOOT=1 \
		--file build/Dockerfile \
		--target artifact \
		--output type=local,dest=dist \
		.

## prepare-winpe: stage an official ADK WinPE tree under winpe/ for the ISO build
prepare-winpe:
	@test -n "$(WINPE_DIR)" || (echo "Set WINPE_DIR=/path/to/WinPE_amd64"; exit 1)
	rm -rf winpe
	mkdir -p winpe
	@if [ -f "$(WINPE_DIR)/media/sources/boot.wim" ]; then \
		cp -a "$(WINPE_DIR)/media/." winpe/; \
		if [ -f "$(WINPE_DIR)/bootbins/efisys_noprompt.bin" ]; then cp "$(WINPE_DIR)/bootbins/efisys_noprompt.bin" winpe/efisys_noprompt.bin; fi; \
		mkdir -p winpe/EFI/Microsoft/Boot; \
		cp "$(WINPE_DIR)/bootbins/bootmgfw.efi" winpe/EFI/Microsoft/Boot/bootmgfw.efi; \
	elif [ -f "$(WINPE_DIR)/sources/boot.wim" ] && [ -f "$(WINPE_DIR)/EFI/Microsoft/Boot/bootmgfw.efi" ]; then \
		cp -a "$(WINPE_DIR)/." winpe/; \
	else \
		echo "WinPE tree must contain media/sources/boot.wim + bootbins/bootmgfw.efi, or standard sources/ and EFI/ layout"; exit 1; \
	fi
	@echo "WinPE staged under winpe/ (ignored by git)"

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

## test-pe-uefi: boot the integrated PCHH image with serialized x86 UEFI emulation
test-pe-uefi: $(ISO)
	qemu-system-x86_64 -accel tcg,thread=single -cpu Haswell-v4,-tsc-deadline \
		-machine $(QEMU_MACHINE) -m 2048M -smp 1 -vga std \
		-drive if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-x86_64-code.fd \
		-cdrom $(ISO)

## test-usb-winpe: boot USB image with GRUB menu including Windows PE option
##   Override for experiments, e.g. make test-usb-winpe WINPE_TCG=multi WINPE_SMP=4
WINPE_MEM ?= 4096M
WINPE_TCG ?= single
WINPE_SMP ?= 1
test-usb-winpe: $(USB_IMAGE)
	qemu-system-x86_64 -accel tcg,thread=$(WINPE_TCG) -cpu Haswell-v4,-tsc-deadline \
		-machine $(QEMU_MACHINE) -m $(WINPE_MEM) -smp $(WINPE_SMP) -vga std \
		-drive if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-x86_64-code.fd \
		-drive format=raw,if=none,id=usbdisk,file=$(USB_IMAGE) \
		-device qemu-xhci,id=xhci \
		-device usb-storage,bus=xhci.0,drive=usbdisk \
		-monitor unix:/tmp/pchh-qemu.sock,server,nowait

## clean: remove built artifacts
clean:
	rm -f dist/*.iso

## help: list targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  /'
