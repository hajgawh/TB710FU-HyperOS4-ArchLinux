# 01 — 总览：结论、架构与能力边界

> 基线：2026-11-09（2026-11-10 的两处更正已并入），Arch 内核 `7.3.0-tb710fu #32`（v36-quiet2），
> OS4 super `dd6cfbb8…`（411d）。
> 本文只给结论与地图；每个结论的证据链在 `docs/03`–`docs/09` 与原始资料索引里。

---

## 1. 这个项目做了什么

在一台**已解锁 Bootloader** 的联想 TB710FU 上：

1. 把小米平板 8（`yupei`）的 HyperOS 4.0.11 移植过来，复用社区 OS3 移植包的联想
   vendor/ODM，做到**升级不 wipe**、硬件功能基本完整；
2. 在同一块 UFS 上装 Arch Linux ARM（btrfs），用 kShimC 菜单在开机时二选一；
3. 修掉两类长期问题：
   - **Android 侧**：字体/R 角/身份/相机/色彩/亮度/侧滑/时间等包内修复；
   - **Arch 侧**：Type-C/DP/Hub/音频/睡眠/内存/温控/日志等内核与用户态问题。

---

## 2. 当前基线

| 层 | 内容 | 关键哈希 |
|---|---|---|
| 引导 | ABL 已解锁；`boot_a` = kShimC 菜单 + GKI 6.1.128 + Linux 7.3 + DTB | Arch 默认 `8c45a8a3…`；Android 默认 `04be8d38…` |
| OS4 system | `yupei` 4.0.11 + bootfix + sepolicy compat | super `dd6cfbb8…`，10,392,436,736 B |
| OS4 vendor | OS3 移植包冻结 | 7 分区 manifest 全 MATCH |
| root | KernelSU-Next LKM | `init_boot_a` |
| OS4 模块 | SetRes v2.0 / Thermal v1.1 / CPUMax v1.2 / Debloat v1.5.2 / Widebus v1.3 / ShareMount v1.1 | 源码在 `modules/` |
| Arch 内核 | 7.3.0-tb710fu #32（v36-quiet2） | Image `37f997fb…`，DTB `349dcec2…` |
| Arch 模块 | 整包 tar | `119374f1…` |
| Arch root | btrfs `sda15` 120 GiB | `/swap/swapfile` 4 GiB |
| 共享 | ext4 `sda16` 8 GiB | `LABEL=share` |
| 时间 | Arch：RTC SDAM offset；OS4：fake-hwclock | — |

> 以上哈希是**作者构建**的基线，用于对照；你的构建结果会不同。双系统的两个 boot
> 哈希不随仓库分发，用 `tools/make-pair.sh` 生成你自己的 `pair.env`。

---

## 3. 四层模型

排查问题时按层定位，不要跨层猜：

| 层 | 内容 | 典型问题 |
|---|---|---|
| L1 引导 | ABL / kShimC / GKI / DTB / boot_a | 卡菜单、卡开机动画、OS4 起不来 |
| L2 OS4 | super（system/system_ext/product）、vendor/ODM | 字体、R 角、相机、色彩、身份 |
| L3 Arch 内核 | Image + modules + DTS | DP/USB/触摸/音频/睡眠/内存 |
| L4 用户态 | systemd、WirePlumber、KWin、脚本 | sink、限充、温控、虚拟键盘、VNC |

**边界**：OS4 的 super 与 Arch 的 `boot_a`/rootfs 互不影响；切换只写 `boot_a`。
日常换 Arch 内核/模块不会动 Android 数据，反之亦然；但**首次从 userdata 尾部建 `sda15`**
会缩 userdata，Android 会重新格式化（见 [00](00-install-paths.md) §1）。

---

## 4. 能力矩阵

### 4.1 OS4（Android）

| 功能 | 状态 | 做法/备注 |
|---|---|---|
| 数据保留升级 | ✅ | 只写 super，不 `--wipe` |
| 字体 100% | ✅ | `/system/etc/tb710fu_bootfix.sh` 每次开机写 1.0 |
| 40px R 角 | ✅ | 原厂 `DevicesOverlay.apk` 资源 |
| 联想 marketname | ✅ | `product/etc/build.prop` |
| 亮度/HBM | ✅ | displayconfig 命中联想面板；日常 516 nit，强光 782 nit |
| 色彩模式 | ✅ | `miui-services.jar` 原位补丁 + 删旧 oat |
| 人脸解锁 | ✅ | OS3 `PearlBiometric` + `support_tee_face_unlock=false` |
| 语音唤醒 | ✅ | `VoiceAssistAndroidT.apk` 白名单 |
| 前置相机 | ✅ | Aperture（MiuiCamera 退役） |
| 相册查看 | ✅ | `SpecialTypesProvider` 替身 |
| 右边缘侧滑 | ✅（主因已修） | `panel_direction` 跟随旋转（横屏 90→1）+ `game_edge=0` + `game_mode=2`；横屏 letterbox 列表（SetRes v2.0）；launcher stub 竞态仍偶发第一下失败（见 `12-os4-touch-backgesture.md`） |
| 刷新率/灵动岛 | ✅ | 保持 4.0.11 原厂，不写额外 prop |
| 时间 | ✅ | fake-hwclock（epoch + RTC raw 锚点，随 SetRes v2.0） |
| 温控/CPU | ✅ | 三模块；原厂热档优先 |
| 精简/反诈冻结 | ✅（可选） | Debloat v1.5.2；停用模块 ≠ 恢复 |
| 外接屏 | ⚠️ | widebus v1.3；带屏重启可能无信号，需规避 |

