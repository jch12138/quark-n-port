# Quark-N LCD 与串口排查交接文档

> 更新时间：2026-08-31。LCD、tty、UART0、Wi-Fi、蓝牙控制器和 ALSA PCM 链路已实机确认。当前外设增强镜像 SHA-256：`7cc540c497602059a49dc1347bbe49ff661a2bfef87e027d5405cd8650394e8c`。
> 镜像路径：`~/quark-n-port/output/quark-n-mainline.img`

## 目标

Seeed Quantum Mini（Quark-N SoM + Atom-N 载板，全志 H3）主线 Linux 移植。当前聚焦 Atom-N 板载 LCD（ST7789VW）点亮和 UART0 串口交互。

## 已确认的 LCD 金标准

原厂 DT 只描述了 SPI/UART 的复用引脚，不能单独证明 LCD 接线。真正的面板参数来自原厂 4.14 内核里的 `fbtft_device.c` 和 `fb_st7789vw.c`：

- 面板：1.14 英寸 ST7789VW，逻辑分辨率 240×135。
- SPI0 mode 3，8-bit 数据 + 独立 D/C。
- 原厂 `fbtft_device` 的 `cs` 参数默认是 0，因此使用 SPI0 原生 CS0 = PC3；PA6/CS1 不是这块板载屏的片选。
- D/C = PA0，RESET = PA1。PA0/PA1 同时是 UART2 引脚，但调试串口 UART0 使用 PA4/PA5，两者不冲突。
- 显存窗口偏移：X=40，Y=53。
- 原厂驱动速度 50 MHz；首次点亮为降低信号完整性变量，主线 DT 暂设 8 MHz，稳定后再逐步提高到约 15 MHz。
- MADCTL=0x70；其余电源、porch、gamma 参数逐字迁移自原厂初始化函数。

## 本轮工程修改

### LCD DTS

- 使用 `compatible = "seeed,quark-n-st7789v", "panel-mipi-dbi-spi"`，避开需要 9-bit SPI 的 `panel-sitronix-st7789v`。
- 节点改为 `display@0` / `reg=<0>`，恢复 `spi0_pins` 原生 PC3/CS0。
- 删除错误的软件 CS GPIO 和 PA6/CS1 推断。
- 增加 `spi-cpol`、`spi-cpha`，匹配原厂 SPI mode 3。
- D/C 改为 PA0，RESET 改为 PA1。
- 分辨率改为 240×135，`hback-porch=40`、`vback-porch=53` 表示控制器 RAM 偏移。
- 暂用 8 MHz；保留 SPI 100 MHz 父时钟预设和禁用 DMA 两项已实机证明有效的稳定性措施。

### 初始化固件

`tools/make-panel-mipi-dbi-firmware.py` 已改为原厂 ST7789VW 初始化值：MADCTL 0x70、COLMOD 0x05、原厂 porch/power/gamma、INVON、SLPOUT、DISPON。额外补足软复位和退出休眠的 120 ms 等待，结尾等待 200 ms。

固件同时通过 `CONFIG_EXTRA_FIRMWARE` 内置进内核，并由 `assembly.sh` 写入 rootfs `/usr/lib/firmware/seeed,quark-n-st7789v.bin`。

### 串口 getty

旧打包脚本把 systemd 的串口专用模板 `serial-getty@ttyS0` 屏蔽了，却启用了虚拟终端模板 `getty@ttyS0`。这会造成串口波特率/TERM/设备生命周期处理错误，也是“有输出但不能可靠输入”的高概率原因。

现改为：

- mask `getty@ttyS0.service`
- 只 enable `serial-getty@ttyS0.service`
- bootargs 继续使用 `console=ttyS0,115200`

### pacman keyring 首次启动初始化

Arch Linux ARM rootfs 自带 `archlinuxarm-keyring` seed 文件，但默认不包含 `/etc/pacman.d/gnupg`，直接运行 pacman 会报 `Public keyring not found`、`keyring is not writable`。

现已加入 `pacman-keyring-init.service`：

- 首次启动在用户登录开放前执行 `pacman-key --init` 和 `pacman-key --populate archlinuxarm`。
- 仅初始化、populate 和可读性检查全部成功后写 `/var/lib/pacman-keyring-init/done`。
- 任一步失败均不写完成标志，下次启动自动重试。
- `assembly.sh` 打包时先检查 `pacman-key`、public/trusted/revoked seed 文件；缺失则中止打包。
- 输出使用 `.new` 临时文件，只有镜像复制和 SHA-256 计算成功后才替换上一版成品，失败构建不会删除最后一个可用镜像。

