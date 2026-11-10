# OS4 右边缘触控与侧滑返回：根因调查与 v2.0 修复（2026-11-10）

设备：Lenovo TB710FU（piano / SM8650Q / 8GB）
系统：HyperOS 4.0.11.0.XPZCNXM.DEV（yupei 移植，KSU root）
触控：Novatek NT36532，FW 26，60×40 节点
显示：2000×3200 原生竖屏，横屏 `ROTATION_90` 为 3200×2000

## 0. 结论摘要

这次不是触控面板/驱动故障。亮屏下 `nvt_selftest` 的 Short/Open/CC/Noise 全 PASS，软件触控检测右半边正常，竖屏正常，插不插充电线无差别。右边缘侧滑问题是**四个问题叠加**（前三个已修，第 4 个 launcher 竞态残留）：

| 层 | 根因 | 状态 |
|---|---|---|
| 1 | `panel_direction` 包内写死 `3`；OS4 驱动里 `3=0xBB(270°)`，而横屏 90° 应写 `1`（0xBC/90°）。固件防误触/握持模型因此反 180° | **已修**：v2.0 改为跟随 `sys.tp.grip_enable` |
| 2 | 横屏未列入横屏名单的 App 被套进居中 1639×2000 竖屏 letterbox，左右各约 780px 桌面；手势 stub 在“桌面→App”边界丢 MOVE | **已修**：v2.0 `post-fs-data` bind-mount `landscape_fullscreen_list.xml`，Settings/浏览器进入 `miui-magic-windows`、右边缘贴屏 |
| 3 | `game_edge=4` / `game_mode=4`（lwky 早期高采样值）：边缘抑制越界、仍保留掌拒 | **早已修正**：`game_edge=0`、`game_mode=2`（本会话前） |
| 4 | MIUI launcher `GestureStubRight/Left` 初始只有 56px，DOWN 后异步扩到 100px；第一下手指滑出 56px 时触摸流被转给 App（`offset_x=0`），第二下因 stub 仍在 100px 而成功 | **未根治**：与系统 load/内存压力强相关；下一步 launcher 初始宽度/换 8602/减负 |

“翻转 180° 后问题跟着 Type-C 边走”是现象层的相关性：横屏时 Type-C 所在短边正好是侧滑返回的边，用户从该侧起手的第一帧位移更大，更容易撞上 launcher 竞态（第 4 个问题）；不是 Type-C 口电气或面板坏。

## 1. 现象与用户实测

- 横屏右侧（Type-C 所在边）触控偏钝，右侧向左滑经常变成向下滚动，而不是侧滑返回；
- 左侧（非 Type-C 边）用同样姿势基本正常，接近小米平板 8；
- 把平板翻转 180°（横屏 `ROTATION_270`），“坏的一侧”跟着 Type-C 边走；
- 软件触控检测右半边正常；竖屏（Type-C 在底部）正常；插不插充电线无差别；
- **停 3 秒后的第一下大概率失败，紧接着第二下很容易成功**（决定性证据）；
- 打开全屏游戏“异环”（`com.hottagames.yh.laohu`，Unreal `GameActivity`，3200×2000 全屏）后体感正常；不是游戏改了 knob（`game_mode` 仍 2、`game_edge` 0、`panel_direction` 1）。

## 2. 现场数据与排除项

### 2.1 触控自检

`/proc/nvt_selftest`：

- `Selftest PASS`、`Short Test PASS`、`Open Test PASS`、`FW CC Test PASS`、`Noise Test PASS`；
- `fw_ver=26`、`PID=0x6095`、`x_num=60, y_num=40`；
- 原始 raw 左右半屏平均只差约 **0.5%**（左 12098.8 / 右 12042.5）；
- 自然底边最后 5 行（40 行中的 35–39）`FW Diff Max/Min` 噪声约 **2 倍**，Open Test 数值略低——那条边信噪比天生稍差，但不足以解释“第一下/第二下”的确定性差异。

> 注意：`/proc/nvt_selftest` 只在**亮屏/awake** 时有意义。2026-11-10 复核发现，灭屏
> （`dumpsys power` 的 `mWakefulness=Asleep`）读取会直接返回 `Selftest FAIL!`，后面只有
> FW/PID 两行；唤醒后同一命令恢复 `Selftest PASS`，Short/Open 等明细也全部 PASS。
> 灭屏 FAIL 是电源状态导致的，不是面板/驱动故障。

### 2.2 触点日志

`getevent -lt /dev/input/event5` 显示右侧起手点确实在边缘（raw `Y=31999`），且轨迹存在上千单位的横向位移；不是“没报点”。

### 2.3 系统状态

