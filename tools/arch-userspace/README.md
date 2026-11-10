# TB710FU Arch 用户态脚本与配置（可直接部署）

本目录是从平板 `/etc`、`/usr/local`、`~/.config` **原样导出**的脚本与配置，
按功能分组。安装用 `install-userspace.sh`（幂等、带 `.before-<时间戳>` 备份）。

```
arch-userspace/
├── audio/     PipeWire/WirePlumber、DP 音频路由、扬声器初始化与监控
├── power/     电源键、s2idle、80% 限充、RTC 同步、DP 唤醒
├── thermal/   tb-thermal-guard v5（纯电池限频）、温度条 widget、CPU boost、governor
├── storage/   zram-generator、swappiness
├── display/   原生 DSI 面板加载顺序、DPMS
├── sensors/   hexagonrpcd 状态树准备
├── tools/     取证与自救工具（stackdump/cycle/kmsg-tap/FF/krfb/DP）
├── attic/     实验或已退役版本（不安装）
└── install-userspace.sh
```

## 快速安装

```bash
sudo ./install-userspace.sh                 # 当前系统
sudo ROOT=/mnt/root ./install-userspace.sh  # 已挂载的 rootfs
```

安装后仍需手动：加入 `realtime` 组、启用用户级 `tb-dp-sink-ensure`、
mask `tb-speaker-keepalive`（详见脚本末尾输出）。

## 分组说明

### audio
| 文件 | 目标路径 | 作用 |
|---|---|---|
| `56-tb710fu-audio.conf` | `/etc/wireplumber/wireplumber.conf.d/` | 禁用 UCM，强制 `pro-audio`；扬声器节点属性、不自动挂起 |
| `58-tb710fu-dp.conf` | `~/.config/wireplumber/...` | 把 `pro-output-1` 命名为 `TB710FU HDMI/DP` |
| `59-tb710fu-noautolink.conf` | `~/.config/wireplumber/...` | 采集不随播放自动拉起（防 TDM/功放重配） |
| `61-tb-alsa-buffer.conf` | `~/.config/wireplumber/...` | 5 期缓冲 + 1024 headroom（抗 XRUN） |
| `99-tb-no-ucm.conf` | `~/.config/wireplumber/...` | 双保险关闭 UCM |
| `tb-audio-init` + `.service` | `/usr/local/sbin` + systemd | 开机路由 MultiMedia1→SECONDARY_TDM_RX_0，开 4 颗 AW882xx |
| `tb-audio-watch` + `.service` | `/usr/local/bin` + systemd | 长期记录 dmesg/PCM 状态/XRun 到 `/var/log/tb-audio/watch.log` |
| `tb-dp-audio` + `.service` | `/usr/local/sbin` + systemd | 打开 `DISPLAY_PORT_RX_0 Audio Mixer MultiMedia2`（幂等，不开 PCM） |
| `71-tb-dp-audio.rules` | `/etc/udev/rules.d/` | DP connector change 时重跑 `tb-dp-audio` |
| `tb-dp-sink-ensure` + user `.service` | `/usr/local/bin` + user systemd | 登录后轮询最多 60 s 等 DP link-up，`pro-output-1` 仍缺则重启一次 PipeWire |

### power
| 文件 | 作用 |
|---|---|
| `10-tb710fu-powerkey.conf` | `HandlePowerKey=ignore` / `HandlePowerKeyLongPress=ignore` |
| `tb710fu-s2idle.conf` + `50-tb-s2idle.conf` | `MemorySleepMode=s2idle` 双保险持久化 |
| `tb-charge-limit` + `.service` + `charge-limit.conf` + sleep hook | 开机/resume 后延迟重写 80% 限充（绕开 0x48 早期写入竞态） |
| `tb-hwclock-sync.*` | 定时把系统时间写回 RTC（SDAM offset） |
| `tb-dp-wake-fix` | 唤醒后如果显示器掉了 HPD，重新协商 alt mode |

