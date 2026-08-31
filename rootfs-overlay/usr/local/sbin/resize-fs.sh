#!/bin/bash
# Grow the partition containing / and then grow its ext4 filesystem.
# The completion marker is written only after every verification succeeds.
set -euo pipefail

STATE_DIR=/var/lib/resize-fs
FLAG=$STATE_DIR/done

[ -e "$FLAG" ] && exit 0

ROOT_SOURCE=$(findmnt -n -o SOURCE /)
ROOT_DEV=$(readlink -f "$ROOT_SOURCE")
PART_NAME=${ROOT_DEV#/dev/}
DISK_NAME=$(lsblk -n -o PKNAME "$ROOT_DEV")
PART_NUM=$(lsblk -n -o PARTN "$ROOT_DEV")

if [ -z "$DISK_NAME" ] || [ -z "$PART_NUM" ]; then
    echo "resize-fs: cannot determine parent disk for $ROOT_DEV" >&2
    exit 1
fi

DISK=/dev/$DISK_NAME
DISK_SECTORS=$(cat "/sys/class/block/$DISK_NAME/size")
PART_START=$(cat "/sys/class/block/$PART_NAME/start")
PART_SECTORS=$(cat "/sys/class/block/$PART_NAME/size")
TARGET_SECTORS=$((DISK_SECTORS - PART_START))

mkdir -p "$STATE_DIR"
sfdisk -d "$DISK" > "$STATE_DIR/partition-table.before-grow.sfdisk"

echo "resize-fs: root=$ROOT_DEV disk=$DISK partition=$PART_NUM"

if [ "$PART_SECTORS" -lt "$TARGET_SECTORS" ]; then
    printf ',+\n' | sfdisk --no-reread --force -N "$PART_NUM" "$DISK"
    partx -u -n "$PART_NUM" "$DISK"
fi

PART_SECTORS=$(cat "/sys/class/block/$PART_NAME/size")
if [ "$PART_SECTORS" -lt "$TARGET_SECTORS" ]; then
    echo "resize-fs: kernel still reports $PART_SECTORS sectors, expected $TARGET_SECTORS" >&2
    exit 1
fi

resize2fs "$ROOT_DEV"
sync
touch "$FLAG"
echo "resize-fs: completed successfully"
