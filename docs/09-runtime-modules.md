# 09 — 运行时模块（KernelSU-Next）

> 六个模块源码在 `modules/`，用 `modules/build_modules.sh` 现场打包。
> 模块不写 boot/super，只做运行时 bind mount / sysfs / Settings 桥 / pm / iptables。
> 安装/卸载后要重启。

---

## 1. 模块模型

| 项 | 值 |
|---|---|
| root | KernelSU-Next（LKM） |
| 模块目录 | `/data/adb/modules/<id>/` |
| 开机时序 | `post-fs-data.sh`（早期）→ `service.sh`（late_start） |
| 常驻循环 | 需要跨 `service.sh` 退出后继续运行时，应使用 `busybox setsid sh <script>` 另起会话（SetRes 的 `tb_loops.sh`）；ksud 会收割 `service.sh` 的子进程 |
| 日志 | `/data/local/tmp/` 或 `/data/adb/tb710fu_*/` |

---

## 2. 必装三件

### 2.1 `TB710FUThermal`（`tb710fu_thermal` v1.1）

作用：性能/均衡双模式 GPU+CPU 温控。

- 性能模式：GPU 用 `back_temp` + `skin` 兜底；CPU 用 `back_temp` + `rear-tof` 兜底；
- 均衡模式：联想原厂 GPU/CPU 曲线，逐字节不变；
- 做法：bind mount `thermal-engine_{gpu,cpu}_0.conf`；
- 开机按缓存模式挂载，运行时按 `POWER_PERFORMANCE_MODE_OPEN` 自动换配置。

验收：

```bash
ksud module list | grep thermal
ps -A | grep thermal-engine
mount | grep -E 'thermal-engine_(gpu|cpu)_0'
cat /data/adb/tb710fu_thermal/applied
tail -30 /data/adb/tb710fu_thermal/thermal.log
```

注意：原厂热档优先；均衡模式下 GPU 500 MHz 是 `skin-msm-therm` 51 ℃ 第 4 档，不一定是模块锁死。

### 2.2 `TB710FUCPUMax`（`tb710fu_cpumax` v1.2）

作用：性能模式四簇满频；均衡/省电与 Scene/澎湃做一次交接。

- 只撤销模块写入的满频，不覆盖更低值；
- 不覆盖 `thermal-engine` 已生效的热档；
- 不用 `cpuss-0` 做门槛，结温保护交给内核 TSENS/TJ 和 thermal-engine。

验收：

```bash
ksud module list | grep cpumax
for p in 0 1 3 5; do echo $p $(cat /sys/devices/system/cpu/cpufreq/policy$p/scaling_max_freq); done
tail -30 /data/adb/tb710fu_cpumax/cpumax.log
```

### 2.3 `TB710FUSetRes`（`tb710fu_setres_noop` v2.0）

作用：只保留必须 root 的桥：

- lwky 开关：`game_mode=2`、`game_edge=0`、`support_pen`；
- **`panel_direction` 跟随屏幕旋转（v2.0）**：`tb_loops.sh` 每 1 秒读 `sys.tp.grip_enable`
  （0/90/180/270），写 `panel_direction = grip/90`（0/1/2/3）。OS4 的 `nt36532_ts.ko` 索引就是
  旋转角/90，横屏 90° 写 1（0xBC/Right Up）；旧包写死 3 是 OS3 经验，在 OS4 上等于 270°，
  防误触/握持模型反 180°；
- **横屏 letterbox 修复（v2.0）**：`post-fs-data.sh` 在 system_server 启动前 bind-mount
  `landscape_fullscreen_list.xml`（原厂列表 + `com.android.settings` + `com.android.browser`），
  App 进入 `miui-magic-windows`、右边缘贴屏，右侧手势 stub 不再跨桌面边界；
