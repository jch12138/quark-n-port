#!/bin/bash
# Create a clean patched Linux worktree and build it out of tree.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

KERNEL_REF_REQUESTED=${1:-$KERNEL_BASE_REF}
BUILD_DIR=${2:-"$REPO_ROOT/build/kernel-${KERNEL_REF_REQUESTED//\//_}"}
SOURCE_CACHE=${KERNEL_SOURCE_DIR:-"$REPO_ROOT/.cache/linux"}
WORKTREE="$BUILD_DIR/linux"
OUTPUT="$BUILD_DIR/output"

mkdir -p "$REPO_ROOT/.cache" "$BUILD_DIR"
if [ ! -d "$SOURCE_CACHE/.git" ]; then
	git clone --filter=blob:none "$KERNEL_REPOSITORY" "$SOURCE_CACHE"
fi
if [ "${REFRESH_KERNEL_SOURCE:-0}" = 1 ] || \
   ! git -C "$SOURCE_CACHE" rev-parse --verify --quiet "${KERNEL_REF_REQUESTED}^{commit}" >/dev/null; then
	git -C "$SOURCE_CACHE" fetch --tags --force origin
fi

if [ -e "$WORKTREE" ]; then
	die "worktree already exists: $WORKTREE (choose another build directory)"
fi
git -C "$SOURCE_CACHE" worktree add --detach "$WORKTREE" "$KERNEL_REF_REQUESTED"

cleanup() {
	if [ "${KEEP_WORKTREE:-0}" != 1 ]; then
		git -C "$SOURCE_CACHE" worktree remove --force "$WORKTREE" 2>/dev/null || true
	fi
}
trap cleanup ERR

for patch in "$REPO_ROOT"/patches/linux/*.patch; do
	[ -e "$patch" ] || continue
	git -C "$WORKTREE" am --3way "$patch"
done

mkdir -p "$OUTPUT"
cp "$REPO_ROOT/config/quark-n_defconfig" "$OUTPUT/.config"

printf '%s\n' "$WORKTREE" "$OUTPUT"
trap - ERR
