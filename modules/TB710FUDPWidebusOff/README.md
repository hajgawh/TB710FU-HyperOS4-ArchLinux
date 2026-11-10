# TB710FUDPWidebusOff v1.3 — A27U 外接屏关闭 widebus

- 模块 ID：`tb_dp_widebus_off`
- 版本：v1.3 / versionCode 4
- 适用：TB710FU OS4（HyperOS 4.0.11，vendor 6.1.128）+ Redmi A27U USB-C DP
- 安装：`ksud module install TB710FUDPWidebusOff.zip`，重启生效
- 日志：`/data/local/tmp/tb-dp-widebus.log`

## 1. 作用与边界

A27U 在 vendor `sde_dp` 的 **HBR3 + widebus** 组合下会黑屏：系统认为外接屏已 ON、
`dp_debug` 显示 4-lane HBR3/4K60，但显示器无信号。把 `drm_dp/widebus_mode` 写成 `N`
之后，同样的 4K60 30bpp 链路正常出图。**这是本模块唯一职责。**

它**不解决**“插着显示器重启后无信号”：这是 vendor DP 在 USB-C/PD/alt-mode 未稳定时
约 11 s 就发起首次训练，把 A27U 的 RX 带到 `p_level=1` 的问题。规避方式：

1. 重启前拔掉显示器 Type-C，进 Android 后再接回；
2. 已经黑屏时给**显示器断电** 10 s（只拔插 Type-C 不保证恢复）。

签名与完整时序见 [docs/07-usbc-dp.md](../../docs/07-usbc-dp.md) §7。

## 2. 实现方式

| 文件 | 作用 |
|---|---|
| `post-fs-data.sh` | 开机最早期（约 4–6 s）扫描 debugfs，写 `widebus_mode=N`，早于 vendor DP 的首次连接 |
| `service.sh` | 启动时再写一次 `widebus=N`；每 3 秒看 `/sys/class/drm/card0-DP-1/status`，每次变为 `connected` 时补写；**不做任何 HPD cycle** |

节点位置由 debugfs 扫描得到：先遍历 `mount` 里的 debugfs，找 `drm_dp/widebus_mode`；
找不到时 `mount -t debugfs none /sys/kernel/debug` 后写。`service.sh` 最多等 180 秒找节点，
找不到就记日志退出，不影响开机。

`module.prop` 里写明：不要加 `hpd`/altmode 操作。

### 为什么绝对不能做 HPD cycle

`hpd=0` 会走 `wcd_usbss_switch_update(connect_status=0)`，把 WCD939x USBSS **硬件**切到
USB 模式；驱动缓存仍认为在 DP 模式，`hpd=1` 不一定把硬件写回 DP。结果会出现：

- 驱动 `dp_debug` 看起来正常，但显示器无信号；
- USB Hub/鼠标丢失；
- 只能冷启动（关机再开机）复位。

提前在 `post-fs-data` 写 `widebus=N` 已经足够让首次连接就使用关闭 widebus 的链路，不需要靠
HPD 重连让设置生效。

## 3. 安装 / 启用

```bash
# 在资料整理目录根下构建
modules/build_modules.sh
# -> work/ksu-modules/TB710FUDPWidebusOff.zip

adb push work/ksu-modules/TB710FUDPWidebusOff.zip /data/local/tmp/
adb shell "ksud module install /data/local/tmp/TB710FUDPWidebusOff.zip"
adb reboot
```

模块没有持久化配置，也没有安装器交互；安装后重启即生效。

## 4. 验收

```bash
# 期望 N
adb shell 'cat /sys/kernel/debug/drm_dp/widebus_mode'

# 期望看到 boot / connected: widebus=N
adb shell 'tail -5 /data/local/tmp/tb-dp-widebus.log'

# 显示器状态
adb shell 'cat /sys/class/drm/card0-DP-1/status'
```

冷启动后接 A27U，若日志有 `boot: widebus=N` 且外接屏正常出图，即本模块工作正常。若日志出现
`drm_dp debugfs not found, giving up`，说明该内核没有暴露 `drm_dp` debugfs，本模块无法生效。

## 5. 卸载 / 回退

```sh
adb shell "ksud module uninstall tb_dp_widebus_off"
adb reboot
```

模块不修改任何持久文件，卸载后重启即完全去掉。若卸载后仍黑屏，按 §1 的方式给显示器断电或
先拔 Type-C 再重启。

## 6. 设计要点与不要做

1. **只写 `widebus=N`。** 这是本模块唯一职责，不要顺手改 lane、rate、bpp 或 alt-mode。
2. **绝对不要用 `hpd` debugfs 做“重连”。** HPD cycle 会把 WCD939x USBSS 硬件切到 USB 模式，
   导致无信号/USB 设备丢失，且不一定能写回 DP。
3. **不要做 alt-mode unbind/rebind。** 同上，属于 USB-C 角色切换，风险远大于收益。
4. **尽量早写。** `post-fs-data.sh` 要早于 vendor DP 的首次连接；只在 `service.sh` 里写会赶不上
   开机时已经插着显示器的场景。
5. **接受“插着显示器重启可能无信号”的边界。** 这不是 widebus 能修的，靠拔线重启或显示器断电规避。
