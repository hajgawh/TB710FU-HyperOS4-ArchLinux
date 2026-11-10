# 05 — Arch 内核 7.3.0-tb710fu：补丁序列、构建与 DTB

> 基线：`7.3.0-tb710fu #32`（v36-quiet2）。
> Image `37f997fb…` / DTB `349dcec2…` / modules `119374f1…`（作者构建，仅作对照）。
> 你的构建哈希会不同；以 `BUILD-INFO.txt` 为准。

---

## 1. 源码构成

```text
vanilla Linux 7.3 (kernel.org)
 └─ 0001 freedom series on 7.3        SM8650/掌机补丁集（195 项干净应用 + 7.3 适配；总说明里的 191/54 是另一基线的统计，不要混用）
    └─ 0002 tb-base                    TB710FU 基础 DTS/驱动/面板/触摸/UFS
       └─ 0003..0019                   TB710FU 逐项修复（显示/触摸/USB/DP/音频/RTC/iris）
          └─ 0020..0027               BT 地址、QMP/DP_ONLY、GEM shrinker、WCD F1、
                                      dwc3 quirk、USB1 s2idle、initramfs、v32–v36 Type-C
```

补丁全部在 `patches/kernel/full/`，是 `git format-patch` 格式，按编号顺序 `git am`。
`patches/kernel/incremental/` 是 `v25-prod → v36` 的 8 个增量，给已经在 v25 的树用。

### 1.1 补丁清单

| # | 补丁 | 作用 |
|---|---|---|
| 0001 | freedom series on 7.3 | SM8650 掌机补丁集 + 7.3 编译适配 |
| 0002 | tb-base | TB710FU 基础 DTS/驱动/面板/触摸/UFS/蓝牙地址占位 |
| 0003 | compile fixes sy7758 / panel orientation | 7.3 编译错误修复 |
| 0004 | main sy7758 enable GPIO pinctrl match v4 | 背光使能 GPIO |
| 0005 | clk_core.orphan_reparent_failed | clk 警告/回归 |
| 0006 | dsi byte/pixel parent fields | DSI 时钟父级 |
| 0007 | disconnect STA before resume | WiFi 休眠重连 |
| 0008 | NT36532 panel regulator enable sync | 面板上电时序 |
| 0009 | gate touch FW health work on panel power | 触摸固件健康检查门控 |
| 0010 | 6-core 1+2+2+1 topology | 6 核拓扑 + PSCI 过滤 + cpu-map |
| 0011 | wire NT36532 backlight directly drm_panel | DPMS 背光（面板模块） |
| 0012 | enable USB-C DisplayPort output | DP alt mode |
| 0013 | allow HBR3 DP link rates | HBR3 速率表 |
| 0014 | DTS RTC SDAM / WCD capture / DP DAI / micbias | RTC、麦克风、DP 音频 |
| 0015 | DP rate re-read / CVT-RB / 8bpc / suspend teardown | DP 稳定性 |
| 0016 | combo PHY SW_PWRDN / WCD939x AUX+DPDM keep alive | 插拔不复位 |
| 0017 | touch FW health panel regulator NULL safety | 触摸空指针 |
| 0018 | qcom iris HFI gen2 fixes | VA-API 硬解 |
| 0019 | q6apm TDM sink PON reason / qmi decode log | 音频 bring-up |
| 0020 | restore factory Bluetooth address | **改成你自己的地址**（见 §2） |
| 0021 | QMP combo skip USB3 init when mux DP_ONLY | DP-only 下不初始化 USB3 |
| 0022 | msm: do not block GEM shrinker on GPU fences | 整屏卡死 C 补丁 |
| 0023 | wcd939x-usbss skip deferred write while attached | 坞 USB3「插上即断」F1 |
| 0024 | dwc3 qcom skip-glue-pm-on-suspend | 带坞 s2idle |
| 0025 | arm64 dts sm8650 keep USB1 up across s2idle | USB1 跨睡眠 |
| 0026 | initramfs.list use /w/initramfs paths | 可复现构建 |
| 0027 | Type-C DP orientation fixes + bring-up log diet | **v32 + v33b…v36** 合集（见 §5） |

---

## 2. 先把蓝牙地址换成你自己的

`0020` 与 `0002` 都写同一个地址；**必须成对改**，否则 `0020` 的 context 对不上。

```bash
# 地址来源：persist 的 bd_addr.bin / getprop ro.odm.lenovo.btaddr / 原厂 getprop 备份
tools/arch-kernel/set-bt-addr.sh 02:11:22:33:44:55
# 默认处理 0002 + 0020 + incremental/0001，自动倒序成小端数组
```

校验：

