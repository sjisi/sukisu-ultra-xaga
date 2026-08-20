# SukiSU Ultra xaga 刷机指南

适用机型：**xaga**（Redmi Note 11T Pro / POCO X4 GT，Dimensity 8100，内核 5.10）。

> 请先确认你的系统版本：
> - **澎湃 OS（HyperOS）/ Android 13+**（含安卓 14 的澎湃 2.0，内核 5.10.101+，如 5.10.226）→ 刷 `...-xaga-hyperos-AnyKernel3.zip`（GKI 内核）
> - **MIUI / Android 12** → 刷 `...-xaga-miui-AnyKernel3.zip`（MTK 内核）

> ⚠️ 刷机有风险，操作前请务必备份数据，并确保手机电量充足（>50%）。

---

## 一、前置条件

1. **解锁 Bootloader**：小米设备需要用 Mi Unlock 工具申请解锁（通常需要绑定账号等待 7 天）。解锁会清除数据。
2. **备份原厂 boot 镜像**（强烈建议）：
   ```bash
   adb shell "dd if=/dev/block/bootdevice/by-name/boot of=/sdcard/boot-stock.img"
   adb pull /sdcard/boot-stock.img
   ```
   有原厂 boot.img 才能随时回滚。
3. **获取刷机包**：
   - 澎湃 OS：`sukisu-ultra-*-xaga-hyperos-AnyKernel3.zip`
   - MIUI：`sukisu-ultra-*-xaga-miui-AnyKernel3.zip`

---

## 二、刷入方式（任选其一）

### 方式 A：手机端刷入（推荐，无需电脑）

1. 安装任意内核刷写工具：Kernel Flasher / Franco Kernel Manager (FKM) / Horizon Kernel Flasher。
2. 把 `AnyKernel3.zip` 放到手机存储。
3. 在工具里选择该 zip 刷入，重启。

### 方式 B：Recovery 刷入

1. 手机重启进入自定义 Recovery（如 TWRP / OrangeFox）。
2. 选择安装 zip → 选中 `AnyKernel3.zip` → 滑动刷入 → 重启。

### 方式 C：Fastboot 刷 boot 镜像

1. 手机重启到 fastboot 模式（关机后长按 音量下 + 电源）。
2. 执行：
   ```bash
   fastboot flash boot sukisu-ultra-boot.img
   fastboot reboot
   ```
3. 如果提示找不到 boot 分区，先 `fastboot getvar current-slot`，然后刷对应的 `boot_a` 或 `boot_b`。

---

## 三、安装管理器并验证

1. 安装 SukiSU-Ultra 管理器 App（从 SukiSU-Ultra 官方 Release 下载，或由本项目构建）。
2. 打开管理器，授予 root 权限，确认内核版本显示为 SukiSU。
3. 终端验证：
   ```bash
   su -c id
   # 应输出 uid=0(root)
   ```

---

## 四、功能说明

- **内核级 su**：root 授权由内核直接管理，权限判定走内核策略。
- **App Profile（应用配置）**：可在管理器里为每个应用定制 root/非 root 环境，把 root 关进"笼子"。
- **模块系统（Magic Mount）**：不依赖 OverlayFS，基于 5ec1cff 的 Magic Mount 实现，模块目录 `/data/adb/modules/`。
- **KPM 内核模块**：内核编译时已开启 `CONFIG_KPM=y`，可加载 KernelPatch 模块（`.kpm` 文件），在管理器或 `kpatch` 工具中管理。
- **环境隐藏**：内核包含隐藏相关支持（selinux 隐藏、挂载点隐藏、uts 伪装），配合管理器里的隐藏功能使用。

---

## 五、回滚

- 刷回原厂 boot：
  ```bash
  fastboot flash boot boot-stock.img
  ```
- 或直接在 Kernel Flasher 里刷入原厂 boot 备份。

---

## 六、常见问题

| 问题 | 处理 |
| --- | --- |
| 刷入后卡开机 | 长按电源强制重启；仍不行则回滚原厂 boot，并在群里反馈 last_kmsg/dmesg |
| 刷错包（MIUI 包刷到澎湃 OS） | 下载对应的 `hyperos` 包重刷；澎湃 OS 用 GKI 包 |
| 管理器显示未授权 | 确认安装的是 SukiSU 系列管理器（不是原版 KernelSU 管理器） |
| 银行/检测类 App 异常 | 在管理器里对该 App 启用隐藏配置（susfs umount/隐藏） |

---

## 七、自行构建

见项目根目录 `README.md` 的"构建"章节，支持：
- 本机 Linux / WSL2 一键构建
- GitHub Actions 自动构建（把仓库推到 GitHub 即可）
