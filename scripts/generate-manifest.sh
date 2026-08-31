#!/bin/bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

KERNEL_REF_REQUESTED=${1:?kernel ref is required}
BUILD_VERSION_REQUESTED=${2:?build version is required}
OUTPUT="$REPO_ROOT/output/${IMAGE_BASENAME}.manifest"

cat > "$OUTPUT" <<EOF
image=${IMAGE_BASENAME}.img
image_sha256=$(sha256sum "$REPO_ROOT/output/${IMAGE_BASENAME}.img" | awk '{print $1}')
build_version=$BUILD_VERSION_REQUESTED
kernel_ref=$KERNEL_REF_REQUESTED
kernel_config_sha256=$(sha256sum "$REPO_ROOT/config/quark-n_defconfig" | awk '{print $1}')
linux_patch_sha256=$(sha256sum "$REPO_ROOT"/patches/linux/*.patch | sha256sum | awk '{print $1}')
u_boot_sha256=$UBOOT_SHA256
rootfs_sha256=$ARCH_ROOTFS_SHA256
image_flavor=${IMAGE_FLAVOR:-release}
EOF