- 原生电池保护三档 → `persist.sys.pc_mode`；
- WPS/CAD mslg rootfs（`/data/vendor/rootfs -> /data/rootfs`）；
- 3198/wmhp 遗留清理（保留 `/data` 升级时兜底）；
- 离线时间 fake-hwclock：`lasttime` 存 `(epoch, RTC raw)` 两行，开机按 raw 增量补时；
- 常驻循环在 `tb_loops.sh`，用 `busybox setsid sh`（否则会被 ksud 收割）。

v2.0 安装包 `TB710FUSetRes-v2.0.zip`，作者构建的 sha256
`811d382705cb9c45f83d862583b9d86f1a318eea64981b0b36266defe2c11776`；作者基线 6 个文件
（`module.prop` / `service.sh` / `system.prop` / `tb_loops.sh` / `post-fs-data.sh` /
`landscape_fullscreen_list.xml`）。`build_modules.sh` 用 `zip` 打包，时间戳不同会得到
不同哈希；这个值只用于对照作者基线，不要拿它校验你刚打的包。

> 本仓库的 `modules/TB710FUSetRes/` 比作者基线多一个 **`uninstall.sh`**（卸载后的运行期
> 数据清理，参考实现），所以你打出来的 zip 是 **7 个文件**，哈希必然不同于上面的基线值——
> 这是预期的。`uninstall.sh` 不带参数只预览，`--yes` 才执行；它不会自动删 WPS/CAD 镜像
> 和时间锚点。卸载残留清单见
> [`modules/TB710FUSetRes/README.md` §5.1](../modules/TB710FUSetRes/README.md)。

背景与证据见 [12-os4-touch-backgesture.md](12-os4-touch-backgesture.md)。

验收：

```bash
ksud module list | grep setres
getprop persist.sys.gesture_wakeup
getprop persist.sys.pc_mode
cat /proc/gesture_control
getprop sys.tp.grip_enable; cat /proc/panel_direction   # 横屏 90 应为 Right Up/1
cat /data/local/tmp/tb710fu_landscape.log               # 期望 landscape list bind ok
grep -c com.android.settings /product/etc/landscape_fullscreen_list.xml
ls -l /data/vendor/rootfs
ps -ef | grep '[t]b_loops'
cat /data/local/tmp/tb710fu_boot.log
cat /data/local/tmp/tb710fu_loops.log
cat /mnt/vendor/persist/tb710fu/lasttime
```

---

## 3. 可选模块

### 3.1 `TB710FUDPWidebusOff`（`tb_dp_widebus_off` v1.3）

- 外接 A27U 且 HBR3 黑屏时用；
- 只写 `sde_dp` 的 `widebus=N`（`post-fs-data` 最早期 + 每次 `connected` 补写）；
- **不做任何 HPD cycle / altmode unbind**：`hpd` 写入会把 WCD939x USBSS 切到 USB 模式，导致
  显示器无信号/USB 设备丢失；
- 插着显示器重启后无信号是 vendor DP 首次训练时序问题，不在本模块范围内。

日志：`/data/local/tmp/tb-dp-widebus.log`。

验收：

```bash
cat /sys/kernel/debug/drm_dp/widebus_mode   # 期望 N
tail -5 /data/local/tmp/tb-dp-widebus.log
```

### 3.2 `TB710FUShareMount`（`tb710fu_share_mount` v1.1）

- 开机把 `sda16`（GPT 名 `share`，ext4）挂到 `/mnt/share`；
- 无 `context=` 挂载 + 挂载后 `chcon media_rw_data_file`；
- `blockdev --setrw` 兜底 fs_mgr 只读；
- 一次性挂载，不能有常驻子进程。

验收：

```bash
mount | grep /mnt/share
ls -Zd /mnt/share
```

详见 [08-dualboot-share.md](08-dualboot-share.md) §5。

### 3.3 `TB710FUDebloat`（`tb710fu_os4_debloat` v1.5.2）

**这是唯一会改变用户应用状态的模块，安装前必须得到用户明确同意。**

三级精简：

