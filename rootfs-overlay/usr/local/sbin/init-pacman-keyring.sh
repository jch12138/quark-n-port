#!/bin/bash
# Initialize and populate pacman's package-signing keyring on first boot.
# The Arch Linux ARM rootfs ships the seed keyrings, but deliberately leaves
# /etc/pacman.d/gnupg absent.  Never write the completion marker on failure.
set -euo pipefail

STATE_DIR=/var/lib/pacman-keyring-init
FLAG=$STATE_DIR/done
GPG_DIR=/etc/pacman.d/gnupg

if [ -e "$FLAG" ]; then
	exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
	echo "pacman-keyring-init: must run as root" >&2
	exit 1
fi

if [ ! -s /usr/share/pacman/keyrings/archlinuxarm.gpg ]; then
	echo "pacman-keyring-init: missing Arch Linux ARM public keyring" >&2
	exit 1
fi

# The revoked list is legitimately empty when no keys are revoked, so these
# companion files must exist but are not required to have non-zero length.
for seed in archlinuxarm-trusted archlinuxarm-revoked; do
	if [ ! -f "/usr/share/pacman/keyrings/$seed" ]; then
		echo "pacman-keyring-init: missing seed keyring $seed" >&2
		exit 1
	fi
done

# Match pacman-key's own initialization permissions.  Individual secret-key
# material remains protected by GnuPG; pacman must be able to read the public
# keyring while using its unprivileged download sandbox.
install -d -o root -g root -m 755 "$GPG_DIR"
install -d -o root -g root -m 755 "$STATE_DIR"

echo "pacman-keyring-init: initializing local keyring"
pacman-key --init
pacman-key --populate archlinuxarm

# Confirm that GnuPG can read the populated keyring before making the service
# permanently idempotent.  A failed/partial run is retried on the next boot.
pacman-key --list-keys >/dev/null

sync
touch "$FLAG"
echo "pacman-keyring-init: completed successfully"
