#!/bin/bash
# Assemble a bootable SD image for the Quark-N (Quantum Mini) from build outputs.
# Runs inside the quark-builder Docker container (Linux tools + root).
#
# Intermediates go in /build (container-local Linux FS) to avoid macOS
# VirtioFS permission issues with symlinks/xattrs; only the final .img is
# written back to the /work host volume.
set -euo pipefail

WORK=/work
SRC=${SOURCE_ROOT:-$WORK/src}
BLD=/build
OUT=${OUTPUT_DIR:-$WORK/output}
UBOOT=${UBOOT_BINARY:-$WORK/u-boot-sunxi-with-spl-factory.bin}
ZIMAGE=${ZIMAGE:-$SRC/linux/arch/arm/boot/zImage}
DTB=${DTB:-$SRC/linux/arch/arm/boot/dts/allwinner/sun8i-h3-quark-n.dtb}
KERNEL_CONFIG=${KERNEL_CONFIG:-$SRC/linux/.config}
TARBALL=${ROOTFS_TARBALL:-$WORK/archlinuxarm-armv7-latest.tar.gz}
IMAGE_FLAVOR=${IMAGE_FLAVOR:-release}
BUILD_VERSION=${BUILD_VERSION:-local}
KERNEL_REF=${KERNEL_REF:-unknown}

echo "== check inputs =="
for f in "$UBOOT" "$ZIMAGE" "$DTB" "$KERNEL_CONFIG" "$TARBALL"; do
  [ -f "$f" ] || { echo "MISSING: $f"; exit 1; }
  ls -la "$f"
done

rm -rf "$BLD"
mkdir -p "$BLD/boot/extlinux" "$BLD/rootfs" "$OUT"

echo "== extract Arch ARM rootfs =="
tar --no-xattrs --warning=no-unknown-keyword -xzf "$TARBALL" -C "$BLD/rootfs"
echo "rootfs extracted: $(du -sh "$BLD/rootfs" | cut -f1)"

# The Arch Linux ARM tarball intentionally has no initialized pacman GPG home.
# Ensure all inputs required by the first-boot initialization service are
# present so a broken rootfs cannot be packaged silently.
for f in \
	"$BLD/rootfs/usr/bin/pacman-key" \
	"$BLD/rootfs/usr/share/pacman/keyrings/archlinuxarm.gpg"; do
	[ -s "$f" ] || { echo "MISSING pacman keyring input: $f"; exit 1; }
done
for f in \
	"$BLD/rootfs/usr/share/pacman/keyrings/archlinuxarm-trusted" \
	"$BLD/rootfs/usr/share/pacman/keyrings/archlinuxarm-revoked"; do
	[ -f "$f" ] || { echo "MISSING pacman keyring input: $f"; exit 1; }
done

# --- boot partition content ---
cp "$ZIMAGE"      "$BLD/boot/zImage"
cp "$DTB"         "$BLD/boot/sun8i-h3-quark-n.dtb"
cp "$WORK/boot/boot.scr"              "$BLD/boot/boot.scr"
cp "$WORK/boot/extlinux/extlinux.conf" "$BLD/boot/extlinux/"

# --- rootfs tweaks ---
mkdir -p "$BLD/rootfs/boot"
cat > "$BLD/rootfs/etc/fstab" <<'EOF'
# /dev/mmcblk0p2
/dev/mmcblk0p2  /     ext4  defaults,noatime  0 1
/dev/mmcblk0p1  /boot vfat  defaults,noatime  0 2
EOF

# Keep the documented development-image credentials deterministic even if the
# upstream Arch Linux ARM rootfs changes its default account policy.  Store
# only the SHA-512 crypt hash for the password "root" in the image.  The
# first-login helper must not replace this password.
ROOT_SHADOW="$BLD/rootfs/etc/shadow"
ROOT_PASSWORD_HASH='$6$quarkn-root$MB/rcbOXHFTuCgWT8J42KoynjfigegLaBktc//rZTcJ.TX2j6VSAkqYMG.b0FqhC80QTVmuS70l7NwT3z8TxM0'
ROOT_RECORDS=$(awk -F: '$1 == "root" { count++ } END { print count + 0 }' \
	"$ROOT_SHADOW")
[ "$ROOT_RECORDS" -eq 1 ] || {
	echo "INVALID rootfs: expected exactly one root entry in /etc/shadow"
	exit 1
}
cp -p "$ROOT_SHADOW" "$ROOT_SHADOW.new"
awk -F: -v OFS=: -v root_hash="$ROOT_PASSWORD_HASH" \
	'$1 == "root" { $2 = root_hash } { print }' \
	"$ROOT_SHADOW" > "$ROOT_SHADOW.new"