问题明显时：`load average ~5`、CPU PSI some ~20%、`MemFree ~200MB`、zram 已用 2.4GB、700+ 任务。重启后 load 降到 ~2.8，第一下体感改善——launcher 竞态被系统负载放大。

## 3. 根因 1：`panel_direction` 在 OS4 上写死 3 是 180° 错误

### 3.1 OS4 驱动映射

`/vendor/lib/modules/nt36532_ts.ko` 的 `nvt_edge_reject_set` 跳转表是 `[0,2,4,6]`：

| 写入 `/proc/panel_direction` | SHOW 文本 | 发送字节 |
|---|---|---|
| 0 | Vertical Direction!(0 degree) | 0xBA |
| 1 | Right Up Direction!(90 degree) | 0xBC |
| 2 | Vertical reverse Direction!(180 degree) | 0xBD |
| 3 | Left Up Direction!(270 degree) | 0xBB |

即 **索引 = 屏幕旋转角 / 90**，SHOW 与 SET 在 OS4 上是一致的。

### 3.2 旧文档为什么写 3

2026-10-26 的结论来自 **OS3 驱动**：OS3 模块的 SET 顺序是 `1→0xBB(270°)、3→0xBC(90°)`，与 SHOW 文本相反；当时为了在横屏 90° 拿到 `0xBC`，写 3 是对的。OS4.0.11 的驱动把 1/3 顺序改回了正常，包内仍按 OS3 经验写 3——在 OS4 上等于告诉固件“屏幕转了 270°”。

### 3.3 旋转来源已实锤

`miui-services.jar` 的 `DisplayRotationStubImpl.writeRotationChangeToProperties()` 把屏幕旋转角度写进：

- `sys.tp.grip_enable` = 0 / 90 / 180 / 270
- `debug.tp.grip_enable` = 同值

实测：竖屏 `sys.tp.grip_enable=0`，横屏 90° 为 `90`。正确逻辑：

```
panel_direction = sys.tp.grip_enable / 90   # 0/1/2/3
```

### 3.4 覆盖坑

`TB710FUSetRes/tb_loops.sh` 的 `lwky_bridge_once()` 原来每 5 秒检查 `/proc/panel_direction`，只要 SHOW 不含 “270 degree” 就写 3。任何手动改的旋转跟随值都会被 5 秒循环覆盖——这也是之前“改桥接没成功”的直接原因。

### 3.5 真机效果

把运行中的 `panel_direction` 从 3 改成 1 后，用户确认左右灵敏度**对称**（此前右侧明显更钝）。这一层成立。

## 4. 根因 2：横屏 letterbox 让手势 stub 离开 App 边缘

### 4.1 现象

横屏下**未列入横屏名单的 App**（Settings、Browser、甚至 chooser）默认被 MIUI 平板策略放进居中的竖屏窗口：

- `mBounds=Rect(781, 0 - 2420, 2000)`，宽 **1639px**、高 2000px；
- `letterBoxed=true`；`mScreenOrientationOuter=PORTRAIT`、`mScreenOrientationPad=UNSPECIFIED`；
- 左侧 781px、右侧 780px 是 launcher/桌面。

### 4.2 手势为什么失败

MIUI 的 `GestureStubLeft/Right` 是贴在屏幕物理边缘的系统小窗。手指从屏幕边起手后，要先穿过约 780px 的桌面区才进入 App；越过“桌面→App”边界/焦点切换时，输入分发会取消或转交触摸流：

```
ACTION_CANCEL received (touch transferred or gesture ended)
[receiveMotionFromOutside] GestureStub blocked: tag= GestureStubRight
should_dispatch_motion_events:false
on_swipe_stop, is_finish: false, offset_x: 0
GestureInputBackHelper ... current_position.x: 3199.7998
```

stub 只拿到 DOWN，后续 MOVE 全丢；App 收到的是一段纵向拖动，于是上下滚动，侧滑返回不触发。

### 4.3 开关与解析链

- 文件：`/product/etc/landscape_fullscreen_list.xml`
- 解析器：`miui-embedding-window.jar` → `MiuiLandscapeFullscreenController`
  - `LANDSCAPE_FULLSCREEN_CONFIG_FILE=landscape_fullscreen_list.xml`
  - `LOCAL_CONFIG_FILE_PATH=/product/etc/`
  - 标签：`<fullscreen_landscape_list>` 包名、`<activity_landscape_list>` Activity 组件、`<reverse_landscape_blacklist>` 反向名单
- 消费方：`MiuiOrientationImpl` 的 `LikelyPadFullScreenManager` → `isLandEnabledForPackagePad()`

### 4.4 修法

把 `com.android.settings`、`com.android.browser` 加进 `<fullscreen_landscape_list>`，bind mount 覆盖原文件，框架重启后：

