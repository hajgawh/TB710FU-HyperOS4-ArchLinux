# TB710FUSetRes v2.0 — OS4 运行时桥接（只做包内做不了的事）

- 模块 ID：`tb710fu_setres_noop`（实际职责是运行时桥接）
- 版本：v2.0 / versionCode 11
- 适用：TB710FU HyperOS 4（OS4.0.11）
- 安装：`ksud module install TB710FUSetRes.zip`，重启生效
- 日志：`/data/local/tmp/tb710fu_boot.log`、`/data/local/tmp/tb710fu_loops.log`、`/data/local/tmp/tb710fu_landscape.log`

> **v2.0（2026-11-10）**：`panel_direction` 不再写死 3，改为每 1 秒跟随 `sys.tp.grip_enable`
> （0/90/180/270 → 0/1/2/3，OS4 驱动索引就是旋转角/90）；新增 `post-fs-data.sh`，在
> system_server 启动前 bind-mount `landscape_fullscreen_list.xml`（Settings/浏览器进入
> `miui-magic-windows`、右边缘贴屏）。背景、证据与未决的 launcher stub 竞态见
> `../../docs/12-os4-touch-backgesture.md`。

这个模块不是“补丁合集”，而是把**必须在 root 下、必须在 system_server 起来之后执行**的几件事集中到
`service.sh` 和它拉起的 `tb_loops.sh` 里。能烧进 `system` / `product` 的默认值已经全部前移到刷机包，
模块不重复。

## 1. 作用与边界

包内已经负责、模块不再做的事：

| 项目 | 现在由谁负责 |
|---|---|
| 字体 100%（`font_scale` / `device_font_scale` / `ui_mode_scale`） | `/system/etc/tb710fu_bootfix.sh`，每次 `sys.boot_completed=1` 后写 |
| 侧滑返回宽度 | 同上；删除旧包遗留的 1.5 倍 Secure 键，回到 framework 默认 1.0 |
| R 角 40px（`DevicesOverlay.apk`） | `product.img` 里就是原厂 40px，不再打 10px 补丁 |
| 刷新率/灵动岛保持原样 | 系统包不写任何相关 Settings/prop；`support_max_fps=144`、`fpsList=120/90/60` 原厂 |
| 联想 marketname | `product/etc/build.prop` 烧入（含各 source 变体） |
| 双击亮屏/保护套/触控采样/手写笔/内存拓展的初值 | `product/etc/build.prop` 烧入（`persist.*`，之后由 `/data/property` 持久化） |
| 颜色模式、人脸、语音唤醒、密钥布局、mslg 版本门 | `system` / `system_ext` / `product` 内 |

模块只负责五件事：

1. **lwky 开关桥**：把 OS4 设置页的开关同步到 lwky 的 persistent property 和节点；
2. **电池保护桥**：把 OS4 原生三档电池保护同步到 `persist.sys.pc_mode`；
3. **WPS/CAD rootfs 桥**：路径、版本门、SELinux、客户机镜像；
4. **升级兜底**：清理旧 OS3 包留下的 3198 分辨率 override 和 wmhp 窗口规则；
5. **离线时间**：用 `(epoch, RTC raw)` 存档在断网开机时补时。

边界：字体、R 角、侧滑、刷新率、灵动岛、联想身份由系统包负责；SoC 调度归 `TB710FUCPUMax`，
温控归 `TB710FUThermal`；FindDevice/云备份的 TEE 伪造故意不做。

## 2. 实现方式

### 2.1 启动时序（`service.sh`）

1. **最前面恢复离线时间**：读 `/mnt/vendor/persist/tb710fu/lasttime`，按 RTC 增量算出目标时间；
   只有目标晚于当前系统时间才 `date -s`。这一步必须最早，晚于系统读时间就没有意义。
2. 写 `/data/local/tmp/tb710fu_boot.log` 的 `service.sh-start` 标记。
3. `sleep 10` 后执行 `cmd window size reset`，并删除旧 OS3 的四个 `cloudFeature_*.xml`
   （先 `chattr -i` 解除 immutable）。
4. 等 `sys.boot_completed=1`（最长约 120 秒），再等 5 秒让 PackageManager 稳定。
5. 建立 WPS/CAD 的 rootfs 桥、释放客户机镜像、把 `/data/rootfs` 顶层设为 0555。
6. 用 `busybox setsid sh "$MODDIR/tb_loops.sh"` 启动常驻循环，另起会话；写
   `service.sh-loops-launch` / `service.sh-exit` 后退出。

