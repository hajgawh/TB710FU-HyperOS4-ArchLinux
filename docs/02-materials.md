# 02 — 材料、工具链与目录布局

> 本仓库不提供任何官方/第三方二进制。本文只给**获取渠道、精确版本、校验方法、解包方式**。
> 所有设备唯一值（序列号、MAC、IP、分区 UUID、作者路径）在示例里都是占位符：
> `<serial>`、`<device-ip>`、`<path>`、`<workspace>`、`<share-uuid>`、`<archlinux-partuuid>`。
> 示例 MAC 只用 `02:11:22:33:44:55`（本地管理地址，不是任何真实设备）。
>
> 当前发布基线：OS4 super 411d（`dd6cfbb8…`，10,392,436,736 B），Arch 内核
> `7.3.0-tb710fu #32`（v36-quiet2）。**本文列的是“从零重建”所需材料版本**；旧文档里的
> v31/v12 只是历史回滚点，不要当材料基线。

---

## 1. 你需要准备的材料

### 1.0 先分清四层

第一次做的人最容易把“Android 系统”“vendor”“内核”“Arch 用户态”混成一件事。按下面四层准备，
每一层缺什么、错了会怎样都很清楚：

| 层 | 材料 | 作用 | 缺了会怎样 |
|---|---|---|---|
| L0 设备与回退 | 你自己的 boot 链备份、GPT/唯一分区备份、firehose、ZUI 救援包 | 读/写 9008、AVB 校验、变砖兜底 | 不能安全写入；写坏后没有退路 |
| L1 OS4 框架 | yupei 4.0.11 全量 OTA、色彩补丁、NCM overlay、Aperture | 组成 `system/system_ext/product` | 没有 Android 框架，super 无法构建 |
| L2 vendor/ODM | 社区 OS3 移植包的 `vendor/odm/vendor_dlkm/system_dlkm`、lwky、PearlBiometric | 联想 TB710FU 的显示/触控/充电/音频/mslg 适配 | 用 yupei vendor 会丢硬件功能 |
| L3 Arch 内核/引导 | ArchLinuxARM rootfs、Linux 7.3 源码、kShimC、DBKP、freedom、tb710fu-linux | Arch 双系统与开机菜单 | 只能跑 OS4，不能双系统 |
| L4 Arch 用户态 | Mesa/freedreno、qcom-va-driver、固件 | 桌面、视频硬解、Wi-Fi/蓝牙/音频 | Arch 能启动，但桌面体验不完整 |

两个关键事实：

1. **OS4 super 里没有内核。** HyperOS 的内核是 `boot_a` 里的 GKI 6.1.128（Image-00），
   由 kShimC 菜单的“HyperOS”项启动。
2. **Arch 内核也在同一个 `boot_a` 里。** 它是 Image-01 `7.3.0-tb710fu`，由同一个 kShimC
   菜单的“Arch Linux”项启动。所以 GKI 6.1.128 和 Linux 7.3 不是二选一，而是同一镜像里的
   两个内核，不能互相替代。

**最小可开机集合**（只做 OS4）：M1 的四个分区 + M2 的 vendor/ODM/dlkm/lwky/PearlBiometric
+ M18 色彩补丁/overlay + M4 firehose + M5 你自己的 boot/vbmeta 备份 + M3 救援包。
M7–M15 是 Arch/桌面可选，M6 是 root 可选；**M13 相机 APK 对 411d 构建是必装**（缺了 `port_build.sh` 直接报错）。

### 1.1 材料总表

| ID | 材料 | 精确版本/代号 | 包含什么 | 官方/社区来源 | 如何校验 | 能否再分发 |
|---|---|---|---|---|---|---|
| M1 | Xiaomi Pad 8 `yupei` 全量 OTA | `OS4.0.11.0.XPZCNXM`；全量包示例名 `yupei-ota_full-OS4.0.11.0.XPZCNXM-user-17.0.zip`；构建后 incremental 为 `OS4.0.11.0.XPZCNXM.DEV` | `payload.bin`、`payload_properties.txt`、`META-INF/`；目标分区 `system/system_ext/product/mi_ext` | 小米官方 ROM 下载页/小米社区 ROM 区；社区镜像页 <https://xiaomirom.com/download/xiaomi-pad-8-pad-9-yupei-stable-OS4.0.11.0.XPZCNXM/#china-recovery>（设备内系统更新推送通常是增量，不要用） | `unzip -l`、`payload-dumper-go -l`、四个镜像 `fsck.erofs` | 否（小米版权） |
| M2 | 社区 HyperOS 3 移植包 | `HyperOS 3.0.305 TB710FU`，目录名 `HyperOS3.0-1.305_A16_TB710FU[c0f13e]`；vendor 底 `ZUXOS 1.5.04.428` | `super.img.zst`（或 `images/super.img`；解压后约 10.2 GB，以你下载的包为准）、`vendor/odm/vendor_dlkm/system_dlkm`、lwky、PearlBiometric、Joyose、firehose、启动链/TWRP（仅参考） | 酷安 @兰微卡鱼：作者页 <https://www.coolapk.com/u/22567520>，置顶下载帖 <https://www.coolapk.com/feed/70239826>，介绍帖 <https://www.coolapk.com/feed/72426511>（网页常只显示二维码，需酷安 App/账号） | `zstd -t`、`stat` 记录实际大小（不同版本会不同）、`lp_unpack.py`、`fsck.erofs`、`dump.erofs` 读 vendor `build.prop` | 否（第三方包，含联想/小米组件） |
| M3 | 联想 ZUI 救援包 | TB710FU / ZUXOS `1.5.04.428` 或更新；`1.5.04.495_WITHOUT_UBL` 是另一个更新包，本项目基线用 428 | 官方完整固件、boot/vendor/super 等；有时含 firehose | 联想官方支持 <https://newsupport.lenovo.com.cn/>（按机型 TB710FU 搜索）；或 Lenovo Rescue and Smart Assistant（LMSA） | 官方页面/校验和；`7z l`/`unzip -l`；检查型号与版本字符串 | 否（联想版权） |
| M4 | firehose programmer | `prog_firehose_ddr-TB710FU.melf` | Qualcomm DDR/UFS programmer，9008 读写用 | OS3 移植包 `bin/9008/`；或 ZUI 救援包 | `file`、`sha256sum`、`edl --loader=... --memory=ufs printgpt`（只读） | 否（Qualcomm/联想） |
| M5 | 你自己的 boot 链备份 | `boot_a`、`init_boot_a`、`dtbo_a`、`vendor_boot_a`、`vbmeta_a`；另加 GPT 与唯一分区 | 你设备的 GKI 6.1.128、ramdisk、DTBO、AVB 元数据 | 你自己的设备：EDL `r` 或已 root 的 `dd` | `shasum -a 256`、`avbtool info_image`、大小对比 `sgdisk --info` | 否（含设备唯一数据） |
| M6 | KernelSU-Next | `v3.4.2` LKM，KMI `android14-6.1`，包名 `com.rifsxd.ksunext` | APK + 与 GKI 6.1.128 匹配的 LKM | GitHub Releases：<https://github.com/KernelSU-Next/KernelSU-Next/releases> | `apksigner verify --print-certs`、`aapt2 dump badging`、`sha256sum`；刷后 `su -c id` | 是（GPL-3.0；建议链接官方 release） |
| M7 | ArchLinuxARM aarch64 rootfs | `ArchLinuxARM-aarch64-latest.tar.gz`（以页面当日为准） | aarch64 rootfs、pacman、systemd、基础工具 | <https://archlinuxarm.org/> / <https://os.archlinuxarm.org/os/>（含 `.md5`、`.sig`） | `md5sum -c`、`gpg --verify`、`tar -tzf`、`uname -m` | 是（按 ALARM 许可证；用官方 tarball） |
| M8 | Linux 7.3 源码 | `linux-7.3.tar.xz`（vanilla，`v7.x`） | 内核源码 | <https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.3.tar.xz> | `sha256sum` / `gpg --verify` | 是（GPL-2.0） |
| M9 | kShimC 源码/产物 | 上游 `sunflower2333/kShimC`；产物 `kShimC.bin` 约 4 MiB | 开机菜单、按键、屏幕、内核交接 | <https://github.com/sunflower2333/kShimC>；构建组合见上游 `tb710fu-hyperos-steamos/docs/dualboot-kshim.md` | `sha256sum`、`file`、`ls -l`（4,194,304 B 量级） | 见上游许可证 |
| M10 | DualBootKernelPatcher | `Project-Aloha/DualBootKernelPatcher`，上游记录 commit `2276163` | `MultiBootKernelPatcher`，把 GKI + Linux + DTB 打进一个 boot | <https://github.com/Project-Aloha/DualBootKernelPatcher> | `git rev-parse`、`file`、`--help`；`kshim_pack_boot.py` 能找到它 | 见上游许可证 |
| M11 | armadaos-freedom | 参考 commit `ba692d8c06fc1d5d7cafe91325448b19765a7b08`（本机核对；以你 clone 的 HEAD 为准） | SM8650/掌机内核补丁集（`packages/kernel/patches/series` 245 项）、kShimC 源码组合、boot 补丁 | <https://github.com/mydanyi/armadaos-freedom> | `git rev-parse HEAD`、`git status --porcelain`、`grep -c` series | 见上游（GPL-2.0） |
| M12 | tb710fu-linux | 仓库 HEAD（记录你下载的 commit） | TB710FU DTS/面板/触摸/音频/WiFi 补丁、固件说明；`0002-tb-base.patch` 的重要来源 | <https://github.com/MeteoricmeteorLL/tb710fu-linux> | `git log -1`、`ls firmware/ board/ release/`、固件 `sha256sum` | 见上游 |
| M13 | Aperture 相机 APK | LineageOS Aperture 1.0；OS3 包内是 `org.lineageos.aperture.dev` 1.0 (1)；本项目定稿横屏版 `8ff4d7e4…` | 相机 APK；定稿版含 `layout-land`、`fullSensor`、fling 换向 | LineageOS <https://github.com/LineageOS/android_packages_apps_Aperture>；OS3 包内 `/app/camera/camera.apk`（product 树 `app/camera/`） | `apksigner verify --verbose --print-certs`、`aapt2 dump badging`、`sha256sum`（OS3 原版大小/哈希以你下载的包为准） | 见上游 `LICENSES/`；第三方测试签名构建不要当官方产物 |
| M14 | Mesa/freedreno | ALARM `mesa 26.2.6-arch1.1`；Turnip 是独立包 `vulkan-freedreno` | freedreno OpenGL/EGL、Turnip Vulkan ICD | ArchLinuxARM 官方仓库 | `pacman -Q mesa vulkan-freedreno`、`eglinfo`、`vulkaninfo --summary` | 是（MIT 等） |
| M15 | qcom-va-driver | `strongtz/libva-v4l2`（无版本号；固定你验证过的 commit） | `qcom_drv_video.so`、`msm_drv_video.so`；仓库内 iris 内核补丁 | <https://github.com/strongtz/libva-v4l2> | `meson` 构建成功、`vainfo` 全档位、`ffmpeg` VA-API 实测 | 见上游许可证 |
| M16 | 主机工具链 | erofs-utils 1.9.4、apktool ≥2.9、payload-dumper-go 2.1.0、AOSP avbtool、bkerler/edl、util-linux | 解包、打包、校验、9008 | 见 §2 | 各自 `-V`/`--help`；见 §2.6 | 各自许可证 |
| M17 | 固件（可选） | 你设备 HyperOS 里的 adsp/cdsp/zap/novatek + linux-firmware + tb710fu-linux 固件 | GPU/WiFi/蓝牙/音频/触摸固件 | `tools/collect_firmware.sh`；<https://gitlab.com/kernel-firmware/linux-firmware>；tb710fu-linux `firmware/` | `sha256sum`、文件大小、`dmesg` 无 firmware load 失败 | 否（厂商 blob；linux-firmware 部分另有许可证） |
| M18 | 由 OTA 派生的补丁件 | `miui-services-tb710fu-411.jar`；`TB710FUTetheringOverlay.apk`、`TB710FUConnectivityOverlay.apk` | 色彩映射补丁；NCM 网络共享 RRO | 由 M1 的 `system_ext/framework/miui-services.jar` 和仓库 `assets/overlay-src/` 生成 | `sha256sum`、`jarsigner -verify`、`aapt2 dump badging` | 否（小米 jar）；overlay 自签仅自用 |

