# work/ —— 你的输入与产物（不入库）

本目录只放占位说明；**不要把官方/第三方二进制或个人数据提交到 GitHub**。
构建脚本默认使用以下布局（可用 `TB_WORK` 覆盖）：

```text
work/
├── hyperos4_411/                    # Xiaomi Pad 8 yupei 4.0.11 解包树
│   ├── x_system/
│   ├── x_system_ext/
│   ├── x_product/
│   ├── x_mi_ext/
│   └── img/                         # 可选：原镜像；首次构建缓存元数据后会删除
├── port/                            # 社区 OS3 移植包
│   ├── system_a.img / vendor_a.img / odm_a.img
│   ├── vendor_dlkm_a.img / system_dlkm_a.img
│   ├── x_system_a/system/lwky/
│   ├── x_system_a/system/etc/init/init.lwky.rc
│   └── x_product_a/app/PearlBiometric/PearlBiometric.apk
├── patches/
│   └── miui-services-tb710fu-411.jar   # 你自己从 4.0.11 打的色彩补丁
├── overlay/
│   ├── TB710FUTetheringOverlay.apk
│   └── TB710FUConnectivityOverlay.apk
├── firehose/
│   └── prog_firehose_ddr-TB710FU.melf  # 你自己的 programmer
├── author/                          # OS3 作者原版 boot/init_boot/dtbo/vendor_boot（v3 链输入）
├── stock/                           # 你自己的 boot_a/vbmeta_a/init_boot_a 备份（回退用）
├── v3/                              # make_v3_bootchain.py 输出（五件）
├── kshim/                           # 你构建的 kShimC.bin
├── kshim-build/                      # kShimC / DualBootKernelPatcher 构建树
├── build_os4/
│   ├── out/                         # super + 三分区 + <super>.manifest.json + sha256
│   └── rollback_prev/               # port_build.sh 自动保存的上一版三分区（回退件）
├── boot/                            # kshim_variants 输出（两个默认变体）
├── kernel73/out/                    # 内核构建输出（Image/DTB/modules tar）
├── arch/                            # NBD 镜像 + nbd.conf（首次安装）
├── firmware/                        # 从本机收集的固件（可选；首次安装用 tb710fu-firmware 包）
├── ksu-modules/                     # modules/build_modules.sh 输出
└── backup/                          # GPT、唯一分区、刷机记录
```

## 材料来源

- Xiaomi Pad 8 `yupei` 4.0.11 全量 OTA：官方渠道；
- 社区 OS3 移植包：从原作者/社区获取，本仓库不提供；
- firehose、ZUI 救援包：联想官方/你自己的移植包；
- KernelSU-Next、ArchLinuxARM、内核/固件：见 `docs/02-materials.md`。

## 备份建议

- 第一次操作前用 9008 备份 GPT 与所有唯一分区（`persist`、`modemst1/2`、`fsg`、`fsc`、
  `devinfo`、`frp`、`keystore`、`ssd`、`secdata`、`uefivarstore`、`cdt`、`ddr`）；
- 每次重建 super 前，把上一版三分区移到 `work/build_os4/rollback_*/`；
- 每次刷 `boot_a` 前，把当前 boot 备份到 `/var/backups/tb710fu/` 或 `work/stock/`；
- 不要把 `work/` 提交到公开仓库。

## 体检

```bash
du -sh work/*
df -h .
# super 的 used_end 必须 < 10 GiB（历史保护线；当前 sda15 在 userdata 尾部，与此无关）
python3 tools/check_super.py work/build_os4/out/super_fixed.img
```