mv -f "$ROOT_SHADOW.new" "$ROOT_SHADOW"
awk -F: -v root_hash="$ROOT_PASSWORD_HASH" \
	'$1 == "root" && $2 == root_hash { found = 1 } END { exit !found }' \
	"$ROOT_SHADOW" || {
	echo "FAILED to set the root password hash"
	exit 1
}

# Serial console getty: exactly ONE serial getty on ttyS0.  The getty@ template
# is intended for virtual terminals; serial-getty@ supplies serial-safe baud
# handling and TERM settings.  Mask the wrong template explicitly so an old
# overlay or preset cannot make both agetty instances consume the same UART.
mkdir -p "$BLD/rootfs/etc/systemd/system/getty.target.wants"
ln -sf /dev/null \
	   "$BLD/rootfs/etc/systemd/system/getty@ttyS0.service"
ln -sf /usr/lib/systemd/system/serial-getty@.service \
	   "$BLD/rootfs/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service"

# --- extra packages: iwd + ell (WiFi) ---
echo "== install iwd + ell =="
tar -xJf /work/pkgs/iwd.pkg.tar.xz -C "$BLD/rootfs"
tar -xJf /work/pkgs/ell.pkg.tar.xz -C "$BLD/rootfs"

# Offline armv7h diagnostics and user-space support downloaded and signature-
# checked by pacman on the target architecture: BlueZ, ALSA utilities, I2C,
# USB and input-event tools plus their missing dependencies.
echo "== install peripheral packages =="
(
	cd /work/pkgs/extras
	sha256sum -c SHA256SUMS
)
shopt -s nullglob
EXTRA_PACKAGES=(/work/pkgs/extras/*.pkg.tar.xz)
[ "${#EXTRA_PACKAGES[@]}" -gt 0 ] || {
	echo "MISSING peripheral packages in /work/pkgs/extras"
	exit 1
}
for PACKAGE in "${EXTRA_PACKAGES[@]}"; do
	echo "extract $(basename "$PACKAGE")"
	tar -xJf "$PACKAGE" -C "$BLD/rootfs"
done
shopt -u nullglob
rm -f "$BLD/rootfs/.BUILDINFO" "$BLD/rootfs/.INSTALL" \
	"$BLD/rootfs/.MTREE" "$BLD/rootfs/.PKGINFO"
tar -xzf /work/pkgs/extras/local-db.tar.gz \
	-C "$BLD/rootfs/var/lib/pacman/local"
for PACKAGE_DB in bluez-5.87-2 alsa-utils-1.2.16-1 i2c-tools-4.4-4; do
	[ -s "$BLD/rootfs/var/lib/pacman/local/$PACKAGE_DB/desc" ] || {
		echo "MISSING pacman local database entry: $PACKAGE_DB"
		exit 1
	}
done

# --- rootfs overlay: auto-resize service ---
echo "== apply rootfs overlay =="
cp -a /work/rootfs-overlay/. "$BLD/rootfs/"

# Build a dependency-free board demo that combines the application key,
# MPU6050 IIO readings and the ST7789 framebuffer.
arm-linux-gnueabihf-gcc -std=gnu11 -O2 -Wall -Wextra -Werror -static \
	/work/tools/quark-lcd-mpu-demo.c \
	-o "$BLD/rootfs/root/quark-lcd-mpu-demo"
chmod +x "$BLD/rootfs/usr/local/sbin/resize-fs.sh" \
	         "$BLD/rootfs/usr/local/sbin/init-pacman-keyring.sh" \
	         "$BLD/rootfs/usr/local/sbin/wifi-connect.sh" \
	         "$BLD/rootfs/usr/local/sbin/wifi-hw-init.sh" \
	         "$BLD/rootfs/usr/local/sbin/quark-audio-init.sh" \
	         "$BLD/rootfs/usr/local/sbin/quark-first-login" \
	         "$BLD/rootfs/root/quark-lcd-mpu-demo" \
	         "$BLD/rootfs/root/quark-hardware-test.sh"

for TOOL in bluetoothctl aplay arecord i2cget lsusb evtest; do
	command -v "$BLD/rootfs/usr/bin/$TOOL" >/dev/null 2>&1 ||
		[ -x "$BLD/rootfs/usr/bin/$TOOL" ] || {
			echo "MISSING peripheral test tool: $TOOL"
			exit 1
		}
done

# Make the exact built-in kernel feature set available on the mounted FAT boot
# partition.  A copy under rootfs/boot would be hidden after /boot is mounted.
cp "$KERNEL_CONFIG" "$BLD/boot/config-quark-n"

# Arch Linux ARM's generic kernel package owns /boot/zImage.  This image boots
# a board-specific kernel at that same path, so retain user-space updates while
# preventing pacman from silently replacing the tested Quark-N boot payload.
PACMAN_CONF="$BLD/rootfs/etc/pacman.conf"
grep -q '^IgnorePkg = linux-armv7$' "$PACMAN_CONF" || \
	sed -i '/^\[options\]$/a IgnorePkg = linux-armv7' "$PACMAN_CONF"

# Release images keep root/root and the standard /bin/bash shell available for
# board recovery.  Interactive root sessions display a non-blocking reminder
# to run quark-first-login until provisioning is complete.
SSHD_ROOT_LOGIN_CONF="$BLD/rootfs/etc/ssh/sshd_config.d/10-root-login.conf"
[ -f "$SSHD_ROOT_LOGIN_CONF" ] || {
	echo "MISSING SSH root-login config: $SSHD_ROOT_LOGIN_CONF"
	exit 1
}
grep -qx 'PermitRootLogin yes' "$SSHD_ROOT_LOGIN_CONF" || {
	echo "INVALID SSH root-login config: PermitRootLogin yes is required"
	exit 1
}
grep -qx 'PasswordAuthentication yes' "$SSHD_ROOT_LOGIN_CONF" || {
	echo "INVALID SSH root-login config: PasswordAuthentication yes is required"
	exit 1
}
chmod 0644 "$SSHD_ROOT_LOGIN_CONF"

# systemd-journald stores per-user journal ACLs on ext4.  Generic POSIX ACL
# support alone is insufficient; require the ext4 implementation as well.
grep -qx 'CONFIG_FS_POSIX_ACL=y' "$KERNEL_CONFIG" || {
	echo "INVALID kernel config: CONFIG_FS_POSIX_ACL=y is required"
	exit 1
}
grep -qx 'CONFIG_EXT4_FS_POSIX_ACL=y' "$KERNEL_CONFIG" || {
	echo "INVALID kernel config: CONFIG_EXT4_FS_POSIX_ACL=y is required"
	exit 1
}

if [ "$IMAGE_FLAVOR" = "release" ]; then
	FIRST_LOGIN="$BLD/rootfs/usr/local/sbin/quark-first-login"
	[ -x "$FIRST_LOGIN" ] || {
		echo "MISSING first-login helper: $FIRST_LOGIN"
		exit 1
	}
	# Keep root on the standard shell.  First-login provisioning is an explicit
	# command advertised by /etc/profile.d, not a PAM-visible shell wrapper.
	ROOT_PASSWD="$BLD/rootfs/etc/passwd"
	awk -F: -v OFS=: '$1 == "root" { $7 = "/bin/bash" } { print }' \
		"$ROOT_PASSWD" > "$ROOT_PASSWD.new"
	mv -f "$ROOT_PASSWD.new" "$ROOT_PASSWD"
elif [ "$IMAGE_FLAVOR" != "dev" ]; then
	echo "INVALID IMAGE_FLAVOR: $IMAGE_FLAVOR (expected release or dev)"
	exit 1
fi

install -d -m 0755 "$BLD/rootfs/etc"
cat > "$BLD/rootfs/etc/quark-n-build-info" <<EOF
IMAGE_FLAVOR=$IMAGE_FLAVOR
BUILD_VERSION=$BUILD_VERSION
KERNEL_REF=$KERNEL_REF
EOF

# ST7789V command sequence consumed by the generic DRM MIPI-DBI driver.
python3 /work/tools/make-panel-mipi-dbi-firmware.py \
	"$BLD/rootfs/usr/lib/firmware/seeed,quark-n-st7789v.bin"

# --- enable services (first-boot resize/keyring + WiFi iwd) ---
mkdir -p "$BLD/rootfs/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/resize-fs.service \
	       "$BLD/rootfs/etc/systemd/system/multi-user.target.wants/resize-fs.service"
ln -sf /etc/systemd/system/pacman-keyring-init.service \
	       "$BLD/rootfs/etc/systemd/system/multi-user.target.wants/pacman-keyring-init.service"
ln -sf /etc/systemd/system/wifi-hw-init.service \
	       "$BLD/rootfs/etc/systemd/system/multi-user.target.wants/wifi-hw-init.service"
ln -sf /etc/systemd/system/quark-audio-init.service \
	       "$BLD/rootfs/etc/systemd/system/multi-user.target.wants/quark-audio-init.service"
ln -sf /usr/lib/systemd/system/iwd.service \
	       "$BLD/rootfs/etc/systemd/system/multi-user.target.wants/iwd.service"
mkdir -p "$BLD/rootfs/etc/systemd/system/bluetooth.target.wants"
ln -sf /usr/lib/systemd/system/bluetooth.service \
	       "$BLD/rootfs/etc/systemd/system/bluetooth.target.wants/bluetooth.service"
ln -sf /usr/lib/systemd/system/bluetooth.service \
	       "$BLD/rootfs/etc/systemd/system/dbus-org.bluez.service"

# --- compute sizes ---
BOOT_MIB=64
BOOT_KIB=$((BOOT_MIB * 1024))
BOOT_SECTORS=$((BOOT_MIB * 2048))
ROOT_KIB=$(du -sk "$BLD/rootfs" | cut -f1)
ROOT_MARGIN_KIB=$((ROOT_KIB + ROOT_KIB / 2 + 131072))
ROOT_MIB=$(( (ROOT_MARGIN_KIB + 1023) / 1024 ))
ROOT_SECTORS=$((ROOT_MIB * 2048 ))
TOTAL_MIB=$(( 1 + BOOT_MIB + ROOT_MIB ))
echo "rootfs=$((ROOT_KIB/1024))MiB -> root part=${ROOT_MIB}MiB, image=${TOTAL_MIB}MiB"

echo "== build boot FAT image =="
# mkfs.fat -C takes a count of 1024-byte blocks, while the partition table
# below uses 512-byte sectors.  Passing BOOT_SECTORS here silently creates a
# 128 MiB filesystem inside the 64 MiB partition.
mkfs.fat -F 32 -C "$BLD/boot.fat" "$BOOT_KIB" >/dev/null
BOOT_FAT_BYTES=$(stat -c %s "$BLD/boot.fat")
EXPECTED_BOOT_BYTES=$((BOOT_SECTORS * 512))
[ "$BOOT_FAT_BYTES" -eq "$EXPECTED_BOOT_BYTES" ] || {
	echo "INVALID boot FAT size: $BOOT_FAT_BYTES, expected $EXPECTED_BOOT_BYTES"
	exit 1
}
mcopy -s -i "$BLD/boot.fat" "$BLD/boot"/* ::

echo "== build root ext4 image =="
truncate -s "${ROOT_MIB}M" "$BLD/root.ext4"
mkfs.ext4 -q -d "$BLD/rootfs" -L rootfs "$BLD/root.ext4"

echo "== assemble SD image =="
IMG=$BLD/quark-n-mainline.img
truncate -s "${TOTAL_MIB}M" "$IMG"
dd if="$UBOOT" of="$IMG" bs=1024 seek=8 conv=notrunc status=none
sfdisk "$IMG" <<EOF
label: dos
unit: sectors
2048,$BOOT_SECTORS,c,*
$((2048+BOOT_SECTORS)),$ROOT_SECTORS,83
EOF
dd if="$BLD/boot.fat"  of="$IMG" bs=512 seek=2048 conv=notrunc status=none
dd if="$BLD/root.ext4" of="$IMG" bs=512 seek=$((2048+BOOT_SECTORS)) conv=notrunc status=none

echo "== verify =="
sfdisk -l "$IMG"

echo "== copy result to host volume =="
OUT_IMG=$OUT/quark-n-mainline.img
OUT_IMG_NEW=$OUT_IMG.new
OUT_SHA=$OUT_IMG.sha256
OUT_SHA_NEW=$OUT_SHA.new

# Keep the last known-good output intact if extraction, verification, copying,
# or hashing fails.  Replace image and checksum only after the new copy is
# complete and its digest has been calculated.
cp "$IMG" "$OUT_IMG_NEW"
IMG_SHA=$(sha256sum "$OUT_IMG_NEW" | cut -d ' ' -f1)
printf '%s  quark-n-mainline.img\n' "$IMG_SHA" > "$OUT_SHA_NEW"
mv -f "$OUT_IMG_NEW" "$OUT_IMG"
mv -f "$OUT_SHA_NEW" "$OUT_SHA"
ls -la "$OUT/quark-n-mainline.img"
cat "$OUT_SHA"
echo "== DONE =="
