# TB710FUThermal v1.1 — 双模式 GPU + CPU 温控

- 模块 ID：`tb710fu_thermal`
- 版本：v1.1 / versionCode 2
- 作用：按 HyperOS 系统性能模式切换两套 thermal-engine 配置
- 日志：`/data/adb/tb710fu_thermal/thermal.log`

| 系统模式 | `POWER_PERFORMANCE_MODE_OPEN` | GPU `thermal-engine_gpu_0.conf` | CPU `thermal-engine_cpu_0.conf` |
|---|---|---|---|
| 性能 | `1` | `back_temp` 43/45/48/51/54 ℃ → 834/720/629/500/366 MHz + `skin-msm-therm` 65/68/70 ℃ 兜底 | 原厂阈值/频率，sensor 从 `rear-tof-therm` 换成 `back_temp` + `rear-tof-therm` 55/58 ℃ 兜底 |
| 均衡 / 省电 | `0` / 未设置 | 原厂 `skin-msm-therm` 曲线，逐字节不变 | 原厂 `rear-tof-therm` 曲线，逐字节不变 |

性能模式使用联想 `lenovo_sys_temp` 已经算好的外壳温度 `back_temp`，不需要自定义内核模块。均衡模式
保持原厂文件。两种模式都只 bind mount `/vendor/etc/thermal-engine_{gpu,cpu}_0.conf`，不碰电池、风扇、
充电、TJ shutdown 和内核 TSENS。

## 1. 作用与边界

- 只替换 GPU/CPU 两个 thermal-engine 配置文件；不改内核、不改 boot/super。
- 性能模式可切到更激进的 GPU 曲线，CPU 仍使用同一套 `back_temp` + rear-tof 兜底配置。
- 真正的硬保护仍是内核 TSENS trip 和 TJ shutdown；模块只调整 thermal-engine 的降频曲线。
- 不要和改同两个 vendor 文件的其他模块同时使用。

## 2. 实现方式

### 2.1 配置文件

```text
profiles/gpu_0.balanced.conf                原厂 GPU 逐字节副本
profiles/gpu_0.performance.conf             GPU back_temp + skin 兜底
profiles/gpu_0.performance_aggressive.conf  可选 48/50/52/54/56 ℃
profiles/cpu_0.balanced.conf                原厂 CPU 逐字节副本
profiles/cpu_0.performance.conf             CPU back_temp（原厂阈值/频率）+ rear-tof 55/58 兜底
```

GPU 的 `performance_aggressive` 通过
`echo performance_aggressive > /data/adb/tb710fu_thermal/performance_profile` 选择；CPU 在
performance 和 aggressive 下都使用 `cpu_0.performance.conf`。

### 2.2 开机选择（`post-fs-data.sh`）

开机早期 thermal-engine 还没启动，直接 bind mount 两个文件即可。模式来源按优先级：

1. `/data/adb/tb710fu_thermal/manual_mode`（手动覆盖，模块不会改写它）；
2. `/data/adb/tb710fu_thermal/mode`（上次 `service.sh` 观察到的系统模式，跨重启保留）；
3. `persist.sys.tb710fu.thermal.mode`；
4. 都没有 → `balanced`。

HyperOS 的设置文件是 ABX 二进制，post-fs-data 阶段不能 `settings get`，所以只能靠缓存模式。挂载前先
`chcon u:object_r:vendor_configs_file:s0` 源文件；挂载失败时回退到 balanced 副本。结果写入
`/data/adb/tb710fu_thermal/applied`。

### 2.3 运行时切换（`service.sh`）

`service.sh` 在后台启动一个 watcher 后退出，每 10 秒看一次 `POWER_PERFORMANCE_MODE_OPEN`：

- `1` → performance；`0` → balanced；其他值 → 沿用缓存模式，没有缓存则 balanced；
- `manual_mode` 存在时覆盖系统模式；
- 期望 profile 与 `applied` 不同，或两个 mount 有一个不在，就重新应用。

thermal-engine 运行中持有配置文件，`umount` 会返回 EBUSY。运行时切换顺序必须是：

```
chcon 两个源文件
ctl.stop thermal-engine
等 pid 消失（最多 15 s）
umount（必要时 -l）
bind mount 两个文件
ctl.start / ctl.restart thermal-engine
```