> `M13 Aperture` 必须与 411d 构建脚本对接；两个 APK 不随仓库分发，见 §4.11.1。
> MiuiCamera 只属于旧基线/回退路径，不要混装。

### 1.2 术语速查

| 术语 | 含义 | 本项目里的具体值 |
|---|---|---|
| GKI | Google 通用内核 | `6.1.128`，在 `boot_a` 的 Image-00 |
| KMI | 内核模块接口 | KernelSU-Next 必须选 `android14-6.1` |
| AVB | Android Verified Boot | 你设备的 `vbmeta_a` + kShimC 重签链 |
| EROFS | 只读文件系统 | OTA 的 `system/system_ext/product/mi_ext` 都是 EROFS |
| payload.bin | OTA 内的分区镜像容器 | 用 `payload-dumper-go` 拆 |
| super | 动态分区容器 | 本机物理 20.4 GB，内容约 9.68 GiB |
| lwky | 兰微卡鱼移植包里的联想硬件适配层 | `lwky_cover`、`lwky_smart_charge_hyper`、`init.lwky.rc` |
| kShimC | 开机菜单 shim | 把 GKI + Linux 7.3 + DTB 打进一个 `boot_a` |
| DBKP | DualBootKernelPatcher | 实际执行多内核打包的 `MultiBootKernelPatcher` |

### 1.3 版本配对表

这张表是本文最重要的一页。材料不是“版本越新越好”，而是**按层配对**：

| 层 | 材料 A | 必须与 B 配对 | 错配后果 | 怎么检查 |
|---|---|---|---|---|
| OS4 框架 | yupei OTA `OS4.0.11.0.XPZCNXM` | 色彩补丁 jar `miui-services-tb710fu-411.jar`；`product/etc/build.prop` 的 4.0.11 内容 | 用 4.0.5 的 jar 或别的 OTA 版本，色彩/资源/oat 对不上，可能开机异常或反色 | `dump.erofs` 读 `system_ext/build.prop` 的 `ro.build.version.incremental`；jar 的 sha256 记录在你的构建记录/manifest |
| vendor/ODM | OS3 移植包 `ZUXOS 1.5.04.428` 底 | `vendor_a`、`odm_a`、`vendor_dlkm_a`、`system_dlkm_a`、lwky、PearlBiometric、Joyose | 用 yupei vendor 会丢联想显示/触控/充电/音频/mslg；用 414/495 vendor 可能温度阈值、节点名、mslg 路径不同 | `dump.erofs --path=/build.prop vendor_a.img` 看 `ro.external.version.code=1.5.04.428` |
| Android 内核 | GKI `6.1.128`（`boot_a` Image-00） | KernelSU-Next KMI `android14-6.1`；`init_boot_a` 的 LKM | 换 GKI 或选错 KMI，KSU 模块不加载，`su` 不可用 | 从 `boot_a` 取 kernel 字符串；KSU 管理器显示 KMI；`su -c id` 返回 `u:r:ksu:s0` |
| Arch 内核 | vanilla Linux `7.3` | `patches/kernel/full/0001..0027`、`config-7.3.0-tb710fu`、`KERNELRELEASE=7.3.0-tb710fu` | 用 7.2.6 模块会 `vermagic` 不匹配；用发行版内核源码会让 `git am` 大面积失败 | `modinfo -F vermagic` 必须是 `7.3.0-tb710fu`；`git am` 顺序成功 |
| 引导 | 你自己的 `boot_a`/`vbmeta_a` | kShimC、DBKP、Image、DTB、`tools/avb` 测试密钥 | 用别人的 vbmeta/boot，AVB 链不匹配，可能直接进 fastboot/9008 | `kshim_variants.sh` 输出 `(avb ok)`；`avbtool verify_image --follow_chain_partitions` |
| Arch 用户态 | ALARM aarch64 rootfs | 7.3.0-tb710fu 的 `modules-*.tar`；`IgnorePkg = linux linux-aarch64 linux-firmware` | pacman 换掉内核后，模块与 boot 不匹配，Arch 起不来 | `uname -r`、`pacman -Q linux`、`/etc/pacman.conf` |
| VA-API | `qcom-va-driver` | 内核 iris 补丁（0018）+ `CONFIG_VIDEO_QCOM_IRIS=m` + `/var/lib/dri` | 只装 VA 驱动不打 iris 补丁，每帧报 `S_CTRL DISPLAY_DELAY ... Invalid argument` | `vainfo` 全绿但 `ffmpeg` 失败；`dmesg` 看 iris |
| 相机 | Aperture 1.0 / 定稿 `8ff4d7e4…` | `product` 里的 Aperture 路径；不要同时保留 MiuiCamera | 两套相机并存会抢 camera role；MiuiCamera 在联想 HAL 上前摄默认 -1 | `aapt2 dump badging`；`pm list packages` 里查 camera |
| 磁盘 | super 逻辑内容 | `used_end < 10 GiB` 保护线；`sda15` 起始扇区 | 超过保护线 `make_super.py` 直接拒绝；强行绕过可能踩到 Linux 根 | `python3 tools/check_super.py`；`sgdisk -p /dev/sda` |

### 1.4 拿不到某材料时：可替代与不可替代

| 缺什么 | 能否替代 | 可以怎么做 | 不能做什么 |
|---|---|---|---|
| M1 全量 OTA | 部分可替代 | 同版本 `4.0.11.0.XPZCNXM` 的官方 fastboot 线刷包（tgz 内 `images/*.img`）可以取四个分区；但脚本默认吃 `payload.bin`，需要自己转成 `system.img` 等 | 不能用别的版本（如 4.0.5、OS3）的 system；不能用单个 `recovery.img` 代替 OTA；不能用增量包 |
| M2 OS3 移植包 | 基本不可替代 | 理论上可从 ZUI 1.5.04.428 完整固件取 vendor/ODM，再另找 lwky/PearlBiometric；这超出本文范围，且要重新校准温度/节点/mslg | 不能换成 yupei 的 vendor/ODM；不能用 495 的 vendor 直接混 428 基线 |
| M3 ZUI 救援包 | 不可替代（回退路径） | 没有它也能开始，但第一次物理写入前必须接受“写坏只能找官方售后/EDL 救”的风险 | 不要在没有救援包的情况下做首次 super/boot 写入 |
| M4 firehose | 不可替代（EDL） | 如果 Arch 已装好，可用 `flash_super_arch.sh` 在线写 super；首次安装、备份、救砖仍要 EDL | 不能用通用 SM8650 programmer；不能靠 fastboot 替代本指南的 super 写入流程 |
| M5 自己的 boot 备份 | 部分可替代 | 同机型同版本官方 stock boot/vbmeta 可应急；但 AVB/回滚索引可能不同，优先自己的备份 | 不能用作者或别人的 boot/vbmeta；不能跳过备份直接写 |
| M6 KernelSU-Next | 可跳过 | 不 root 也能跑 OS4；依赖 root 的六个模块、`switch2arch`、部分验收不能做 | 不要用 Magisk 替代（本项目明确用 KSU-Next LKM）；不要选错 KMI |
| M7 ALARM rootfs | 可跳过 | 只做 OS4，不做 Arch 双系统 | 不能用 x86_64 rootfs；不能用其他发行版冒充 ALARM |
| M8 Linux 7.3 | 不可替代（要 Arch 内核时） | 必须从 kernel.org 取 vanilla 7.3 再打 27 个补丁；本仓库不提供预编译 Image/DTB | 不要用 7.2.6 模块；不要用已打过补丁的树；不要指望作者哈希 |
| M9 kShimC | 可跳过（不双系统） | 只做 OS4 时不需要；要双系统必须自己构建或使用你信任的旧产物 | 不要用来路不明的 prebuilt shim |
| M10 DBKP | 不可替代（打包 boot 时） | 用上游源码构建；`kshim_pack_boot.py` 依赖它 | 不要手工拼 boot 后跳过 AVB 校验 |
| M11/M12 补丁基线 | 不可替代（要 7.3 内核时） | 必须按 NOTICE 的来源取 freedom 与 tb710fu-linux；仓库已提供适配后的 27 个补丁 | 不要直接套他们的预编译 boot/kernel；不要跳过 7.3 适配 |
| M13 Aperture | 可替代 | 用你自己的 Aperture 构建（定稿版或 LineageOS 原版）；只有回退旧基线时才用 MiuiCamera | 不要从随机 APK 站下载；不要 Aperture 与 MiuiCamera 混装 |
| M14 Mesa/freedreno | 不可替代（Arch 桌面） | ALARM 官方 `mesa` 必须装；Turnip 可选 | 不要用 x86_64 的 Arch 包；不要指望 ALARM `mesa` 自带 Vulkan ICD |
| M15 qcom-va-driver | 可跳过 | 没有它 Firefox 走软解，系统仍可用 | 不要只装驱动不打 iris 补丁；不要 `rmmod qcom_iris` |
| M16 主机工具 | 不可替代（对应步骤） | 按 §2 安装；erofs-utils 必须 ≥1.9 | 不要用旧版 erofs-utils 做 4K EROFS；不要用来源不明的 avbtool |

