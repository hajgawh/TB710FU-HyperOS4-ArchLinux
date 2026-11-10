# AGENT.md — 给执行刷机的 AI Agent 的操作规程

你是一个能执行命令的 AI 编程 Agent。用户请你把 **联想小新 Pad Pro GT（TB710FU，已解锁 BL）**
刷成 **HyperOS 4.0.11（yupei 底 + OS3 vendor）**，可选 Arch Linux 双系统；升级时**必须保留
`/data`**。本文件是规程；`README.md` 是总览，`docs/00-install-paths.md` 是首次安装/升级
决策与首次分区链，`docs/01`–`docs/11` 是步骤与背景，`tools/README.md` 是脚本参数，
`modules/*/README.md` 是运行时行为。

> 本规程假设设备**已经解锁 Bootloader**。解锁本身不在本项目范围内；不要提供或执行解锁漏洞。
> 你面对的是用户自己的设备；**任何物理写入都必须先得到用户明确确认**。

---

## 一、硬性规则（任何情况下都不能违反）

1. **唯一分区永不写入、永不擦除**：
   `persist`、`modemst1`、`modemst2`、`fsg`、`fsc`、`devinfo`、`frp`、`keystore`、`ssd`、
   `secdata`、`uefivarstore`、`cdt`、`ddr`。
   任何 `edl w/wl/e/es/ws/qfil` 的目标里出现这些名字，立即停止并报告。
2. **先备份，再写入**：GPT（6 个 LUN）+ 上述唯一分区 + 你打算替换的 boot 链。
   备份文件不存在/大小为 0/没核对之前，不进入任何写入。
3. **每次物理写入前都要用户明确确认**，先列出：设备状态、目标分区、源文件、源文件
   sha256、完整命令、影响、回退办法；然后停下等用户回复「确认/yes」。
   上一次的确认不覆盖下一次写入。读操作（`printgpt`、`getprop`、`adb devices`）不需要确认。
4. **写后校验**：能读回的都读回；super 至少校验 `SUPER METADATA OK` 和 manifest；
   启动链能读回就比 sha256。不一致就停，不要继续。
5. **升级默认不 `--wipe`**：`flash_super.sh` 不加 `--wipe` 只写 super；`/data`、KSU、
   Arch、账号、共享分区都保留。只有用户明确要求「首次安装/彻底重置」时，才单独确认
   `--wipe`，并说明会清 `/data`。首次安装的完整判断见 `docs/00-install-paths.md`；
   `--wipe` 不能代替 v3 链、建 `sda15` 或 NBD 试跑。
6. **不要恢复旧 userdata 整盘镜像**：TEE 防回滚，PIN 可能永远解不开。
7. **不要在设备上点系统 OTA**；不要建议用户这么做。
8. **不要打开「查找设备」**：联想固件没有小米 TEE；本项目用 `.DEV` incremental 绕过检查。
   向导阶段不登录小米账号（除非用户已过向导并明确要登录）。
9. **不重签 system UID APK、不把系统 APK 放 `/data/app`**；系统 APK 只用原位补丁。
10. **进程管理按 PID**，不要用 `pkill -f`、`killall` 这类宽泛匹配。
11. **不要在命令、日志、文件、提交里回显**：密码、Wi-Fi 密码、账号、序列号、IMEI/MEID、
    MAC、密钥、ADB 授权、设备备份。文档/日志用 `<serial>`、`<device-ip>`、`<path>`。
12. **不要编造**分区名、偏移、哈希、命令参数。不确定就 `printgpt`/`--help`/问用户。
13. **不要把 `work/`、官方/第三方二进制、个人数据提交到 git**。`.gitignore` 已排除
    `work/*`，只保留 `work/README.md`。
14. **不要在低电量下刷机**：电量 <30% 先让用户充电；EDL 写入期间不要拔线/让主机睡眠。
15. **不要使用仓库里的占位符标识**：`02:11:22:33:44:55`、`<serial>`、`<device-ip>`、
    `<share-uuid>` 都是示例。蓝牙地址用用户机器的 `persist`/`getprop`；IP/序列号让用户提供；
    分区 UUID 用 `blkid` 现场读。详见 [PRIVACY.md](PRIVACY.md)。