### SSH 默认 root 登录

已加入 `rootfs-overlay/etc/ssh/sshd_config.d/10-root-login.conf`，明确设置：

- `PermitRootLogin yes`
- `PasswordAuthentication yes`

因此后续打包镜像默认可使用 `root/root` 通过 SSH 登录。`assembly.sh` 会把 root 密码固定为 `root`，检查上述两项 SSH 配置是否存在，并将配置权限设为 `0644`；账户或配置处理失败时直接中止打包。

## 串口卡住与 LCD 的关系

这是两个可能叠加的故障层：

1. 之前启用 SPI DMA 时，大块 fbcon 刷屏曾让 sun6i SPI DMA 路径挂住并拖死内核。这种情况下串口也停止输出/输入，和 LCD 异常有直接因果关系。当前继续禁用 SPI DMA。
2. 当日志已经出现 `fb0: panel-mipi-dbi` 且 systemd 仍继续启动，只是键盘输入或登录提示异常时，更符合两个 getty 争用或错误 getty 模板的问题，与 LCD 引脚无关。

LCD 使用 PC0-PC3、PA0、PA1；调试串口 UART0 使用 PA4、PA5，没有管脚冲突。因此本轮新 LCD 参数不会抢占 ttyS0。

## 重新上电后的最小验证

```bash
journalctl -k -b | grep -Ei 'mipi|dbi|st7789|spi0.0|drm|fb0|timeout|dma'
cat /sys/class/graphics/fb0/virtual_size
systemctl status serial-getty@ttyS0.service --no-pager
systemctl is-enabled getty@ttyS0.service serial-getty@ttyS0.service
systemctl status pacman-keyring-init.service --no-pager
test -e /var/lib/pacman-keyring-init/done && echo keyring-ready
pacman-key --list-keys >/dev/null && echo pacman-key-ok
sshd -T | grep -iE 'PermitRootLogin|PasswordAuthentication'
cat /proc/cmdline
```

预期：设备名为 `spi0.0`，fb0 为 `240,135`，无 `-110` SPI timeout；`serial-getty@ttyS0` active，`getty@ttyS0` masked。

统一外设自检已放在 root 家目录：

```bash
/root/quark-hardware-test.sh
/root/quark-hardware-test.sh --interactive
```

默认模式只读并生成 `/root/quark-hardware-report-*.txt`；交互模式额外录放 3 秒音频、等待按键并闪烁 LED。当前板在旧内核上实测为 PASS=14、WARN=2、FAIL=1；唯一真实失败是 MPU6050 在 I2C0 地址 0x68 无 ACK。原理图已确认 MPU 接 I2C0，且扫描所有三条总线的 0x68/0x69 都无应答，因此下一步是检查器件贴装、供电、上拉和焊接，而不是继续猜测总线。

本轮还补齐了 USB storage/UAS、USB 串口、ACM、USB 网卡、UVC、USB Audio、HIDRAW、configfs gadget 等内核选项，rootfs 离线预装 BlueZ、ALSA、i2c-tools、usbutils 和 evtest。以太网仍保持禁用：原厂 DT 同样禁用 EMAC，载板尚未确认存在 PHY，不能盲目启用。

屏幕图案测试：

```bash
dd if=/dev/zero of=/dev/fb0 bs=64800 count=1
dd if=/dev/urandom of=/dev/fb0 bs=64800 count=1
```

RGB565 一帧是 `240*135*2 = 64800` 字节。随机噪点能出现即可证明复位、片选、D/C、SPI mode、窗口偏移和像素写入链路基本都通。

## 构建命令

```bash
docker run --rm -v "$PWD:/work" quark-builder \
  make -C /work/src/linux ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- \
  allwinner/sun8i-h3-quark-n.dtb zImage
docker run --rm -v "$PWD:/work" quark-builder bash /work/assembly.sh
```

## 关键文件

- `src/linux/arch/arm/boot/dts/allwinner/sun8i-h3-quark-n.dts`
- `tools/make-panel-mipi-dbi-firmware.py`
- `assembly.sh`
- `rootfs-overlay/usr/local/sbin/init-pacman-keyring.sh`
- `rootfs-overlay/etc/systemd/system/pacman-keyring-init.service`
- `rootfs-overlay/etc/ssh/sshd_config.d/10-root-login.conf`
- `rootfs-overlay/root/quark-hardware-test.sh`
- `rootfs-overlay/usr/local/sbin/quark-audio-init.sh`
- `rootfs-overlay/etc/systemd/system/quark-audio-init.service`
- `output/quark-n-mainline.img`