### 1.5 哪些能复用、哪些绝不能替换

**可以复用（原样保留）：**

- OTA 的 `system`、`system_ext`、`product`、`mi_ext` 四个分区镜像；
- OS3 移植包的 `vendor_a.img`、`odm_a.img`、`vendor_dlkm_a.img`、`system_dlkm_a.img`；
- OS3 的 `system/lwky/lwky_cover`、`lwky_smart_charge_hyper`、`system/etc/init/init.lwky.rc`；
- OS3 的 `product/app/PearlBiometric/PearlBiometric.apk`；
- OS3 product `pangu/system` 下的 Joyose（`build_os4.py` 会搬进 system）；
- 你自己的 `boot_a`/`init_boot_a`/`dtbo_a`/`vendor_boot_a`/`vbmeta_a` 备份；
- 你自己的 firehose programmer；
- 你验证过的 kShimC.bin、Linux 7.3 的 Image/DTB/modules、ALARM rootfs。

**绝不能替换：**

- **OS3 vendor/ODM/dlkm 不能换成 yupei 的。** 联想硬件适配（显示、触控、充电、音频、mslg/PC 栈）
  都在这里；换了会“能开机但硬件残废”。
- **lwky 二进制不能换成 OS3 的 `wmhp`/`set_res`。** 本项目只保留 cover/smart_charge，
  `wmhp`/`set_res` 已删除（会 3198 卡死）。
- **PearlBiometric 不能换成 OS4 的 TEE 人脸。** TB710FU 没有 TEE face HAL，OS3 的软件 2D 版才可用。
- **你自己的 vbmeta/boot 不能换成作者的。** AVB 链、GKI、DTBO 都是设备/版本相关。
- **firehose 不能用通用 SM8650 的。** 必须 TB710FU/UFS 匹配。
- **GKI 6.1.128 不能用别的 KMI 替代。** KernelSU-Next LKM 必须 `android14-6.1`。
- **7.3 内核不能用 7.2.6 的模块替代。** `vermagic` 不同，加载失败。
- **ALARM 内核不能被 pacman 的 `linux-aarch64` 替换。** `IgnorePkg` 必须保留。
- **super 不能越过 10 GiB 保护线。** 脚本会直接退出；精简 product。
- **Aperture 与 MiuiCamera 不要混装。** 选一条路径。

---

## 2. 主机工具链

### 2.1 macOS（示例）

```bash
brew install erofs-utils openjdk apktool android-platform-tools python@3 \
             payload-dumper-go zstd dtc gptfdisk util-linux meson ninja ripgrep gnupg
# edl 放独立 venv，避免污染系统 Python
python3 -m venv tools/venv
tools/venv/bin/pip install --upgrade pip edl protobuf
```

说明：

- 下文命令里的 `sha256sum` 在 macOS 用 `shasum -a 256` 代替；`stat -c%s` 用 `stat -f%z` 代替。
- `payload-dumper-go` 2.1.0 在 Homebrew 有 formula；没有就下 GitHub Release 二进制。
- `gptfdisk` 提供 `sgdisk`；`util-linux` 提供 `partx`/`blkid`（Homebrew 可能是 keg-only，
  需要按提示加 PATH）。
