# tools/ 使用说明

所有脚本默认以**仓库根目录**为工作目录：

```bash
cd <repo>
```

**构建脚本不会刷机。** 物理写入只由 `flash_super.sh` 执行，默认不 wipe。

---

## 1. 脚本清单

### 1.1 OS4 构建/验收

| 脚本 | 作用 |
|---|---|
| `port_build.sh` | 一条命令：检查输入 → `build_os4.py` → `make_super.py` → `verify_package.sh` |
| `build_os4.py` | staging + 包内修复；可单独跑 `system`/`system_ext`/`product` |
| `make_super.py` | 7 分区 super 组装 + manifest |
| `check_super.py` | 读 super 元数据，逐分区比 manifest |
| `verify_package.sh` | 61 项包内验收（不挂载） |
| `verify_device.sh` | 40 项真机验收（只读） |
| `flash_super.sh` | EDL 写 super；`--wipe` 单独确认 |
| `flash_super_arch.sh` | Arch 在线直写 super（ssh、512 MiB 分块、fullblock、回读校验） |
| `post_flash_modules.sh` | 安装 3 个必装模块并卸载退役模块 |

> 411d 构建还需要 `hyperos/camera/{Aperture.apk,CameraParallelServiceStub.apk}`
> （第三方二进制，不随仓库分发；`port_build.sh` 会在输入检查阶段报错）。见
> `hyperos/camera/README.md`。

常用环境变量：

| 变量 | 默认 | 作用 |
|---|---|---|
| `TB_WORK` | `<repo>/work` | 工作目录 |
| `TB_OS4_DIR` | `$TB_WORK/hyperos4_411` | yupei 解包树 |
| `TB_PARTS` | `system system_ext product` | 要重建的分区（不能改 vendor） |
| `TB_SUPER_NAME` | `super_fixed.img` | 输出名 |
| `TB_SUPER_SIZE` | `0x4c0000000` | 20.4 GB 物理 |
| `TB_CORNER_PADDING` | `40` | 原厂 40px |
| `TB_NO_FINDDEVICE` | 未设 | 首次过向导用：去掉 FindDevice，过完再脏刷正常 super |
| `TB_DEBUG` | 未设 | **个人调试镜像**：关 adb 鉴权并信任 `TB_ADB_KEY`；不要分发 |
| `TB_MIUI_SERVICES_SHA256` | 作者基线 `0b41ff18…` | 自建色彩 jar 的期望哈希（verify_package） |
| `TB_DEVICES_OVERLAY_SHA256` | 作者基线 `128f7e97…` | 自改 40px APK 的期望哈希（verify_package） |
| `TB_ADB_KEY` | `~/.android/adbkey.pub` | `TB_DEBUG=1` 时注入的 adb 公钥；文件不存在直接报错 |
| `TB_ALLOW_PLACEHOLDER_BT` | 未设 | 允许用占位符蓝牙地址构建内核（不推荐，仅调试） |
| `TB_SKIP_STAGE` / `TB_KEEP_STAGE` / `TB_KEEP_BASE` | 未设 | 调试用 |
| `EDL` / `LOADER` | `edl` / `work/firehose/...` | EDL 工具/programmer |

### 1.2 启动链

| 脚本 | 作用 |
|---|---|
| `kshim_pack_boot.py` | 把 GKI + Linux + DTB + kShimC 打进 boot |
| `kshim_variants.sh NAME IMAGE DTB` | 打两个菜单默认变体，AVB 校验 |
| `kshim_gki_check.py` | 打印 boot.img 的 GKI 身份（sha256/大小/`Linux version`），供人工核对 6.1.128 |
| `make_v3_bootchain.py` | v3 启动链五件（boot/init_boot/dtbo/vendor_boot/vbmeta） |

### 1.3 双系统

