# Quark-N mainline Linux image builder

Reproducible image builder for the **Seeed Quantum Mini** platform: the
Allwinner H3-based Quark-N system-on-module and Atom-N carrier. It builds a
patched upstream ARM Linux kernel, combines it with a pinned Arch Linux ARM
root filesystem, and produces a flashable microSD-card image.

> [!WARNING]
> This is board bring-up work, not a general-purpose distribution. Generated
> images pass automated structural checks, but must still be validated on the
> target hardware before relying on them. Mainline U-Boot DDR bring-up has not
> been board-verified; release images deliberately use the supplied factory
> U-Boot binary.

## What is in this repository

- A board Device Tree patch for Quark-N / Atom-N, including the ST7789VW LCD,
  MPU6050 I2C sensor, Lima GPU supply, and the application key.
- A pinned kernel and Arch Linux ARM rootfs input in
  [`sources.lock`](sources.lock).
- An image assembly script, rootfs overlay, diagnostics, and a compact
  framebuffer MPU6050/key demonstration program.
- GitHub Actions workflows that lint build inputs and can create candidate
  prereleases.

Large kernel source trees, rootfs downloads, build directories, and generated
images are intentionally ignored by Git. They are recreated locally and are
not part of this repository.

## Current support boundary

The baseline is intended for a Quark-N SoM on the Atom-N carrier. The project
contains board-side work for the following components:

| Area | Current state |
| --- | --- |
| Bootloader | Factory U-Boot is used; mainline U-Boot DRAM support is unverified |
| Kernel / DTB | Upstream Linux with the repository patch applied |
| LCD | ST7789VW framebuffer support is included |
| MPU6050 | I2C0 setup and IIO access are included |
| GPU | Lima support and the required Mali supply are described in the DT |
| Wi-Fi / Bluetooth | RTL8723BU support and userspace provisioning are included; real network association still needs board-side verification |
| Ethernet | Disabled: the Atom-N carrier PHY has not been confirmed |

See [`NOTES.md`](NOTES.md) for the detailed hardware log, assumptions, and
open questions. Do not treat a successful image build as proof that every
peripheral works on a particular board revision.

## Requirements

- Git
- Docker Desktop or another working Docker daemon
- Sufficient local disk space and internet access for kernel sources, the
  Arch Linux ARM rootfs, and container packages
- A microSD card and a way to access the board serial console for first boot

The build container provides the ARM cross-compiler and image tools. You do
not need to install an ARM toolchain on the host.

## Build an image

Clone the repository, then run the checks and image build:

```bash
git clone https://github.com/<your-account>/quark-n-port.git
cd quark-n-port

make lint
make image
make verify
```

Without an override, `make image` uses the immutable baseline recorded in
[`sources.lock`](sources.lock). To test another upstream Linux tag or commit,
pass it explicitly:

```bash
make image KERNEL_REF=<upstream-linux-tag-or-commit>
```

The build writes these files to `output/`:

- `quark-n-mainline.img` — the flashable image
- `quark-n-mainline.img.sha256` — image checksum
- `quark-n-mainline.manifest` — exact kernel, patch, rootfs, and bootloader
  inputs

`make verify` checks the checksum, partition layout, FAT boot filesystem, and
ext4 filesystem contents. It is a structural check only.

## Flash and first boot

1. Verify that the target device is the microSD card, not a system disk.
2. Write `output/quark-n-mainline.img` using a tool such as balenaEtcher, or
   use your operating system's raw-image writer.
3. Boot with a serial console connected and run the board-side test after
   login:

   ```bash
   /root/quark-hardware-test.sh --interactive
   ```

The initial account is `root` with password `root`. Run
`quark-first-login` to create a normal user.

> [!CAUTION]
> Root SSH and the factory `root/root` password are enabled for recovery in
> the current release policy. Do not expose a newly flashed board to an
> untrusted network. Change the root password and restrict or disable root SSH
> before regular network use.

## Repository layout

| Path | Purpose |
| --- | --- |
| `patches/linux/` | Linux Device Tree patch applied during the build |
| `config/` | Kernel configuration fragment and rootfs package list |
| `rootfs-overlay/` | Files installed into the Arch Linux ARM root filesystem |
| `scripts/` | Fetching, kernel preparation, build, manifest, and verification scripts |
| `docker/` | Reproducible build-container recipe |
| `tools/` | Host-side helpers and the target LCD/MPU demonstration source |
| `docs/releasing.md` | Candidate release and input-update process |

## Automated candidate releases

The scheduled **Build candidate release** workflow discovers the newest final
upstream Linux tag, builds an image, runs structural verification, and creates
a GitHub prerelease only on success. Candidate releases are intentionally
labelled as such: they are not hardware certification.

## Contributing and licensing

Please include the target board revision, serial log, and the output of
`/root/quark-hardware-test.sh --interactive` when reporting hardware results.

No project license has been declared yet. Do not assume reuse rights until a
license is added.