- `avbtool` 不在 Homebrew 核心，也不能从发行版源装；从 **AOSP `external/avb`** 取
  `avbtool.py` 放进 `tools/avb/`，同时需要 `testkey_rsa4096.pem`、`testkey_rsa2048.pem`
  才能重签 v3 启动链。**本仓库不附带这两把 key**；取法、GitHub 镜像与 sha256 校验见
  [§2.1.1](#211-toolsavb-的取法与校验两平台通用不随仓库分发)。
- macOS 上 `edl` 若报 libusb 相关错误，`brew install libusb`。

#### 2.1.1 `tools/avb/` 的取法与校验（两平台通用，不随仓库分发）

`tools/avb/` 需要三个文件，全部来自公开源码，**不要用来源不明的副本**：

| 文件 | 来源 | 说明 |
|---|---|---|
| `avbtool.py` | AOSP `external/avb` 仓库根目录 | Apache-2.0；各 AOSP 分支版本略有差异，1.2+ 均可 |
| `testkey_rsa4096.pem` | 同仓库 `test/data/` | **AOSP 公开测试密钥**（不是任何设备的真实密钥） |
| `testkey_rsa2048.pem` | 同仓库 `test/data/` | 同上，用于旧式 2048 签名的镜像 |

**权威地址（AOSP 官方）：**

```text
https://android.googlesource.com/platform/external/avb     # 整树，分支 main / android-<版本>
```

**GitHub 镜像（2026-11-10 实测可访问）：**

```text
https://github.com/GrapheneOS/platform_external_avb        # 分支 17
https://github.com/LineageOS/android_external_avb          # 分支 lineage-24.0
```

直取三个文件（以 GrapheneOS 镜像为例；换镜像只改前缀和分支）：

```bash
mkdir -p tools/avb
BASE=https://raw.githubusercontent.com/GrapheneOS/platform_external_avb/17
curl -fsSL "$BASE/avbtool.py"                        -o tools/avb/avbtool.py
curl -fsSL "$BASE/test/data/testkey_rsa4096.pem"     -o tools/avb/testkey_rsa4096.pem
curl -fsSL "$BASE/test/data/testkey_rsa2048.pem"     -o tools/avb/testkey_rsa2048.pem

python3 tools/avb/avbtool.py version        # 期望打印 avbtool 1.x.y
```

**必须核对 testkey 的 sha256**。两把 key 是公开且固定的，两个互不相关的镜像上逐字节相同
（作者已比对）；对不上就说明拿错了文件：

```bash
shasum -a 256 tools/avb/testkey_rsa4096.pem tools/avb/testkey_rsa2048.pem
# 6a224754880a57ab9cbd308267cd157d94cf05a1c8cb851aec4090e045d24121  testkey_rsa4096.pem
# f1d5765a2bdfb92fb08aee021107c7ac1a7a3f590dafd853771c85375ef0fbd7  testkey_rsa2048.pem
```

> `avbtool.py` **不要**按哈希校验：不同 AOSP 分支的版本不同（GrapheneOS 17 与
> LineageOS 24.0 就差几百字节），用 `version` 能跑、能量出 `Algorithm: SHA256_RSA4096`
> 即可。真正决定 AVB 链能不能通的是**两把 testkey**。
>
> 为什么仓库不带：一是避免在公开仓库里出现密钥文件（也避免 GitHub secret scanning 每次
> 提交报警），二是保证你取到的是 AOSP 原始文件而不是别人的副本。缺这三个文件时，
> `make_v3_bootchain.py` 和 `kshim_variants.sh` 的 AVB 校验会直接失败，不会静默跳过。

### 2.2 Linux（Debian/Ubuntu 示例）

```bash
sudo apt install erofs-utils openjdk-17-jdk apktool android-sdk-build-tools \
                 android-tools-adb android-tools-fastboot python3 python3-pip \
                 python3-venv zstd device-tree-compiler gdisk util-linux \
                 meson ninja-build ripgrep gnupg
python3 -m venv tools/venv
tools/venv/bin/pip install --upgrade pip edl protobuf
```

说明：

- 发行版的 `apktool` 可能太旧；以 `apktool -version` ≥2.9 为准，不够就下官方 jar。
- `avbtool` 同样从 AOSP `external/avb` 取（GitHub 镜像与 sha256 见 §2.1.1），不要用来路不明的二进制。
- Linux 访问 9008 需要 udev 规则/root；按 `bkerler/edl` 的 README 配。
- `payload-dumper-go` 从 GitHub Releases 取，或 `go install github.com/ssut/payload-dumper-go@latest`。

### 2.3 必需工具与用途

| 工具 | 用途 | 最低版本/说明 | 校验命令 |
|---|---|---|---|
| `mkfs.erofs` / `fsck.erofs` / `dump.erofs` | 制作/校验/读取 EROFS | erofs-utils **1.9.4**（≥1.9） | `mkfs.erofs -V` |
| `apktool` + JDK | 反编译/回编 APK 与 jar | apktool ≥2.9；JDK 17+ | `apktool -version`、`java -version` |
| `avbtool` | 校验 vbmeta/boot、重签 v3 链 | AOSP `external/avb`（取法见 §2.1.1） | `python3 tools/avb/avbtool.py version` |
| `edl`（bkerler） | 9008/EDL 读写 | 最新；装在 `tools/venv` | `tools/venv/bin/edl --help` |
| `payload-dumper-go` | 提取 OTA `payload.bin` | 2.1.0（≥1.0 即可） | `payload-dumper-go -h` |
| `sgdisk` / `partx` / `blkid` | 共享分区、GPT、UUID | util-linux/gptfdisk | `sgdisk --version`、`blkid --version` |
| Python 3 | 构建脚本 | 3.9+ | `python3 --version` |
| `adb` / `fastboot` | 设备侧验收 | Android platform-tools 最新 | `adb version` |
| `zstd` | 解压 `super.img.zst` | 任意近期版本 | `zstd --version` |
| `dtc` | 手工编译 DTB | 任意近期版本 | `dtc --version` |
| Docker | 内核/kShimC 构建 | Docker Desktop 或 Engine | `docker version` |
| `meson` / `ninja` | 设备上构建 qcom-va-driver | 任意近期版本 | `meson --version`、`ninja --version` |
| `apksigner` / `aapt2` | APK 签名/信息 | Android SDK build-tools | `apksigner --version` |
| `gpg` | 校验内核/ALARM 签名 | GnuPG | `gpg --version` |
| `rg` | 隐私自检 | 可选 | `rg --version` |

可选：`unpack_bootimg`（AOSP）或 `magiskboot`，用来读 `boot_a` 里的 kernel 版本；
不装也能构建，只是核对 GKI 6.1.128 时麻烦一点。

工具来源：

- erofs-utils：<https://github.com/erofs/erofs-utils>（GPL-2.0）
- Apktool：<https://github.com/iBotPeaches/Apktool>（Apache-2.0）
- payload-dumper-go：<https://github.com/ssut/payload-dumper-go>（Apache-2.0）
- AOSP avb：<https://android.googlesource.com/platform/external/avb/>（Apache-2.0）
- bkerler/edl：<https://github.com/bkerler/edl>
- util-linux：<https://github.com/util-linux/util-linux>
- gptfdisk（`sgdisk`）：<https://www.rodsbooks.com/gdisk/>

### 2.4 `edl` 的隔离安装

```bash
python3 -m venv tools/venv
tools/venv/bin/pip install --upgrade pip edl protobuf
tools/venv/bin/edl --help
```

`.gitignore` 已排除 `tools/venv/`。构建/刷机脚本用 `EDL=tools/venv/bin/edl` 指定。

### 2.5 Docker / 内核构建环境

- 内核构建推荐容器，避免 macOS 工具链差异：
  ```bash
  docker run --rm \
    -v tb-kwork:/w \
    -v "$PWD":/src:ro \
    -v "$PWD/out":/out \
    kernel-build:latest bash /src/tools/arch-kernel/build-from-series.sh
  ```
- `kernel-build:latest` 需要 `build-essential`、`bison`、`flex`、`libssl-dev`、`libelf-dev`、
  `bc`、`python3`、`git`、`tar`、`xz-utils`。没有现成镜像就按上游 Dockerfile 自建。
- **内核树必须放 case-sensitive 文件系统。** macOS 默认 APFS 大小写不敏感，Linux 源码里
  有仅大小写不同的文件，会在 `git am`/编译时出问题。用 Docker volume（Linux ext4）或
  case-sensitive APFS 稀疏卷。
- Docker volume 约 25 GB；做完立即 `git bundle` + `git format-patch` 存档，别只留容器卷。

### 2.6 工具校验

```bash
mkfs.erofs -V
fsck.erofs -V
apktool -version
payload-dumper-go -h >/dev/null && echo "payload-dumper-go ok"
python3 tools/avb/avbtool.py version
tools/venv/bin/edl --help >/dev/null && echo "edl ok"
sgdisk --version
java -version
python3 --version
```

任何一项失败，先修工具再动材料；不要“先用旧版凑合”。

---

## 3. `work/` 布局

构建脚本默认使用 `work/`（可用 `TB_WORK` 覆盖）。完整说明见 `work/README.md`：

```text
work/
├── ota/                          # OTA zip / payload.bin / payload_properties.txt
├── ota_extract/                  # payload-dumper-go 输出：system.img 等
├── hyperos4_411/                 # yupei 4.0.11 解包树
│   ├── x_system/
│   ├── x_system_ext/
│   ├── x_product/
│   ├── x_mi_ext/
│   └── img/                      # 可选：原镜像；TB_KEEP_BASE=1 时保留
├── port/                         # OS3 移植包分区与树
│   ├── super.img                 # zstd 解压后的 super
│   ├── system_a.img / vendor_a.img / odm_a.img
│   ├── vendor_dlkm_a.img / system_dlkm_a.img
│   ├── x_system_a/system/lwky/
│   ├── x_system_a/system/etc/init/init.lwky.rc
│   └── x_product_a/app/PearlBiometric/
├── author/                       # 可选：OS3 作者原版启动链（首次安装/回退）
├── patches/miui-services-tb710fu-411.jar
├── overlay/TB710FU{Tethering,Connectivity}Overlay.apk
├── firehose/prog_firehose_ddr-TB710FU.melf
├── stock/                        # 你自己的 boot_a/vbmeta_a/init_boot_a 备份
├── backup/                       # GPT、唯一分区、刷机记录
├── kshim/kShimC.bin
├── kshim-build/                  # kShimC / DBKP 构建树
├── v3/                           # v3 启动链五件
├── build_os4/out/                # super + 三分区 + <super>.manifest.json + sha256
├── build_os4/rollback_prev/       # 上一版三分区（回退件）
├── boot/                         # kshim_variants 输出（两个默认变体）
├── kernel73/                     # Image/DTB/modules tar + linux-7.3.tar.xz
├── ksu-modules/                  # modules/build_modules.sh 输出
└── release/                      # boot/pair 归档（可选）
```

注意：

- **不要把 `work/` 提交到 git**；`.gitignore` 已排除。
- `work/hyperos4_411/img/` 是可选的；`build_os4.py` 第一次会用它们缓存 uid/gid/xattr，
  之后默认删除以省磁盘；要保留就设 `TB_KEEP_BASE=1`。
- 磁盘紧张时，`work/port/x_product_a` 只保留 `app/PearlBiometric` 即可；`x_system_a`
  至少保留 `system/lwky` 和 `system/etc/init/init.lwky.rc`。
- `work/stock/` 是**你自己的**备份，不是作者备份；`work/backup/` 放 GPT 和唯一分区。
- `work/author/` 只在你要用 OS3 作者原版启动链做首次安装/回退时需要。

---

## 4. 材料解包与逐项校验

### 4.1 M1：Xiaomi Pad 8 `yupei` 全量 OTA

#### 4.1.1 全量还是增量

| 特征 | 全量 OTA（你要的） | 增量 OTA（不要用） |
|---|---|---|
| 文件名/体积 | 常见 `yupei-ota_full-OS4.0.11.0.XPZCNXM-user-17.0.zip`，数 GB | 常带 `incremental`/`ota_incremental`，通常几百 MB 到 1 GB 多 |
| payload 内容 | 所有目标分区的完整镜像 | 只有相对底包的差分操作 |
| 提取结果 | `system/system_ext/product/mi_ext` 四个镜像齐全，`fsck.erofs` 通过 | 可能缺 `mi_ext`，或 `payload-dumper-go` 报错/输出不完整 |
| 用途 | 本项目唯一可用的构建输入 | 本项目不用；除非你有完整底包并用 `payload-dumper-go -old`，也不推荐 |

不要只靠文件名判断。**真正的判据是：`payload-dumper-go` 能完整提取四个分区，并且
`fsck.erofs` 全部通过。** 缺一个就换全量包。

#### 4.1.2 取 `payload.bin`

```bash
mkdir -p work/ota work/ota_extract
cd work/ota
unzip -l <path>/yupei-ota_full-OS4.0.11.0.XPZCNXM-user-17.0.zip | sed -n '1,40p'
unzip -l <path>/yupei-ota_full-OS4.0.11.0.XPZCNXM-user-17.0.zip \
  | grep -E 'payload\.bin|payload_properties\.txt|care_map|metadata'
unzip <path>/yupei-ota_full-OS4.0.11.0.XPZCNXM-user-17.0.zip payload.bin payload_properties.txt
```

检查：

- `payload.bin` 存在且体积与 `payload_properties.txt` 的 `FILE_SIZE` 接近；
- `payload_properties.txt` 里有 `FILE_HASH`、`FILE_SIZE`、`METADATA_HASH`、`METADATA_SIZE`；
- 记录整个 zip 的 sha256：`shasum -a 256 <zip>`（macOS）或 `sha256sum <zip>`（Linux）。

#### 4.1.3 提取四个分区

```bash
payload-dumper-go -l work/ota/payload.bin
payload-dumper-go -p system,system_ext,product,mi_ext \
                  -o work/ota_extract work/ota/payload.bin
ls -lh work/ota_extract
```

- `-l` 先看分区列表；如果只列出一部分，或提取时报 “unsupported op”，基本是增量包/损坏包。
- `-p` 只提取本项目要的四个分区，省磁盘；确认无误后再考虑全量提取。
- 输出文件名通常是 `system.img`、`system_ext.img`、`product.img`、`mi_ext.img`。

#### 4.1.4 EROFS 解包

```bash
for p in system system_ext product mi_ext; do
  mkdir -p "work/hyperos4_411/x_$p"
  fsck.erofs --extract="work/hyperos4_411/x_$p" "work/ota_extract/$p.img"
done
```

检查关键路径：

```bash
ls work/hyperos4_411/x_system/system/etc/build.prop
ls work/hyperos4_411/x_product/etc/build.prop
ls work/hyperos4_411/x_product/etc/device_features/yupei.xml
ls work/hyperos4_411/x_system_ext/framework/miui-services.jar
```

读镜像内单个文件用 `dump.erofs`：

```bash
dump.erofs --path=/system/etc/build.prop work/ota_extract/system.img
dump.erofs --path=/etc/device_features/yupei.xml work/ota_extract/product.img
```

注意：`system.img` 是 system-as-root，镜像里的 `/etc` 是指向 `/system/etc` 的符号链接；
`dump.erofs` 不跟随符号链接，查 `/etc/...` 会“读不到”。另外，`dump.erofs` 查询不存在的
路径**返回码仍可能是 0**，脚本要检查输出里的 `Path :`，不能只看 `$?`。

#### 4.1.5 可复用/绝不能替换与坑

- 可复用：四个分区原样作为 `system/system_ext/product/mi_ext` 的底；
- 绝不能替换：不要用 yupei 的 `vendor`/`ODM`（本项目用 OS3 的）；不要把 OS3 的 system
  framework 混进 OS4；不要把 4.0.5 的 `miui-services.jar` 混进 4.0.11；
- 坑：
  - 只下了增量包：`mi_ext` 缺失或提取失败；换全量；
  - 下载截断：`unzip -t` 报错；重新下载并比对哈希；
  - 页面上的 `recovery.img` 是单个分区镜像，不是 OTA；`Recovery ROM`（卡刷 zip）才是
    全量 OTA 的常见形态；
  - 4.0.11 的 `product` 约 6.76 GB，解包树很大；磁盘不够时先只保留构建需要的路径。

### 4.2 M2：社区 HyperOS 3 移植包（ZUXOS 1.5.04.428 底）

#### 4.2.1 包的身份

- 名称：兰微卡鱼 HyperOS 3.0.305 TB710FU 移植包；
- 目录名/标记：`HyperOS3.0-1.305_A16_TB710FU[c0f13e]`；
- 底层：联想 ZUXOS `1.5.04.428`（vendor/ODM 的来源）；框架来自 Redmi Pad 2 Pro
  （`flute`）HyperOS 3.0.305；
- vendor API level 34（Android 14 基线，作者记录）；OS4 是 Android 17，所以需要
  `hyperos/sepolicy_compat.cil` 补 Android 17 删除的 SELinux 类型；
- `super.img.zst` 解压后约 **10.2 GB**（不同移植包版本不同，记录实际大小）；
- vendor 约 1.48 GB、ODM 约 0.46 GB、两个 dlkm 各约 0.04 GB。

来源：酷安 @兰微卡鱼。作者页 <https://www.coolapk.com/u/22567520>，置顶下载帖
<https://www.coolapk.com/feed/70239826>，介绍帖 <https://www.coolapk.com/feed/72426511>。
酷安网页常只显示二维码，实际下载通常要用酷安 App/账号，文件可能在中国移动云盘。
**不要从二次转存网盘拿**；拿到后自己核对大小与哈希。

#### 4.2.2 解压并拆 super

```bash
mkdir -p work/port
cp <path>/super.img.zst work/port/
# 如果包里直接是 super.img，跳过下面两行，直接复制/解压到 work/port/super.img
zstd -t work/port/super.img.zst
zstd -d work/port/super.img.zst -o work/port/super.img

# macOS
stat -f%z work/port/super.img
# Linux
stat -c%s work/port/super.img
# 记录实际大小；不同移植包版本会不同

python3 tools/lp_unpack.py work/port/super.img work/port
ls -lh work/port/*.img
```

至少要有：

```text
system_a.img
vendor_a.img
odm_a.img
vendor_dlkm_a.img
system_dlkm_a.img

# v3 启动链的输入（放 work/author/）；包里没有就从现役 OS3 设备回读
boot.img
init_boot.img
dtbo.img
vendor_boot.img
```

#### 4.2.3 解出 lwky / PearlBiometric / Joyose

```bash
fsck.erofs --extract=work/port/x_system_a  work/port/system_a.img
fsck.erofs --extract=work/port/x_product_a work/port/product_a.img
```

确认：

```bash
ls work/port/x_system_a/system/lwky/lwky_cover
ls work/port/x_system_a/system/lwky/lwky_smart_charge_hyper
ls work/port/x_system_a/system/etc/init/init.lwky.rc
ls work/port/x_product_a/app/PearlBiometric/PearlBiometric.apk
ls work/port/x_product_a/pangu/system 2>/dev/null   # Joyose 等；build_os4.py 会搬进 system
```

磁盘紧张时：

- `x_product_a` 至少保留 `app/PearlBiometric`；如果构建脚本要搬 Joyose，再保留
  `pangu/system`；
- `x_system_a` 只保留 `system/lwky` 和 `system/etc/init/init.lwky.rc` 也能构建；
- 但保留完整树方便排查，第一次做建议留全。

#### 4.2.4 确认 vendor 版本

```bash
dump.erofs --path=/build.prop work/port/vendor_a.img \
  | grep -E 'ro\.external\.version\.code|ro\.vendor\.build\.version'
# 期望看到 ro.external.version.code=1.5.04.428
```

如果版本不是 428：

- 温度阈值、节点名、mslg 路径可能不同；
- 本指南的温控/模块配置需要重新校准；
- 不要直接把 414/495 的 vendor 混进 428 基线。

#### 4.2.5 可复用/绝不能替换与坑

- 可复用：`vendor_a`、`odm_a`、`vendor_dlkm_a`、`system_dlkm_a`；`x_system_a/system/lwky`；
  `init.lwky.rc`；`PearlBiometric.apk`；`pangu/system` 里的 Joyose；`bin/9008` 的 firehose；
- 绝不能替换：
  - vendor/ODM/dlkm 不能换 yupei 的；
  - lwky 不能换成 `wmhp`/`set_res`（已删）；
  - PearlBiometric 不能换 OS4 的 TEE 版；
  - 不要把 OS3 的 system framework/product 应用整套搬进 OS4（只取上面几项）；
- 坑：
  - 早期流传的包有截断的 `super.img`；用实际大小和 `zstd -t` 先验；
  - `1.5.04.495_WITHOUT_UBL` 是另一个更新包，本项目基线是 428；不要把 495 的 vendor
    直接混进 428 基线，只作救砖/对照；
  - 不要把 OS3 移植包整包刷到已跑 OS4 的设备上来“取 vendor”；只解包取文件；
  - `PearlBiometric` 路径大小写要准确；缺它会导致人脸解锁缺失，但不影响开机。

### 4.3 M3：联想 ZUI 救援包

来源：

- 联想官方支持 <https://newsupport.lenovo.com.cn/>，按机型 **TB710FU** 搜索；
- 或 Lenovo Rescue and Smart Assistant（LMSA）下载官方固件；
- 以官方页面为准，不提供网盘转载。

用途：

- 最后的救砖/回退；
- 有时可从中提取 `prog_firehose_ddr-TB710FU.melf`；
- **不要**把 ZUI 固件当作 OS4 构建输入（vendor/ODM 用 OS3 移植包的 428 底）。

与 v3 启动链的关系（纯原厂起步必读）：

- v3 链要求 `recovery_a`/`vbmeta_system_a`/`pvmfw_a` 是 **testkey 版**；
  只有 `495_WITHOUT_UBL` 这类社区补充包里的这三件满足；
- 只刷 `recovery`/`vbmeta_system`/`pvmfw` 三件，**不要刷它的 vendor**；
  判定方法与 sha256 比对见 [00 §3.2.1](00-install-paths.md)。

校验：

```bash
7z l <zui-rescue>.7z | head -40        # 或 unzip -l
# 找 build.prop / vendor/build.prop 里的 TB710FU 与 1.5.04.428
sha256sum <zui-rescue>.7z
```

坑：

- 第三方“免解锁/一键救砖”包不要用；
- 495 的救援包可以救砖，但不要把它的 vendor 混进 428 基线；
- 没有救援包也能开始，但第一次物理写入前要接受“写坏只能找售后/EDL”的风险。

### 4.4 M4：firehose programmer

文件：

```text
prog_firehose_ddr-TB710FU.melf
```

来源：

- OS3 移植包常见路径 `bin/9008/`；
- 或联想 ZUI 救援包；
- 必须与 TB710FU/UFS 匹配。

校验：

```bash
file work/firehose/prog_firehose_ddr-TB710FU.melf
shasum -a 256 work/firehose/prog_firehose_ddr-TB710FU.melf

# 只读测试：能出 GPT 就说明 programmer/连接基本正确
tools/venv/bin/edl --loader=work/firehose/prog_firehose_ddr-TB710FU.melf \
  --memory=ufs printgpt > work/backup/gpt.txt
```

期望：`printgpt` 能列出 6 个 LUN/已知分区名；如果报错，先查：

- 设备是否真的在 9008（`lsusb`/`ioreg` 出现 `05c6:9008`）；
- `--memory=ufs` 是否写错（不要用 `emmc`）；
- programmer 是否 TB710FU 的（不要用通用 SM8650 的）；
- USB 线/口是否可靠。

坑：

- 不要用来路不明的 programmer；
- 不要在不确认设备型号时执行写操作；先 `printgpt` 只读；
- programmer 不随仓库分发。

### 4.5 M5：你自己的 boot 链与唯一分区备份

至少备份：

```text
boot_a
init_boot_a
dtbo_a
vendor_boot_a
vbmeta_a
```

另外建议备份 GPT 与唯一分区：

```text
persist
modemst1 / modemst2
fsg / fsc
devinfo / frp
keystore
ssd / secdata / uefivarstore / cdt / ddr
```

命令（设备在 9008）：

```bash
EDL=tools/venv/bin/edl
LOADER=work/firehose/prog_firehose_ddr-TB710FU.melf

$EDL --loader="$LOADER" --memory=ufs printgpt > work/backup/gpt.txt
$EDL --loader="$LOADER" --memory=ufs r boot_a        work/stock/boot_a.img
$EDL --loader="$LOADER" --memory=ufs r init_boot_a   work/stock/init_boot_a.img
$EDL --loader="$LOADER" --memory=ufs r dtbo_a        work/stock/dtbo_a.img
$EDL --loader="$LOADER" --memory=ufs r vendor_boot_a work/stock/vendor_boot_a.img
$EDL --loader="$LOADER" --memory=ufs r vbmeta_a      work/stock/vbmeta_a.img
```

校验：

```bash
shasum -a 256 work/stock/*
ls -lh work/stock/*
python3 tools/avb/avbtool.py info_image --image work/stock/vbmeta_a.img
```

检查：

- 文件大小与 `sgdisk --info=<n> /dev/sda` 的分区大小一致（`boot_a` 约 96 MiB；
  `init_boot_a` 约 8 MiB）；
- `avbtool info_image` 能看到 algorithm、rollback index、flags；
- `boot_a` 里的内核字符串应为 GKI `6.1.128`。可选做法：
  ```bash
  # AOSP unpack_bootimg（boot v4）
  unpack_bootimg --boot_img work/stock/boot_a.img --out work/stock/unpacked
  strings work/stock/unpacked/kernel | grep -m1 'Linux version'
  # 或 magiskboot unpack work/stock/boot_a.img
  ```
- 备份文件不要放在会被构建脚本覆盖的目录。

> `tools/kshim_gki_check.py` 已随包提供：它打印 boot.img 里 GKI 的 sha256、大小和
> `Linux version ...`。它不做 6.1.128 断言，看到 `6.1.128-android14` 才是可用的 GKI。

为什么必须是你自己的：

- kShimC 用 **v3 Android-only boot**（本机型作者原件）取 GKI 和 footer 参数；当前的
  kShimC `boot_a` 已经是多内核载荷，不能当底座；
- v3 `vbmeta` 是你的 AVB 底座；别的机型/来源不明的 boot/vbmeta 会在启动时被拒绝；
- `dtbo_a` 影响面板/显示时序；`init_boot_a` 是 KSU 的落点。

坑：

- 不要用**别的机型/来源不明**的 boot/vbmeta；v3 链的本机型作者原件见 M2；
  打完 v3 后 kShimC 打包用 `work/v3/boot.img`，不要用当前 kShimC `boot_a`；
- 首次安装的分工：v3 链输入 = M2 的本机型作者原件（`work/author/`）；M5 备份 = 你设备
  当前链，只用于回退；
- 不要在 Android 运行时 `dd` 写 boot 分区；切换/刷入前确认目标；
- 只写 `boot_a`，不要写 `boot_b`；不要切槽。

### 4.6 M6：KernelSU-Next（LKM）

版本：

- KernelSU-Next **v3.4.2**；
- LKM，KMI **`android14-6.1`**；
- 包名 `com.rifsxd.ksunext`；
- 与 `boot_a` 里的 GKI **6.1.128** 配对。

来源：<https://github.com/KernelSU-Next/KernelSU-Next/releases>。选 KMI `android14-6.1`
的 APK；不要选 `android15-6.6`/`android14-6.6`。

校验：

```bash
apksigner verify --verbose --print-certs KernelSU-Next.apk
aapt2 dump badging KernelSU-Next.apk | grep -E 'package:|sdkVersion|targetSdkVersion'
sha256sum KernelSU-Next.apk
```

安装：

1. 安装 APK；
2. 打开 app → “安装” → **直接安装**（写 `init_boot_a`）；
3. 重启；
4. 设置里开 “ADB Root”。

验收：

```bash
adb -s <serial> shell su -c id
# 期望 uid=0(root) ... context=u:r:ksu:s0
```

坑：

- 只做文件修补/fastboot 修补有时不完整；回到 app 内“直接安装”；
- 不要用 Magisk 替代（本项目红线）；
- 换 GKI 后 LKM 必须重新匹配；不要混用别的 KMI。

### 4.7 M7：ArchLinuxARM aarch64 rootfs

文件：

```text
ArchLinuxARM-aarch64-latest.tar.gz
```

来源：

- <https://archlinuxarm.org/> → 下载页；
- 或直接 <https://os.archlinuxarm.org/os/>（同目录有 `.md5`、`.sig`）。

校验：

```bash
md5sum -c ArchLinuxARM-aarch64-latest.tar.gz.md5
# 先按 archlinuxarm.org 页面提示导入 ALARM 签名密钥，再验签
gpg --verify ArchLinuxARM-aarch64-latest.tar.gz.sig ArchLinuxARM-aarch64-latest.tar.gz
tar -tzf ArchLinuxARM-aarch64-latest.tar.gz | head
file ArchLinuxARM-aarch64-latest.tar.gz
```

安装要点：

```bash
tar --xattrs --numeric-owner -xpf ArchLinuxARM-aarch64-latest.tar.gz -C <mountpoint>
pacman-key --init
pacman-key --populate archlinuxarm
```

> 这里只讲 rootfs 本身。**分区从哪来、NBD 怎么试跑、怎么 rsync 到 `sda15`**，见
> [00-install-paths.md](00-install-paths.md) §3.3–§3.5。第一次安装不要跳过 NBD 试跑。

配对：

- 只支持 **aarch64**；不要用 x86_64 Arch；
- 装完后 `uname -m` 应为 `aarch64`；
- 在 `/etc/pacman.conf` 加：
  ```ini
  IgnorePkg = linux linux-aarch64 linux-firmware
  ```
  内核由 `boot_a` 的 7.3.0-tb710fu 提供，不能让 pacman 换掉；
- 7.3 模块用 `modules-7.3.0-tb710fu.tar` 安装，`depmod -a`。

坑：

- ALARM 的 `latest` tarball 可能只有很小的本地 pacman DB；构建时用 `pacman -Sy --needed`
  正常安装即可；
- 不要把 32G 的 MBR 磁盘镜像直接 `dd` 到 `/dev/sda15`（会在分区里再套分区表，
  内核找不到 `LABEL=archlinux-root`）；sda15 要直接 `mkfs.btrfs` 或把镜像写到整盘/U 盘；
- 首次启动后如果镜像小于分区，`btrfs filesystem resize max /`；
- 不要装 ALARM 的 `linux-aarch64` 包；不要让它覆盖 `/lib/modules/7.3.0-tb710fu`。

### 4.8 M8：kernel.org Linux 7.3 源码

文件：

```text
linux-7.3.tar.xz
```

来源：

```bash
curl -fLO https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.3.tar.xz
```

校验：

```bash
sha256sum linux-7.3.tar.xz
# 以 kernel.org 的 sha256sums / 签名页为准
curl -fLO https://cdn.kernel.org/pub/linux/kernel/v7.x/sha256sums.asc
# 先按 kernel.org/signature.html 导入签名密钥
gpg --verify sha256sums.asc
grep 'linux-7.3.tar.xz' sha256sums.asc
```

构建前：

```bash
# 在仓库根目录先改蓝牙地址（不带文件参数 = 默认改 0002 + 0020 + incremental/0001）
<workspace>/tools/arch-kernel/set-bt-addr.sh 02:11:22:33:44:55

tar xf linux-7.3.tar.xz
cd linux-7.3
git init -q
git add -A
git -c user.name=tb -c user.email=tb@local commit -qm "vanilla 7.3"
git am <workspace>/patches/kernel/full/*.patch
```

校验：

```bash
git log --oneline | head -30
make -s LOCALVERSION= KERNELRELEASE=7.3.0-tb710fu olddefconfig
make -j"$(nproc)" LOCALVERSION= KERNELRELEASE=7.3.0-tb710fu Image dtbs modules
# 构建产物里找到 msm.ko（或装到 /lib/modules 后直接 modinfo -F vermagic msm）
modinfo -F vermagic <path>/msm.ko
# 期望：7.3.0-tb710fu
```

坑：

- 不要用 7.2.6 的模块；`vermagic` 不同，加载失败；
- 不要用发行版内核源码或已经打过补丁的树；`git am` 会大面积失败；
- `0020` 的蓝牙地址必须与 `0002` 成对改，否则 `git am` context 对不上；
- 所有 `make` 都显式带 `KERNELRELEASE=7.3.0-tb710fu`，否则模块 `vermagic` 可能带 `+`；
- 构建树放 case-sensitive 卷；做完 `git bundle` + `format-patch` 存档。

### 4.9 M9/M10：kShimC 与 DualBootKernelPatcher

kShimC：

- 源码：<https://github.com/sunflower2333/kShimC>；
- 构建组合（上游记录）：freedom 的 `kshim-success-source`、CrDK `b6c3335`、picolibc
  `f7edb08`、lvgl `7f07a12`、kShimC `lib/libfdt`；
- 产物：`work/kshim-build/out/menu/kShimC.bin`，复制到 `work/kshim/kShimC.bin`；
- 体积约 4,194,304 B（4 MiB）。

DBKP：

- 源码：<https://github.com/Project-Aloha/DualBootKernelPatcher>；
- 上游记录 commit `2276163`；另需 freedom 的 `patches/boot` 0001/0002 + inih；
- 产物：`work/kshim-build/DBKP/build/MultiBootKernelPatcher`；
- `tools/kshim_pack_boot.py` 会自动找到它。

校验：

```bash
ls -l work/kshim/kShimC.bin
file work/kshim/kShimC.bin
shasum -a 256 work/kshim/kShimC.bin

ls -l work/kshim-build/DBKP/build/MultiBootKernelPatcher
file work/kshim-build/DBKP/build/MultiBootKernelPatcher
```

打包：

```bash
# 底座是 v3 Android-only 链，不是你当前的 kShimC boot_a
STOCK_BOOT=work/v3/boot.img \
VBMETA=work/v3/vbmeta.img \
SHIM=work/kshim/kShimC.bin \
OUT=work/boot \
tools/kshim_variants.sh local work/kernel73/out/Image work/kernel73/out/sm8650-lenovo-tb710fu-kshim.dtb
```

期望每个变体输出 `(avb ok)`；不通过脚本会拒绝。

坑：

- kShimC 源码组合需要精确 commit；不要拿随机 prebuilt；
- DBKP 打包器偶尔以 234 退出，`kshim_variants.sh` 已自动重试；
- `boot_a` 分区约 96 MiB；Image + DTB + shim 必须装得下；Linux 内核用精简配置；
- 只写 `boot_a`，不要写 `boot_b`；不要切槽。

### 4.10 M11/M12：armadaos-freedom 与 tb710fu-linux

armadaos-freedom：

- 固定 commit `ba692d8c06fc1d5d7cafe91325448b19765a7b08`；
- `packages/kernel/patches/series` 共 245 项；
- 在 7.3 上实测大部分能干净应用，失败的多为 7.3 已包含的改动（总说明记录 191/54；随 commit 与 tarball 会变）；
- 提供 SM8650/掌机补丁、kShimC 源码组合、`patches/boot`。

tb710fu-linux：

- 仓库 <https://github.com/MeteoricmeteorLL/tb710fu-linux>；
- 提供 TB710FU DTS/面板/触摸/音频/WiFi 补丁、固件说明；
- `0002-tb-base.patch` 的重要来源；
- 常见内容：`firmware/tb710fu-firmware-20261005.tar.gz`、`board/board-root.tgz`、
  `release/linboot-20261006.img`（以你下载时的仓库为准）。

校验：

```bash
git -C <workspace>/freedom rev-parse HEAD
# 期望 ba692d8c06fc1d5d7cafe91325448b19765a7b08
git -C <workspace>/freedom status --porcelain
grep -c '^' <workspace>/freedom/packages/kernel/patches/series

git -C <workspace>/tb710fu-linux log -1 --oneline
ls <workspace>/tb710fu-linux/firmware <workspace>/tb710fu-linux/board <workspace>/tb710fu-linux/release
sha256sum <workspace>/tb710fu-linux/firmware/tb710fu-firmware-*.tar.gz
```

坑：

- 不要直接套他们的预编译 boot/kernel；本项目是 7.3 适配后的 27 个补丁；
- 245 项里失败的多数是“7.3 已包含该改动”，不要强行 `patch`；
- 固件/board 产物版本会变；以你下载时的 commit 和 sha256 记录；
- `tb710fu-linux` 是参考来源，不是“刷机包”。

### 4.11 M13：Aperture 相机 APK

来源与版本：

- 上游：LineageOS `android_packages_apps_Aperture`，包名 `org.lineageos.aperture`，
  许可证见上游 `LICENSES/`；
- OS3 移植包内：`/app/camera/camera.apk`（product 树 `app/camera/`），包名
  `org.lineageos.aperture.dev`，版本 1.0 (1)，min26/target33，AOSP testkey，debuggable；
- OS3 原版：大小/哈希以你下载的包为准；
- 本项目定稿横屏版：`8ff4d7e4…`（含 `layout-land` + fling 换向），**不随仓库分发**。

> OS3 包内的 Aperture 是 `debuggable=true` + AOSP testkey 的调试构建；它能用，但会扩大
> 攻击面。生产环境建议从 LineageOS 源码构建并用你自己的 key 重签，或至少知道这个风险。

校验：

```bash
apksigner verify --verbose --print-certs Aperture.apk
aapt2 dump badging Aperture.apk | grep -E 'package:|sdkVersion|targetSdkVersion'
sha256sum Aperture.apk
```

使用：

- 如果你要 411d 的横屏 UI：自备定稿 APK（从作者成品或自己按 `docs/03` 的 APK 补丁流程重打）；
- 如果只要相机能用：用 OS3 包里的原版 Aperture，或从 LineageOS 源码构建；
- 安装测试：`adb install -r Aperture.apk`；不要同时装 `.dev` 和正式包。

#### 4.11.1 与本仓库构建脚本的对接（411d 路径）

本发布包的 `tools/build_os4.py` 是 **411d 版**：它会

1. 删除 `product/priv-app/MiuiCamera`（联想 HAL 没有 Xiaomi `campostproc`，JPEG 路径不可用）；
2. 把 `hyperos/camera/Aperture.apk` 装到 `product/app/Aperture`；
3. 把 `hyperos/camera/CameraParallelServiceStub.apk` 装成 `CameraParallelServiceStub`
   （提供相册/AGC 依赖的 `SpecialTypesProvider`）；
4. 写入 `hyperos/camera/default-permissions-aperture.xml`。

`tools/verify_package.sh` 对应检查：Aperture 存在且与 `hyperos/camera/Aperture.apk`
一致、`MiuiCamera` 不存在、default-permissions 已预授、stub 存在。

**两个 APK 是第三方二进制，不随仓库分发**；`tools/port_build.sh` 会在输入检查阶段
直接报错，直到你把它们放进 `hyperos/camera/`。详见
[`hyperos/camera/README.md`](../hyperos/camera/README.md)。

> **`CameraParallelServiceStub.apk` 现在可以自己构建**：最小源码在
> [`hyperos/camera/src/`](../hyperos/camera/src/README.md)（约 60 行 Java + `build.sh`），
> 只依赖 JDK 17 与 Android SDK build-tools，不需要 gradle/联网：
>
> ```bash
> KEYSTORE=~/aperture.keystore KS_ALIAS=aperture hyperos/camera/src/build.sh
> ```
>
> 它是按作者成品**行为**重写的参考实现（同 authority、空游标、`call()` 返回 null），
> 本机构建并验签通过（8,591 B），但**未在平板上复测**。要 100% 复现 411d 基线，
> 仍建议用作者成品里的那份。

`tools/patch_miuicamera_front.py` 只用于旧基线（4fbe52ee 时代）或回退包，不再参与
411d 构建。

### 4.12 M14/M15：Mesa/freedreno 与 qcom-va-driver

Mesa/freedreno：

- ALARM 官方 `mesa 26.2.6-arch1.1`（GL/EGL，freedreno）；
- Turnip 在 ALARM 是独立包 `vulkan-freedreno`；ALARM 的 `mesa` 包不含 Vulkan ICD；
- 验证：
  ```bash
  pacman -Q mesa vulkan-freedreno
  pacman -S --needed mesa-utils vulkan-tools libva-utils
  eglinfo -B | grep -E 'Mesa|freedreno'
  vulkaninfo --summary | grep -E 'GPU|driver'
  ```
- Blender 重负载 EEVEE 用 freedreno OpenGL 更快；Turnip 留给其他 Vulkan 应用。

qcom-va-driver：

- 仓库 <https://github.com/strongtz/libva-v4l2>（qcom-va-driver；VA-API over V4L2 stateful M2M，
  专为 Iris）；
- 设备上构建：
  ```bash
  pacman -S --needed meson ninja gcc pkgconf libva libdrm
  meson setup build --buildtype=release -Dcdsp_vpp=disabled -Dvulkan_vpp=disabled
  ninja -C build
  ```
- 产物：`qcom_drv_video.so`、`msm_drv_video.so`；
- 部署到 `/var/lib/dri`（flatpak 保留 `/usr`，所以不要只放 `/usr/lib/dri`）；
- 配对内核 iris 补丁（`patches/kernel/full/0018`）+ `CONFIG_VIDEO_QCOM_IRIS=m`；
- 验证：
  ```bash
  LIBVA_DRIVERS_PATH=/var/lib/dri vainfo
  LIBVA_DRIVERS_PATH=/var/lib/dri ffmpeg -hwaccel vaapi \
    -hwaccel_device /dev/dri/renderD128 -i <sample> -f null -
  ```
  期望 H264/HEVC/VP9/AV1 档位可见，解码帧数完整、无 `Invalid argument`。

坑：

- 只装 VA 驱动不打 iris 补丁：每帧 `S_CTRL DISPLAY_DELAY ... Invalid argument`；
- `qcom_iris` **绝不能** `rmmod` 热卸载：会卡 D 状态 `synchronize_irq`，kill 无效，
  可能关不了机；更新唯一姿势 = 装 modules tar + 重启；
- 不要把 x86_64 的 Arch 包/驱动混进 aarch64。

### 4.13 M17：固件（可选，但 Arch 桌面需要）

来源：

- 你设备 HyperOS 分区：`tools/collect_firmware.sh <out>`（需要 adb + root）；
  拉取 adsp/cdsp/zap/novatek 等；
- `linux-firmware`：<https://gitlab.com/kernel-firmware/linux-firmware>（GPU/WiFi/BT/音频）；
- tb710fu-linux 的 `firmware/`（TB710FU 专用固件说明与打包）。

校验：

```bash
find <out> -type f | sort | head -40
shasum -a 256 <out>/qcom/sm8650/xiaoxin/gt/*.mdt
dmesg | grep -i -E 'firmware|ath12k|adsp|cdsp'   # 刷后看有没有 load 失败
```

坑：

- 厂商 blob 不能随仓库分发；
- 固件版本要与你的 vendor/内核配对；不要混别的机型；
- `gen70900_zap.mbn`、`novatek_ts_fw.bin` 是设备相关，必须从你自己的 HyperOS 取。

### 4.14 M18：由 OTA 派生的色彩补丁与 overlay

色彩补丁 jar：

- 输入：M1 的 `system_ext/framework/miui-services.jar`（4.0.11）；
- 做法：按 `docs/03-os4-build.md` 反编译、改色彩映射、回编；
- 产物：`work/patches/miui-services-tb710fu-411.jar`；
- 校验：`sha256sum`；作者基线记录为 `0b41ff18…c1646a`（你的构建会不同）。`verify_package.sh`
  默认按作者基线比对；你自建 jar 时设 `TB_MIUI_SERVICES_SHA256=<你的 sha256>`，否则 61/61
  会在这个检查点 FAIL。
- 绝不能：用 OS3 的 `miui-services.jar` 混 4.0.11。

NCM overlay：

- 源码在 `assets/overlay-src/`；
- 构建：
  ```bash
  tools/build_overlays.sh
  ```
- 产物：`work/overlay/TB710FUTetheringOverlay.apk`、`TB710FUConnectivityOverlay.apk`；
- 自签即可；系统分区 APK 走 skipVerify；不要把测试密钥用于其他 APK。

---

## 5. 磁盘与时间预算

### 5.1 峰值磁盘

| 阶段 | 峰值新增磁盘 | 说明 |
|---|---|---|
| 下载全部材料 | ~20–25 GB | OTA + OS3 包 + ZUI 救援 + ALARM + 内核源码 + 工具 |
| OTA 解包 + 四分区 EROFS 树 | ~15–18 GB | 四个镜像 + 解包树；`product` 约 6.76 GB |
| OS3 拆包 + 提取树 | ~12–15 GB | `super.img` 10.2 GB + 分区镜像/解包树 |
| OS4 staging + tar + 三分区镜像 | ~20 GB | stage 约 8.6 GB + 单次 tar 约 6.8 GB + 旧/新镜像 |
| super 组装 | +10.5 GB | 411d 约 9.679 GiB |
| 内核构建 | ~25 GB | 源码树 + 对象文件 + 模块；Docker volume |
| ALARM rootfs + Plasma | ~10–15 GB | 解包 + 安装桌面/开发工具 |
| **构建 OS4 瞬时峰值** | **~30 GB** | 官方记录；不要在这个阶段同时解压别的包 |

建议：

- **整机至少预留 80–100 GB 空闲**（从零准备全部材料 + 保留回退件）；
- 构建前清理旧的 `out/super_*.img`；回退分区镜像放 `work/build_os4/rollback_prev/`；
- `cp -cR` 在大量小文件上不一定真的 APFS clone，按实际占用预留；
- 内核构建卷单独 25 GB，不要和 OS4 构建抢空间。

### 5.2 super 不能踩 sda15

`make_super.py` 有硬保护：

```python
LINUX_ROOT_OFFSET = 10 << 30   # 10 GiB
```

- `used_end` 超过 10 GiB 时脚本直接退出（没有绕过开关）；
- 本包 411d 的 super 文件是 **9.679 GiB**（10,392,436,736 B），低于保护线；
  `used_end` 以 `manifest.json` 为准，且必须 <10 GiB；
- **不要**绕过 10 GiB 保护；先精简 product；
- 保护线的历史来源是 super 尾部曾保留给 Linux 根；当前 `sda15` 布局以你机器的
  `sgdisk -p /dev/sda` 为准，示例起始扇区是 `27836416`，不要照抄。无论保护线来源如何，
  `make_super.py` 都会按 10 GiB 拒绝超限；按脚本执行即可。

检查：

```bash
df -h .
sgdisk -p /dev/sda | sed -n '1,20p'
python3 tools/check_super.py work/build_os4/out/super_fixed.img
```

刷入前确认：

- `super` 没有被 Android/dm-verity 占用；
- 目标分区是 `/dev/disk/by-partlabel/super`；
- 已备份当前 super 至少头部/manifest；
- 不在 Android 运行时写 super。

### 5.3 时间

| 阶段 | 时间（M2/SSD，参考） |
|---|---|
| 下载全部材料 | 30–120 min（看网络） |
| OTA 解包 + 四分区 EROFS | 5–10 min |
| OS3 拆包 + 提取 | 5–10 min |
| OS4 构建 + super 组装 | 15–30 min |
| 内核构建（容器，-j6） | 20–40 min |
| ALARM rootfs + Plasma | 20–40 min |
| 首次全流程（不含下载） | 2–4 h |

第一次做不要赶时间；每一步校验通过再下一步。

---

## 6. 校验材料完整性

### 6.1 一键自检

```bash
set -e

# M1 OTA
for p in system system_ext product mi_ext; do
  test -f "work/ota_extract/$p.img"
  fsck.erofs "work/ota_extract/$p.img"
done
test -f work/hyperos4_411/x_system/system/etc/build.prop
test -f work/hyperos4_411/x_product/etc/device_features/yupei.xml

# M2 OS3
for p in system_a vendor_a odm_a vendor_dlkm_a system_dlkm_a; do
  test -f "work/port/$p.img"
done
test -f work/port/x_system_a/system/lwky/lwky_cover
test -f work/port/x_system_a/system/lwky/lwky_smart_charge_hyper
test -f work/port/x_system_a/system/etc/init/init.lwky.rc
test -f work/port/x_product_a/app/PearlBiometric/PearlBiometric.apk

# M4/M5
test -f work/firehose/prog_firehose_ddr-TB710FU.melf
for p in boot_a init_boot_a dtbo_a vendor_boot_a vbmeta_a; do
  test -f "work/stock/$p.img"
done

# M8/M9
test -f work/kernel73/linux-7.3.tar.xz
test -f work/kshim/kShimC.bin

# M16 工具
mkfs.erofs -V >/dev/null
apktool -version >/dev/null
payload-dumper-go -h >/dev/null
python3 tools/avb/avbtool.py version >/dev/null
tools/venv/bin/edl --help >/dev/null

echo "materials: basic checks passed"
```

### 6.2 记录哈希

> macOS 没有 `sha256sum` 时用 `shasum -a 256`；Linux 两者都可用。下面统一写 `shasum`。

```bash
# OTA / OS3 / ZUI
shasum -a 256 work/ota/payload.bin
shasum -a 256 work/port/super.img
shasum -a 256 work/stock/*.img

# 构建产物
shasum -a 256 work/build_os4/out/super_fixed.img
shasum -a 256 work/build_os4/out/{system,system_ext,product}.img
shasum -a 256 work/kernel73/out/Image work/kernel73/out/*.dtb
```

所有哈希写进你自己的构建记录（如 `work/BUILD-NOTES.txt`），刷机前再对一次。哈希只用于**你自己**的构建对照；
作者的哈希（`dd6cfbb8…`、`37f997fb…`、`349dcec2…`、`119374f1…`）只作基线说明，
不要要求你的构建逐字节一致。

### 6.3 关键期望值

| 项 | 期望 |
|---|---|
| OS3 `super.img` 解压大小 | 约 10.2 GB（以你下载的包为准） |
| 411d super | 10,392,436,736 B（9.679 GiB）；`used_end` 以 `manifest.json` 为准，且必须 <10 GiB |
| OS4 四分区 | `fsck.erofs` 全部通过；`system/system_ext/product/mi_ext` 齐全 |
| OS3 vendor | `ro.external.version.code=1.5.04.428` |
| GKI | `boot_a` Image-00 = 6.1.128 |
| Arch 内核 | `uname -r` = `7.3.0-tb710fu`；模块 `vermagic` 同值 |
| ALARM | `uname -m` = `aarch64`；`pacman-key --populate archlinuxarm` 成功 |
| KSU | `su -c id` = `uid=0 ... u:r:ksu:s0` |
| AVB | `kshim_variants.sh` 输出 `(avb ok)` |

---

## 7. 常见材料问题

| 现象 | 原因 | 处理 |
|---|---|---|
| `payload-dumper-go` 缺 `mi_ext` | 下了增量包 | 换全量 OTA；确认文件名/体积 |
| `unzip -l` 没有 `payload.bin` | 下的是 fastboot 线刷包或错误页面 | 换 Recovery ROM 全量 zip；线刷包只能手工取 `images/*.img` |
| `fsck.erofs` 报版本不支持 | erofs-utils 太旧 | 升级到 ≥1.9（推荐 1.9.4） |
| `dump.erofs` 查 `/etc` 为空 | `/etc` 是符号链接 | 查 `/system/etc`；并检查输出里的 `Path :` |
| OS3 `zstd -t` 失败/大小不对 | 包截断或不是 `[c0f13e]` 完整包 | 重新下载，记录并比对实际大小 |
| OS3 vendor 不是 428 | 拿了 414/495 的 vendor | 换 428 底；重新校准温度/节点 |
| OS3 包缺 `lwky` | 不是完整移植包 | 找原作者的完整包；不要用残缺 super |
| `PearlBiometric` 缺失 | 路径大小写/版本不对 | 从 OS3 `product` 解包；确认 `app/PearlBiometric/PearlBiometric.apk` |
| firehose `printgpt` 失败 | programmer 不对/没进 9008/`--memory` 错 | 用 TB710FU programmer + `--memory=ufs`；先只读 |
| `avbtool` 校验失败 | 用了别人的 vbmeta/boot | 用你自己的 `work/stock/*` 备份 |
| KSU LKM 不加载 | KMI 不是 `android14-6.1` 或 GKI 不是 6.1.128 | 换匹配的 release；重新装 `init_boot_a` |
| 内核 `git am` 在 0001 失败 | tarball 不是干净 7.3 | 用 kernel.org vanilla 7.3，`git init` 后先提交 |
| `git am` 在 0020 失败 | 蓝牙地址两处不一致 | `tools/arch-kernel/set-bt-addr.sh` 成对改 0002/0020 |
| 模块 `vermagic` 带 `+` | 没显式 `KERNELRELEASE` | 所有 `make` 加 `KERNELRELEASE=7.3.0-tb710fu` |
| Arch 起不来/模块不匹配 | pacman 换了内核 | `IgnorePkg = linux linux-aarch64 linux-firmware`；重装 modules tar |
| `vainfo` 绿但解码失败 | 只装 VA 驱动，没打 iris 补丁 | 应用 0018 + 重装 modules tar + 重启 |
| `rmmod qcom_iris` 卡死 | iris 驱动 D 状态 | 不要 rmmod；装 modules tar + 重启 |
| super 超过 10 GiB | product 太大 | 精简 product；脚本会直接退出 |
| Aperture 缺失/相机打不开 | `hyperos/camera/` 缺 Aperture.apk/stub，或用了旧 MiuiCamera 构建脚本 | 按 §4.11.1 放好两个 APK；确认 `build_os4.py` 是 411d 版；再检查 `product/app/Aperture` |
| `mkfs.erofs` 不认选项 | erofs-utils 太旧 | 升级 ≥1.9 |

---

## 8. 隐私与占位符规则

### 8.1 规则

1. 不写真实序列号、IMEI/MEID、MAC、Wi-Fi SSID、内网 IP、分区 UUID、账号、密钥；
2. 不写作者/他人的主机路径；统一用 `<workspace>`、`<path>`；
3. 示例 MAC 只用 `02:11:22:33:44:55`（本地管理地址），不要用你设备的真实地址；
4. 不要整段粘贴 `adb devices -l`、`getprop`、`ip addr`、`dmesg`、`logcat`、GPT/EDL 日志；
   这些输出常含序列号/MAC/IP；
5. 不要把 `work/`、`persist`/`modemst*` 备份、`boot_a`/`vbmeta_a` 提交到公开仓库；
6. 发布前跑 §8.3 的 grep；发现真实值就替换成占位符。

### 8.2 占位符表

| 占位符 | 含义 | 从哪里读 |
|---|---|---|
| `<serial>` | `adb devices` 第一列 | `adb devices` |
| `<device-ip>` | 无线 adb/SSH 目标地址 | 你的局域网；不要写死 |
| `<workspace>` | 仓库根目录 | 你的本地路径 |
| `<path>` | 任意本地文件/目录 | 你的本地路径 |
| `<share-uuid>` | sda16 的 UUID | `blkid /dev/sda16` |
| `<archlinux-partuuid>` | sda15 的 PARTUUID | `sgdisk --info=15 /dev/sda` |
| `02:11:22:33:44:55` | 示例蓝牙地址 | 仅占位，不是真实设备 |

### 8.3 发布前 grep

```bash
# 1) 真实 MAC（排除示例占位符）
rg -n --no-heading -e '\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b' . \
  | grep -viE '02:11:22:33:44|00:03:7F:00:00:00|02:00:00|00:00:00:00:00:00' || echo "OK: no real MAC"

# 2) 内网 IP
rg -n --no-heading -e '\b192\.168\.|\b10\.[0-9]+\.|\b172\.(1[6-9]|2[0-9]|3[01])\.' . \
  | grep -viE '<device-ip>|172\.16\.42\.' || echo "OK: no LAN IP"

# 2b) DTS 小端蓝牙地址数组（白名单占位符/全零）
rg -n --no-heading -e 'local-bd-address[[:space:]]*=[[:space:]]*\[' . \
  | grep -v '55 44 33 22 11 02' | grep -v '00 00 00 00 00 00' \
  || echo "OK: no real bd-address array"

# 3) 作者/主机路径
rg -n --no-heading -e '/Users/|/home/[a-z]+/Desktop' . || echo "OK: no host path"

# 4) 设备序列号样式（按你的机型调整）
rg -n --no-heading -e '\b[A-Z]{2}[0-9]{2}[A-Z]{4}\b' . | grep -v '<serial>' || echo "OK: no serial"

# 5) 密码/密钥
rg -n --no-heading -i -e 'password\s*[:=]\s*[^ <]|BEGIN [A-Z ]*PRIVATE KEY|api[_-]?key' . \
  | grep -viE 'passwordSet|password-store|<path>|示例' || echo "OK: no secret"
```

> `172.16.42.x` 是 initramfs 的 NBD/USB-NCM 固定网段，不是个人网络，所以 grep 里排除；
> 但本文示例仍用 `<device-ip>`，不写具体地址。

---

## 9. 下一步

材料齐了以后：

1. 构建 OS4：看 [03-os4-build.md](03-os4-build.md)；
2. 刷入/备份/KSU：看 [04-os4-install.md](04-os4-install.md)；
3. Arch 内核：看 [05-arch-kernel.md](05-arch-kernel.md)；
4. Arch 用户态：看 [06-arch-userspace.md](06-arch-userspace.md)；
5. 双系统/共享分区：看 [08-dualboot-share.md](08-dualboot-share.md)。

> 最后再强调一次：**只写 `boot_a`，不写 `boot_b`；只写 `super`，不 `--wipe`；
> 唯一分区永远不要写、不要擦。**