- Settings：`mBounds=Rect(1160, 0 - 3200, 2000)`；
- `mWindowingMode=miui-magic-windows`、`letterBoxed=false`、`isSpecificEmbedded=true`；
- 宽 2040px，**右边缘贴到 x=3200**；右侧 stub 直接压在 App 上，右侧侧滑恢复；左侧仍留 1160px 桌面。

注意：名字叫 fullscreen，但这台 ROM 的 embedding 策略实际给的是 **miui-magic-windows（嵌入式、右对齐）**，不是 3200×2000 纯全屏。`/product/etc/fixed_orientation_list.xml` 里 `com.android.settings` 是 `disable="true"`，原列表也没有 Settings/Browser。

小米平板 8 对比：OS4.0.12 的 Settings/Browser 跑在 `miui-magic-windows`，`mBounds=Rect(1176, 0 - 3200, 2136)`，右贴边，所以同样手势可用。

## 5. 残留：launcher `GestureStub` 56→100px 扩张竞态

这是第 4 个问题，也是“第一下失败、第二下成功”的直接原因，**本次没有根治**。

- 失败：`GestureStubRight` 有 `on_swipe_start`，但 `on_swipe_stop, offset_x: 0`，`current_position.x` 仍是起手值 `3199.7998`；伴随 `ACTION_CANCEL`/`GestureStub blocked`/`should_dispatch_motion_events:false`。
- 成功：`offset_x` 为 323 / 486 / 523 / 530，`should_invoke_back=true`。
- 连续快速滑动时后几次成功；停顿后的第一下又变成 0。

机制：

- `GestureStubRight/Left` 初始宽度只有 **56px**（约 20dp）；
- 手指 DOWN 后才异步扩张到 **100px**（`expand_window_for_gesture: 0 -> 100`）；
- 第一下手指很快滑出 56px，stub 还没扩完，触摸流被转给下面的 App；
- 第二下时 stub 仍停留在 100px 扩张状态，捕获成功。

相关日志来自 launcher Rust 代码（`libapp_launcher.so`，`gesture_stub_view_manager.rs`）：

```
expand_window_for_gesture: 0 -> 100
restore_window_width: -> 56
```

放大因素：系统 `load average ~5`、CPU PSI some ~20%、`MemFree ~200MB`、zram 已用 2.4GB、700+ 任务；relayout 被拖慢，第一帧竞态更容易输。重启后 load 降到 ~2.8，第一下明显改善，但竞态本身仍存在。

排除项：亮屏下 `nvt_selftest` 全 PASS、软件触控正常、竖屏正常、充电无差别；1.5× `back_gesture_inset_scale_*` 对 OS4 launcher 无效（stub 仍 56px）。

## 6. 为什么“倒过来坏边跟着 Type-C 走”

横屏 `ROTATION_90` 时，Type-C 所在短边正好是逻辑右侧；`ROTATION_270` 时它变成逻辑左侧。用户从 Type-C 侧起手时第一帧位移更大/握持姿态不同，更容易撞上 launcher 竞态；第 1 个问题 `panel_direction` 写死 3 又会把固件防误触模型方向反 180°，让这一侧的初始体验更差。两者叠加，表现为“问题跟着 Type-C 物理边走”。Type-C 口电气、面板走线不是主因。

## 7. v2.0 模块落地

模块：`TB710FUSetRes`（id `tb710fu_setres_noop`），v2.0 / versionCode 11。
安装包：`TB710FUSetRes-v2.0.zip`，sha256 `811d382705cb9c45f83d862583b9d86f1a318eea64981b0b36266defe2c11776`。

文件：

| 文件 | 作用 |
|---|---|
| `module.prop` | v2.0 / 11，描述更新 |
| `service.sh` | 原有 fake-hwclock / mslg / 等等；通过 `setsid` 启动 `tb_loops.sh` |
| `tb_loops.sh` | **删除写死 3**；新增 `tb_paneldir_follow()`，每 1 秒读 `sys.tp.grip_enable`，`panel_direction = grip/90`，仅变化时写；日志 `/data/local/tmp/tb710fu_loops.log` |
| `post-fs-data.sh` | system_server 启动前把模块的 `landscape_fullscreen_list.xml` copy 到 `/data/local/tmp` 并 `mount --bind` 到 `/product/etc/landscape_fullscreen_list.xml`；日志 `/data/local/tmp/tb710fu_landscape.log` |
| `landscape_fullscreen_list.xml` | 原厂列表 + `com.android.settings` + `com.android.browser` |
| `system.prop` | 保持 comment-only（不覆盖用户设置） |

为什么之前改桥接没成功：旧 `tb_loops.sh` 每 5 秒写回 3；这次把该段整体删除，改为跟随旋转。

## 8. 重启后验收（2026-11-10）

