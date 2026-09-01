# Quark-N / Quantum Mini Linux 主线移植笔记

## 板子概况
- **SoM**：Quark-N（= 稚晖君开源的 Quark-Core），全志 H3（sun8i-h3，四核 Cortex-A7 @1GHz）+ Mali400 MP2 + 512MB LPDDR3 + 16GB eMMC，M.2 Key-A 金手指引出 GPIO
- **载板**：Atom-N（= Atom-Shield-N），2×USB2.0 + 1×USB-C + MicroSD + RTL8723BU(WiFi/BT) + 麦克风 + MPU6050 + 按键 + ST7789V IPS 屏
- **用户目标**：移植最新主线 Linux；选型 = 新版板、完整外设、Arch Linux rootfs

## 权威来源（全部已获取）
- 硬件 + U-Boot + 内核：`github.com/peng-zhihui/Project-Quantum`（GPL-3.0）
  - `1.Hardware/Quark-Core` = SoM 原理图（Altium .SchDoc），`1.Hardware/Atom-Shield-N` = 载板
  - `2.Bootloader/uboot.tar.gz` = FriendlyARM u-boot（含 quark_n_h3_defconfig + sun8i-h3-quark-n.dts）
  - `3.Kernel/kernel.tar.gz` = Git LFS 指针（532MB，内核源码，网盘另有备份）
- 原厂镜像：`files.seeedstudio.com/wiki/Quantum-Mini-Linux-Dev-Kit/quark-n-21-1-11.zip`（3.8GB → 10GB img）
- 从镜像 boot 分区反编译的内核设备树：`sun8i-h3-atom_n.dtb` → `sun8i-h3-atom_n.dts`（完整引脚映射）

## 关键参数（移植必需）
### DRAM（DDR3-1333 @408MHz，最易翻车点）
```
CONFIG_DRAM_CLK=408        # 408MHz
CONFIG_DRAM_ZQ=3881979
CONFIG_DRAM_ODT_EN=y
CONFIG_SUNXI_DRAM_DDR3_1333=y
```
> 注意：Seeed 官网写"LPDDR3"是错的。原厂 U-Boot 编译产物 `include/generated/autoconf.h` 明确是 `CONFIG_SUNXI_DRAM_DDR3_1333=y`（DDR3，非 LPDDR3）。
- U-Boot SPL 走 `arch/arm/mach-sunxi/dram_sunxi_dw.c`（DesignWare 控制器）

### 引脚映射（来自 sun8i-h3-atom_n.dts）
| 功能 | 引脚 | 备注 |
|---|---|---|
| 调试串口 UART0 | PA4(TX) PA5(RX) | 115200n8，走 USB-C 串口 |
| SD (mmc0) | PF0–PF5，CD=PF6 | 4-bit |
| eMMC (mmc2) | PC5,PC6,PC8–PC16 | 8-bit，non-removable |
| SPI0 | PC0(CLK) PC2(MOSI) PC1(MISO) PC3(CS0)，CS1=PA6 | LCD 用 |
| SPI1 | PA15,PA16,PA14,PA13 | |
| I2C0 | PA11,PA12 | |
| I2C1 | PA18,PA19 | |
| I2C2 | PE12,PE13 | |
| LCD (ST7789VW) | SPI0 CS0=PC3，DC=PA0，RESET=PA1，mode 3 | 1.14 英寸 240x135 IPS，RAM 偏移 40/53 |
| vdd-cpux（CPU 电压） | PL6 | gpio-regulator 1.1V/1.3V |
| vcc1v2 / vdd-cpux-en | PL8 | |
| vcc-dram | PL9 | |
| usb0-vbus | PL2 | |
| LED status | PA10 | heartbeat |
| LED pwr | PL10 | |
| 应用按键 GPIO-KEY | PL3，映射为 `KEY_PROG1` | 普通应用按键，不触发 systemd 关机；首次创建用户已加入 `input` 组 |
| 以太网 EMAC | DT 中 disabled（RGMII PD0–PD17）| 载板疑似未接 PHY |