```bash
grep -n 'local-bd-address' patches/kernel/full/0002-tb-base.patch \
                           patches/kernel/full/0020-*.patch
# 两处新增数组应相同，例如 [ 55 44 33 22 11 02 ]
```

不想要固定地址：运行 `set-bt-addr.sh 00:00:00:00:00:00`（或构建时设
`TB_ALLOW_PLACEHOLDER_BT=1` 跳过硬检查）。零占位时 `btqca` 会用 SoC 序列号
**确定性推导** `00:03:7F:…`，不是每次随机；但地址不可控，可能与旧 bond 不符。
要固定地址就写自己的工厂地址。

---

## 3. config 要点

`tools/arch-kernel/config-7.3.0-tb710fu` 是 canonical config。关键项：

| 项 | 值 | 为什么 |
|---|---|---|
| `CONFIG_LOCALVERSION` | `"-tb710fu"` | `kernelrelease=7.3.0-tb710fu` |
| `CONFIG_PSI` | `y` | earlyoom/KDE 压力传感器 |
| `CONFIG_LRU_GEN` | `y` | MGLRU |
| `CONFIG_ZRAM_BACKEND_LZ4/ZSTD/LZO` | `y` | 生产 zstd，基准可切 |
| `CONFIG_DRM_MSM` | `m` | DP/DPU 修复按模块更新 |
| `CONFIG_DRM_PANEL_NT36532_WQHD_DUAL_DSI` | `m` | 面板模块 |
| `CONFIG_TOUCHSCREEN_NT36XXX_SPI` | `m` | 触摸模块 |
| `CONFIG_SND_SOC_QCOM_*` / `AW882XX` | `m` | 音频 |
| `CONFIG_VIDEO_QCOM_IRIS` | `m` | VA-API |
| `CONFIG_ATH12K` | `m` | WiFi |
| `CONFIG_INITRAMFS_SOURCE` | `"initramfs.list"` | NBD/USB 救援 |
| `CONFIG_MODULE_SIG` | 关 | 自编模块可加载 |

> **不要**在 `olddefconfig` 后手工改 `.config` 再直接编；两份 canonical config 要同步，
> 否则 PSI/MGLRU/zram 会被旧 config 覆盖（2026-11-08 踩过）。

---

## 4. 构建

### 4.1 容器（推荐）

```bash
docker run --rm \
  -v tb-kwork:/w \
  -v "$PWD":/src:ro \
  -v "$PWD/work/kernel73/out":/out \
  kernel-build:latest bash /src/tools/arch-kernel/build-from-series.sh
```

脚本做：

1. 下载/解压 vanilla 7.3，`git init` + 初始 commit；
2. `git am patches/kernel/full/*.patch`（27 个）；
3. 检查占位符 MAC 是否还在（警告）；
4. 生成 `initramfs.list`，拷 `initramfs/{init,diag.sh,nbdroot.sh}` + busybox；
5. `cp config` → `make olddefconfig` → `make Image dtbs modules`；
6. `modules_install`（strip），校验 `kernelrelease == 7.3.0-tb710fu`；
7. 输出 `Image` / DTB / `modules-7.3.0-tb710fu.tar` / `BUILD-INFO.txt`。

### 4.2 手工命令（需要时）

```bash
cd /w/tb710fu-build/linux-7.3
cp /src/tools/arch-kernel/config-7.3.0-tb710fu .config
make -s LOCALVERSION= KERNELRELEASE=7.3.0-tb710fu olddefconfig
make -j"$(nproc)" LOCALVERSION= KERNELRELEASE=7.3.0-tb710fu Image dtbs modules

# DTB（若 make dtbs 没生成）
cpp -nostdinc -I include -I arch/arm64/include -I arch/arm64/include/generated \
    -undef -D__DTS__ -x assembler-with-cpp \
    arch/arm64/boot/dts/qcom/sm8650-lenovo-tb710fu-kshim.dts -o /tmp/tb.dts
dtc -I dts -O dtb -o out/sm8650-lenovo-tb710fu-kshim.dtb /tmp/tb.dts
```

### 4.3 单模块重编

```bash
# 用法：build-single-module.sh <源码子目录> <ko 名> [输出目录]
tools/arch-kernel/build-single-module.sh drivers/gpu/drm/msm msm.ko /tmp/out
tools/arch-kernel/build-single-module.sh drivers/gpu/drm/panel panel-nt36532-wqhd-dual-dsi-dsc.ko /tmp/out
# 容器卷/树路径可用 KERNEL_VOLUME / KERNEL_TREE_IN_VOL / KERNELRELEASE 覆盖
```

重编后 `depmod -a 7.3.0-tb710fu`，替换 `/lib/modules/.../` 下文件，重启。
**不要 `rmmod` 触摸/iris/DP 模块**（卸载 Oops 或 D 状态死锁）。