### thermal
| 文件 | 作用 |
|---|---|
| `tb-thermal-guard` + `.service` + `thermal-guard.conf` | **纯电池温控 v5**：38/39/40 °C 写 `scaling_max_freq`（X4 2.63/2.30/2.04 GHz），40.5 °C 最低频、40.9 °C 停充，0.5 °C 回差；不再读 CPU 温度/写 cdev |
| `widget/org.tb710fu.batterytempbar/` + `widget/tb-batt-read` | 面板双行温度条（上电池、下 CPU）；helper 装到 `~/.local/bin/tb-batt-read`（QML 硬编码该路径） |
| `tb-cpu-boost` + `.service` + `cpu-boost.conf` | X4 硬件 boost（3052.8 → 3302.4 MHz） |
| `tb-cpufreq-governor` + `.service` + `cpu-governor.conf` | 固定 schedutil |

> v3 的 `tb-thermal-guard` 与 `thermal-guard.conf` 已退役，放在 `attic/tb-thermal-guard.v3`、
> `attic/thermal-guard.conf.v3`，只用于回滚，不进默认安装列表。

### storage
| 文件 | 作用 |
|---|---|
| `zram-generator.conf` | zram0 = min(RAM, 8 GiB)，zstd（2026-11-08 起；需配套 v31 `zram.ko d6045fa9…`），swap 优先级 100 |
| `99-zram.conf` | `swappiness=180`、`page-cluster=0`、`watermark_boost_factor=0`、`watermark_scale_factor=250`（2026-11-09 由 125 提升）、`dirty_ratio=10`、`dirty_background_ratio=5` |
| `earlyoom` | `/etc/default/earlyoom`：去掉 `-n`（dry-run），`-m 8 -s 5` 真杀 |
| `lru-gen.conf` | `/etc/tmpfiles.d/lru-gen.conf`：MGLRU `min_ttl_ms=1000` |
| `app.slice.d/50-memory.conf`、`session.slice.d/50-memory.conf` | 用户级 cgroup：`app.slice MemoryHigh=4G`、`session.slice MemoryLow=1G` |

### display
| 文件 | 作用 |
|---|---|
| `tb710fu-display.conf` | blacklist/install=false 阻止 udev 提前加载 msm/panel/背光 |
| `tb-native-display` + `.service` | 固定顺序加载 aw37503→sy7758→dispcc→panel→msm，并做一次 DRM off/on 解决 panel latch |
| `tb-panel-cycle-py` | 上述 DRM off/on 的实现 |

### tools
`tb-stackdump`（逐任务 `/proc/<tid>/stack`）、`tb-cycle`（3 轮 suspend 自检）、
`tb-kmsg-tap`（0.5 s sync 落盘）、`tb-hangdump`、`tb-dpwatch`、`tb-dp-off/on/toggle`、
`tb-msm-swap`/`tb-mux-swap`（模块 A/B）、`tb-ff-restart`/`tb-ff-diag`、
`tb-vk-restart`（v3：登录 +6s 只切一次）、
`tb-vk-restart.desktop`（装到 `~/.config/autostart/`）、`tb-krfb-start`/`tb-krfb-stop`。

## 注意

- **不要 `systemctl restart systemd-logind`**：会踢掉当前图形会话（实测）。
- `tb-speaker-keepalive` 默认 **masked**：破音主因是 RT 调度，keepalive 只是减噪。
- `tb-charge-limit` 的 unit 仍写 `After=multi-user.target tb-thermal-guard.service`（历史顺序）；
  v5 不再写 `charge_control_end_threshold`，两者没有数据耦合。
- `tb-phy58.service`、`tb-dp-mode-keep`、`tb-dp-bootgate`、`tb-usb-*` 属于实验/调试，
  不在默认安装列表里。
- `~/.config/autostart/*.desktop.disabled` 仍会被 systemd 的
  xdg-autostart-generator 执行；真要禁用请把文件移出 autostart 目录，或让文件名里
  不再出现 `.desktop`（详见 `docs/06-arch-userspace.md` §6.5 与 `docs/11-lessons.md`）。
- 虚拟键盘脚本的现行版本是 `tools/tb-vk-restart`（v3，只 +6s 一次）；旧 v2 备份
  不随包分发，需要时从设备的 `/usr/local/bin/tb-vk-restart.v2-3toggles.bak` 取。
