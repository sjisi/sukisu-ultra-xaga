# SukiSU Ultra · xaga

面向 **xaga**（Redmi Note 11T Pro / POCO X4 GT）的完整内核级 root 解决方案，基于 [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra)（KernelSU 增强分支）。

根据系统版本提供两条构建路径：

| 目标 | 系统 | 内核底座 | 刷机包 |
| --- | --- | --- | --- |
| `hyperos`（默认） | 澎湃 OS / Android 13+（含 2.0/安卓 14，如 5.10.226） | GKI 5.10.260（`android12-5.10-gki`） | 内核级 AK3（不动模块） |
| `miui` | MIUI / Android 12 | 小米官方 `xaga-s-oss`（5.10.66，MTK） | AK3（内核 + 模块） |

## 特性

- 内核级 `su` 与 root 权限管理（授权走内核策略，不依赖完整 userspace 守护）
- **App Profile**：按应用锁定 root 权限/环境
- **模块系统**：不基于 OverlayFS，采用 5ec1cff 的 **Magic Mount**（bind mount + tmpfs）
- **KPM** 内核模块支持（`CONFIG_KPM=y`，含 KALLSYMS）
- 非 GKI / GKI 1.0 设备支持
- 环境隐藏：selinux 隐藏、挂载隐藏、uts 伪装（susfs 系能力）

## 仓库结构

```
├── xaga-kernel/          # 已集成 SukiSU-Ultra 的 xaga 内核源码
├── gki-kernel/           # 已集成 SukiSU-Ultra 的 GKI 5.10 内核源码（澎湃 OS 用）
├── sukisu-ultra/         # SukiSU-Ultra 上游源码（参考）
├── build/
│   ├── build_xaga.sh                 # Linux 一键构建脚本
│   ├── anykernel3/                   # MIUI 刷机包模板（AnyKernel3，含模块）
│   ├── anykernel3-hyperos/           # 澎湃 OS 刷机包模板（AnyKernel3，纯内核）
│   ├── gki-sukisu.config             # GKI 路径的 KSU 配置覆盖
│   ├── modules-load/                 # vendor_boot/vendor_dlkm 模块清单
│   ├── xaga-kernel-sukisu-ultra.patch# MTK 内核集成补丁
│   └── gki-kernel-sukisu-ultra.patch # GKI 内核集成补丁
├── docs/FLASH-xaga.md    # 刷机指南
└── .github/workflows/    # GitHub Actions 自动构建
```

## 集成内容

在小米官方 `xaga-s-oss` 内核树上的改动（全部可复现）：

1. `drivers/kernelsu/` ← SukiSU-Ultra 内核代码（KSU + KPM + App Profile）
2. `drivers/Makefile`、`drivers/Kconfig` 注册 `CONFIG_KSU`
3. 配置开启：
   `CONFIG_KSU=y`、`CONFIG_KPM=y`、`CONFIG_KPROBES=y`、`CONFIG_KALLSYMS(_ALL)=y`、`CONFIG_EXT4_FS=y`、`CONFIG_MODULES=y`
4. MTK 路径额外：`drivers/mihw/Kconfig` stub（小米公开源码缺失的目录，补齐使 kconfig 可解析）

## 构建

内核编译需要在 **Linux** 环境（WSL2 / Ubuntu / 云主机均可），Windows 原生无法编译。

### 没有 Linux？一条命令装 WSL2（Windows 10/11）

```powershell
wsl --install -d Ubuntu
```

装好后重启电脑，进入 Ubuntu 终端：

```bash
mkdir -p ~/sukisu
cp -r "/mnt/c/Users/31890/Documents/Codex/2026-08-21/s/build" ~/sukisu/
cd ~/sukisu/build
sudo apt update && sudo apt install -y bc bison flex libssl-dev make zip zstd xz-utils kmod cpio python3 git
./build_xaga.sh
```

脚本会自动下载内核源码（固定版本）并应用 SukiSU 补丁，全程无需手动干预。

### 一键构建（AnyKernel3 刷机包）

```bash
sudo apt update && sudo apt install -y bc bison flex libssl-dev make zip zstd xz-utils kmod cpio python3 git
./build/build_xaga.sh                # 默认构建澎湃 OS（GKI）刷机包
```

产物在 `out/`：`sukisu-ultra-<版本>-xaga-hyperos-AnyKernel3.zip`

MIUI（Android 12）用户构建：

```bash
TARGET=miui ./build/build_xaga.sh
```

### MIUI 路径同时重打包 boot.img（需要原厂 boot）

```bash
STOCK_BOOT_IMG=/path/to/boot-stock.img TARGET=miui ./build/build_xaga.sh
```

### GitHub Actions

把本仓库推到 GitHub，`.github/workflows/build-xaga.yml` 会自动拉取内核源码、应用补丁、构建并上传两个目标的刷机包。

## 刷机

完整步骤见 [docs/FLASH-xaga.md](docs/FLASH-xaga.md)。核心三步：

1. 解锁 Bootloader（Mi Unlock）
2. 用 Kernel Flasher / FKM 刷入对应的 AnyKernel3 zip（澎湃 OS 用 `hyperos` 包）
3. 安装 SukiSU 管理器并授权

## 状态

- [x] SukiSU-Ultra 内核代码集成
- [x] 双底座配置合并验证（GKI 5.10 + MTK 5.10，KSU/KPM 生效）
- [x] 构建流水线（Linux 脚本 + CI）
- [x] 刷机包模板（AnyKernel3，澎湃 OS / MIUI 各一套）
- [ ] 实际编译出包（需要 Linux 构建环境）
- [ ] 实机验证
