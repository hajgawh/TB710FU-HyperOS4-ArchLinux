# 联想小新 Pad Pro GT（TB710FU）HyperOS 4 + Arch Linux 移植与修复指南

> **English:** A community, data-preserving port of Xiaomi Pad 8 (`yupei`) HyperOS 4.0.11
> to the Lenovo TB710FU (Xiaoxin Pad Pro GT, SM8650Q), reusing a community HyperOS 3
> port's Lenovo vendor/ODM, plus an optional Arch Linux ARM dual-boot on the same UFS.
> No proprietary binaries are included; official packages are linked, not redistributed.
> All device-unique identifiers in this repository are placeholders — see [PRIVACY.md](PRIVACY.md).

把 **小米平板 8（`yupei`）的 HyperOS 4.0.11** 移植到 **联想小新平板 Pro GT（TB710FU，
骁龙 8 Gen 3 / SM8650Q，3200×2000）**，复用社区 OS3 移植包的联想 vendor/ODM，并在同一块
UFS 上做 **Arch Linux ARM 双系统**。

本仓库是 2026-11-06 → 2026-11-09 全部修复的**重新整理版**：只保留可复现的脚本、补丁、
模块与结论，不含任何官方/第三方二进制、设备备份或个人数据。

> 这是社区研究项目，不是联想/小米/高通官方项目。刷机有变砖、丢数据、失去保修的风险；
> 操作前请完整备份，并在每次物理写入前确认目标分区。**第一次从原厂/OS3 安装，先看
> [docs/00-install-paths.md](docs/00-install-paths.md)**；已有双系统的升级路径见下方
> 「首次安装 vs 升级」。

---

## 状态（2026-11-09 基线）

> 2026-11-10 的两处机内更正已并入：`panel_direction` 横屏 90 应为 1（docs/04 §8）、
> Aperture 横屏 UI 定稿（docs/12）。其余哈希/版本仍以 11-09 基线为准。

| 项 | 值 |
|---|---|
| 设备 | Lenovo TB710FU（Xiaoxin Pad Pro GT），SM8650Q，8+256（测试机） |
| OS4 底包 | Xiaomi Pad 8 / `yupei` / `OS4.0.11.0.XPZCNXM` |
| vendor/ODM | 社区 HyperOS 3 移植包（联想 ZUXOS 1.5.04.428 底），冻结不换 |
| 引导 | 已解锁 BL；kShimC 菜单；v3 启动链（testkey，`vbmeta flags=1`） |
| root | KernelSU-Next LKM（`init_boot_a`） |
| 最终 super | `dd6cfbb8…`，10,392,436,736 B（9.679 GiB），7 分区 manifest 全 MATCH |
| 包内验收 | 61/61（`verify_package.sh`）；真机 40 项 0 失败（`verify_device.sh`） |
| 数据 | 升级只写 super、不 `--wipe`；`/data`、KSU、Arch、账号、共享分区都保留 |
| 槽位 | 当前 `_a`；super `_b` 全 0 extent，boot B 与 A 不同，**不要切 B** |
| Arch 内核 | `7.3.0-tb710fu` **#32**（v36-quiet2），Image `37f997fb…`，DTB `349dcec2…` |
| Arch boot_a | `8c45a8a3…`（v36 Arch 默认变体，96 MiB） |
| Arch 模块 | `119374f1…`（整包 tar，含 `msm.ko` 非阻塞 shrinker、zram zstd） |
| 双系统 | kShimC 配对 v36 作者基线：Android 默认 `04be8d38…` / Linux 默认 `8c45a8a3…`；**脚本不读取这两个值**，用 `tools/make-pair.sh` 生成你自己的 `pair.env` |
| 共享分区 | `sda16 share` ext4 8 GiB；Arch `/mnt/share`，OS4 模块 `TB710FUShareMount` v1.1 |
| 时间 | Arch：RTC SDAM offset 持久化；OS4：fake-hwclock（epoch + RTC raw 增量） |

### OS4 侧已验证

- 字体 100%、40px R 角、联想 marketname、亮度/HBM、色彩模式、人脸、语音唤醒、
  前置相机（Aperture）、相册查看、右边缘侧滑（主因已修；launcher stub 竞态偶发）、
  刷新率/灵动岛保持原厂；
