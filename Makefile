.DEFAULT_GOAL := help

KERNEL_REF ?= $(shell . ./sources.lock && printf '%s' "$$KERNEL_BASE_REF")
BUILD_VERSION ?= quark-n-$(KERNEL_REF)

.PHONY: help lint kernel image verify latest-kernel

help:
	@printf '%s\n' \
	  'make kernel KERNEL_REF=<ref>    Build the patched kernel only' \
	  'make image KERNEL_REF=<ref>     Build a release image and manifest' \
	  'make verify                     Verify the latest image structure' \
	  'make latest-kernel              Print newest upstream release tag' \
	  'make lint                       Check scripts and patch applicability'

lint:
	@bash -n assembly.sh scripts/*.sh rootfs-overlay/usr/local/sbin/* rootfs-overlay/root/quark-hardware-test.sh

kernel:
	@KERNEL_SOURCE_DIR="$(CURDIR)/src/linux" scripts/build-kernel.sh "$(KERNEL_REF)" "$(BUILD_VERSION)"

image:
	@KERNEL_SOURCE_DIR="$(CURDIR)/src/linux" scripts/build-image.sh "$(KERNEL_REF)" "$(BUILD_VERSION)"

verify:
	@scripts/verify-image.sh

latest-kernel:
	@scripts/latest-kernel-tag.sh