`system.prop` 故意只有注释：所有 `persist.*` 默认值由 product build.prop 首次开机写入，之后由
`/data/property` 持久化。若在 `system.prop` 里写值，KSU 每次开机 `resetprop` 会覆盖用户在设置里的
选择，所以这里不写任何值。

### 2.2 lwky 硬件层

lwky 是兰微卡鱼 OS3 移植包里的联想硬件适配层，由三部分组成。

#### `init.lwky.rc`：节点权限 + property 触发器

启动时（`sys.boot_completed=1`）把联想私有节点交给 `system` 用户并放开 0666：

```
/sys/class/power_supply/battery/charge_control_limit
/sys/class/power_supply/battery/charging_enable
/proc/gesture_control
/proc/support_pen
/proc/game_mode
/proc/game_edge
```

然后监听四个 persistent property，直接写节点：

| property | 值 | 节点效果 |
|---|---|---|
| `persist.sys.gesture_wakeup` | `2` / `0` | `/proc/gesture_control` = `1` / `0`（双击亮屏开关） |
| `persist.sys.stylus.enable` | `1` / `0` | `/proc/support_pen` = `1` / `0`（手写笔支持） |
| `persist.sys.high_touch_sampling_rate.enable` | `1` / `0` | `/proc/game_mode` = `2` / `5`，`/proc/game_edge` = `0` / `0`（游戏模式/移除掌拒；边缘防误触关闭） |
| `persist.sys.pc_mode` | `0/1/2` | 不直接写节点，由 `lwky_smart_charge_hyper` 读取 |

这些触发器只认**数字**，写成 `true` 不会生效。

`init.lwky.rc` 还负责启动两个常驻服务（`class main`、`user root`、`seclabel u:r:shell:s0`）：

- `lwky_cover`
- `lwky_smart_charge`（可执行文件是 `/system/lwky/lwky_smart_charge_hyper`）

以及 `sys.boot_completed=1` 时 `start micharge-hal_lwky`（vendor 里的小米充电 HAL，负责快充动画/充电协议）。

#### `lwky_cover`：保护套合盖/开盖

行为：

1. 扫描 `/dev/input/event*`，用 `EVIOCGNAME` 找名字为 `hall_irq` 的输入设备（联想霍尔传感器）。
2. `poll()` 等事件；只看 key 值 `0xfc`（合盖）和 `0xfd`（开盖）。
3. 先 `getprop persist.sys.device_case_enabled`，不是 `1` 就忽略。
4. 读 `/sys/class/backlight/panel0-backlight/brightness` 判断当前屏幕是否点亮。
5. 合盖且屏亮 → 执行 `input keyevent 26`（POWER）关屏；开盖且屏灭 → 同样注入 POWER 开屏。
6. 已经有防抖（约 300 ms），屏幕状态与目标一致时只打日志，不重复注入。

边界：它只做“亮/灭屏”，**不会绕过锁屏 PIN/密码**；合盖再开盖仍然要正常解锁。日志形如
`-> lid closed, screen off` / `-> lid open, screen on`。

#### `lwky_smart_charge_hyper`：把 `pc_mode` 变成真实充电控制

主循环（每 2 秒一次，只在状态变化时写节点）：

1. 读 `/sys/class/power_supply/battery/status`。如果是 `Discharging`（没插电），把停止状态清零
   （`charge_control_limit=0`、`charging_enable=1`），继续下一轮。
2. 读 `persist.sys.pc_mode` 并 `atoi()`：
   - **`0`（正常充满）**：停止状态 = 0。
   - **`1`（智慧充电保护/旁路）**：读 `/sys/class/backlight/panel0-backlight/brightness`；
     亮度 > 4（亮屏）→ 停止状态 = 1；亮度 ≤ 4（息屏）→ 停止状态 = 0。
     也就是“亮屏时不给电池充电，息屏恢复”，等价于旁路供电。
   - **`2`（电池健康保护）**：读 `/sys/class/power_supply/battery/capacity`；
     电量 > 79% → 停止状态 = 1；≤ 79% → 停止状态 = 0。
3. `set_stop_current(1)` 写：
   - `/sys/class/power_supply/battery/charge_control_limit` = `12`
   - `/sys/class/power_supply/battery/charging_enable` = `0`
4. `set_stop_current(0)` 写：
   - `charge_control_limit` = `0`
   - `charging_enable` = `1`
5. 用静态变量记住上一次状态，避免每 2 秒重复写 flash/sysfs。

所以 OS3 包里的“三档电池保护”不是 APK 假开关，而是这个守护进程真正在写充电节点。

### 2.3 OS4 Settings 桥（`tb_loops.sh`）