16. **双系统脚本只认用户自己的 `pair.env`**：不要用作者的 boot 哈希，也不要把
    `pair.env` 换成「看起来能过」的值。切换前必须 `--dry`。
17. **改 GPT 前先回读，且「删 15 号」只允许一次**：任何 `sda15`/`sda16` 操作（缩 btrfs、
    重建 15 号、建共享分区）必须先 `sgdisk -p /dev/sda` 看清 15/16 号是否存在，再决定
    做哪一步，**不要把它们写成一个跑到底的脚本**。`sgdisk -d 15` 只在「15 号存在、准备用
    原参数重建」时执行**一次**；`partx -u` 后 `/dev/sda16` 没出现 = GPT 已写成功，正确动作
    是**重启后只补 `mkfs.ext4`**，再删一次会把 Arch 根分区的 GPT 记录删掉。`mkfs` 前必须
    `[ -b /dev/sda16 ]` 确认节点存在。完整判定表见 `docs/08` §1.1。

---

## 二、需要用户动手的事

你无法替用户做这些；到这一步说清楚怎么做，然后等用户回复「好了」：

- 解锁 Bootloader（如果还没解锁；本规程从已解锁开始）。
- 进入 9008：关机拔线 → 长按电源 15–20 秒 → 按住音量 +/− 再插线；或已 root/开 USB 调试时
  `adb reboot edl`。
- 把 USB 数据线接到主机（不是只接充电器）。
- 在平板上：解锁、USB 调试授权、KSU 的 ADB Root、向导、kShimC 菜单选择、无线调试开关/配对。
- 下载需要账号/人工确认的文件（OTA、社区 OS3 移植包、ZUI 救援包、Arch rootfs）。
- 提供自己的蓝牙工厂地址（`persist`/`getprop`）、设备序列号、无线 adb 的 IP（如用）。
- 插拔数据线、短按/长按电源、在菜单里选系统。

---

## 三、判断设备当前状态

| 检测 | 含义 | 下一步 |
|---|---|---|
| `lsusb`/`ioreg` 有 `05c6:9008`（QUSB_BULK） | 9008/EDL | 可以 `edl` |
| `lsusb` 有 `05c6:900e` | 内核崩溃转储 | 先用 `edl` 导出转储分析，不要直接重写 |
| `adb devices` 有 `device` | Android 运行中 | `adb shell getprop sys.boot_completed`；`su -c id` 判断 root |
| `fastboot devices` 有设备 | fastboot | `fastboot reboot` 回系统 |
| 能 ping 通但 adb 连不上 | Wi-Fi 在，无线调试端口变了/关了 | 让用户解锁并开无线调试；`adb mdns services` 找 `_adb-tls-connect._tcp` |
| 有 `172.16.42.x` 网卡且 SSH 可连 | Arch/救援环境（initramfs NBD） | 按 Arch 文档处理；不要写 HyperOS 分区 |
| 都没有 | 关机/睡眠/线没插好 | 让用户检查电源和数据线 |

> 主机是 macOS 时，`system_profiler` 在沙盒 shell 里可能为空；用 `ioreg -p IOUSB` 或
> `edl` 自己探测。

---

## 四、阶段与检查点

严格按顺序。每阶段开始前确认上一阶段检查点通过；做完向用户报告结果和下一步。
任何检查点失败，停下来报告，不要「再试一次写入」。

### 阶段 0：环境与输入

**进入条件**：用户已解锁 BL，主机有 Python 3.9+、erofs-utils ≥1.9、apktool、JDK、`edl`。
**检查点**：

- `work/hyperos4_411/x_{system,system_ext,product,mi_ext}` 存在；
- `work/port/{system_a,vendor_a,odm_a,vendor_dlkm_a,system_dlkm_a}.img` 存在；
- `work/port/x_system_a/system/lwky/{lwky_cover,lwky_smart_charge_hyper}` 与
  `x_system_a/system/etc/init/init.lwky.rc` 存在；
- `work/port/x_product_a/app/PearlBiometric/PearlBiometric.apk` 存在；
- `work/patches/miui-services-tb710fu-411.jar`（或 `TB_MIUI_SERVICES_PATCH`）存在；
- `work/overlay/TB710FUTetheringOverlay.apk`、`TB710FUConnectivityOverlay.apk` 存在；
- `work/firehose/prog_firehose_ddr-TB710FU.melf` 存在；
- 电量 ≥30%（推荐 ≥50%）。

