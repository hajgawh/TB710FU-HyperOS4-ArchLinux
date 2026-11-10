# TB710FUCPUMax v1.2 — 性能模式 CPU 满频

- 模块 ID：`tb710fu_cpumax`
- 版本：v1.2 / versionCode 3
- 作用：按 HyperOS 系统模式接管 CPU 频率上限
- 日志：`/data/adb/tb710fu_cpumax/cpumax.log`

按 HyperOS/澎湃的系统模式，把 CPU 频率归属拆成三份：

| 模式 | 判断依据 | 模块行为 |
|---|---|---|
| 性能模式 | `POWER_PERFORMANCE_MODE_OPEN=1` | 把四个 CPU 簇解锁到 `cpuinfo_max_freq`；只撤销 Scene/系统写的上限，不覆盖 thermal-engine 已生效的热档 |
| 均衡模式 | 非性能、非省电 | 退出性能模式时做一次交接：只把仍是硬件最大值的簇恢复成进入性能模式前的值；之后不再写，交给 Scene |
| 省电模式 | `POWER_SAVE_MODE_OPEN=1` 或 `EXTREME_POWER_SAVE_MODE_OPEN=1` 或全局 `low_power=1` | 同样只撤销模块写的满频，之后不再写，交给澎湃系统 |

省电判断优先于性能：即使性能开关还留着 1，只要省电/极省电/`low_power` 任一打开，就按省电处理。

## 1. 作用与边界

- 只处理 `policy0/1/3/5` 四个 CPU 簇的 `scaling_max_freq`。
- 不碰 GPU 的 `devfreq/max_freq`；GPU 上限本来就是 903 MHz，游戏时的 GPU 降频由 `TB710FUThermal` 管理。
- 不改 thermal-engine 配置，不覆盖 thermal-engine 已经写入的热档。
- 不设置任何“CPU 结温门槛”；结温保护由内核 TSENS/TJ 和 thermal-engine 负责。

## 2. 实现方式

### 2.1 性能模式解锁

1. 进入性能模式时，先把当前四个簇的 `scaling_max_freq` 记录到
   `/data/adb/tb710fu_cpumax/pre_caps`。
   - 如果四个簇本来就已经是硬件最大值，说明没有可保留的 Scene/系统基线（例如模块刚启动），
     此时快照写 Scene `fast` 值，避免把满频当成 Scene 的选择。
2. 对每个簇：
   - 已经是 `cpuinfo_max_freq`：不写。
   - 当前值命中 `thermal-engine_cpu_0.conf` 的某个热档：不覆盖，等 thermal-engine clear。
   - 后盖 `back_temp < 33.9℃` 且 `rear-tof < 52℃`：四簇都已 clear，直接解锁。
   - 否则按簇判断：
     - policy0/1：`back_temp < 36.5℃`
     - policy3：`back_temp < 35.5℃`（Scene 的 2841600 和原厂第一档相同，用更保守的 clear 点）
     - policy5：`back_temp < 38.5℃`
     - 同时要求 `rear-tof < 54.5℃`
   - `cpuss-0` 不参与判断。
3. 每 2 秒检查一次；Scene 把 p0 写回 1804800 时，最多 2 秒会重新抬到 2265600。

这样解锁的是 **Scene/系统写下的频率上限**；thermal-engine 的热降频和 95℃ 墙仍然有效。

### 2.2 均衡 / 省电的交接

关闭性能模式后，Scene 和系统不会主动把 `scaling_max_freq` 降回去；如果模块完全不管，均衡/省电
也会一直满频。所以模块在模式切出性能时做一次交接：

- 只处理当前 `scaling_max_freq == cpuinfo_max_freq` 的簇，也就是只撤销模块自己写进去的满频。
- 恢复值优先取 `pre_caps` 里的进入性能模式前快照；没有快照时用 Scene `fast` 值
  （1804800/2841600/2841600/2995200）。
- 如果当前值已经被 thermal-engine、Scene 或澎湃改成更低的值，保持不动。
- 交接完成后删除状态文件，均衡/省电期间模块**不再写任何频率**。

因此均衡模式把上限还给 Scene 的基线，省电模式只撤销模块的满频，之后由澎湃的省电策略接管；
模块不会在省电模式里抬频。

`service.sh` 在后台启动 watcher 后退出；watcher 等 `sys.boot_completed=1` 再等 15 秒开始工作。

### 2.3 状态文件与权限

- 日志：`/data/adb/tb710fu_cpumax/cpumax.log`
- 进入性能模式前的快照：`/data/adb/tb710fu_cpumax/pre_caps`
- 活跃标记：`/data/adb/tb710fu_cpumax/active`
- 开机/手动重启 watcher 时会先删掉旧的交接状态；如果当前是性能模式，会重新快照。
- `policy1/3/5` 的 `scaling_max_freq` 是 0444，`policy0` 是 0664；写入时临时 `chmod 0644`，
  写完恢复原 mode。