### 外设
- **WiFi/BT**：RTL8723BU（USB 接口，主线 `rtl8xxxu` 驱动 + 固件 rtl8723bu）
- **MPU6050**：原理图确认接 I2C0（PA11/PA12，标准地址 0x68）；板级 DTS 为未布置外部上拉的总线启用内部上拉后，驱动绑定及六轴原始数据均已实机验证
- **麦克风**：H3 codec 模拟输入（"MIC1"→"Mic"，MBIAS），audio-routing 已定义
- **LCD**：ST7789VW，8 位 SPI MIPI-DBI mode 3，CS0=PC3、DC=PA0、RST=PA1，240x135，RAM 偏移 X=40/Y=53

### 启动流程（boot.cmd）
```
SPL → U-Boot → fatload mmc 0:1 (zImage + rootfs.cpio.gz + sun8i-h3-atom_n.dtb)
→ bootz，bootargs: console=ttyS0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rw
→ overlayfs data=/dev/mmcblk0p3
```
分区：p1=FAT boot(40MB) / p2=ext4 rootfs(1.2GB) / p3=data(8.2GB)

## 移植计划
1. **主线 U-Boot**：新建 `quark_n_h3_defconfig`，移植 DRAM 参数（408MHz/ZQ/ODT），复用 sunxi H3 平台；DT 用精简的 sun8i-h3-quark-n.dts（UART0+SD+eMMC）
2. **主线内核**：写现代语法的 `sun8i-h3-quark-n.dts`（参考 mainline `sun8i-h3-nanopi-neo-core.dts`，把上面的引脚映射套进去）；逐个使能外设
3. **rootfs**：Arch Linux ARM armv7h（滚动发行，内核紧跟主线）
4. **验证**：先 SD 卡启动出串口 log，再逐个点亮外设

## 待办/开放项（拿到板子后 5 分钟定位）
- [x] MPU6050 I2C0：内部上拉修复已实机验证，IIO 六轴数据可读
- [x] GPIO-KEY 使用 PL3，并映射为应用按键 `KEY_PROG1`
- [ ] 以太网是否真没接 PHY
- [ ] LPDDR3 时序在主线 U-Boot 下能否直接点亮（最可能翻车，需串口验证 SPL 阶段）

## 本地已固化文件（~/quark-n-port/）
- sun8i-h3-atom_n.dts / sun8i-h3-unit.dts（反编译的内核设备树，引脚映射金标准）
- quark_n_h3_defconfig / sun8i-h3-quark-n.dts / sun8i-h3-nanopi.dtsi（U-Boot 侧）
- boot.cmd

## 构建结果（2026-08-31）
- **成品镜像**：`~/quark-n-port/output/quark-n-mainline.img`（3,212,836,864 bytes；SHA-256 `3838f23418dc23b08fbf03459f70973829e9fede31685283503d24f759641293`，release 首登用户创建版）
- 分区：p1 FAT32 64MB（zImage + sun8i-h3-quark-n.dtb + boot.scr + extlinux.conf），p2 ext4 2.9GB（Arch ARM rootfs，首启自动扩容）
- **内核**：主线 7.2（torvalds master），`sunxi_defconfig` + 自制 `arch/arm/boot/dts/allwinner/sun8i-h3-quark-n.dts`
- **rootfs**：Arch Linux ARM armv7h；root 使用标准 `/bin/bash`，首次登录提示手动运行 `quark-first-login` 创建普通用户，root SSH 保持开放
- **Bootloader**：原厂 `u-boot-sunxi-with-spl.bin`（2017.11 FriendlyARM 版，从原厂镜像 8KB 偏移提取）
- 烧录：`dd if=quark-n-mainline.img of=/dev/<SD> bs=4M` 或 balenaEtcher