模块用 `/data/adb/tb710fu_thermal/service.lock`（pid + boot_id）保证一次开机只有一个 watcher；
卸载或模块被停用时 watcher 会恢复原厂文件并退出。

### 2.4 热区与实测依据

设备实测（OS4.0.11 / piano / 1.5.04.428）：

- 热区命名：`back_temp` tz55、`user_back_temp` tz58、`skin-msm-therm` tz61、`rear-tof-therm` tz65、
  `gpuss-0` tz41。空载大致 back 25 ℃、user_back 30 ℃、skin 30 ℃、rear-tof 30 ℃。
- 系统性能模式键是 `Settings.System.POWER_PERFORMANCE_MODE_OPEN`（1=性能，0=均衡/省电），
  PowerKeeper `IrisServiceUtils` 使用。
- KSU 启动脚本在全局 mount namespace；bind mount 对 init/thermal-engine 可见；源文件必须
  `chcon u:object_r:vendor_configs_file:s0`。
- 同一个 `gpu` action 的仲裁实测是“只降不升”：已压到 366 MHz 时，skin 78.7 ℃ 触发的 629 MHz 被
  抑制；主监控 629 MHz 时，兜底 366 MHz 能正常生效。CPU 的 `cpu-cluster0..3` action 同理。
- CPU 2112 MHz 的来源：原厂 `cpu5-0-0` 在 `rear-tof-therm` 46 ℃ 把 cluster3 限到 2112000，其他簇
  同档限到 2035.2/1708.8/1459.2 MHz。性能配置把 sensor 换成 `back_temp` 后，这一档会相应后移；
  rear-tof 55/58 ℃ 的兜底仍会在后盖热点过高时压回去。

## 3. 安装 / 启用

```sh
# 在资料整理目录根下构建
modules/build_modules.sh
# -> work/ksu-modules/TB710FUThermal.zip

adb push work/ksu-modules/TB710FUThermal.zip /data/local/tmp/
adb shell "ksud module install /data/local/tmp/TB710FUThermal.zip"
adb reboot
```

模块不写 boot/super，只做运行时 bind mount。KernelSU 管理器确认启用后重启。

## 4. 模式与手动覆盖

- 跟随系统：设置 → 电池 → 性能模式（或 `settings put system POWER_PERFORMANCE_MODE_OPEN 1`）。
- 首次安装时还没有模式缓存，`post-fs-data` 会先按均衡启动；`service.sh` 在 `boot_completed` 后约
  5 秒读到系统模式并自动切换（会短暂重启 thermal-engine）。之后每次开机直接命中缓存。
- 强制某个档位（调试用）：

  ```sh
  echo performance > /data/adb/tb710fu_thermal/manual_mode
  echo balanced    > /data/adb/tb710fu_thermal/manual_mode
  rm /data/adb/tb710fu_thermal/manual_mode
  ```

- GPU 还可选更激进的 48/50/52/54/56 ℃ 曲线：

  ```sh
  echo performance_aggressive > /data/adb/tb710fu_thermal/performance_profile
  ```

## 5. 验收

```sh
# 两个配置文件当前挂的是哪套
adb shell "head -4 /vendor/etc/thermal-engine_gpu_0.conf"
adb shell "head -4 /vendor/etc/thermal-engine_cpu_0.conf"
adb shell "mount | grep -E 'thermal-engine_(gpu|cpu)_0'"

# 当前应用的 profile / 缓存的系统模式
adb shell "cat /data/adb/tb710fu_thermal/applied"
adb shell "cat /data/adb/tb710fu_thermal/mode"

# thermal-engine 是否加载了正确段
adb shell "logcat -d -s ThermalEngine | grep -E 'SS-GPU|cpu5-0-0|cpu3-backstop|Created section'"

# 模块日志
adb shell "tail -30 /data/adb/tb710fu_thermal/thermal.log"
```

性能模式应看到 GPU 的 `back_temp`、CPU 的 `cpu5-0-0`/`cpu3-backstop`；均衡模式只有原厂的
`skin-msm-therm`/`rear-tof-therm`。

## 6. 实时监控与校准

电脑端（无线 ADB）：

```sh
python3 tools/tb710fu_thermal_monitor.py
python3 tools/tb710fu_thermal_monitor.py --once
python3 tools/tb710fu_thermal_monitor.py --interval 1 --csv thermal.csv
```