## 3. 安装 / 启用

```sh
# 在资料整理目录根下构建
modules/build_modules.sh
# -> work/ksu-modules/TB710FUCPUMax.zip

adb push work/ksu-modules/TB710FUCPUMax.zip /data/local/tmp/
adb shell "ksud module install /data/local/tmp/TB710FUCPUMax.zip"
adb reboot
```

模块只在性能模式写频率；装好后切到 HyperOS 性能模式即可验证，不需要额外开关。

## 4. 验收

验证性能模式：

```sh
adb shell "settings get system POWER_PERFORMANCE_MODE_OPEN"   # 1
adb shell "settings get system POWER_SAVE_MODE_OPEN"           # null/0
adb shell "for p in 0 1 3 5; do echo \$p \$(cat /sys/devices/system/cpu/cpufreq/policy\$p/scaling_max_freq); done"
# 期望 p0=2265600, p1/p3=2956800, p5=3302400
```

验证均衡/省电交接：

```sh
adb shell "settings put system POWER_PERFORMANCE_MODE_OPEN 0"
sleep 3
adb shell "for p in 0 1 3 5; do echo \$p \$(cat /sys/devices/system/cpu/cpufreq/policy\$p/scaling_max_freq); done"
# 期望回到 Scene fast 1804800/2841600/2841600/2995200
adb shell "tail -20 /data/adb/tb710fu_cpumax/cpumax.log"
# 应看到 handoff: removed module max caps
```

再打开性能模式，3 秒内应重新看到四簇满频。日志里应能看到 `start mode=...`、`mode ... -> ...`、
`performance: raised to hw max` 或 `perf waiting: ...`。

## 5. 卸载 / 回退

```sh
adb shell "ksud module uninstall tb710fu_cpumax"
adb reboot
```

`uninstall.sh` 只撤销仍处于硬件最大值的簇，不会覆盖 thermal-engine/Scene/澎湃已经改低的值；找不到
`pre_caps` 时用 Scene `fast` 值兜底，然后删除状态目录。watcher 看到模块被移除或出现 `disable`/
`remove` 标记后会退出。

## 6. 仅测试用的环境变量

正常运行时不要设置这些变量：

```sh
TB710FU_CPUMAX_MODE=performance|balanced|powersave   # 覆盖模式判断
TB710FU_CPUMAX_STATE=/some/dir                        # 覆盖状态目录
TB710FU_CPUMAX_TEMP_BACK=40000                        # 模拟后盖 40℃
TB710FU_CPUMAX_TEMP_REAR=30000                        # 模拟 rear-tof 30℃
TB710FU_CPUMAX_TEMP_CPUSS=95000                       # 只用于日志，不参与门槛
ONESHOT=1                                             # 跑一次后退出
```

## 7. 设计要点与不要做

1. **不要把 `cpuss-0` 当门槛。** CPU 结温顶到 95℃ 墙是正常工况；用 `cpuss < 50℃` 会让关闭再打开
   性能模式后一直暂停到 CPU 冷却。模块只根据后盖 `back_temp` / `rear-tof-therm` 判断 thermal-engine
   是否真的在压频。
2. **不要覆盖 thermal-engine 已生效的热档。** 当前值命中热档时跳过，等 thermal-engine clear 后自然
   恢复；真正的硬保护仍是内核 TSENS trip 和 TJ shutdown。
3. **只撤销模块自己写的满频。** 交接和卸载都只处理 `scaling_max_freq == cpuinfo_max_freq` 的簇；
   已经被对方改低的值保持不动。
4. **不要把满频当成 Scene 的基线。** 如果进入性能模式时四簇都已经是硬件最大值，快照要写 Scene `fast`
   值，而不是当前满频，否则均衡模式会一直停在满频。
5. **省电优先于性能。** 省电/极省电/`low_power` 任一打开就交给澎湃，不要在省电模式里抬频。
6. **写 sysfs 前后要恢复权限。** `scaling_max_freq` 的 mode 因簇而异，写入时临时 0644，写完恢复原值。

## 8. 注意

- 只在性能模式下解锁；均衡/省电只做一次交接，之后不写。
- 不覆盖 thermal-engine 已经生效的热档；如果后盖进入 37–53℃ 的原厂热档，仍会按原厂曲线降频。
- 不碰 GPU 的 `devfreq/max_freq`；GPU 温控仍由 `TB710FUThermal` 的性能/均衡配置管理。
- 如果 Scene 云端更新了 `fast` 方案，`pre_caps` 不存在时的兜底值可能变；当前硬编码的是本机 Scene
  `fast.app` 的 1804800/2841600/2841600/2995200。
