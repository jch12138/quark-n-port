# Boot mainline Linux on Quark-N (Quantum Mini)
setenv bootargs console=ttyS0,115200 root=/dev/mmcblk0p2 rootwait rw
fatload mmc 0:1 0x46000000 zImage
fatload mmc 0:1 0x48000000 sun8i-h3-quark-n.dtb
bootz 0x46000000 - 0x48000000