- 六个运行时模块：`TB710FUSetRes` v2.0、`TB710FUThermal` v1.1、`TB710FUCPUMax` v1.2、
  `TB710FUDebloat` v1.5.2、`TB710FUDPWidebusOff` v1.3、`TB710FUShareMount` v1.1；
- 升级路径不 wipe；61 项包内验收 + 40 项真机验收。

### Arch 侧已验证

- 7.3 内核 v36：6 核 1+2+2+1 拓扑、X4 boost 3302 MHz、PSI/MGLRU、zram zstd；
- Type-C/DP：A27U 直连 4-lane HBR2 4K60，扩展坞 2-lane HBR3 4K60 + USB3 5000M；
- 换向/插拔硬复位已收口（v34 `tb_hpd_delay_ms=1000`，8 轮 0 复位）；
- 坞 USB3「插上即断」已修（v32 跳过 QMP COM 重建；v33e 换向前停 USB3 PCS）；
- 熄屏后显示器不再每 27 s 弹「无信号」（`keep_link=0`，DPMS 完整下电）；
- 音频：禁 UCM + pro-audio + TDM 四功放 + RTKit + 5 期缓冲，0 XRUN；
- 电源：短按电源键不关机、80% 限充、s2idle 持久化、纯电池温控 v5；
- 内存：PSI/MGLRU、zram 6.8 GiB zstd、earlyoom、`watermark_scale_factor=250`；
- 桌面：虚拟键盘 v3、krfb VNC、CJK 简体字形、KDE 密钥环、Firefox VA-API 硬解；
- 双系统：`switch2os4` / `switch2arch.sh` + 共享分区双向 E2E。

### 明确没做 / 不可用

- 4-lane HBR3 + 4K60 30bpp **不作日常默认**（DPMS 唤醒后 sink 锁不住，已回退 HBR2/24bpp）；
- A27U 直连时，睡眠后显示器侧内置 USB2 HUB 不回枚举（显示器行为，需拔插或给显示器断电）；
- 扬声器「稳态偶发噼啪」口径为**待定**：卡顿/XRUN 已修，但缺少客观录音/频谱验证；
- Mesa freedreno batch cache 32 槽耗尽后单进程活锁（上游缺陷，只能 `tb-ff-restart`）；
- Waydroid 暂缓（需重编内核补策略路由）；UU 远程 + box64/Wine 不可用；
- OS4 插着 A27U 重启后可能无信号（vendor DP 首训时序），规避见 docs/07；
- 不提供解锁 Bootloader 的方法；本项目从「已解锁」开始。

---

## 首次安装 vs 升级（先读这一节）

本仓库默认写给**已经在用本项目基线**的人：升级只写 `super`、不 `--wipe`。如果你是
**第一次**把一台原厂/OS3 的 TB710FU 装成 OS4 + Arch 双系统，先看
[docs/00-install-paths.md](docs/00-install-paths.md) 的决策表；两者的步骤和红线不同。

| 你的现状 | 走哪条路 | `super --wipe` | 缩 userdata（会清 Android 数据） | 建 `sda15` |
|---|---|---|---|---|
| 原厂 ZUI / OS3，没有本项目的 OS4 | **首次安装**：备份 → v3 链 → NBD 试跑 → 缩 userdata/建 `sda15`/rsync → 首次刷 OS4 | 是，一次 | 是 | 是 |
| 已刷本项目 OS4，没有 Arch | **加装 Arch**：NBD 试跑 → 缩 userdata/建 `sda15`/rsync → 写 kShimC boot | 否 | **是（Android 数据仍会丢）** | 是 |
| 已有 OS4 + Arch，`sda15` 存在 | **升级**：OS4 走 04 §3/§4，Arch 走 05/06，切换/共享走 08 | 否 | 否 | 否 |

**三条硬规则：**

1. **升级不 wipe。** 只写 `super`（04 §3）或换 `boot_a`/模块（05 §8）、`pacman -Syu`（06）。
2. **只有首次安装/加装 Arch 才建 `sda15`。** 原厂盘是分满的，`userdata` 不能在线缩；
   加装 Arch 必然要离线缩 `userdata`，Android 会重新格式化，**即使不加 `--wipe` 也会丢数据**。
   已有 `sda15` 的升级路径绝不重建。
