# Quark-N 主线 Linux 镜像构建器

[English](README.md)

这是面向 **Seeed Quantum Mini** 平台的可复现镜像构建器：目标硬件为
基于 Allwinner H3 的 Quark-N 核心板与 Atom-N 载板。它构建打过板级补丁的
上游 ARM Linux 内核，配合已锁定版本的 Arch Linux ARM 根文件系统，输出可
直接烧录到 microSD 卡的镜像。

> [!WARNING]
> 本项目处于板级适配阶段，并非通用发行版。构建出的镜像通过自动化结构
> 校验后，仍必须在目标硬件上完成验证，才能用于实际场景。主线 U-Boot 的
> DDR 初始化尚未在本板实机验证；发布镜像刻意使用仓库提供的原厂 U-Boot
> 二进制文件。

## 仓库内容

- Quark-N / Atom-N 的板级 Device Tree 补丁，覆盖 ST7789VW LCD、MPU6050
  I2C 传感器、Lima GPU 供电与应用按键。
- [`sources.lock`](sources.lock) 中锁定的内核与 Arch Linux ARM 根文件系统
  输入。
- 镜像组装脚本、rootfs 覆盖层、硬件诊断工具，以及一个紧凑的帧缓冲
  MPU6050/按键演示程序。
- 用于校验构建输入、创建候选预发布版本的 GitHub Actions 工作流。

大型内核源码、rootfs 下载文件、构建目录与生成的镜像都被 Git 有意忽略；
它们在本地重新生成，不属于本仓库内容。

## 当前支持边界

当前基线面向 Atom-N 载板上的 Quark-N 核心板。项目已包含以下组件的板级
适配工作：

| 项目 | 当前状态 |
| --- | --- |
| 引导加载器 | 使用原厂 U-Boot；主线 U-Boot 的 DDR 支持尚未验证 |
| 内核 / DTB | 使用应用本仓库补丁后的上游 Linux |
| LCD | 已包含 ST7789VW 帧缓冲支持 |
| MPU6050 | 已包含 I2C0 设置与 IIO 访问支持 |
| GPU | DT 已描述 Lima 支持与所需的 Mali 供电 |
| Wi-Fi / 蓝牙 | 已包含 RTL8723BU 支持和用户空间配置；实际联网仍需在板端验证 |
| 以太网 | 保持禁用：尚未确认 Atom-N 载板是否存在 PHY |

详细硬件日志、假设与待解决问题请参阅 [`NOTES.md`](NOTES.md)。镜像构建
成功不代表所有外设已在某个具体硬件版本上通过验证。

## 构建要求

- Git
- Docker Desktop 或其他可正常运行的 Docker daemon
- 足够的本地磁盘空间与网络访问，用于内核源码、Arch Linux ARM rootfs 和
  容器软件包
- microSD 卡，以及首启时访问板端串口的条件

构建容器内已提供 ARM 交叉编译器和镜像工具，宿主机无需单独安装 ARM
工具链。

## 构建镜像

克隆仓库后，运行检查和镜像构建：

```bash
git clone https://github.com/<your-account>/quark-n-port.git
cd quark-n-port

make lint
make image
make verify
```

未显式指定时，`make image` 使用 [`sources.lock`](sources.lock) 中的不可变
基线。如需测试其他上游 Linux 标签或提交，必须明确传入：

```bash
make image KERNEL_REF=<上游-Linux-标签或提交>
```

构建完成后会在 `output/` 生成：

- `quark-n-mainline.img`：可烧录的镜像
- `quark-n-mainline.img.sha256`：镜像校验和
- `quark-n-mainline.manifest`：内核、补丁、rootfs 与 bootloader 的精确输入

`make verify` 会检查校验和、分区布局、FAT 启动文件系统和 ext4 文件系统
内容；它仅为结构检查，不等同于板端启动或硬件验证。

## 烧录与首次启动

1. 确认目标设备是 microSD 卡，而不是系统磁盘。
2. 使用 balenaEtcher 等工具，或系统自带的原始镜像写入工具，将
   `output/quark-n-mainline.img` 写入卡中。
3. 连接串口后启动开发板，登录后执行板端检测：

   ```bash
   /root/quark-hardware-test.sh --interactive
   ```

初始账户为 `root`，密码为 `root`。请执行 `quark-first-login` 创建普通用户。

> [!CAUTION]
> 当前发布策略为便于恢复，root SSH 与出厂 `root/root` 密码均默认开启。
> 新烧录的开发板不得接入不可信网络；日常联网前请修改 root 密码，并限制
> 或禁用 root SSH。

## 目录结构

| 路径 | 作用 |
| --- | --- |
| `patches/linux/` | 构建时应用的 Linux Device Tree 补丁 |
| `config/` | 内核配置片段与 rootfs 软件包列表 |
| `rootfs-overlay/` | 安装到 Arch Linux ARM 根文件系统中的文件 |
| `scripts/` | 下载、内核准备、构建、生成清单与校验脚本 |
| `docker/` | 可复现构建容器的配方 |
| `tools/` | 宿主机辅助工具和目标端 LCD/MPU 演示程序源码 |
| `docs/releasing.md` | 候选发布与更新输入的详细流程 |

## 自动候选发布

定时执行的 **Build candidate release** 工作流会发现最新的上游正式 Linux
标签、构建镜像、运行结构校验，并且仅在全部成功后创建 GitHub 预发布版本。
候选版本会明确标记为候选，不代表硬件认证。

## 贡献与许可证

反馈硬件问题时，请附上目标板版本、串口日志与
`/root/quark-hardware-test.sh --interactive` 的输出。

项目目前尚未声明许可证。在添加许可证前，请勿假定代码可被复用。