## 外设驱动状态（2026-08-31 更新）
| 外设 | 状态 | 说明 |
|---|---|---|
| WiFi (RTL8723BU) | ✅ 已修复待新镜像真机复验 | `rtl8xxxu` 内置驱动首次探测早于 rootfs 固件；新增开机 USB interface reprobe，补齐 iwd 内核加密选项，连接脚本动态发现无线接口 |
| 蓝牙 | ✅ 实机控制器验证 | `btusb`/`btbcm` + BlueZ；hci0 存在且 `bluetoothctl show` 为 Powered=yes，配对/传输待晚间外设测试 |
| MPU6050 | ✅ 实机验证通过 | 原理图确认 I2C0/PA11/PA12、3.3V、AD0=GND/0x68，但未设计外部上拉；板级 DTS 为 PA11/PA12 增加 `bias-pull-up` 后驱动正常绑定，六轴原始数据可读 |
| 麦克风/音频 | ✅ PCM 链路验证 | H3 codec 播放/录音设备存在，`arecord`/`aplay` 命令成功；实际扬声器/麦克风音质待晚间听测 |
| 按键/LED | ✅ | PL3 通过 gpio-keys 映射为 `KEY_PROG1`，供应用从 evdev 读取；不再使用 `KEY_POWER` |
| USB 外设 | ✅ 驱动固化、待插拔验证 | 增加 U 盘/UAS、USB 串口、ACM、USB 网卡、UVC、USB Audio、HIDRAW、configfs gadget 等常用类驱动 |
| GPU | ✅ 实机验证通过 | DTS 补上 Mali 1.2V regulator 后 Lima 正常 probe，`/dev/dri/renderD128` 已存在 |
| 自动扩容 | ✅ 串口实机验证 | 使用 `sfdisk --no-reread --force` + `partx -u` + `resize2fs`；任何一步失败均不写完成标志，实机根分区已从 2.8GB 扩至 29.4GB |
| pacman | ✅ 已固化首启修复 | Landlock 正常；新增 `pacman-keyring-init.service`，登录前自动 init/populate，仅成功后写完成标志 |
| LCD (ST7789VW) | ✅ 实机验证通过 | 屏幕点亮并显示 tty；240x135、PC3/PA0/PA1、SPI mode 3、偏移 40/53 |

## 2026-08-30 串口诊断与修复
- **LCD 根因**：串口内核日志为 `st7789v spi0.0: error -EINVAL: Failed to setup spi`。旧 DT 绑定到 `panel-sitronix-st7789v`，该驱动需要 SPI 9-bit，并且像素路径是 DPI/RGB；Quark-N 实际是 8 位 SPI 像素流 + 独立 DC GPIO，因此驱动类型不匹配。
- **LCD 修复**：DT 改为 `seeed,quark-n-st7789v`+`panel-mipi-dbi-spi`；后续从原厂 `fbtft_device.c`/`fb_st7789vw.c` 确认真实参数为 240x135、CS0=PC3、DC=PA0、RESET=PA1、SPI mode 3、窗口偏移 40/53，初始化固件也按原厂寄存器值重做。
- **扩容根因**：旧脚本在在线修改分区表失败后用 `|| true` 吞掉错误，仍执行 `touch /etc/resize-fs.done`，导致以后永久跳过。
- **扩容修复**：严格检查根设备、分区表更新、内核分区大小及 `resize2fs`；仅全部成功后写 `/var/lib/resize-fs/done`，同时保存修改前分区表。
- **WiFi 根因**：`CONFIG_RTL8XXXU=y` 令 RTL8723BU 在 rootfs 挂载前探测，`rtl8723bu_nic.bin` 尚不可用而失败，之后不会自动重试；旧 wpa_supplicant 手工解包又缺 `libpcsclite.so.1`。串口手动写 `3-1:1.2` 到 `/sys/bus/usb/drivers_probe` 后 `wlan0` 正常出现，证明硬件、USB 和固件本身无误。
- **WiFi 修复**：新增 `wifi-hw-init.service` 在本地文件系统就绪后重探测未绑定的 `0bda:b720` USB interface；`wifi-connect.sh` 动态查找无线接口并调用 iwd；内核补齐 iwd 所需 key/crypto user API、MD5、DES 选项。

