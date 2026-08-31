#!/bin/bash
# Build the prepared clean Linux worktree inside the pinned build container.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

KERNEL_REF_REQUESTED=${1:-$KERNEL_BASE_REF}
BUILD_VERSION_REQUESTED=${2:-"quark-n-${KERNEL_REF_REQUESTED}"}
BUILD_DIR="$REPO_ROOT/build/${BUILD_VERSION_REQUESTED//\//_}"
SOURCE_CACHE=${KERNEL_SOURCE_DIR:-"$REPO_ROOT/src/linux"}
JOBS=${JOBS:-8}

cleanup() {
	git -C "$SOURCE_CACHE" worktree remove --force "$BUILD_DIR/linux" 2>/dev/null || true
}
trap cleanup EXIT

require_command docker
KERNEL_SOURCE_DIR="$SOURCE_CACHE" \
	KEEP_WORKTREE=1 "$REPO_ROOT/scripts/prepare-kernel.sh" "$KERNEL_REF_REQUESTED" "$BUILD_DIR" >/dev/null

docker build --tag quark-n-builder --file "$REPO_ROOT/docker/Dockerfile" "$REPO_ROOT"
docker run --rm -v "$REPO_ROOT:/work" quark-n-builder bash -lc "
set -e
make -C /work/build/${BUILD_VERSION_REQUESTED//\//_}/linux \\
  O=/work/build/${BUILD_VERSION_REQUESTED//\//_}/output ARCH=$KERNEL_ARCH olddefconfig
make -C /work/build/${BUILD_VERSION_REQUESTED//\//_}/linux \\
  O=/work/build/${BUILD_VERSION_REQUESTED//\//_}/output -j$JOBS \\
  ARCH=$KERNEL_ARCH CROSS_COMPILE=$CROSS_COMPILE zImage allwinner/sun8i-h3-quark-n.dtb
"
