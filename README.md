# Quark-N mainline Linux image builder

Reproducible release builder for the Seeed Quantum Mini: Quark-N (Allwinner
H3) SoM and Atom-N carrier. It builds a patched upstream ARM Linux kernel,
packages an Arch Linux ARM rootfs and publishes a flashable SD-card image.

```bash
make lint
make image KERNEL_REF=<upstream Linux tag>
```

The release image uses a fixed factory U-Boot binary, a board-specific kernel
and DTB, and a pinned Arch rootfs digest. `linux-armv7` is held in pacman so an
ordinary Arch user-space update cannot replace `/boot/zImage`.

On first boot, log in once as `root` with password `root`. The forced setup
creates a normal user, requests new passwords and disables root SSH. See
[docs/releasing.md](docs/releasing.md) for local builds and automated candidate
releases.