3. **只写 A 槽。** `super _b` 全 0 extent、`boot_b` 不是备份；不要 `fastboot set_active b`。

> 「从零开始」= 已解锁 + 能进 9008 + 会恢复自己的 `boot_a`/`vbmeta_a`；解锁本身不在
> 本仓库范围内。首次安装的完整命令（GPT 备份、v3 链、NBD 服务、缩分区、rsync、首次
> `--wipe`）都在 [docs/00-install-paths.md](docs/00-install-paths.md)。

---

## 为什么选这个方案（与其它 TB710FU Linux 项目的差异）

**一句话结论**：本项目 = **mainline Linux 7.3 + Arch Linux ARM + KDE Plasma 6 Wayland +
完整 Type-C DP alt mode + 与 HyperOS 4 双系统共存**。目标是一台**能接 4K60 显示器日常
办公的平板**，不是 SteamOS 游戏机方案，也不是抹掉 Android 的纯 Linux 单系统。

差异不在「能不能启动 Linux」，而在三件事：

1. **整机可用性**：不是只点亮内屏，而是把 Type-C DP（直连/坞）、DP 音频、USB3、s2idle、
   温控与限充作为一组链路逐项验收（docs/05–08）。
2. **办公桌面**：Arch + Plasma 6 Wayland 上，Firefox 硬解、中文虚拟键盘、krfb、CJK 字形、
   KDE 密钥环都有包内配置与验收口径（docs/06）。
3. **不牺牲 Android**：HyperOS 4.0.11 与 Arch 同盘共存，升级只写 super、不 wipe；
   不是单系统方案（docs/08）。

### 与其它公开方案的对比

> 除「本项目」为本机实测/包内验收外，其余信息来自各项目公开 README/描述（截至
> 2026-11-09），未在本机逐项复测；这不是功能排名，版本与支持范围以对方仓库为准。