**失败**：缺什么报告什么；不要用来源不明的文件替代。

### 阶段 1：9008 备份

**进入条件**：阶段 0 通过；设备进 9008。
**动作**：

1. `printgpt` 6 个 LUN，保存；
2. 读唯一分区（列表见硬性规则 1），保存；
3. 读 `boot_a`/`init_boot_a`/`dtbo_a`/`vendor_boot_a`/`vbmeta_a`（如果打算替换）；
4. 记录 sha256，检查无 0 字节文件；
5. 读 `persist` 里的蓝牙地址（只读），交给用户确认。

**检查点**：GPT 文件齐全；唯一分区文件非空；sha256 清单存在。
**失败**：不进入任何写入；先让用户检查线/9008/存储空间。

### 阶段 2：主机侧构建

**进入条件**：阶段 0 通过（阶段 1 可以与构建并行，但写入前必须完成）。
**动作**：

```bash
tools/port_build.sh
modules/build_modules.sh
```

**检查点**：

- `verify_package.sh` 全部 OK（或只有预期的 INFO）；
- `check_super.py` 显示 7 个分区与 manifest MATCH；
- super `used_end < 10 GiB`（Arch 保留区）；
- 记录 `super_fixed.img` 的 sha256、大小、三分区 sha256；
- 把上一版三分区放到 `work/build_os4/rollback_prev/`（`port_build.sh` 会自动复制），保留回退件。

**失败**：按 `docs/03-os4-build.md` 的构建错误表处理；不要手工拼 super。

### 阶段 3：刷入

先问用户：**是升级（保留数据）还是首次安装（会清 data）？**

#### A. 升级（默认）

**进入条件**：阶段 1、2 通过；设备在 9008；电量 ≥30%。
**动作**：

```bash
EDL=tools/venv/bin/edl \
LOADER=work/firehose/prog_firehose_ddr-TB710FU.melf \
bash tools/flash_super.sh work/build_os4/out/super_fixed.img
```

**不要加 `--wipe`。**
**检查点**：输出 `Wrote ... to sector ...` 和 `SUPER METADATA OK`；设备 reset；能进系统。
**失败**：不要重复写；回退到 `rollback_*` 重建的 super。

#### B. 首次安装（会清 data）

**进入条件**：用户明确确认会清 `/data`；阶段 1 的 boot 链备份已完成。**先读
`docs/00-install-paths.md` §3**：如果还要装 Arch，完整顺序是 GPT 备份 → v3 链 →
NBD 试跑 → 缩 userdata/建 `sda15`/rsync → 再回来刷 `super --wipe`；Android 只配置一次。

**动作**：

1. 写 v3 启动链五件（`boot_a`/`init_boot_a`/`dtbo_a`/`vendor_boot_a`/`vbmeta_a`），先链；
2. `flash_super.sh ... --wipe`；
3. 向导：不登小米账号、不开查找设备、开 USB 调试；
4. 如果向导卡激活检查，改用 `TB_NO_FINDDEVICE=1` 构建的 super 过向导，再脏刷正常 super。

**不要**在用户只说「升级」时走本路径；**不要**在 KSU 装好后再重写 `init_boot_a` 的 v3 链。

**检查点**：能进系统；`sys.boot_completed=1`；USB 调试可用。

### 阶段 4：KSU-Next

**动作**：安装 KernelSU-Next APK → app 内「安装」→ 直接安装（写 `init_boot_a`）→ 重启 →
设置开 ADB Root。

**检查点**：

```bash
adb -s <serial> shell su -c id
# uid=0(root) ... context=u:r:ksu:s0
```

**失败**：只文件修补/fastboot 有时不完整；回到 app 内直接安装。

### 阶段 5：模块

**动作**：

```bash
tools/post_flash_modules.sh <serial>
adb -s <serial> reboot
```

**检查点**（按需启用）：

