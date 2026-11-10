# 06 — Arch 用户态：音频、电源、温控、内存、显示与桌面

> **前提**：Arch 已安装并能从 kShimC 菜单启动（`df /` = `/dev/sda15`）。首次安装、
> 分区、NBD 试跑、rsync 见 [00-install-paths.md](00-install-paths.md) §3；内核/boot
> 打包见 [05-arch-kernel.md](05-arch-kernel.md)。本文只讲装好之后要补什么。

> 一键安装：`sudo tools/arch-userspace/install-userspace.sh`
> 覆盖范围：P0/P1/P2；实验性单元（`tb-phy58`/`tb-dp-mode-keep`/`tb-dp-bootgate`/`tb-usb-*`）
> **不启用**。所有同名旧文件先备份为 `.before-<时间戳>`。
>
> 文中提到的部分历史调试脚本（`tb710fu-mic-path`、`tb-scrcpy-hw`、`tb-touch-rollback`、
> `tb-hbr2-watch`、`tb-usb-*` 等）**未随仓库发布**；以 `tools/arch-userspace/` 实际文件
> 为准。这些工具的**等价排查思路**（观测点 + 判据）见 [§8.1](#81-未发布脚本等价排查思路只给判据不给脚本)。

---

## 1. 安装与重刷后补装

```bash
cd tools/arch-userspace
sudo ./install-userspace.sh
# 或装进已挂载的 rootfs
sudo ROOT=/mnt/root ./install-userspace.sh
# 用户名不是 ALARM 默认的 archlinux
sudo USER_NAME=<user> USER_HOME=/home/<user> ./install-userspace.sh
```

> ALARM 的 `latest` tarball 不带完整 pacman local DB。用它修复现有系统时不要直接
> `pacman -Syu`：先用缓存里的精确版本包 + `pacman -U/-S --dbonly` 只补元数据，再 `-Syu`
> 接管（见 §7.1）。

装完按提示手动做：

```bash
sudo usermod -aG realtime <user>          # PipeWire 实时调度
systemctl --user enable --now tb-dp-sink-ensure
systemctl --user mask --now tb-speaker-keepalive   # 当前策略：不保留 limiter
```

**重刷 rootfs 后必装**（否则已知故障复发）：

| 文件 | 丢了会怎样 |
|---|---|
| `10-tb710fu-powerkey.conf` | 短按电源键直接关机 |
| `tb-charge-limit` + service + conf + sleep hook | 充到 100%，电池长期满电 |
| `tb-thermal-guard` + service + conf | 电池高温无用户态限频 |
| `tb-dp-audio` + service + udev | 外接屏无音频 |
| `tb-dp-sink-ensure` + user unit | 插着 DP 但只有扬声器 sink |
| `56/58/59/61/99-*.conf` | UCM 风暴/破音/DP sink 异常 |
| `tb-audio-init` + service | 扬声器无声/路由错 |
| `tb710fu-display.conf` + `tb-native-display` | 冷启动黑屏/花屏 |
| `tb710fu-s2idle.conf` + `50-tb-s2idle.conf` | 重启回 `deep` |
| `zram-generator.conf` + `99-zram.conf` | 内存行为退化 |
| `earlyoom` + `lru-gen.conf` + cgroup slice | OOM/MGLRU 失效 |

---

## 2. 音频

### 2.1 方案：禁 UCM + pro-audio

- 本机没有 TB710FU 的 UCM profile；UCM 会触发 PCM-open 风暴 → ADSP `audio_process`
  断言 → 17.9 s / 29.9 s 硬件复位。
- 因此：`use-ucm=false`，走 `pro-audio`；
  - `pro-output-0` = MultiMedia1 = 扬声器（SECONDARY TDM，4× AW882xx）；
  - `pro-output-1` = MultiMedia2 = DP/HDMI。
- UCM 文件只改名 `.disabled`，可回退。

### 2.2 关键文件

| 文件 | 作用 |
|---|---|
| `/etc/wireplumber/wireplumber.conf.d/56-tb710fu-audio.conf` | 禁 UCM、pro-audio、suspend-timeout=0 |
| `58-tb710fu-dp.conf` | DP sink 命名 |
| `59-tb710fu-noautolink.conf` | 采集不随播放自动 link |
| `61-tb-alsa-buffer.conf` | 5 期缓冲 + headroom |
| `99-tb-no-ucm.conf` | 双保险禁 UCM |
| `/usr/local/sbin/tb-audio-init` | 开机 TDM/功放路由 |
| `/usr/local/bin/tb-audio-watch` | XRUN/功放日志 |
| `/usr/local/bin/tb710fu-mic-path` | 麦克风路径（历史调试脚本，未随仓库发布；等价判据见 §8.1.1） |

### 2.3 RTKit 与缓冲

```bash
pacman -S --needed rtkit realtime-privileges
sudo usermod -aG realtime <user>
systemctl --user restart pipewire wireplumber
ps -eLo cls,rtprio,ni,comm | grep -E 'pipewire|data-loop'
# 期望：data-loop.0 = RR/20（之前是 TS/nice 0）
```

- 3×20 ms 缓冲扛不住 Firefox/KWin 突发；改 5 期 + `api.alsa.headroom=1024`。
- 满 CPU 负载播 60 s 实测零欠载。

### 2.4 麦克风

- `swr2` 的 DAI0 只有 playback；采集必须用 DAI1：
  `<&wcd939x 1>, <&swr2 1>, <&lpass_txmacro 0>`。
- DTS 已修；麦克风路径由 DTS `<&swr2 1>` 提供，历史用户态脚本 `tb710fu-mic-path`
  未随仓库发布（需要时按 §8.1.1 的分层判据手动验证）。

### 2.5 DP 音频

- tplg 追加 `DISPLAY_PORT_RX_0` 子图；
- mixer 控件 `DISPLAY_PORT_RX_0 Audio Mixer MultiMedia2` = on；
- `tb-dp-audio.service` + udev 在 DP 出现时打开路由；
- `tb-dp-sink-ensure` 轮询 60 s，等 `card*-DP-*/status=connected` 后必要时重启一次
  PipeWire（冷启动竞态）。

### 2.6 验收

```bash
wpctl status | grep -E 'TB710FU|HDMI'
grep -c 'state=XRUN' /var/log/tb-audio/watch.log      # 0
journalctl -k -b | grep -c "audio_process' crash"      # 0
```

---

## 3. 电源、睡眠、充电

### 3.1 电源键

`/etc/systemd/logind.conf.d/10-tb710fu-powerkey.conf`：

```ini
[Login]
HandlePowerKey=ignore
```

短按只锁屏（PowerDevil `PowerButtonAction=32`），不关机。长按 10 s 的 PMIC 硬复位
无法软件禁用。

### 3.2 睡眠

- `mem_sleep = s2idle`（`/etc/systemd/sleep.conf.d/tb710fu-s2idle.conf`）；
- `deep` 历史上丢 RTC/不唤醒；
- 带 HDMI 坞：v30+ 的两级 hub 可跨 s2idle；A27U 直连的内置 USB2 hub 仍掉（显示器侧）；
- `systemd-suspend.service` 不要 mask。

### 3.3 80% 限充

```bash
cat /etc/tb710fu/charge-limit.conf     # end=80 start=70
systemctl status tb-charge-limit
cat /sys/class/power_supply/battery/charge_control_end_threshold
```

机制：

- `qcom_battmgr` 对 `0x48` 的响应硬编码成功；开机早期写入会被驱动缓存、固件不执行；
- `tb-charge-limit` 在开机/resume 延迟重写；
- 会话/UPower 已选有效值时优先用会话值。

### 3.4 RTC

- 不要写「把系统时间写回 RTC」：APPS 写 pm8xxx RTC 会被 SPMI 仲裁器的 APID 权限表拒绝
  （`disallowed SPMI write ... addr=0x6146`，`RTC_SET_TIME` EPERM/ENODEV），硬件计数器照走；
- 实际只能写 SDAM `nvram@7100` 的 `rtc-offset@7c`（0x7C..0x7F，4 字节偏移）：
  `tb-hwclock-sync.timer` 每 5 min 把「系统时间 − RTC raw」写入该 offset，驱动读时做
  `raw + offset`；
- 健康检查：`epoch − RTC raw` 应恒等于 Arch 侧写入 SDAM 的 offset。

---

## 4. 温控 v5（纯电池限频）

`/usr/local/sbin/tb-thermal-guard` + `/etc/tb710fu/thermal-guard.conf`：

| 电池温度 | 动作 |
|---|---|
| ≥38 °C | X4 2.63 GHz / A720 2.38 / A520 1.80 |
| ≥39 °C | X4 2.30 / A720 2.13 / A520 1.46 |
| ≥40 °C | X4 2.04 / A720 1.82 / A520 1.25 |
| ≥40.5 °C | X4 1.5936 / A720 1.4976 / A520 1.0176 GHz（应急档） |
| ≥40.9 °C | 只写 `constant_charge_current=0` 停充；不动 `charge_control_end_threshold` |
| 回落 0.5 °C | 回差，逐级恢复 |

> 40.5 ℃ 的应急档是 OPP 就近取值后的实际频率，不是「全簇最低频」；40.9 ℃ 只停充，
> `charge_control_end_threshold` 留给 `tb-charge-limit` 的 80% 上限，避免互相覆盖。

设计依据：

- SoC 的 LMH 在 95 °C 已硬件降频；
- CPU 温区只有 110 °C critical，没有 passive trip；
- 因此**不再做用户态 CPU 闭环**，只按电池温度限 `scaling_max_freq`。

验收：

```bash
systemctl status tb-thermal-guard
cat /run/tb-thermal-guard/state        # batt_tier/cap0..cap5/t1..t3
cat /sys/devices/system/cpu/cpufreq/policy*/scaling_max_freq
```

> `htop`/`scaling_cur_freq` 是**请求值**；实际频率看 `cpuinfo_cur_freq`（LMH 回读）。

---

## 5. 内存与存储

### 5.1 生产参数

| 项 | 值 |
|---|---|
| zram | 6.8 GiB，zstd |
| `vm.swappiness` | 180 |
| `vm.page-cluster` | 0 |
| `vm.watermark_boost_factor` | 0 |
| `vm.watermark_scale_factor` | **250**（2026-11-09 由 125 提升） |
| `vm.dirty_ratio` / `dirty_background_ratio` | 10 / 5 |
| MGLRU | `0x0003`，`min_ttl_ms=1000` |
| earlyoom | `-r 60 -m 8 -s 5 --avoid (^|/)(init|systemd|Xorg|sshd)$`，**无 `-n`** |
| app.slice | `MemoryHigh=4G` |
| session.slice | `MemoryLow=1G` |

### 5.2 为什么 `watermark_scale_factor=250`

- 双屏一次 swapchain 突发约 110–170 MB；
- 125 时 Normal `low` 只有 110.8 MB，容易在突发中直接回收；
- 250 时 `low/high = 184.4/331.5 MB`，降低 Mesa batch cache 耗尽概率
  （不能根治上游活锁）。

### 5.3 验证

```bash
zramctl
sysctl vm.swappiness vm.page-cluster vm.watermark_scale_factor
cat /sys/kernel/mm/lru_gen/enabled
cat /proc/pressure/memory
systemctl status earlyoom
systemctl --user show app.slice -p MemoryHigh
```

### 5.4 文件系统

- root：btrfs `sda15` 120 GiB；
- swapfile：`/swap/swapfile` 4 GiB；
- 共享：`sda16 share` ext4 8 GiB → `/mnt/share`；
- `IgnorePkg = linux linux-aarch64 linux-firmware`（防 pacman 覆盖内核）。

---

## 6. 显示与桌面

### 6.1 模块加载顺序

`/etc/modprobe.d/tb710fu-display.conf` 固定 panel/backlight/touch 顺序；
`tb-native-display.service` 在启动时处理 panel latch。冷启动黑屏/花屏先查这里。

### 6.2 DPMS 背光

- 根因：`CONFIG_DRM=y + BACKLIGHT_CLASS_DEVICE=m` 让
  `drm_panel_of_backlight()` 变成空桩；
- 修法：面板模块直接 `devm_of_find_backlight()`；
- 只换模块，不刷 boot。

### 6.3 `keep_link=0`

- 关屏后 DPTX 不再一直驱动主链路；
- DPMS off 走 `psm(D3) + off_link + phy_exit`；下次 enable 完整 re-init；
- 若设 `Y`，A27U 每约 27 s 弹「无信号」。

### 6.4 Night Light / 色彩准确性

- 「色彩准确性」= `colorPowerTradeoff=PreferAccuracy`（合成阶段 shader 转换）；
- 「性能优先」= `PreferEfficiency`（下推 KMS）；
- 切换后 KWin 运行时颜色管线不会立即重建，**锁屏再解锁**可复位；
- 显示器 OSD 已设 sRGB 时，KWin 也选 sRGB，不要再套 ICC/EDID（双重转换）。

### 6.5 虚拟键盘

- `tb-vk-restart` v3：登录 +6 s 切一次 InputMethod，之后不再反复切；
- autostart 必须是 `.desktop`（systemd 也会执行 `.desktop.disabled`）；
- 平板模式 `kwinrc [Input] TabletMode=auto/on/off` 只影响电源键/自动旋转/Kirigami，
  不影响虚拟键盘；
- VSCodium flatpak 会强制 Wayland text-input-v3，是弹键盘的常见触发者；不需要就关
  「虚拟键盘 → Never」，但仍可能被 `lastInputHandler` 绕过；
- resume 钩子在 system-sleep post 阶段执行时 `user.slice` 仍冻结：`systemd-run --user`
  不可达，`su` 会报 "Cannot start frozen unit User Slice"；必须交给 `system.slice` 里带
  `User=` 的 transient unit，并延迟到解冻之后：
  `systemd-run --system --collect -p User=<user> -p Environment=HOME=... -p Environment=XDG_RUNTIME_DIR=... -p Environment=DBUS_SESSION_BUS_ADDRESS=... /bin/sh -c 'sleep 10; exec /usr/local/bin/tb-vk-restart'`；
- 测 resume 钩子必须用 `systemctl suspend`；`rtcwake -m mem` 直写内核、绕过 systemd-sleep，
  钩子根本不跑（可用 `rtcwake -m no -s N` 先设自动唤醒闹钟）。

### 6.6 krfb VNC

- 26.08.0–26.08.2 上游回归：GUI 路径不置 `passwordSet`；
- portal Response 竞态 + RFB 坐标缩放（物理 vs 逻辑 ×2.25）已打补丁；
- **修复在插件里**：必须同时替换 `/usr/lib/qt6/plugins/krfb/framebuffer/pw.so` 与
  `/usr/lib/qt6/plugins/krfb/events/xdp.so`，只换 `krfb` 二进制无效；
- krfb 是 `KDBusService::Unique` 单实例；起第二个实例（如 staging 测试）必须先停第一个；
- 按需启动：`tb-krfb-start` / `tb-krfb-stop`；
- **先在 KDE 共享设置里设自己的密码**；仓库不提供密码。

### 6.7 CJK 字形

`LANG=C` 时会选到 Noto Sans CJK KR/JP；host + flatpak 都加 SC 规则。
验收：`fc-match 'sans-serif:lang=zh-cn'` 应命中 SC。

### 6.8 Firefox VA-API

三件套：

1. 内核 iris 补丁（0018）；
2. `qcom-va-driver` 放 `/var/lib/dri`（flatpak 保留 `/usr`）；
3. `MOZ_DISABLE_RDD_SANDBOX=1`（RDD 沙箱拒绝 `/dev/video*`）。

> Firefox 自带的 V4L2-M2M 路径在 iris 上会「假成功」：打印 `V4L2 FFmpeg init successful`
> 之后第 1 帧就因 pts=NOPTS 被拒（`rejects requested type 'video/avc'`），然后静默回软解。
> 不要用 init 日志验收；看 `MOZ_LOG=PlatformDecoderModule:5,FFmpegVideo:5` 的真实解码路径
> 和 RDD CPU。

验收：`about:support` 显示 `vaapi`；B 站播放时 `iris` 中断增长、RDD CPU 3% 左右。

### 6.9 scrcpy

```bash
LIBVA_DRIVERS_PATH=/var/lib/dri scrcpy --hwdec=auto --video-codec=h264
# 历史 tb-scrcpy-hw 只是包装同样的参数；判据（vainfo/CPU）见 §8.1.2
```

### 6.10 KDE 密钥环（KWallet / Secret Service）

libsecret 调用永久挂起时按三层根因查（Chromium 另做隔离）：

- `~/.local/share/kwalletd/` 没有钱包：首次使用会弹「创建钱包」模态框，无人值守等于挂死；
  离线生成**空密码** `Default keyring.kwl` 并部署（0600），钱包名必须与 `kwalletrc` 里的
  `Default keyring` 逐字节一致（含大小写和中间空格）；
- KWallet 的 SHA1 是**非标准实现**（小端机器上不做字节交换，`SHA1("")` 也不是标准值），
  密钥派生和完整性摘要都要用它算，标准 SHA1 生成的钱包会被判「密码错」；
- Arch 的 kwallet 包缺 `org.freedesktop.secrets` 的 D-Bus 激活文件：补
  `/usr/share/dbus-1/services/org.freedesktop.secrets.service`（`Exec=/usr/bin/ksecretd`），
  否则客户端直接报 `The name is not activatable`；
- Chromium 保留 `--password-store=basic` 做隔离，避免密钥环故障再次拖死导航。

### 6.11 Firefox 排障三板斧

- `about:cache` 作 privileged 进程对照：能秒开渲染 = 进程/渲染层没问题，问题在页面自身；
- `MOZ_LOG=PlatformDecoderModule:5,FFmpegVideo:5` 看真实解码路径，不要只看 `init successful`；
- WebDriver BiDi 读 `readyState`/`bodyLen`/`href`（参数 camelCase、`awaitPromise`）；但对
  `about:` 页导航可能被拒并落 `about:blank`，结果不能当真；
- `--new-tab` 启动参数和 BiDi 新建的标签都不等于真实 UI 路径；端到端点击验证用 krfb VNC 指针。

### 6.12 双浏览器「打开就卡」是启动尖峰

7 GB 内存占用（Firefox 2G + Chromium 1.3G + Plasma 0.9G 等）时再开浏览器，18 个进程同时
spawn 会把 `PSI some avg60` 冲到 7% 再回落；这不是 OOM。优先降载（收敛标签、关
Discover/systemsettings、开 Chromium 内存节省），不要先加 swap 或改 watermark。

---

## 7. 桌面软件生态

### 7.1 ALARM `latest` tarball 与 pacman local DB

ALARM 的 `latest` tarball 只带很小的本地 pacman DB。用它修复现有系统时不要直接
`pacman -Syu`（会按残缺 DB 算依赖，可能误判/降级）：

1. 用 pacman 缓存里的精确版本包（或同版本仓库下载）；
2. `pacman -U --dbonly <包>` / `pacman -S --dbonly <包>` 只写入元数据、不覆盖文件；
3. DB 补齐后再 `pacman -Syu` 正常接管。

> `--dbonly` 只适合「文件已经在位、只缺数据库记录」的场景；缺文件仍要正常安装。

### 7.2 OBS Studio

- ALARM 官方仓库和 Flathub 都没有 aarch64 的 OBS；用 AUR `obs-studio-tytan652` 源码构建；
- 本机保留系统 `ffmpeg`，要把 PKGBUILD 的 `ffmpeg-obs>=9` 改成 `ffmpeg>=9`；
  **每次升级 OBS 都要重打这一行**（AUR 升级会覆盖 PKGBUILD）；
- 录屏画布设 3200×2000，否则默认 1920×1080 画布只覆盖屏幕中央。

### 7.3 VLC

ALARM 把 VLC 拆成几十个 `vlc-plugin-*` 子包；只装 `vlc` 元包不带 FFmpeg 解码插件，
H.264/HEVC 会报 "could not decode h264"。补 `pacman -S vlc-plugin-ffmpeg`。

### 7.4 Blender

- 官方没有 Linux arm64 构建（builder.blender.org、Flathub、snap 都只有 x86_64），只能源码构建；
- EEVEE 重负载下 freedreno OpenGL 约 2.3 s/帧，Turnip Vulkan 约 4.8–5.0 s/帧（约 2 倍）：
  保持默认 OpenGL，Turnip 留给其他 Vulkan 应用；Cycles 走 CPU。

### 7.5 LM Studio

- 官方 linux-arm64 运行时没有 Vulkan 后端，GPU 推理要用自编 llama.cpp；
- mtmd 视觉路径在 ARM64 上会卡死，多模态/OCR 必须用 llama.cpp 原生引擎。

### 7.6 scrcpy

必须 `LIBVA_DRIVERS_PATH=/var/lib/dri`（`qcom_drv_video.so`/`msm_drv_video.so` 装在那里），
否则 `--hwdec=auto` 静默回软解；历史 `tb-scrcpy-hw` 包装器未随仓库发布，等价做法与判据
见 §8.1.2。

---

## 8. 取证/自救工具

| 工具 | 用途 |
|---|---|
| `tb-kmsg-tap` | 0.5 s `sync`，硬复位不丢日志 |
| `tb-stackdump` / `tb-hangdump` | 逐任务 `/proc/<tid>/stack` |
| `tb-cycle` | 3 轮 suspend 自检 |
| `tb-dpwatch` | DP 状态/HPD 观测 |
| `tb-dp-off` / `tb-dp-on` / `tb-dp-toggle` | DP 手动开关 |
| `tb-msm-swap` / `tb-mux-swap` | msm/mux 模块 A/B |
| `tb-ff-restart` / `tb-ff-diag` | Firefox 卡死自救 |
| `tb-touch-rollback` | 触摸模块回退（未随仓库发布；只能换 `.ko` + 重启，见 §8.1.3） |
| `tb-hbr2-watch` | HBR2 观测（未随仓库发布；等价 `dp_debug` 判读见 §8.1.4） |
| `phyreg` | eUSB2 PHY 寄存器 poke（实验，未随仓库发布） |

### 8.1 未发布脚本：等价排查思路（只给判据，不给脚本）

下面这些包装器当时是一次性排障工具，依赖临时路径/设备状态，没有随仓库发布。
**思路可以复现，脚本不必复现**——按下面的观测点自己做，结论是一样的。

#### 8.1.1 麦克风路径（`tb710fu-mic-path`）

现象：录音全零、只有底噪；AGC（相机）录像没有声音。

按**四层**依次排除，不要跳层：

1. **DTS 绑定**（最常见）：`swr2` 的 DAI0 是 **playback-only**，采集必须用 DAI1。
   在 DTS 里应是 `<&wcd939x 1>, <&swr2 1>, <&lpass_txmacro 0>`；写成 `<&swr2 0>` 时
   驱动能起来、`arecord` 也不报错，但数据永远是 0。
   核对：`dtc -I dtb -O dts <你的 dtb> | grep -B2 -A6 'swr2'`。
2. **有没有 capture 端点**：`arecord -l` 应能看到对应 card 的 capture device。
   看不到 = DAI link 没建起来，回到第 1 层。
3. **抓 2 秒 PCM 看是否全零**：
   `arecord -D hw:<card>,<device> -f S16_LE -r 48000 -c 2 -d 2 /tmp/t.wav`
   然后 `sox /tmp/t.wav -n stat` 看 `Maximum amplitude` / `RMS`。
   全零 = 上游 DAI/时钟没走；有值但很小 = 模拟增益/micbias 侧。
4. **路由与增益**：`amixer -c <card> contents | grep -iE 'ADC|MIC|TX'`；
   pro-audio 下控件名与普通 UCM 不同，用 `pactl list sources short` 对照。

> 判据组合：第 1 层错 → 全零且不报错（最像“驱动坏了”，其实没坏）；
> 第 2 层错 → `arecord -l` 缺设备；第 3 层有波形但小 → 才去看增益。

#### 8.1.2 scrcpy 硬解（`tb-scrcpy-hw`）

那个包装器其实只做三件事：设 `LIBVA_DRIVERS_PATH`、指定 H.264、传 `--hwdec`。
手工等价操作：

```bash
ls -l /var/lib/dri/qcom_drv_video.so        # 驱动在不在（在 /var/lib/dri，不在 /usr/lib/dri）
LIBVA_DRIVERS_PATH=/var/lib/dri vainfo | grep -i H264High
LIBVA_DRIVERS_PATH=/var/lib/dri scrcpy --hwdec=auto --video-codec=h264
```

判据：

- `vainfo` 没有 `VAProfileH264High` = 驱动/路径不对，`--hwdec` 只会静默回软解；
- 播放时对照 CPU：硬解 <2%，软解 5–8%（同分辨率帧率）；
- 只有 H.264 走 qcom V4L2 稳；HEVC 不一定有对应 profile，别用“没报错”当成功。

#### 8.1.3 触摸回退（`tb-touch-rollback`）

**为什么没有脚本**：`nvt_36xxx` 热卸载会在 `platform_device_unregister` 里解引用空指针
（refcnt 已经 -1），触摸直接消失、直到重启；`rmmod` 和 sysfs `unbind` 是同一条路径。
所以“回退”只能是**换 `.ko` + 重启**，没有运行时方案。

做法：

```bash
sha256sum /lib/modules/$(uname -r)/kernel/drivers/input/touchscreen/nvt_36xxx.ko
# 从上一版 boot/模块目录取回旧 .ko 覆盖 -> depmod -> reboot
```

验收：`dmesg | grep -i nvt` 无 Oops；`/proc/bus/input/devices` 有触摸设备；`getevent -pl`
能看到 ABS_MT 事件。**不要**在设备上试 `rmmod nvt_36xxx`。

#### 8.1.4 HBR2 / DP 链路观测（`tb-hbr2-watch`）

`tb-hbr2-watch` 只是“每 N 秒 dump 一次链路状态”。等价做法：

```bash
cat /sys/kernel/debug/dri/*/dp_debug        # 只看这个；dp_test_* 一读就 Oops
```

关注字段与判读：

| 字段 | 含义 | 正常/异常 |
|---|---|---|
| `rate=` | 链路速率（kHz） | 162000/270000 = RBR/HBR；540000 = HBR2；810000 = HBR3 |
| `lanes=` | lane 数 | 直连 4、坞 2（本机实测） |
| `bpp=` | 每像素位数 | 24 = 8bpc；18/16 = 6bpc（黑屏高发） |
| `p_level=` | 链路训练档位 | 稳定时为 0；`1` 且 `test_req=unknown` = 失败签名 |
| `test_req=` | 训练请求 | `unknown` + p_level 非 0 = 训练没走完 |

动态观测用 `udevadm monitor --subsystem-match=drm` 或 `dmesg -w | grep -iE 'dp|hpd'`。
判定“稳不稳”要看**同一份插拔序列的多次 dump**，单次好看的数值不算。

#### 8.1.5 `tb-usb-*` 与 `phyreg`

- `tb-usb-*`（host/device 强制、DPM 改动）：**不要复刻**。用户态钉 host 会在拔线瞬间
  重建 xHCI，把 greeter 一起拖崩（见 [11-lessons.md](11-lessons.md)）。需要断电/关屏只用
  仓库里有源码的 `tb-dp-off`/`tb-dp-on`。
- `phyreg`：eUSB2 PHY 寄存器 poke，属于“能一次把链路弄死、且没有回滚”的实验；不发布，
  也不建议照抄网上的同类脚本。

---

## 9. 回退

| 目标 | 操作 |
|---|---|
| 音频回 UCM（不推荐） | 恢复 `56-...conf.ucm-trial` + 把 UCM `.disabled` 改回 |
| 限充 | `systemctl disable --now tb-charge-limit` + 删 sleep hook |
| 温控 | `systemctl disable --now tb-thermal-guard`；要回 v3 用 `.v3` 备份 |
| 电源键 | 删 `10-tb710fu-powerkey.conf`，重启 logind（会踢会话，建议重启） |
| 虚拟键盘 | `systemctl --user disable --now tb-vk-restart` + 删 autostart |
| 共享分区 | `systemctl disable --now tb-share-fixperm` + `umount /mnt/share` |

> 不要 `systemctl restart systemd-logind`（会踢掉图形会话）；改 logind 配置后直接重启。