| 方案 | 定位 | 内核 / 桌面 | 关键能力与已知边界 | 与 Android 共存 |
|---|---|---|---|---|
| **本项目** | TB710FU 整机：HyperOS 4 移植 + Arch 双系统 | mainline `7.3.0-tb710fu #32`（v36-quiet2）；Arch Linux ARM + KDE Plasma 6 Wayland | 6 核 1+2+2+1、X4 boost 3302 MHz；直连 4L HBR2 4K60 8bpc，坞 2L HBR3 4K60 + USB3 5000M + DP 音频；v34 换向 8 轮 0 复位；s2idle；zram/PSI/MGLRU；温控 v5 + 80% 限充 | HyperOS 4.0.11 + Arch 同一 UFS；升级只写 super、不 wipe；8 GiB 共享分区双向可读 |
| [lich-wang/tb710fu-hyperos-steamos](https://github.com/lich-wang/tb710fu-hyperos-steamos) | SteamOS/游戏导向；本项目的双系统与 OS4 构建脚本基线 | 内核基线早于 7.3（公开资料以 SteamOS/游戏为主） | 面向游戏场景与 SteamOS 工作流；不以 Arch 办公桌面/完整 DP 外设为目标（本项目未复测其当前状态） | 提供 HyperOS + SteamOS 双系统思路，是本项目双系统方案的参考 |
| [MeteoricmeteorLL/tb710fu-linux](https://github.com/MeteoricmeteorLL/tb710fu-linux) | TB710FU 独立 Linux 移植（DTS/面板/触摸/音频等） | 公开 README：mainline 7.2 + Plasma 6 | 公开 README 自述的边界：WiFi 延迟/吞吐与稳定性、扬声器失真待完善；麦克风/传感器/相机/suspend 未完成或未测试（以其 README 为准） | 独立分区安装、保留原 Android 槽位；未描述 HyperOS 4 移植与 Android vendor 适配 |
| [mydanyi/armadaos-freedom](https://github.com/mydanyi/armadaos-freedom) | SM8650 / 掌机（Y700 等）参考方案 | 面向 SM8650 的内核/补丁基线 | 不作为 TB710FU 整机方案；平板面板/触摸/DP/音频需自行适配（本项目仅参考其内核补丁） | 不含 TB710FU 的 Android 双系统 |
| 通用 postmarketOS / Debian 类 | 通用 ARM64 发行版 | 各发行版主线内核 + 各自桌面 | 主线对 SM8650 平板支持有限；Type-C DP、DP 音频、s2idle、温控通常不完整，需要自行 bring-up | 一般单独占机/分区，不做 HyperOS 数据保留 |

### 日常办公体验（包内已落地）

| 办公场景 | 包内实现 / 验收 |
|---|---|
| 桌面与显示 | KDE Plasma 6 Wayland；KWin 原生缩放与多屏，内屏 3200×2000@120，外接 DP 4K60 |
| 浏览器 | Firefox VA-API 硬解（iris 补丁 + `qcom-va-driver` 放 `/var/lib/dri` + `MOZ_DISABLE_RDD_SANDBOX=1`）；B 站播放时 RDD CPU 约 3% |
| 中文输入 | 虚拟键盘 v3（登录 +6 s 切一次；`enabledLocales=zh_CN,en_US`，简体拼音）；硬件键盘用你自己的输入法（如 fcitx5/Rime，需自行安装） |
| 远程桌面 | krfb VNC 按需 `tb-krfb-start` / `tb-krfb-stop`；已修 `passwordSet`、portal 竞态、坐标缩放（物理/逻辑 ×2.25） |
| 中文字形 | fontconfig SC 规则；`fc-match 'sans-serif:lang=zh-cn'` 命中 Noto Sans CJK SC |
| 密钥环 | KDE 密钥环（ksecretd D-Bus 激活 + 空密码钱包），libsecret/Chromium 不再挂死；空密码是刻意的取舍（与自动登录同级） |
| 内存 | zram 6.8 GiB zstd、swappiness 180、MGLRU、earlyoom、`watermark_scale_factor=250` |
| 充电 | 80% 限充（`end=80` / `start=70`，开机/resume 延迟重写）；短按电源键只锁屏 |
| 温控 | v5 纯电池限频：38/39/40 ℃ 三档降 `scaling_max_freq`，40.9 ℃ 停充，0.5 ℃ 回差 |
| 睡眠 | `mem_sleep=s2idle` 持久化；带 HDMI 坞的 USB hub 跨 s2idle 存活 |

### 不适合谁

如果你的主要目标命中以下任一条，这个方案不是最优解：

- **只想要 Waydroid / 安卓应用容器**：Waydroid 暂缓（需重编内核补策略路由），当前没有开箱方案。
- **要跑 UU 远程 + box64/Wine**：当前不可用（Wine 11 断言），不建议为此刷机。
- **追求 4-lane HBR3 + 4K60 30bpp**：不是日常默认；DPMS 唤醒后 sink 锁不住，已回退 4L HBR2 / 24bpp。
- **A27U 直连且经常睡眠**：睡眠后显示器侧内置 USB2 hub 不重新枚举，需拔插或给显示器断电（显示器侧行为）。
- **还没解锁 Bootloader**：本项目从「已解锁」开始，不提供解锁方法。

完整边界见上文「明确没做 / 不可用」。

---

## 架构

```
ABL（已解锁，不强制 AVB）
 └─ boot_a = kShimC 菜单 + GKI 6.1.128（HyperOS）+ Linux 7.3.0（Arch）+ DTB
      ├─ 菜单 "HyperOS" → super
      │    ├─ system / system_ext / product ← yupei OS4.0.11 重建
      │    └─ vendor / odm / vendor_dlkm / system_dlkm ← OS3 移植包冻结
      └─ 菜单 "Arch Linux" → initramfs → UFS sda15（btrfs @）
                                    └─ sda16 share（ext4，两侧共用）
```

```
TB710FU super（约 20.4 GB 物理，内容约 9.68 GB）
├── system        0.96 GB   yupei 4.0.11 + lwky + bootfix + sepolicy compat
├── system_ext    0.83 GB   yupei 4.0.11 + 色彩补丁 jar
├── product       6.76 GB   yupei 4.0.11 + piano.xml + PearlBiometric + NCM RRO
├── vendor        1.48 GB   OS3 移植包（联想硬件适配）
├── odm           0.46 GB   OS3 移植包（联想/小米 mslg 栈）
└── dlkm          0.04 GB   OS3 移植包
```

---

## 仓库结构

```
README.md                 本文
AGENT.md                  给执行刷机的 AI Agent 的操作规程（红线、状态判断、检查点）
PRIVACY.md                隐私与脱敏说明（哪些是占位符、怎么换成你自己的）
NOTICE.md                 上游/第三方项目、许可证、未包含的二进制
LICENSE                   GPL-2.0（与上游一致）
docs/
  00-install-paths.md     首次安装 vs 升级、决策表、首次分区/NBD/wipe 完整链
  01-overview.md          结论、架构、能力矩阵、阅读顺序
  02-materials.md         官方/第三方材料、工具链、work/ 布局、磁盘预算
  03-os4-build.md         OS4 构建流水线、包内修复、61 项验收
  04-os4-install.md       备份、EDL、v3 启动链、刷入、KSU、模块、回退
  05-arch-kernel.md       7.3 内核 v36：补丁序列、config、DTB、boot 打包
  06-arch-userspace.md    Arch 用户态：音频/电源/温控/内存/显示/桌面
  07-usbc-dp.md           Type-C/DP/Hub/DP 音频/睡眠专项
  08-dualboot-share.md    kShimC 配对、切换器、共享分区
  09-runtime-modules.md   六个 KernelSU 模块的行为与验收
  10-troubleshooting.md   症状 → 根因 → 修法
  11-lessons.md           经验与「不要做」
  12-os4-touch-backgesture.md  OS4 右边缘触控/侧滑根因、SetRes v2.0、launcher stub 竞态
tools/
  build_os4.py             OS4 staging + super 组装
  port_build.sh            一条命令构建 + 验收
  flash_super.sh           EDL 写 super（默认不 wipe）
  check_super.py / verify_package.sh / verify_device.sh
  kshim_pack_boot.py / kshim_variants.sh / kshim_gki_check.py
  make-pair.sh             用你自己的两份 boot 镜像生成 pair.env
  arch-side/               Arch 侧双系统切换（switch2os4 + sudoers + 桌面图标）
  os4-switch/              OS4 侧切换（switch2arch.sh + KSU 模块 + 安装器）
  arch-kernel/             7.3 补丁序列构建、单模块重编、config 检查
  arch-userspace/          install-userspace.sh + 全部用户态配置
modules/                   六个在用 KSU 模块源码 + build_modules.sh
patches/
  kernel/full/              vanilla 7.3 → v36 的 27 个补丁
  kernel/incremental/       v25-prod → v36 的 8 个补丁
  arch/                    锁屏 DPMS 背光、Blender 触摸、ksystemstats（历史专题）
  ksystemstats/            KDE 系统监视器 GPU 传感器
hyperos/                   笔键位、displayconfig、SELinux 兼容、camera/（Aperture 自备 + stub 源码）
assets/                    NCM overlay 源码
work/                      你的输入与产物（不入库；见 work/README.md）
```

---

## 快速开始

> 路径均为示例，按你的实际目录替换。`<serial>` 是 `adb devices` 里的设备序列号；
> 所有 MAC/序列号/IP/分区 UUID 在仓库里都是占位符，见 [PRIVACY.md](PRIVACY.md)。

```bash
# 0) 主机工具（示例：macOS + Homebrew）
brew install erofs-utils openjdk apktool android-platform-tools
pip3 install --user protobuf

# 1) 准备材料（见 docs/02-materials.md）
#    - Xiaomi Pad 8 / yupei / OS4.0.11.0.XPZCNXM 全量 OTA
#    - 社区 OS3 移植包（vendor/ODM/lwky/PearlBiometric）
#    - 你自己的 boot_a / vbmeta_a 备份、firehose programmer
#    - KernelSU-Next、ArchLinuxARM、内核/固件源码

# 2) 构建 OS4（只构建，不刷机）
tools/port_build.sh
# -> work/build_os4/out/super_fixed.img
# -> 61 项包内验收

# 3) 刷入（设备在 9008/EDL，电量 >=30%）
#    首次安装（原厂/OS3）不要只跑这一条：先按 docs/00 做备份、v3 链、
#    NBD 试跑、建 sda15；首次刷 super 要加 --wipe（只一次）。
#    已有双系统升级：不要加 --wipe。
EDL="$PWD/tools/venv/bin/edl" \
LOADER="$PWD/work/firehose/prog_firehose_ddr-TB710FU.melf" \
bash tools/flash_super.sh work/build_os4/out/super_fixed.img

# 4) 装模块 + 验收
tools/post_flash_modules.sh <serial>
tools/verify_device.sh <serial>

# 5) Arch（可选）
#    先按 docs/00 §3 做 GPT 备份、v3 链、NBD 试跑、建 sda15；再构建内核/boot
tools/arch-kernel/build-from-series.sh        # 在 kernel-build 容器里
STOCK_BOOT=work/v3/boot.img VBMETA=work/v3/vbmeta.img \
  tools/kshim_variants.sh local <Image> <DTB>  # 打两个默认变体
tools/make-pair.sh work/boot/current/boot_android.img \
                   work/boot/current/boot_linux.img > pair.env
# 按 docs/05、docs/06、docs/08 安装
```

详细步骤与风险点：

0. [首次安装 vs 升级：先选路径](docs/00-install-paths.md)
1. [总览与结论](docs/01-overview.md)
2. [材料与工具链](docs/02-materials.md)
3. [构建 OS4](docs/03-os4-build.md)
4. [安装/刷入](docs/04-os4-install.md)
5. [Arch 内核](docs/05-arch-kernel.md)
6. [Arch 用户态](docs/06-arch-userspace.md)
7. [Type-C/DP 专项](docs/07-usbc-dp.md)
8. [双系统与共享分区](docs/08-dualboot-share.md)
9. [运行时模块](docs/09-runtime-modules.md)
10. [排错](docs/10-troubleshooting.md)
11. [经验与不要做](docs/11-lessons.md)
12. [OS4 右边缘触控与侧滑返回](docs/12-os4-touch-backgesture.md)

---

## 关键经验（先看这十条）

1. **vendor 不要换。** OS4 的 yupei vendor 是小米平板 8（SM8735P）的；TB710FU 的显示、
   触控、充电、音频、mslg/PC 栈都在 OS3 vendor/ODM 里。
2. **升级只写 super、不 `--wipe`。** `/data`、KSU、Arch、账号、共享分区都在。
3. **每次物理写入前确认目标分区。** `persist`、`modemst1/2`、`fsg`、`fsc`、`devinfo`、
   `frp`、`keystore`、`ssd`、`secdata`、`uefivarstore`、`cdt`、`ddr` 永不写入。
4. **字体 0.85 是陷阱。** OS4 字体页只有 90/100/110/…；包内 bootfix 每次开机写 1.0。
5. **R 角只差一个资源。** `DevicesOverlay.apk` 的 `rounded_corner_content_padding`：
   原厂 40px，旧 OS3/piano 适配 10px；硬件圆角两台机器都是 54px。
6. **Type-C 复位有三层。** WCD939x 全断全建、QMP combo 在 DP_ONLY 下初始化、msm PHY
   引用计数不配对；v32/v33 之后还要让 DP 连接上报避开 USB/SS 枚举窗口（v34）。
7. **`keep_link` 必须是 N。** 否则关屏后 DPTX 一直驱动主链路，A27U 无法真正待机，
   每约 27 s 弹一次「无信号」。
8. **Firefox 整屏卡死 ≠ Firefox 卡死。** 先看 `kswapd0` 与 `msm_gem_shrinker`；
   11-08 已把回收路径的 `wait_for_idle()` 改成 `dma_resv_test_signaled()`。
9. **单进程 `gdrv0` 100% 是 Mesa batch cache 活锁。** RSS 不动、GPU 空闲、无 D 状态；
   只能 `tb-ff-restart`，降概率靠 `watermark_scale_factor=250`。
10. **双系统切换 = 配对镜像，没有运行时「下次启动选择」。** 两个变体同 Image/DTB，
    只是菜单默认项不同；切换 = 备份 → 写 `boot_a` → 回读 sha256 → 重启。

> ⚠️ **改分区表的红线（建共享分区 `sda16`）。** 这是全书唯一一处改 GPT 的操作。
> `sgdisk -d 15` **只能执行一次**；`partx -u` 之后 `/dev/sda16` 没出现**不是失败**——
> GPT 已经写好了，正确动作是**重启后只补 `mkfs.ext4`**。再删一次 15 号，删掉的是刚重建
> 的 Arch 根分区记录。逐步判定表见 [docs/08 §1.1](docs/08-dualboot-share.md)。

> 完整经验与「不要做」见 [docs/11-lessons.md](docs/11-lessons.md)。

---

## 参考的开源项目

| 项目 | 用途 | 许可证/说明 |
|---|---|---|
| [lich-wang/tb710fu-hyperos-steamos](https://github.com/lich-wang/tb710fu-hyperos-steamos) | 基线：锁 BL 双系统、`build_os4.py`/`make_super.py`/`flash_super.sh` | GPL-2.0 |
| [sunflower2333/kShimC](https://github.com/sunflower2333/kShimC) | 开机菜单 shim | 见上游 |
| [Project-Aloha/DualBootKernelPatcher](https://github.com/Project-Aloha/DualBootKernelPatcher) | 多内核打包 | 见上游 |
| [mydanyi/armadaos-freedom](https://github.com/mydanyi/armadaos-freedom) | SM8650 内核补丁基线 | 见上游 |
| [MeteoricmeteorLL/tb710fu-linux](https://github.com/MeteoricmeteorLL/tb710fu-linux) | TB710FU DTS、面板/触摸/音频/WiFi | 见上游 |
| [KernelSU-Next/KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) | root（LKM） | GPL-3.0 |
| [bkerler/edl](https://github.com/bkerler/edl) | 高通 9008 读写 | 见上游 |
| [erofs/erofs-utils](https://github.com/erofs/erofs-utils) | `mkfs.erofs` / `fsck.erofs` / `dump.erofs` | GPL-2.0 |
| [iBotPeaches/Apktool](https://github.com/iBotPeaches/Apktool) | APK 反编译/回编 | Apache-2.0 |
| [ssut/payload-dumper-go](https://github.com/ssut/payload-dumper-go) | OTA payload 提取 | Apache-2.0 |
| [AOSP avb](https://android.googlesource.com/platform/external/avb/) | `avbtool` / testkey | Apache-2.0 |
| [ArchLinuxARM](https://archlinuxarm.org/) | Arch aarch64 rootfs | 见上游 |
| 酷安 @兰微卡鱼 | HyperOS 3 移植包（vendor/ODM/lwky 基础） | 第三方，非本仓库 |

---

## 不包含与隐私

本仓库**不包含**：

- 小米官方 OTA、联想官方固件、任何 `super`/`vendor`/`boot`/`firehose` 二进制；
- 社区 OS3 移植包、修改后的 `miui-services.jar`、`PearlBiometric.apk`、`lwky` 二进制；
- 设备备份、分区镜像、`persist`/`modemst`/`keystore` 等唯一分区数据；
- 任何真实序列号、IMEI/MEID、MAC、Wi-Fi SSID、IP、账号、密钥、ADB 授权文件；
- 个人路径、日志中的设备标识、WPS/CAD 用户数据。

**本仓库中的 MAC 地址、序列号、内网 IP、分区 UUID 全部是占位符**，例如
`02:11:22:33:44:55`、`<serial>`、`<device-ip>`、`<share-uuid>`。它们不能直接用于你的设备；
请按 [PRIVACY.md](PRIVACY.md) 换成你自己的值。

---

## 许可证与免责声明

- 本仓库的文档与脚本以 **GPL-2.0** 发布（与上游一致）；第三方项目各自保留其许可证，
  见 [NOTICE.md](NOTICE.md)。
- 本项目与联想、小米、高通、Valve 无关；所有商标归其所有者。
- 解锁 Bootloader、刷写分区可能违反保修条款或当地法规；请自行确认你拥有设备并承担风险。
- 不提供任何明示或暗示的担保；因使用本指南造成的设备损坏、数据丢失、账号异常，
  作者不承担责任。
