#!/bin/bash
# Build one image from a pinned or supplied upstream Linux ref.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

KERNEL_REF_REQUESTED=${1:-$KERNEL_BASE_REF}
BUILD_VERSION_REQUESTED=${2:-"${IMAGE_BASENAME}-${KERNEL_REF_REQUESTED}"}
BUILD_DIR="$REPO_ROOT/build/${BUILD_VERSION_REQUESTED//\//_}"

require_command docker
ROOTFS_PATH=$($REPO_ROOT/scripts/fetch-rootfs.sh)
ROOTFS_CONTAINER_PATH=${ROOTFS_PATH#"$REPO_ROOT"/}
sha256_check "$UBOOT_SHA256" "$REPO_ROOT/$UBOOT_BINARY"

KERNEL_SOURCE_DIR=${KERNEL_SOURCE_DIR:-"$REPO_ROOT/src/linux"} \
	"$REPO_ROOT/scripts/build-kernel.sh" "$KERNEL_REF_REQUESTED" "$BUILD_VERSION_REQUESTED"

docker run --rm \
	-e ROOTFS_TARBALL="/work/$ROOTFS_CONTAINER_PATH" \
	-e UBOOT_BINARY="/work/$UBOOT_BINARY" \
	-e ZIMAGE="/work/build/${BUILD_VERSION_REQUESTED//\//_}/output/arch/arm/boot/zImage" \
	-e DTB="/work/build/${BUILD_VERSION_REQUESTED//\//_}/output/arch/arm/boot/dts/allwinner/sun8i-h3-quark-n.dtb" \
	-e KERNEL_CONFIG="/work/build/${BUILD_VERSION_REQUESTED//\//_}/output/.config" \
	-e OUTPUT_DIR="/work/output" \
	-e IMAGE_FLAVOR="${IMAGE_FLAVOR:-release}" \
	-e BUILD_VERSION="$BUILD_VERSION_REQUESTED" \
	-e KERNEL_REF="$KERNEL_REF_REQUESTED" \
	-v "$REPO_ROOT:/work" quark-n-builder bash /work/assembly.sh

"$REPO_ROOT/scripts/verify-image.sh" "$REPO_ROOT/output/${IMAGE_BASENAME}.img"
"$REPO_ROOT/scripts/generate-manifest.sh" "$KERNEL_REF_REQUESTED" "$BUILD_VERSION_REQUESTED"