OS4（yupei 底）没有 OS3 移植包里的 SystemUI `PropObserver`，设置页里的开关不会自动变成上面那些
persistent property。`tb_loops.sh` 由 `service.sh` 以 setsid 启动，负责四个循环
（lwky 5 s / panel_direction 1 s / pc_mode 15 s / 存档 180 s）：

**lwky 开关桥（每 5 秒）**

- 读 `settings get system gesture_wakeup_option`（`2`/`1`/`true` 视为开，`0`/`false` 视为关），
  同步到 `persist.sys.gesture_wakeup`，并**直接校准** `/proc/gesture_control`。
- 高触控采样按 `persist.sys.high_touch_sampling_rate.enable` 校准：
  开 → `/proc/game_mode=2`、`/proc/game_edge=0`；关 → `/proc/game_mode=5`、`/proc/game_edge=0`。
- **v2.0 起不再写死 `panel_direction=3`**。`tb_loops.sh` 新增独立的 1 秒循环
  `tb_paneldir_follow()`：读 `sys.tp.grip_enable`（WMS 发布的旋转角，0/90/180/270），
  写 `panel_direction = grip/90`（0/1/2/3）；只在变化时写，避免多余 SPI 命令。
  OS4 的 `nt36532_ts.ko` 索引就是旋转角/90（0=0°、1=90°、2=180°、3=270°）；
  旧包写 3 在横屏 90° 时等于 270°，防误触/握持模型反 180°。
- 按 `persist.sys.stylus.enable` 校准 `/proc/support_pen`。

直接写节点是因为 KSU 的 `resetprop` 可能绕过 init 的 property 触发器；而且 `init.lwky.rc` 只在属性
**变化**时响应，开机时手写笔开关已经是 1，它的一次性触发器不会执行。

**横屏 letterbox 修复（`post-fs-data.sh`，v2.0）**

OS4.0.11 的 MIUI 平板策略把不在 `/product/etc/landscape_fullscreen_list.xml` 里的 App 放进
居中的竖屏 letterbox（横屏 3200×2000 时 `mBounds=781..2420`，左右各约 780px 桌面）。手势
stub 在“桌面→App”边界会丢 MOVE，右侧侧滑变成上下滚动。

`post-fs-data.sh` 在 `system_server` 启动前：

1. 把模块自带的 `landscape_fullscreen_list.xml`（原厂列表 + `com.android.settings` +
   `com.android.browser`）复制到 `/data/local/tmp/tb710fu_landscape_list.xml`；
2. `mount --bind` 覆盖 `/product/etc/landscape_fullscreen_list.xml`；
3. 用 `grep com.android.settings` 自检，结果写 `/data/local/tmp/tb710fu_landscape.log`。

必须在 `post-fs-data` 做，不能在 `service.sh` 做：后者在 system_server 之后，框架已经读完列表。
注意 `post-fs-data` 阶段 fake-hwclock 还没恢复时间，日志时间戳可能是 1970，属正常。

**电池保护桥（每 15 秒）**

读 `settings get secure security_pc_secure_protect_mode_key`（OS4 原生“设置→省电与电池→电池保护”
三档写的键，语义与 `pc_mode` 相同：0 正常/1 智慧/2 健康），同步到 `persist.sys.pc_mode`。
值不是 `0/1/2` 时写 `0`，让守护进程回到正常充电。

**离线时间存档（启动立即一次，之后每 180 秒）**

读当前 `date +%s` 和 `/sys/class/rtc/rtc0/since_epoch`，以两行写
`/mnt/vendor/persist/tb710fu/lasttime`。只存档，不恢复；恢复在 `service.sh` 最前面。

### 2.4 离线时间（fake-hwclock）

Android 读不到内核 RTC（原始计数器恒 1970），断网开机时间只能靠存档。锚点必须是
`(epoch, RTC raw)` 两行：

```
<存档时的 epoch 秒>
<存档时的 /sys/class/rtc/rtc0/since_epoch>
```

开机时：

```
目标时间 = 存档 epoch + (当前 RTC raw - 存档 RTC raw)
```

RTC 原始计数跨系统、跨关机一直在走，所以从 Arch 待一整天再回 Android 也能补上。兜底：

- 只有一行（旧格式）或 RTC raw 回退（PMIC 复位）时，退回“存档 epoch 晚于当前时间就直接用存档”；
- 目标时间必须晚于当前系统时间才写，避免把时间调回去；
- 没有 busybox 时用 `awk` 把 epoch 转成 `date` 可接受的格式。

### 2.5 WPS / CAD（mslg）桥

OS4 的 WpsLauncher/CadLauncher（5.0.5）与冻结的 OS3 ODM（mslg）有代差：