- 必装：`tb710fu_thermal`、`tb710fu_cpumax`、`tb710fu_setres_noop`；
- 可选：`tb710fu_os4_debloat`（用户明确要精简时；停用模块 ≠ 恢复，先告知）、
  `tb_dp_widebus_off`（外接 A27U 且 HBR3 黑屏时）、
  `tb710fu_share_mount`（已建共享分区时）；
- 退役的 `Font100`/`Corner40`/`Identity` 不在。

**注意**：模块可逆；但安装/卸载后要重启，重启前告诉用户。
Debloat 会在用户态冻结/卸载应用（`pm uninstall -k --user 0`），**必须先得到用户明确同意**；
恢复用模块的 `action.sh`/`restore.sh`，不是「停用模块」。

### 阶段 6：验收

**动作**：

```bash
tools/verify_device.sh <serial>
```

**检查点**（0 failed）：

- `font_scale=1.0`、`device_font_scale=1.0`、`ui_mode_scale=1`；
- `rounded_corner_content_padding=40.0px`；
- `peak_refresh_rate` 为 120/空，`miui_refresh_rate`/`user_refresh_rate` 未写；
- `persist.sys.gesture_wakeup=2` 等 lwky props；
- `/proc/gesture_control=1`、`game_mode=2`、`game_edge=0`、`support_pen=1`；
- `/proc/panel_direction` 跟随 `sys.tp.grip_enable`（横屏 90 → 数值 1 / Right Up；旧包写 3 是 OS3 语义）；
  侧滑 Secure 键为 null/1.0；
- `lwky_cover`、`lwky_smart_charge` running；
- `thermal-engine` running；性能模式时 GPU/CPU 有 bind mount；
- `/data/vendor/rootfs -> /data/rootfs`；
- Arch 分区仍在；共享分区（如有）挂载正常；
- 模块清单符合预期。

人工确认：字体页 100%、R 角、色彩、双击亮屏、保护套、电池保护三档、WPS/CAD、性能/均衡、
前置相机切换、右边缘上/中/下侧滑、日常亮度不刺眼且强光 HBM 生效。

### 阶段 7：Arch 内核（可选）

**进入条件**：HyperOS 侧验收通过；用户明确要 Arch。
**动作**：

1. 在 `kernel-build` 容器里用 `tools/arch-kernel/build-from-series.sh` 从 vanilla 7.3
   重放 `patches/kernel/full/0001..0027`；
2. 用 `tools/arch-kernel/check-7.3.sh` 检查 config/sy7758 回归；
3. 先改蓝牙补丁里的地址（`tools/arch-kernel/set-bt-addr.sh`），再应用 0020；
4. `tools/kshim_variants.sh <name> Image DTB` 打两个默认变体（需要用户自己的
   `boot_a`/`vbmeta_a`/kShimC）；
5. 只装 modules 先试（DP/触摸可用），确认后再刷 `boot_a`；
6. 刷前备份 `boot_a`，刷后回读 sha256。

**检查点**：菜单能进 Arch；`uname -v` 与构建一致；WiFi/触摸/音频/电池基本可用；
`/mnt/share`（如有）自动挂载；`mem_sleep=s2idle`。
**红线**：不要在 NBD 根盘上做睡眠测试；不要写 HyperOS 的 super/唯一分区；
不要把 sda15 当 super 的一部分。

### 阶段 8：双系统与共享分区（可选）

**双系统**：

```bash
tools/make-pair.sh boot_android.img boot_linux.img > pair.env
# Arch 侧：安装 switch2os4 + pair.env 到 /usr/local/share/tbboot/
# OS4 侧：TB_SERIAL=<serial> tools/os4-switch/install_switch2arch.sh boot_linux.img pair.env
```

**检查点**：两侧 `--status` 显示同一 `PAIR_VERSION`；`--dry` 通过；切换后 `boot_a`
哈希等于目标变体；`switch2arch` 回程后仍能进 Arch。
**红线**：只写 `boot_a`；不写 `boot_b`/`misc`；不切 A/B 槽。

**共享分区**：

- **只在还没有 `sda16` 时创建**：按 `docs/08` §1.1 的判定表逐步做（先 `sgdisk -p` 看
  15/16 号，再缩 btrfs，再重建 15 号 + 建 16 号，再 `partx -u`）；