## 2026-08-31 剩余外设完善与统一自检
- DTS 根据载板原理图将 MPU6050 从错误的 I2C1 改到 I2C0，并为 USB0 ID 检测加入 PG12；Mali 节点绑定 1.2V regulator。
- 内核补齐常用 USB host/gadget、USB 串口、UVC、USB Audio、USB 网卡和 HIDRAW 驱动。
- rootfs 离线预装 BlueZ、ALSA utilities、i2c-tools、usbutils、evtest 及依赖，并同步 pacman 本地数据库，避免运行时依赖未登记或首次联网装包。
- 新增 `/root/quark-hardware-test.sh`：默认只读检测；`--interactive` 额外执行 3 秒录放音、按键等待和 LED 闪烁；报告保存在 `/root/quark-hardware-report-*.txt`。
- 新增静态程序 `/root/quark-lcd-mpu-demo`：在 ST7789 LCD 上显示 MPU6050 六轴数据，PL3/`KEY_PROG1` 用于切换 LIVE/HOLD，不依赖 Python 或图形桌面。
- 修复 FAT 启动分区容量单位：`mkfs.fat -C` 使用 KiB 块而非 512B 扇区；旧脚本曾把 64MiB 分区误建成 128MiB 文件系统。现在分别计算 KiB/扇区并在写入镜像前强制校验精确字节数。
- 当前镜像实机运行修正版脚本：PASS=14、WARN=3、FAIL=0；核心外设全部通过。警告分别为 WiFi 尚未获取 IPv4、FAT 启动分区缺少内核 config 快照、载板无已确认以太网 PHY。打包脚本现已将 config 快照写入真正的 FAT `/boot`，镜像校验也会检查该文件和 ACL 配置。

## 2026-08-30 LCD 适配排查（阶段性结论，已被次日原厂源码核对修正）
- **结论**：此前 NOTES 记录的"已改用 panel-mipi-dbi-spi"实际未落地——内核树 DT（`src/linux/arch/arm/boot/dts/allwinner/sun8i-h3-quark-n.dts` 22:47 版）的 compatible 仍是 `sitronix,st7789v`（匹配 `panel-sitronix-st7789v.c`，probe 硬编码 `spi->bits_per_word=9`，sun6i SPI 仅 8 位 → 仍报 "Failed to setup spi"），且残留 fbtft 属性 rotate/fps/buswidth（DRM 不认，全无效）。
- **阶段性修复**：先切换到 `panel-mipi-dbi-spi`；当时采用的 240x320、PA1/PG11、软件 CS/PA6 等参数随后被证明不是板载 1.14 英寸面板的真实参数，不能再使用。
- **reset-gpios 极性**：核对过 `GPIO_ACTIVE_HIGH` 正确（in-tree 的 anbernic rg-nano / fairytux2 例子同为 ACTIVE_HIGH，配合 mipi_dbi_hw_reset "先低后高"时序）。
- **固件**：当时使用的 93B 通用初始化序列已被 2026-08-31 的 101B 原厂 ST7789VW 初始化序列替换。
- **待办**：真机烧录目视复验；先确认 fb0=240x135 和测试图案，再根据实际颜色决定是否调整 RGB/BGR。