- Launcher 硬编码 `/data/vendor/rootfs`；ODM 只服务 `/data/rootfs`。
- Launcher 要求 `ro.vendor.mslg.rootfs.version >= 26.01.01`；ODM 是 `rootfs-25.09.04.tgz`。
- Launcher 见到 `/data/rootfs/version.txt` 会尝试“迁移”并删除旧 rootfs。
- 客户机镜像（`mslgkingsoftimg` / `mslgzwcad2025img`）需要从 Launcher APK 的 assets 里释放。

`service.sh` 的处理：

1. `/data/vendor/rootfs -> /data/rootfs` 符号链接。
2. `resetprop ro.vendor.mslg.rootfs.version rootfs-26.01.01.tgz`（包内 build.prop 也烧了一份）。
3. 两条 `ksud sepolicy patch`：允许 `mslg_app` 搜索/读取 `vendor_data_file`。
4. 从 `WpsLauncher.apk` / `CadLauncher.apk` 的 assets 释放镜像，写 `kingsoft.txt` /
   `kingsoft_md5.txt` / `zwcad2025.txt` / `zwcad2025_md5.txt`。
5. `/data/rootfs` 顶层 `chmod 0555`，阻止 Welcome 的迁移逻辑删除 rootfs。

### 2.6 升级兜底清理

- `cmd window size reset`：清掉旧 OS3 `set_res.sh` 留下的 `wm size 2000x3198` override。
  新包已经不装 `set_res.sh`，这里是给“保留 /data 从旧包升级”的设备兜底。
- 删除 `/data/system/cloudFeature_{autoui2_list,autoui_list,embedded_rules_list,fixed_orientation_list}.xml`：
  旧 OS3 `wmhp` 完美横屏规则，按 320 密度调，在 434/440 下会造成桌面日历重叠。新包不再装 `wmhp`，
  同样只是升级兜底。

## 3. 安装 / 启用

```sh
# 在资料整理目录根下构建
modules/build_modules.sh
# -> work/ksu-modules/TB710FUSetRes.zip

adb push work/ksu-modules/TB710FUSetRes.zip /data/local/tmp/
adb shell "ksud module install /data/local/tmp/TB710FUSetRes.zip"
adb reboot
```

安装后下一次开机由 `service.sh` 自动执行，不需要手动跑脚本。模块没有安装器交互，安装本身不改
`/data` 里的用户数据。发布仓库不附带 zip，用 `build_modules.sh` 生成；整理目录里另有预打包的
`TB710FUSetRes-v2.0.zip`（sha256 `811d3827…`）。

## 4. 验收

```sh
# 模块是否安装
ksud module list | grep setres

# 常驻循环是否另起会话
ps -ef | grep '[t]b_loops'          # 期望 PPID=1 的常驻 shell
cat /data/local/tmp/tb710fu_boot.log
cat /data/local/tmp/tb710fu_loops.log

# lwky 守护
ps -A | grep -E 'lwky_cover|lwky_smart_charge'
getprop init.svc.lwky_cover
getprop init.svc.lwky_smart_charge

# 节点
cat /proc/gesture_control /proc/support_pen /proc/game_mode /proc/game_edge /proc/panel_direction
cat /sys/class/power_supply/battery/charging_enable
cat /sys/class/power_supply/battery/charge_control_limit

# v2.0：panel_direction 跟随旋转（横屏 90 应为 Right Up/1，竖屏应为 Vertical/0）
getprop sys.tp.grip_enable
cat /proc/panel_direction
tail -5 /data/local/tmp/tb710fu_loops.log

# v2.0：横屏 letterbox 列表是否 bind 成功
cat /data/local/tmp/tb710fu_landscape.log
grep -c com.android.settings /product/etc/landscape_fullscreen_list.xml
dumpsys activity top | grep -m1 mCurrentConfig   # 期望 letterBoxed=false、右边缘到 3200

# 桥接
adb shell settings get system gesture_wakeup_option
adb shell getprop persist.sys.gesture_wakeup
adb shell settings get secure security_pc_secure_protect_mode_key
adb shell getprop persist.sys.pc_mode

# 离线时间存档（两行）
cat /mnt/vendor/persist/tb710fu/lasttime
date

# WPS/CAD
ls -l /data/vendor/rootfs
cat /data/rootfs/kingsoft.txt /data/rootfs/zwcad2025.txt
getprop ro.vendor.mslg.rootfs.version
```

lwky 二进制本身把日志打到 stdout/stderr（由 init 收进 `logd`），可用
`logcat | grep -iE 'lwky|hall'` 观察合盖/开盖事件。

## 5. 卸载 / 回退