### 4.2 Arch Linux

| 功能 | 状态 | 备注 |
|---|---|---|
| 6 核 1+2+2+1 | ✅ | X4 boost 3302 MHz；A720/A520 按簇 |
| 内屏 3200×2000@120 | ✅ | 面板/背光/触摸模块化 |
| 锁屏 DPMS 背光 | ✅ | 面板模块直接 `devm_of_find_backlight()` |
| Type-C DP 直连 | ✅ | 4-lane HBR2 4K60 8bpc |
| 扩展坞 4K60 + USB3 | ✅ | 2-lane HBR3 CVT-RB；USB3 5000M |
| 换向/插拔 | ✅ | v34 后 8 轮 0 复位（出图状态） |
| 睡眠 | ✅ | s2idle；带坞 USB hub 存活；A27U 直连 hub 需拔插 |
| DP 音频 | ✅ | tplg 子图 + mixer；禁 UCM |
| 扬声器/麦克风 | ✅ | TDM 四功放 + SoundWire 采集；0 XRUN |
| 80% 限充 | ✅ | 开机/resume 延迟重写 |
| 纯电池温控 v5 | ✅ | 38/39/40 ℃ 限 `scaling_max_freq` |
| zram/PSI/MGLRU | ✅ | 6.8 GiB zstd；`watermark_scale_factor=250` |
| Firefox VA-API | ✅ | iris 补丁 + `/var/lib/dri` + RDD 沙箱 |
| 虚拟键盘 | ✅ | v3：登录 +6s 切一次 |
| krfb VNC | ✅ | portal 竞态 + 坐标缩放补丁 |
| 共享分区 | ✅ | `LABEL=share` / OS4 模块 |
| Waydroid | ⚠️ 暂缓 | 需策略路由/xtables 重编 |
| UU + box64/Wine | ❌ | Wine 11 断言；不可用 |
| 4L HBR3 + 30bpp | ⚠️ 非默认 | DPMS 唤醒后 sink 锁不住 |

---

## 5. 关键设计决定

1. **vendor/ODM 冻结**：联想硬件适配（显示、触控、充电、音频、mslg）都在 OS3 vendor 里；
   换 OS4 的 yupei vendor 会丢硬件。
2. **包内优先，模块只做 root/运行时**：字体、R 角、身份、相机、色彩都进 super；
   KSU 模块只做需要 root 或需要读 Settings 的桥。
3. **内核对 DP 用「状态机 + 延迟上报」而不是用户态守门**：KWin 在 hotplug 里会立刻
   enable 输出，用户态 `kscreen-doctor` 抢不过；v34 在 `pmic_glink_altmode` 延迟 1 s
   上报 DP 连接，让 USB/SS 枚举先完成。
4. **日志默认安静**：bring-up 调试打印全部降级/编译掉；空闲 60 s 0 行内核日志。
5. **可回退**：每次 boot/super/模块改动都留备份；双系统切换前备份 `boot_a`。

---

## 6. 阅读顺序

| 你想做什么 | 看 |
|---|---|
| 先判断走哪条路（首次安装 / 升级） | [00-install-paths.md](00-install-paths.md) |
| 先判断值不值得做 | 本文 §4 + `README.md`「明确没做」 |
| 从零准备材料 | [02-materials.md](02-materials.md) |
| 重建 OS4 | [03-os4-build.md](03-os4-build.md) → [04-os4-install.md](04-os4-install.md) |
| 重建 Arch 内核 | [05-arch-kernel.md](05-arch-kernel.md) |
| 装 Arch 用户态修复 | [06-arch-userspace.md](06-arch-userspace.md) |
| 查 Type-C/DP 问题 | [07-usbc-dp.md](07-usbc-dp.md) |
| 做双系统/共享分区 | [08-dualboot-share.md](08-dualboot-share.md) |
| 管理 KSU 模块 | [09-runtime-modules.md](09-runtime-modules.md) |
| 出问题了 | [10-troubleshooting.md](10-troubleshooting.md) |
| 避免重复踩坑 | [11-lessons.md](11-lessons.md) |

---

## 7. 术语

- **yupei**：小米平板 8 代号；OS4 底包来源。
- **OS3 移植包**：社区（酷安 @兰微卡鱼）做的 HyperOS 3 联想移植包，提供 vendor/ODM/lwky。
- **kShimC**：开机菜单 shim，把 GKI + Linux + DTB 打进一个 `boot_a`，菜单默认项固化。
- **配对（pair）**：同一 Image/DTB 的两个菜单默认变体；切换 = 写 `boot_a`。
- **super**：Android 动态分区容器（system/system_ext/product/vendor/odm/dlkm），物理约
  20.4 GB；本项目只写它的内容，不写 GPT。
- **`sda14` / `sda15` / `sda16`**：`userdata`（Android 数据）/ `archlinux`（Arch 根）/
  `share`（可选共享分区）。`sda15` 从 `userdata` 尾部切出，不是紧贴 `super`。
- **`--wipe`**：`flash_super.sh` 的可选参数，清零 `metadata` + `userdata` 头部，使 Android
  恢复出厂；**升级永远不加**。缩 `userdata` 同样会让 Android 重新格式化。
- **NBD**：网络块设备。首次安装时平板从 USB NCM 启动 Arch，根盘是主机导出的镜像；
  用来在不动 UFS 的情况下试跑，再 rsync 到 `sda15`。
- **超级精简冻结**：Debloat 模块的三级精简（包级/组件级/DNS 黑洞）。
- **L1–L4**：本文 §3 的四层模型。
