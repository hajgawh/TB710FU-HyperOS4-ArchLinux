# NOTICE / 致谢与许可证

## 本仓库的来源

本仓库的构建/刷机脚本（`tools/build_os4.py`、`make_super.py`、`flash_super.sh`、
`kshim_pack_boot.py`、`kshim_variants.sh`、`lp_unpack.py`、`erofs_meta.py`、
`patch_apk_res.py` 等）来自
[lich-wang/tb710fu-hyperos-steamos](https://github.com/lich-wang/tb710fu-hyperos-steamos)，
上游以 **GPL-2.0** 发布。本仓库在其基础上做了：

- 已解锁 BL / 数据保留的 OS4.0.11 移植流程；
- 包内字体/40px R 角/marketname/mslg 版本门/Aperture/相册 stub/NTP 等修复；
- `tools/port_build.sh`、`verify_package.sh`、`verify_device.sh`、`check_super.py`、
  `post_flash_modules.sh` 等验收脚本；
- 六个运行时模块：`TB710FUThermal`、`TB710FUCPUMax`、`TB710FUSetRes`、
  `TB710FUDebloat`、`TB710FUDPWidebusOff`、`TB710FUShareMount`；
- Arch Linux 7.3 内核补丁序列（`patches/kernel/full/0001..0027`）与用户态修复；
- 双系统切换器的 `pair.env` 参数化改造（不再硬编码作者的 boot 哈希）。

因此本仓库的**文档与脚本**按 **GPL-2.0** 发布。上游与第三方项目各自保留其版权与许可证。
`modules/TB710FUThermal/profiles/` 是设备配置参考（见下文），不属于上游 GPL 代码。

`patches/arch/` 中的源码补丁：

| 补丁 | 上游 | 许可证 |
|---|---|---|
| `panel-backlight-fix.patch` | Linux 内核 `panel-nt36532-wqhd-dual-dsi-dsc.c` | GPL-2.0 |
| `blender-wayland-touch-fix.patch` | Blender `GHOST_SystemWayland.cc` | GPL-2.0-or-later |
| `ksystemstats/mr149.patch` | KDE ksystemstats MR !149 | LGPL-2.0-or-later |
| `ksystemstats/local-fallback.patch` | KDE ksystemstats（本项目改动） | LGPL-2.0-or-later |
| `ksystemstats/PKGBUILD` | Arch Linux ARM / KDE 打包 | 见上游 |

`patches/kernel/full/` 的补丁来自 Linux 7.3 + freedom 补丁集 + 本项目改动，均为 GPL-2.0。
其中 `0001-freedom-series-on-7.3.patch` 与 `0002-tb-base.patch` 来自
[mydanyi/armadaos-freedom](https://github.com/mydanyi/armadaos-freedom) 与
[MeteoricmeteorLL/tb710fu-linux](https://github.com/MeteoricmeteorLL/tb710fu-linux) 的
公开工作，本仓库只做 7.3 适配与 TB710FU 增量。

## 第三方项目

| 项目 | 用途 | 备注 |
|---|---|---|
| [kShimC](https://github.com/sunflower2333/kShimC) | 开机菜单 shim | 见上游 |
| [DualBootKernelPatcher](https://github.com/Project-Aloha/DualBootKernelPatcher) | 多内核打包 | 见上游 |
| [armadaos-freedom](https://github.com/mydanyi/armadaos-freedom) | SM8650 内核补丁基线 | 见上游 |
| [tb710fu-linux](https://github.com/MeteoricmeteorLL/tb710fu-linux) | TB710FU DTS/驱动/固件说明 | 见上游 |
| [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) | root（LKM） | GPL-3.0 |
| [bkerler/edl](https://github.com/bkerler/edl) | 9008 读写 | 见上游 |
| [erofs-utils](https://github.com/erofs/erofs-utils) | EROFS 制作/校验 | GPL-2.0 |
| [Apktool](https://github.com/iBotPeaches/Apktool) | APK 反编译/回编 | Apache-2.0 |
| [payload-dumper-go](https://github.com/ssut/payload-dumper-go) | OTA payload 提取 | Apache-2.0 |
| [AOSP avb](https://android.googlesource.com/platform/external/avb/) | avbtool / testkey | Apache-2.0 |
| [ArchLinuxARM](https://archlinuxarm.org/) | Arch aarch64 rootfs | 见上游 |
| [Mesa](https://gitlab.freedesktop.org/mesa/mesa) | freedreno / batch cache 研究 | MIT |
| 酷安 @兰微卡鱼 | HyperOS 3 移植包（vendor/ODM/lwky 基础） | 第三方，非本仓库 |

## 未包含的二进制

本仓库 **不包含** 任何联想、小米、高通、Valve 或第三方的二进制/固件/镜像，包括但不限于：

- Xiaomi Pad 8 `yupei` OTA、`system`/`system_ext`/`product`/`mi_ext` 镜像；
- 社区 HyperOS 3 移植包、`super.img`、`vendor`/`ODM`/`dlkm` 镜像、`lwky` 二进制；
- 修改后的 `miui-services.jar`、`PearlBiometric.apk`、`VoiceAssistAndroidT.apk`、
  `DevicesOverlay.apk`、Aperture/WPS/CAD APK；
- 联想 ZUI 固件、firehose programmer、`boot`/`init_boot`/`dtbo`/`vendor_boot`/`vbmeta`；
- 设备备份、唯一分区、序列号、密钥、账号。

这些文件请从官方渠道或原项目获取，并遵守各自的许可证/服务条款。参考下载链接见
[docs/02-materials.md](docs/02-materials.md)。

## 温控配置说明

`modules/TB710FUThermal/profiles/` 中的 GPU/CPU 温控文本配置来自测试机
（ZUXOS 1.5.04.428 / TB710FU）的 vendor 配置及其修改版，仅作为**同型号设备的参考**。
它们不是上游 GPL 代码；如果你机器的 vendor 版本不同，请以
`/vendor/etc/thermal-engine_*.conf` 为准，按 `modules/TB710FUThermal/README.md` 与 `service.sh` 的说明重新生成或自行调整。
发布/再分发前请确认你所在司法辖区的规定。

## 隐私

本仓库的文档与脚本不包含任何个人信息、真实设备序列号、IMEI/MEID、MAC、Wi-Fi SSID、
IP、账号、密钥、ADB 授权文件、设备备份或个人路径。所有设备唯一值都换成了占位符，
详见 [PRIVACY.md](PRIVACY.md)。