---

## 5. v32 + v33b…v36 做了什么（0027 合集）

`0027` 是合集：**v32** 修坞 USB3「插上即断」（`USB3DP ↔ USB3ONLY` 且 USB3 已初始化时
只更新 mode，不重建 QMP COM，见 [07-usbc-dp.md](07-usbc-dp.md) §2.2）；**v33b…v36**
修换向硬复位并做日志治理，下面三层根因按出现顺序列出。

### 5.1 三层根因

1. **COM 整块重建**（v33b）：`qmp_combo_typec_switch_set()` 换向时
   `com_exit → com_init`，按 `USB3_ONLY` 编程，DP PHY 停在复位；
2. **lane 重路由时序**（v33e）：写 `TYPEC_CTRL` 前必须
   `usb_power_off → com_set_mode → usb_power_on`，否则 SS 端口 polling 被打断；
3. **DP 点亮落在枚举窗口**（v34）：`drm_bridge_connector_handle_hpd()` 在
   `msm_dp_bridge_hpd_notify()` 之前就把 connector 置 connected；只能在生产者
   `pmic_glink_altmode` 延迟上报。

### 5.2 v34 参数

```bash
# 默认 1000 ms；可热调；0 = 关闭
cat /sys/module/pmic_glink_altmode/parameters/tb_hpd_delay_ms
echo 0 | sudo tee /sys/module/pmic_glink_altmode/parameters/tb_hpd_delay_ms
```

行为：

- DP 连接上报延后 `tb_hpd_delay_ms`；
- 拔出/ACK 不延后；
- 到点复核状态，已拔出则丢弃（`dropped deferred` 应为 0）。

### 5.3 v35b/v36 日志治理

- bring-up 调试打印降级为 `dev_dbg/pr_debug` 或编译掉（`ucsi_glink` 从 1313 行/13 min
  降到 0）；
- NVT checksum 失配的 11 行 hex dump → `pr_debug`；
- Awinic `aw_dev_info` 编译掉（`TB710FU_AW_VERBOSE=0`），`aw_dev_err` 保留；
- 空闲 60 s 内核日志 0 行。

### 5.4 验证口径

| 场景 | 样本 | 期望 |
|---|---|---|
| 坞插拔/换向（出图） | 8 轮 | 0 复位；每次只 probe 一次；延迟 1003–1008 ms |
| 坞 USB3 | 多次 | `2-1`/`2-1.2` 5000M；`Cannot enable` = 0 |
| 坞 + s2idle | 1 轮 | resume 后 USB 未重枚举，hub 原样存活 |
| 空闲日志 | 60 s | 0 行新增 |

---

## 6. DTB/DTS 改了什么

| 功能 | 改动 |
|---|---|
| CPU 拓扑 | 6 核 1+2+2+1；PSCI 只认 `0x0`/`0x300–0x700`；禁用核用 `status="fail"`；4 个 cpu-map |
| 面板/背光 | NT36532 直接 `devm_of_find_backlight()`；`panel->backlight` 不再依赖空桩 |
| 触摸 | `nvt_36xxx` 面板上电门控、FW health、NULL 判空 |
| USB-C/DP | combo PHY `SW_PWRDN`、WCD939x AUX/DPDM 常开、DP-only 不初始化 USB3 |
| RTC | `nvmem-cells` 指到 SDAM `nvram@7100` 的 `rtc-offset@7c` |
| 麦克风 | `swr2` 采集用 DAI1（DAI0 只有 playback） |
| 热区 | CPU 只有 110 °C critical（无 passive trip）；GPU 95 °C passive |
| 内存保留 | super/Arch 边界、`qcom,skip-glue-pm-on-suspend` |
| 蓝牙 | `local-bd-address`（小端，改成你自己的） |

> DTB 自 v31 未变（`349dcec2…`）。改 DTS 后必须重新 `make dtbs`，并重打 boot；
> 只换 `.ko` 不会更新 DTB。

---

## 7. boot 打包与双系统

```bash
# 输入：v3 Android-only 启动链（work/v3/boot.img + vbmeta.img）、kShimC、Image、DTB
# 注意：不要用当前的 kShimC boot_a 当 STOCK_BOOT；它已经是多内核载荷，不是 GKI 底座
STOCK_BOOT=work/v3/boot.img \
VBMETA=work/v3/vbmeta.img \
SHIM=work/kshim/kShimC.bin \
OUT=work/boot \
tools/kshim_variants.sh local work/kernel73/out/Image work/kernel73/out/sm8650-lenovo-tb710fu-kshim.dtb
# -> work/boot/local_android/boot.img（默认 HyperOS）
# -> work/boot/local_linux/boot.img  （默认 Arch）
# -> work/boot/current/boot_{android,linux}.img
```