- `partx -u` 后 `/dev/sda16` 没出现 → 停止本阶段，让用户重启，回来只补 `mkfs.ext4`；
  **不要重复 `sgdisk -d 15`**（见硬性规则 17）；
- Arch：`fstab` 用 `LABEL=share` + `tb-share-fixperm.service`；
- OS4：`TB710FUShareMount` v1.1；
- 验收：两侧各写一个文件，另一侧能读；`0600` 文件在扫权限后可读。

**检查点**：`sgdisk -p /dev/sda` 有 16 号且 `/dev/sda16` 存在；`blkid /dev/sda16` 有
`LABEL=share`；两侧各写读一个文件成功。

---

## 五、写前确认模板

任何物理写入前，发这段并等用户回复：

```text
即将写入（<设备状态>）：
- 分区：<super / boot_a / ...>
- 文件：<path>（sha256 <...>，大小 <...>）
- 命令：<完整命令>
- 影响：<会/不会清 data；会不会动 vendor；会不会影响 Arch>
- 回退：<rollback 文件/命令>
- 风险：<断电/写坏/需要 9008 救援>
请回复「确认」继续；回复其他内容则停止。
```

`--wipe`、写 `boot_a`/`init_boot_a`、写 `vbmeta_a`、装 Debloat 都要单独确认，
不能和「刷 super」共用一次确认。

---

## 六、已知故障特征（2026-11-09 版）

| 输出/现象 | 原因 | 处理 |
|---|---|---|
| EDL 工具连不上 / 没有 QUSB 9008 | 只接充电线、没进 9008、hub/线问题 | 换线/直连；关机后长按电源 15–20 秒 → 音量 +/− 按住插线 |
| 电量 <30% | 不安全 | 插充电器；不要继续 |
| `edl reset` 报参数错误 | `reset` 不接受 `--memory` | 只传 `--loader` |
| 开机卡动画/bootloop | super 与 /data 不兼容、启动链不匹配、写坏 | 回刷 `rollback_*`；再写回 boot 链备份；最后 ZUI 救援 |
| 向导 `cloudsp_fid 参数不能为空` | 查找设备需要小米 TEE | `TB_NO_FINDDEVICE=1` 过向导，再脏刷正常 super |
| PIN 永远解不开 / `IKMHal_sendCmd status -30` | 恢复了旧 userdata | 只能清 data；不要恢复旧 userdata |
| 无线 ADB 重启后连不上 | 端口变化/无线调试关了/未解锁 | 解锁 + 开无线调试；`adb mdns services`；或 USB ADB |
| KSU 没有 `su` | 只文件修补/没开 ADB Root | app 内直接安装 → 重启 → 设置 ADB Root |
| 字体页 100% 但字小 | 旧 0.85 + uiMode 早退 | 包内 bootfix 应已写 1.0；`settings get system font_scale` |
| R 角 10px | 旧 product/Corner40 | 卸载 Corner40 后重启；确认 `DevicesOverlay` 40px |
| 色彩反了 | 旧 jar 或旧 oat | 确认补丁 jar；删 `oat/*/miui-services.*` 后重启 |
| SystemUI 冻结/截图卡住 | 在线 `wm density`/`wm size` | `cmd window size reset`，重启；不要在线切密度 |
| WPS/CAD 环境异常 | rootfs/版本/sepolicy/镜像 | 看 `/data/vendor/rootfs`、mslg 版本、`/data/rootfs/kingsoft.txt` |
| 双击亮屏/保护套失效 | prop 不对/节点没写 | 看 `gesture_wakeup_option`、`persist.sys.*`、`/proc/*` |
| 充电上限无效 | `pc_mode` 没同步/守护没跑 | 看 `security_pc_secure_protect_mode_key`、`persist.sys.pc_mode`、`ps` |
| GPU 锁 500MHz | 均衡原厂 skin 51℃ 第 4 档 | 切性能模式；看 `thermal.log` |
| CPU 锁 2112MHz | 原厂 rear-tof 46℃ 第 4 档 | 等降温/性能模式；看 `cpumax.log` |
| `dump.erofs` 读不到 `/etc/...` | system 镜像里 `/etc` 是符号链接 | 用 `/system/etc/...` |
| super 超过 10 GiB | 踩 Arch 保留区 | `make_super.py` 会直接退出；精简 product |
| Arch 锁屏后背光不灭 | 面板模块不是 DPMS 修复版 | 换 `panel-nt36532…` 模块；不要刷 boot |
| 熄屏后显示器每 27 s 弹无信号 | `keep_link=Y` | 设 N，DPMS off 完整下电 |
| 坞 USB3 插上即断 | QMP COM 块在枚举窗口重建 | v32/v33 内核；确认 `USB3DP↔USB3ONLY` 不重建 |
| 换向/插拔硬复位 | DP 点亮落在 USB/SS 枚举窗口 | v34 `tb_hpd_delay_ms=1000`；刷新 boot_a |
| 整屏停 10–18 s、声音继续 | `msm_gem_shrinker` 等 GPU fence | v31+ `msm.ko`（非阻塞 shrinker） |
| 单个进程 `gdrv0` 100%、RSS 不动 | Mesa batch cache 活锁 | `tb-ff-restart`；`watermark_scale_factor=250` |
| 插 A27U 冷启动只有扬声器 sink | `tb-dp-sink-ensure` 早于 link-up | 轮询版已修；临时 `systemctl --user restart pipewire` |
| OS4 带 A27U 重启后无信号 | vendor DP 首训时序 | 重启前拔屏；黑屏时给显示器断电 10 s |
| 共享分区 OS4 侧报 read-only | `mount -o context=` 被 SELinux 拒 | 模块 v1.1 已改 chcon；不要加 context |
| 双系统脚本拒绝写入 | `pair.env` 与镜像哈希不一致 | 重新 `make-pair.sh`；不要 `--force` |

