# Quark-N release process

`main` contains only source, patches, configuration, rootfs overlay and small
offline diagnostic packages. Large source trees, rootfs archives and images are
deliberately ignored because the build scripts recreate them from `sources.lock`.

## Local release

```bash
make lint
make image KERNEL_REF=<upstream-tag>
```

The result is `output/quark-n-mainline.img`, its SHA-256 file and a manifest
containing the kernel ref, patch/config digests, rootfs digest and bootloader
digest. `make verify` performs checksum, partition and ext4 checks. These are
structural checks only; a candidate becomes hardware-verified only after the
board-side `/root/quark-hardware-test.sh --interactive` run succeeds.

## Automated candidates

The scheduled `Build candidate release` workflow finds the newest final upstream
Linux tag, applies `patches/linux`, builds the image, verifies its structure and
creates a GitHub prerelease. If a patch no longer applies or the build fails, no
release is created. Existing release tags are skipped.

The workflow deliberately does not replace the fixed factory U-Boot binary.
Mainline U-Boot remains a separate project because its DDR bring-up is not yet
board-verified.

## Updating Arch Linux ARM inputs

The rootfs archive is pinned by SHA-256 in `sources.lock`. To refresh it, first
download the intended archive, validate boot/package compatibility locally, then
update both `ARCH_ROOTFS_SHA256` and the offline packages under `pkgs/` together.
Do not point a release build at an unpinned `latest` archive. In the installed
image, `linux-armv7` must remain ignored by pacman: Quark-N ships its own
`/boot/zImage` and DTB.

## First boot

Release images permit exactly one interactive `root/root` login. The forced
first-login shell creates a normal user, asks for that user's password and a new
local root recovery password, then disables root SSH. Non-interactive root SSH
commands are refused until provisioning completes.