| 脚本 | 作用 |
|---|---|
| `make-pair.sh` | 用你自己的两份 boot 镜像生成 `pair.env` |
| `arch-side/switch2os4` | Arch → OS4（读 `/usr/local/share/tbboot/pair.env`） |
| `arch-side/tb-switch.sudoers` | 桌面图标免密（`%wheel`） |
| `arch-side/tb-switch2os4.desktop` | 桌面项 |
| `os4-switch/switch2arch.sh` | OS4 → Arch（读 `/data/adb/tbboot/pair.env`） |
| `os4-switch/install_switch2arch.sh` | 主机侧安装器（校验/守门/push） |
| `os4-switch/device_install.sh` | 设备端落盘 |
| `os4-switch/action.sh` | KernelSU「执行动作」 |
| `os4-switch/module.prop` | 模块元数据 |
| `os4-switch/pair.env.example` | 配对文件格式 |

### 1.4 内核

| 脚本 | 作用 |
|---|---|
| `arch-kernel/build-from-series.sh` | 容器内从 vanilla 7.3 重放 27 补丁并构建 |
| `arch-kernel/build-single-module.sh` | 单模块重编 |
| `arch-kernel/check-7.3.sh` | 7.3 回归检查（config/sy7758） |
| `arch-kernel/set-bt-addr.sh` | 把占位符蓝牙地址换成你自己的（成对改补丁） |
| `arch-kernel/config-7.3.0-tb710fu` | canonical config |
| `arch-kernel/config-modules.fragment` | Tier B 模块化片段（未采用） |
| `arch-kernel/initramfs/` | init / diag.sh / nbdroot.sh |

### 1.5 用户态

| 脚本 | 作用 |
|---|---|
| `arch-userspace/install-userspace.sh` | 安装 P0/P1/P2 用户态修复 |
| `arch-userspace/README.md` | 每个文件的作用/验收 |
| `arch-userspace/{audio,power,thermal,storage,display,tools}/` | 配置与脚本原件 |
| `arch-userspace/thermal/widget/` | 面板温度条 plasmoid |

### 1.6 其他

| 脚本 | 作用 |
|---|---|
| `build_overlays.sh` | 构建两个 NCM RRO（需本地测试密钥） |
| `erofs_meta.py` | EROFS 元数据缓存（`build_os4.py` 依赖） |
| `patch_apk_res.py` | APK 资源原位补丁 |
| `patch_miuicamera_front.py` | 历史：MiuiCamera 前摄（现已退役） |
| `patch_tplg.py` | tplg 追加 DP 子图 |
| `patch_voice_wakeup.py` | 语音唤醒白名单 |
| `sepolicy_fix.py` | sepolicy 兼容 |
| `lp_unpack.py` | logical partition 解包 |
| `collect_firmware.sh` | ADSP/CDSP 固件提取 |
| `tb710fu_thermal_monitor.py` | 温控观测 |

---

## 2. 典型流程

### 2.1 只构建 OS4

```bash
tools/port_build.sh
tools/verify_package.sh
```

### 2.2 构建内核

```bash
docker run --rm -v tb-kwork:/w -v "$PWD":/src:ro -v "$PWD/work/kernel73/out":/out \
  kernel-build:latest bash /src/tools/arch-kernel/build-from-series.sh
```

### 2.3 打 boot + 配对

```bash
# STOCK_BOOT/VBMETA 指向 v3 Android-only 链，不要用当前的 kShimC boot_a
STOCK_BOOT=work/v3/boot.img VBMETA=work/v3/vbmeta.img \
SHIM=work/kshim/kShimC.bin OUT=work/boot \
tools/kshim_variants.sh local work/kernel73/out/Image work/kernel73/out/sm8650-lenovo-tb710fu-kshim.dtb

tools/make-pair.sh work/boot/current/boot_android.img \
                   work/boot/current/boot_linux.img > pair.env
```

> kshim DTB 的 `/chosen/bootargs` 默认带 `tb710fu.nbd nbd.max_part=8`；第一次安装时
> 盘上还没有 `sda15`，`boot_linux` 会自动回退到 NBD，不需要另打 “NBD 变体”。

### 2.4 装模块

```bash
modules/build_modules.sh
tools/post_flash_modules.sh <serial>
```

---

## 3. 约定

- 所有需要 root 的设备操作都显式 `sudo`/`su -c`；
- 不自动重启、不自动刷机；
- 写前备份、写后回读；
- 失败时保留日志与回退件，不要「再试一次写入」。