## 2026-08-31 原厂 ST7789VW 参数迁移与串口修复
- 原厂 `fbtft_device.c` 明确注册 `ips_114inch_240_135`：默认 CS0、SPI mode 3、reset GPIO 1/PA1、dc GPIO 0/PA0；`fb_st7789vw.c` 明确 240x135、MADCTL 0x70、X/Y 偏移 40/53 和完整初始化寄存器值。
- DTS 已改为 PC3/CS0、PA0/DC、PA1/RESET、mode 3、240x135、偏移 40/53，首次点亮速度 8MHz；继续禁用 SPI DMA并保留 100MHz 父时钟预设。
- `assembly.sh` 已纠正为只启用 `serial-getty@ttyS0`，并屏蔽不适用于串口的 `getty@ttyS0`。旧日志已显示 systemd 运行到 `getty@ttyS0.service` 和登录 banner，所以当前“无法输入”更像 getty 模板错误，不是 LCD 管脚冲突。
- LCD/串口镜像已完成 DTB、boot 文件、rootfs、固件和 getty 检查，随后由用户实机确认屏幕点亮、tty 显示和 UART0 输入输出正常。

## 2026-08-31 pacman keyring 首启修复
- 根因：Arch Linux ARM tarball 安装了 `archlinuxarm-keyring`，但按设计不包含 `/etc/pacman.d/gnupg`；首次直接执行 pacman 因 keyring 未初始化而失败。
- 新增 `init-pacman-keyring.sh` 和 `pacman-keyring-init.service`，在 `getty.target`/用户登录前执行 `pacman-key --init`、`--populate archlinuxarm` 和 `--list-keys` 验证。
- 服务幂等：只有全部成功才写 `/var/lib/pacman-keyring-init/done`，失败会在下次启动重试。
- `assembly.sh` 会校验 pacman-key 与三份 seed keyring；已处理合法的 0 字节 `archlinuxarm-revoked` 文件。
- 打包输出改为原子替换：旧的可用镜像会保留到新镜像复制和 SHA-256 计算全部成功，校验文件由 `assembly.sh` 自动生成。
- 新镜像已静态验证：服务软链存在，脚本为 0755，seed 文件尺寸正确，GPG 目录和 done 标志在首启前均不存在，rootfs `e2fsck -fn` 通过。首次启动执行结果仍需上板确认。

## U-Boot 主线移植 —— 卡点与后续
- 目标：用主线 U-Boot 2026 替换原厂 bootloader（defconfig 已写好：`configs/quark_n_h3_defconfig`）
- **卡点**：Ubuntu 的 `gcc-arm-linux-gnueabihf`（13 和 14 都试过）**默认 Thumb-2 模式**，而 U-Boot 2026 的 sunxi 代码（psci.c / cache_v7_asm.S 的 mcr/mrc）需要 ARM 模式；U-Boot 的 `-marm` 走 `PF_CPPFLAGS_ARM→PLATFORM_CPPFLAGS→cpp_flags`，该路径会漏进 host 步骤（asm-offsets）导致 host gcc 报 `unrecognized -marm`。已尝试：关 Thumb、`-mtune=cortex-a7`、`-marm` 进 tune-y/PLATFORM_RELFLAGS——都因 flag 泄漏或未生效失败。
- **解决方向**（任选）：
  1. 用默认 ARM 模式的工具链（ARM 官方 arm-none-linux-gnueabihf / Linaro / Debian），避开 Thumb 默认
  2. 或在 U-Boot 构建系统里把 `-marm` 正确只注入 `KBUILD_AFLAGS`（.S 汇编）和 `KBUILD_CFLAGS`（.c 内联汇编），不碰 cpp_flags

## 待办/开放项（拿到板子后 5 分钟定位）
- [x] MPU6050 I2C0：DTS 内部上拉修复已通过 IIO 实机数据验证
- [x] GPIO-KEY 固定使用 PL3，映射为 `KEY_PROG1` 普通应用按键
- [ ] 以太网是否真没接 PHY（原厂 DT 里 EMAC 是 disabled）
- [ ] 新镜像晚间跑 `/root/quark-hardware-test.sh --interactive`，完成音频听测、按键、LED、蓝牙配对和 USB 插拔验证