> 如果设备已经装过 KSU/Magisk、重打包 boot，`VBMETA` 改用当前回读的 `vbmeta_a`
> （KSU 可能改过它）；`STOCK_BOOT` 仍用 `work/v3/boot.img`。

每个变体都会用**你自己的 vbmeta** 校验 AVB；不通过会拒绝。缺 `tools/avb/` 时按
[02 §2.1.1](02-materials.md) 准备 AOSP `avbtool.py` + 两把 testkey（含 GitHub 镜像与
sha256 校验）。

> **NBD 不需要另打变体**：kshim DTB 的 `/chosen/bootargs` 默认带
> `tb710fu.nbd nbd.max_part=8`。第一次安装、盘上还没有 `sda15` 时，`boot_linux` 的
> initramfs 会先找 `PARTNAME=archlinux`，找不到就自动走 NBD。完整首次安装顺序见
> [00-install-paths.md](00-install-paths.md) §3。

双系统配对：

```bash
tools/make-pair.sh work/boot/current/boot_android.img \
                   work/boot/current/boot_linux.img > pair.env
```

详见 [08-dualboot-share.md](08-dualboot-share.md)。

---

## 8. 安装模块与 boot

```bash
# 模块（整包）
sudo tar xf work/kernel73/out/modules-7.3.0-tb710fu.tar -C /lib/modules
sudo depmod -a 7.3.0-tb710fu
# 或只换单个 .ko
sudo cp <module-out>/msm.ko /lib/modules/7.3.0-tb710fu/kernel/drivers/gpu/drm/msm/
sudo depmod -a 7.3.0-tb710fu

# boot（先备份！）
sudo dd if=/dev/disk/by-partlabel/boot_a of=/var/backups/tb710fu/boot_a.before-$(date +%F).img bs=4M
sudo dd if=work/boot/current/boot_linux.img of=/dev/disk/by-partlabel/boot_a bs=4M conv=fsync
sudo sha256sum /dev/disk/by-partlabel/boot_a
```

**只写 `boot_a`**；不要写 `boot_b`，不要切槽。

---

## 9. 验收

```bash
# 版本/vermagic
uname -v                                  # #NN ...
modinfo -F vermagic msm nvt_36xxx panel_nt36532_wqhd_dual_dsi_dsc sy7758

# 关键 config
zcat /proc/config.gz | grep -E 'CONFIG_PSI|CONFIG_LRU_GEN|ZRAM_BACKEND'

# 回归检查
tools/arch-kernel/check-7.3.sh /path/to/tree /path/to/sy7758.ko

# 运行时
cat /sys/class/drm/card1-DP-1/status
cat /sys/kernel/debug/dri/1/DP-1/dp_debug | head -20
btmgmt info | grep address
```

期望：

- `kernelrelease = 7.3.0-tb710fu`；
- DP：直连 4 lane `540000` / `bpp24`；坞 2 lane `810000` / `535680`；
- `btmgmt info` 显示你自己的工厂地址；
- 无 `Oops`、无 `phy initialization timed-out`、无 `audio_process' crash`。

---

## 10. 构建/刷机错误表

| 现象 | 原因 | 处理 |
|---|---|---|
| 模块 `vermagic` 带 `+` | 没显式 `KERNELRELEASE` | 所有 make 都加 `KERNELRELEASE=7.3.0-tb710fu` |
| `git am` 在 0020 失败 | 0002 与 0020 的地址不一致 | 重跑 `set-bt-addr.sh`，两个补丁一起改 |
| `git am` 在 0001 失败 | 7.3 tarball 不是 7.3 / 已打过补丁 | 用干净 tarball，`git init` 后先提交 |
| DTB 没生成 | 没跑 `dtbs` 或 Makefile 未包含 | `make dtbs`；或手工 cpp+dtc |
| 刷后不能启动 | Image/DTB 不匹配、GKI 版本错 | 回到备份 boot_a；确认 GKI 6.1.128 |
| 触摸消失 | `rmmod nvt_36xxx` | 只能重启；换文件后重启 |
| DP 黑屏 | 4L HBR3/30bpp 实验 | 回 HBR2/24bpp；不要移除 4-lane clamp |
| 坞 USB3 掉 | QMP COM 重建 | v32+；确认 `USB3DP↔USB3ONLY` 不重建 |
| 换向复位 | DP 点亮早于枚举 | v34；`tb_hpd_delay_ms=1000` |
| 整屏卡 10–18 s | shrinker 等 fence | v31+ `msm.ko` |
| 空闲日志刷屏 | 调试打印未降级 | v35b/v36；检查 `TBMSC7/TBPNL7/TBBL7` = 0 |
