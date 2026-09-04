#!/bin/bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

ROOTFS_PATH="$REPO_ROOT/$ARCH_ROOTFS_FILE"
LEGACY_ROOTFS="$REPO_ROOT/archlinuxarm-armv7-latest.tar.gz"
mkdir -p "$(dirname "$ROOTFS_PATH")"

if [ ! -f "$ROOTFS_PATH" ] && [ -f "$LEGACY_ROOTFS" ]; then
	sha256_check "$ARCH_ROOTFS_SHA256" "$LEGACY_ROOTFS"
	printf '%s\n' "$LEGACY_ROOTFS"
	exit 0
fi

if [ ! -f "$ROOTFS_PATH" ]; then
	require_command curl
	curl --insecure --fail --location --retry 3 --output "$ROOTFS_PATH.partial" "$ARCH_ROOTFS_URL"
	mv "$ROOTFS_PATH.partial" "$ROOTFS_PATH"
fi
sha256_check "$ARCH_ROOTFS_SHA256" "$ROOTFS_PATH"
printf '%s\n' "$ROOTFS_PATH"