显示 6 个温度、4 个 CPU policy 的 max/cur、GPU cap/cur、模式、两个文件是否挂载、thermal status 和最后
一条 ThermalEngine action。脚本会自动找 `product:piano` 设备；设备重启后如果没自动连上，会尝试
`adb mdns services` 里的 `_adb-tls-connect` 端点。

设备端校准（每 2 秒记录外壳温、rear-tof、gpuss、gpuclk、CPU/GPU cap、模式和 CPU cur）：

```sh
adb shell "sh /data/adb/modules/tb710fu_thermal/tools/thermal_log.sh 900"
adb pull /data/adb/tb710fu_thermal/calibration.csv
```

看三件事：

1. `back_temp` 达到 43/45/48/51/54 时，`skin-msm-therm`、`rear-tof-therm` 和手感温度分别是多少。
2. CPU 2112 档在 `rear-tof-therm` 多少度出现；新配置是否把它后移。
3. rear-tof 55/58 兜底是否触发；如果模型和实际后盖脱节，再调阈值或把 CPU 的 sensor 改成
   `user_back_temp`。

## 7. 卸载 / 回退

```sh
adb shell "ksud module uninstall tb710fu_thermal"
adb reboot
```

`uninstall.sh` 会杀 watcher、卸两个 mount、重启 thermal-engine。也可以手动立即恢复原厂：

```sh
adb shell "setprop ctl.stop thermal-engine; \
  umount -l /vendor/etc/thermal-engine_gpu_0.conf; \
  umount -l /vendor/etc/thermal-engine_cpu_0.conf; \
  setprop ctl.start thermal-engine"
```

## 8. 设计要点与不要做

1. **源文件必须先 `chcon u:object_r:vendor_configs_file:s0`。** 否则 thermal-engine 读不到 bind
   mount 进来的配置；chcon 要在停 thermal-engine 之前完成，失败就保留当前配置，不要继续停守护进程。
2. **thermal-engine 持有配置文件，`umount` 会 EBUSY。** 运行时切换必须按
   `ctl.stop` → 等 pid 消失 → `umount`（必要时 `-l`）→ bind → `ctl.start` 的顺序，不能直接覆盖挂载。
3. **post-fs-data 不能 `settings get`。** HyperOS 设置是 ABX 二进制；必须靠 `manual_mode` /
   `mode` / persist prop 的缓存选择配置。
4. **同 action 的仲裁“只降不升”。** 兜底不会把已经更低的频率抬回去；真正的硬保护是内核 TSENS trip
   和 TJ shutdown，不要指望 thermal-engine 配置做硬切断。
5. **不要和改同两个 vendor 文件的其他模块共用。** 两个 bind mount 会互相覆盖，切换顺序也不可控。
6. **不要在跑分/游戏中频繁切模式。** 每次运行时切换都会短暂停 thermal-engine。

## 9. 限制与原厂遗留

1. **CPU 也进入性能配置了。** 性能模式 CPU 的阈值/频率仍是原厂表，只换 sensor 并加 rear-tof 兜底；
   均衡模式完全原厂。若 rear-tof 仍到 55/58 ℃，兜底会按原厂深度压频。
2. **`thermal_user_case.conf` 的 case 700 仍指向空的 `gpu_1.conf`/`cpu_4.conf`。** 当前日志一直是
   case 0；若某个游戏触发 case 700，温控会切到空配置。这是原厂遗留，本模块不解决。

## 10. 文件清单

```text
module.prop
post-fs-data.sh                         开机早期按缓存模式 bind GPU+CPU
service.sh                              轮询系统模式，变更时切换两个文件并重启 thermal-engine
uninstall.sh                            卸载时恢复原厂
profiles/gpu_0.balanced.conf            原厂 GPU 逐字节副本
profiles/gpu_0.performance.conf         GPU back_temp + skin 兜底
profiles/gpu_0.performance_aggressive.conf  可选 48/50/52/54/56
profiles/cpu_0.balanced.conf            原厂 CPU 逐字节副本
profiles/cpu_0.performance.conf         CPU back_temp（原厂阈值/频率）+ rear-tof 55/58 兜底
tools/thermal_log.sh                    设备端校准 CSV
```