1. **包级冻结** 30 个不用的系统包（小爱/AI、账号云互联、负一屏/推送/快应用、广告统计）；
   `finddevice` 走 `pm uninstall -k --user 0`；
2. **组件级冻结** 6 个反诈组件（`pm disable 包/类`，绕过 MIUI_CORE_APPS 包级拦截）；
3. **DNS 黑洞** 4 个反诈上报域名（iptables hex-string 匹配 QNAME）。

状态：

```text
/data/adb/tb710fu_os4_debloat/state
/data/adb/tb710fu_os4_debloat/uninstalled.txt
/data/adb/tb710fu_os4_debloat/net_state
```

恢复：

```bash
# 模块 action 按钮，或
su -c sh /data/adb/modules/tb710fu_os4_debloat/action.sh
# 或卸载模块
su -c 'ksud module uninstall tb710fu_os4_debloat'
adb reboot
```

> **KSU 停用模块 ≠ 恢复**：停用只停止开机执行，已经冻结/卸载的应用状态还在。
> 必须跑 `restore.sh`/`action.sh` 或卸载模块后重启。

---

## 4. 构建与安装

```bash
modules/build_modules.sh
# -> work/ksu-modules/TB710FUSetRes.zip
# -> work/ksu-modules/TB710FUThermal.zip
# -> work/ksu-modules/TB710FUCPUMax.zip
# -> work/ksu-modules/TB710FUDebloat.zip
# -> work/ksu-modules/TB710FUDPWidebusOff.zip
# -> work/ksu-modules/TB710FUShareMount.zip

# 一次性安装/清理
tools/post_flash_modules.sh <serial>
```

手动：

```bash
adb -s <serial> push work/ksu-modules/TB710FUThermal.zip /data/local/tmp/
adb -s <serial> shell "ksud module install /data/local/tmp/TB710FUThermal.zip"
adb -s <serial> reboot
```

---

## 5. 不再随包发布的模块

`TB710FUFont100`、`TB710FUCorner40`、`TB710FUIdentity` 不再发布：

- 字体 100% 与侧滑 1.0 由包内 `/system/etc/tb710fu_bootfix.sh`；
- 40px R 角由包内原厂 `DevicesOverlay.apk`；
- marketname 由包内 product build.prop。

从旧包升级时 `post_flash_modules.sh` 会尝试卸载它们。

---

## 6. 常见失败

| 现象 | 原因 | 处理 |
|---|---|---|
| 模块列表没有 | zip 结构错/ksud 未 root | 看 `ksud module install` 输出 |
| 需要跨 `service.sh` 的循环没跑 | 子进程被收割 | 用 `busybox setsid sh` 另起会话 |
| 性能模式无变化 | 没切 HyperOS 性能模式/热档更高 | 看 `thermal.log`/`cpumax.log` |
| 均衡模式 GPU 锁 500 | 原厂 skin 51 ℃ 第 4 档 | 正常；切性能或降温 |
| 限充不生效 | `pc_mode` 没同步/守护没跑 | 看 `persist.sys.pc_mode`、`ps` |
| 共享分区只读 | 用了 `context=` | 去掉 `context=`，挂载后 `chcon` |
| Debloat 后找不到应用 | 已卸载/冻结 | `restore.sh` 或卸载模块重启 |
| 停用 Debloat 没恢复 | 停用 ≠ 恢复 | 跑 action/restore |
| 外接屏仍黑屏 | 插着显示器重启/未写 widebus | 拔线重启，看 `tb-dp-widebus.log` |
| 离线开机时间不对 | 存档缺失/RTC 回退 | 看 `lasttime` 两行和 `tb710fu_loops.log` |
| 模块卸载后仍有 bind mount | 未重启 | 重启 |
| Thermal/CPUMax watcher 重启后不工作 | `run_watcher &` 是 `service.sh` 的子进程，理论上可能被 ksud 收割（SetRes 已踩过） | 先 `ps` + 日志确认；若确未存活，按 SetRes 的方式改成 `busybox setsid sh`。当前为待真机复核项 |