```
module.prop: v2.0 / versionCode 11
/data/adb/modules/tb710fu_setres_noop/post-fs-data.sh 存在
/data/adb/modules/tb710fu_setres_noop/landscape_fullscreen_list.xml 存在
/data/local/tmp/tb710fu_landscape.log: "landscape list bind ok"
/product/etc/landscape_fullscreen_list.xml: grep -c com.android.settings = 1
sys.tp.grip_enable=90; /proc/panel_direction = "Right Up Direction!(90 degree)" (1)
tb710fu_loops.log: "panel_direction=1 (grip=90)"
```

注意：`post-fs-data` 阶段 fake-hwclock 还没恢复时间，日志时间戳可能是 `1970-01-17_...`，这是正常的；bind 本身成功。

## 9. 复发/排查命令

```bash
# 1. 旋转跟随是否一致
getprop sys.tp.grip_enable
cat /proc/panel_direction

# 2. 模块是否生效
cat /data/adb/modules/tb710fu_setres_noop/module.prop
cat /data/local/tmp/tb710fu_landscape.log
grep -c com.android.settings /product/etc/landscape_fullscreen_list.xml

# 3. App 是否还在 letterbox
dumpsys activity top | grep -m1 mCurrentConfig   # 期望 mBounds=...,1160..3200, letterBoxed=false

# 4. 手势 stub 是否仍丢 MOVE
dumpsys input | grep -E "GestureStub(Right|Left)" | grep -o "frame=\[[^]]*\]\[[^]]*\]"
logcat -d -v time | grep -E "on_swipe_start|on_swipe_stop|should_invoke_back"

# 5. 触控自检
cat /proc/nvt_selftest | head -5   # 必须在亮屏/awake 下；灭屏会直接返回 FAIL

# 6. 系统压力
uptime; cat /proc/pressure/memory; cat /proc/pressure/cpu; free -m
```

## 10. 未决与下一步

1. **launcher 56→100px 竞态**（本报告第 5 节）：
   - 方案 A：小米平板 8 的 launcher `RELEASE-8.01.02.8602-260918`（本机 `8593`），签名同为 `c9009d01…`，可 `adb install -r` 测试，失败可回装原 APK；
   - 方案 B：native 补丁 `libapp_launcher.so`，把初始 stub 宽度 56 改成 100（和扩张目标一致），再 bind mount APK；
   - 方案 C：降低 Android 内存/CPU 压力（关后台、减 bloat、重启）可缓解第一下失败；
   - 临时用法：第一下当“预热”，紧接着第二下；或先点一下 App 内容再滑。
2. **包内 `tb710fu_paneldir.rc` 仍写 3**：运行时模块 v2.0 会在 `tb_loops.sh` 启动后 1 秒内纠正；`service.sh` 要等 `boot_completed`，所以实际是开机完成后的数秒内。下次重打 system 包时应把 rc 改成“不写/跟随”，或直接删除该 rc 的写死 3。
3. **`landscape_fullscreen_list.xml` 只加了 Settings/Browser**：如果其他常用 App 也频繁遇到侧滑问题，可把包名追加到 `<fullscreen_landscape_list>`；注意不要给纯竖屏 App 加，否则会被强制横屏。
4. **面板本身**：`nvt_selftest` 的底边噪声略高是正常硬件差异，不建议为此改固件/驱动；若未来出现真实断触，再按 `nvt_selftest`/`nvt_diff` 复查。

## 附录：关键日志片段

失败（第一下）：

```
GestureStubViewWindow on_swipe_start: down_position_y=1169.9414, stub_pos=Right
GestureStubViewWindow dispatch_touch_event: ACTION_CANCEL received (touch transferred or gesture ended)
GestureStubViewWindow on_swipe_stop, is_finish: false, offset_x: 0
on_swipe_stop result: should_invoke_back=false, ...
GestureInputBackHelper DHT on_swipe_stop,current_position.x: 3199.7998,should_invoke_back: false
```

成功（紧接着第二下）：

```
GestureStubViewWindow on_swipe_start: down_position_y=1201.9404, stub_pos=Right
GestureStubViewWindow on_swipe_stop, is_finish: true, offset_x: 486.88477
on_swipe_stop result: should_invoke_back=true, ...
GestureInputBackHelper DHT on_swipe_stop,current_position.x: 2712.915,should_invoke_back: true
```

模块验收：

```
/data/local/tmp/tb710fu_landscape.log:
2026-11-10_02:48:13 landscape list bind ok
1970-01-17_20:00:47 landscape list bind ok

/data/local/tmp/tb710fu_loops.log:
2026-11-10_03:17:15 loops-start pid=8445
2026-11-10_03:17:15 panel_direction=1 (grip=90)
```