```sh
adb shell "ksud module uninstall tb710fu_setres_noop"
adb reboot
```

卸载后 `service.sh` / `tb_loops.sh` 不再运行，Settings 桥停止；lwky 服务本身属于系统包，不受影响。

### 5.1 卸载后残留的运行期数据（`uninstall.sh`）

`ksud module uninstall` **只删模块目录、停开机脚本**；模块在运行期建立的东西不会回滚：

| 残留 | 位置 | 默认处理 |
|---|---|---|
| 路径桥 | `/data/vendor/rootfs` → `/data/rootfs` 符号链接 | `uninstall.sh` 删除 |
| 目录权限 | `/data/rootfs` 顶层 `0555` | `uninstall.sh` 恢复 `0755` |
| 版本门 property | `ro.vendor.mslg.rootfs.version` | `uninstall.sh` `resetprop -d`（重启本也会失效） |
| 被改名保留的旧目录 | `/data/vendor/rootfs.old-<时间戳>` | **只提示，不自动动** |
| 离线时间锚点 | `/mnt/vendor/persist/tb710fu/lasttime` | **保留**（`--purge-clock` 才删） |
| WPS/CAD 客户机镜像 | `/data/rootfs/mslg*img` + 4 个 txt | **保留**（`--purge-images` 才删，几百 MB 用户数据） |
| 开机诊断日志 | `/data/local/tmp/tb710fu_*.log` | `uninstall.sh` 删除 |

脚本随模块打包（`modules/build_modules.sh` 会带上），也可以单独跑：

```sh
adb push modules/TB710FUSetRes/uninstall.sh /data/local/tmp/
adb shell "sh /data/local/tmp/uninstall.sh"                 # 预览，什么都不改
adb shell "sh /data/local/tmp/uninstall.sh --yes"           # 执行
adb shell "sh /data/local/tmp/uninstall.sh --yes --purge-clock"   # 连时间锚点一起清
```

> **默认 `--yes` 才会动手**。不带参数只打印将要执行的动作；这样即使某些 KernelSU
> 版本在卸载时自动调用 `uninstall.sh`，也不会在你没看清的情况下删数据。
>
> **这是参考实现**：命令与路径按 v2.0 的 `service.sh` 核对过，脚本在 macOS/Linux 上
> 做过语法与预览运行，**没有在真机上执行过 `--yes`**。第一次用建议先跑预览，
> 逐条对着自己的设备确认。

若只是暂时不想让桥生效，可在 KernelSU 管理器里停用模块并重启——注意 **停用 ≠ 恢复**：
停用只停止开机执行，已建立的符号链接/权限/镜像都还在。

## 6. 设计要点与不要做

1. **ksud 会收割 `service.sh` 的子进程。** 跨 `service.sh` 退出后仍需存活的循环必须用
   `busybox setsid sh "$MODDIR/tb_loops.sh"` 另起会话；只验证“首轮同步执行生效”不能证明后台进程还活着。
2. **fake-hwclock 锚点必须是 `(epoch, RTC raw)` 两行。** 只存 epoch 在 Arch 待一整天再回 Android 会
   恢复成一天前；恢复必须放在 `service.sh` 最前面，且只在目标晚于当前时间时写。
3. **高触控采样用 `game_mode=2`，不要用 4。** 2 是 vendor 的“游戏模式/移除掌拒”（固件 `0x79/0x04`）；
   4 保留掌拒，右边缘返回手势很难触发。`game_edge` 只接受 `0..3`，写 `0` 关闭边缘抑制，不要写 4。
4. **property 触发器只认数字。** `init.lwky.rc` 只响应 `2/0`、`1/0`，写 `true` 不生效；KSU `resetprop`
   可能绕过 init 触发器，所以桥接必须同时直接校准节点。
5. **`support_pen` 必须主动同步。** init 只在属性变化时写节点；开机时手写笔开关已经是 1，一次性触发器
   不会执行，否则厂商笔扫描器一直不开。
6. **`system.prop` 保持注释、不写任何 persist 值。** 默认值由 product build.prop 首次开机写入，之后由
   `/data/property` 持久化；若在这里写值，KSU 每次开机 `resetprop` 会覆盖用户在设置里的选择。

## 7. 不归这个模块管的事

- **字体/R 角/侧滑/刷新率/灵动岛/联想身份**：系统包负责。
- **SoC 调度**：`TB710FUCPUMax`（性能模式满频，均衡/省电交接）。
- **温控**：`TB710FUThermal`（性能模式 back_temp + 兜底，均衡原厂）。
- **FindDevice/云备份的 TEE 伪造**：故意不做（安全降级）。
