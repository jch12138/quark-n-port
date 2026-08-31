#!/bin/bash
# Structural verification only: this cannot replace a real board boot test.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

IMAGE=${1:-"$REPO_ROOT/output/${IMAGE_BASENAME}.img"}
[ -f "$IMAGE" ] || die "image does not exist: $IMAGE"
require_command docker

docker run --rm -v "$REPO_ROOT:/work:ro" quark-n-builder bash -lc '
set -e
cd /work/output
sha256sum -c quark-n-mainline.img.sha256
dd if=quark-n-mainline.img of=/tmp/root.img bs=512 skip=133120 status=none
e2fsck -fn /tmp/root.img
debugfs -R "stat /root/quark-hardware-test.sh" /tmp/root.img >/dev/null
debugfs -R "stat /usr/local/sbin/quark-first-login" /tmp/root.img >/dev/null
debugfs -R "stat /etc/quark-n-build-info" /tmp/root.img >/dev/null
'