---

## 七、汇报格式

每次向用户汇报：

1. **结论先行**：成功/失败/卡在哪一步；
2. 关键命令与输出（只贴必要行，去掉序列号/IP/MAC/账号）；
3. 检查点是否通过；
4. 下一步需要用户做什么（或「无需操作」）；
5. 如果失败：回退到哪个文件、需要用户确认什么。

不要粘贴整段 logcat/构建日志；只贴错误行和关键校验行。
不要把 `work/`、备份、官方/第三方二进制、个人数据写进仓库或提交。

---

## 八、停止条件

遇到以下情况立即停止，不要继续写：

- 目标分区包含唯一分区；
- 备份未完成/文件为 0；
- 源文件 sha256 与记录不一致；
- 设备电量 <30% 或不在充电；
- EDL/fastboot/adb 状态与预期不符；
- 写后读回不一致；
- 用户没有明确确认；
- 用户说「停/不要刷」；
- 需要清 `/data` 但用户没有单独确认；
- 准备安装 Debloat 但用户没有明确同意；
- 准备使用仓库占位符 MAC/IP/序列号；
- 你准备执行一条自己不确定后果的命令。

---

## 九、与上游锁 BL 流程的差异（重要）

| 上游（lich-wang） | 本项目 |
|---|---|
| 锁 BL，ABL 信任 AOSP testkey | **已解锁 BL**；不强制 AVB，但 v3 链内部哈希仍要一致 |
| 要求 ZUI 1.5.04.495、先全量刷 OS3 移植包 | 不要求全量刷；但 v3 链假设 `recovery_a`/`vbmeta_system_a`/`pvmfw_a` 是 495/WITHOUT_UBL 的 testkey 版，不是就先单独刷这三个（见 docs/00 §3.2） |
| root 用 Magisk | **KernelSU-Next LKM** |
| 第二系统 SteamOS | **Arch Linux ARM** |
| 模块：Magisk 模块为主 | **KSU 模块**：Thermal / CPUMax / SetRes（+ 可选 Debloat/Widebus/Share） |
| OS4 4.0.5 | **OS4.0.11**，`yupei` 底 + OS3 vendor |
| 字体/R 角/身份在模块 | **前移进系统包**，模块只做 root/运行时 |
| 双系统切换硬编码作者哈希 | **`pair.env` 参数化**，用户自己生成 |

不要照搬上游的 495、全量 OS3 线刷、Magisk 修补、SteamOS 步骤；需要时把它们当参考，
以本仓库的 `README.md`/`docs/` 为准。
