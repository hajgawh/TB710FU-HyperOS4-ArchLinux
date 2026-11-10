# 10 — 排错：症状 → 根因 → 修法

> 先按 `docs/01-overview.md` §3 的 L1–L4 分层定位：引导 / OS4 / Arch 内核 / 用户态。
> 不要跨层猜；每层都有可观测信号。
> 命令里的 `<serial>`、`<device-ip>` 是占位符。
>
> 部分历史调试脚本（`tb710fu-mic-path`、`tb-scrcpy-hw`、`tb-touch-rollback`、
> `tb-hbr2-watch`、`tb-usb-*`）**未随仓库发布**；对应的**等价排查思路**（观测点 + 判据）
> 见 [06 §8.1](06-arch-userspace.md#81-未发布脚本等价排查思路只给判据不给脚本)。
> 表里写“未随仓库发布”时，先去那里找判据，不要去网上找同名脚本。

---

## 1. 引导与刷机

| 症状 | 根因 | 修法 |
|---|---|---|
| 进不了 9008，`edl` 连不上 | 只接充电线/没进 9008/hub | 关机拔线 → 长按电源 15–20 s → 按住音量 +/− 插线；直连主机 |
| `edl reset` 参数错误 | `reset` 不接受 `--memory` | 只传 `--loader` |
| 刷 super 卡住/中断 | 线/hub/主机睡眠/电量低 | 换线直连；电量 ≥30%；重进 9008；不要重复写 |
| 刷完卡开机动画 | super 与 /data 不兼容、启动链不匹配、写坏 | 回刷 `rollback_*`；写回 boot 链备份；最后 ZUI 救援 |
| 开机直接进 fastboot/9008 | boot 链哈希/AVB 不匹配 | 写回 `boot_a`/`vbmeta_a` 备份 |
| 首次只刷了 super，卡 fastboot/动画 | 没写 v3 启动链（testkey vbmeta/flags=1） | 按 [00 §3.2](00-install-paths.md) 写 v3 五件，再刷 super |
| 首次没 `--wipe`，卡解密/循环开机 | 旧 `/data` 与新 system/vendor 不兼容 | 只首次重刷 `flash_super.sh ... --wipe`；升级不要 |
| 按 08 执行 `sgdisk -d 15` 报错/删错分区 | 盘上还没有 `sda15` | 停止；先按 [00 §3.5](00-install-paths.md) 离线缩 userdata/建分区 |
| 缩 userdata 后 Android 要求重置 | f2fs + FBE 不能在线缩，头被清零 | 预期行为；数据不可恢复，完成重置即可 |
| NBD 起不来 / 找不到 `172.16.42.x` | nbd-server 用了 `-d`、镜像不是 512B MBR、主机睡了 | 用常驻模式；`-b 512`；`caffeinate`；检查 `10809` 和导出名 `archlinux` |
| 切 B 槽后黑屏 | `_b` 全 0 extent | 切回 `_a`；不要用 B |
| `SUPER METADATA OK` 但有分区不匹配 | manifest 与镜像不一致 | `check_super.py` 重验；重新组装 |
| 向导 `cloudsp_fid 参数不能为空` | 查找设备需要小米 TEE | `TB_NO_FINDDEVICE=1` 过向导，再脏刷正常 super |
| PIN 永远解不开 / `IKMHal_sendCmd status -30` | 恢复了旧 userdata | 只能清 data；不要恢复旧 userdata |

---

## 2. OS4 包内

| 症状 | 根因 | 修法 |
|---|---|---|
| 字体页 100% 但字小 | 旧 0.85 + `uiMode&15` 早退 | 确认 `/system/etc/tb710fu_bootfix.sh` 存在且 0755；`settings get system font_scale` |
| R 角 10px | 旧 product/Corner40 | 卸载 Corner40；确认 `DevicesOverlay` 40px；`TB_CORNER_PADDING=40` |
| 色彩反了 | 旧 jar 或旧 oat | 确认补丁 jar；删 `oat/*/miui-services.*` 后重启 |
| UI 物理变小 27% | 删了 `ro.sf.lcd_density=440` | 恢复 prop；不要在线 `wm density` |
| SystemUI 冻结/截图卡住 | 在线 `wm density`/`wm size` | `cmd window size reset`，重启 |
| 前置相机不能切 | role tag 缺失 | Aperture 默认值/前摄 id 1；MiuiCamera 已退役 |
| 相册查看崩溃 | `SpecialTypesProvider` 缺失 | 确认 stub provider 在 product |
| 双击亮屏/保护套失效 | prop 不对/节点没写 | 看 `gesture_wakeup_option`、`persist.sys.*`、`/proc/*` |
| 右边缘侧滑无效 | `panel_direction` 与旋转不符（OS4 横屏应为 1 不是 3）/App 在 letterbox/`game_edge`/`game_mode` 不对/launcher stub 竞态 | `getprop sys.tp.grip_enable; cat /proc/panel_direction`（横屏 90 应 Right Up/1）；`game_edge=0`、`game_mode=2`；看 `/data/local/tmp/tb710fu_landscape.log` 与 `dumpsys activity top` 的 `letterBoxed` |
| 触控自检 `Selftest FAIL` | 灭屏（`mWakefulness=Asleep`）时 `/proc/nvt_selftest` 直接返回 FAIL | 亮屏/awake 后重读；awake 下应 PASS（见 `12-os4-touch-backgesture.md` §2.1） |
| 充电上限无效 | `pc_mode` 没同步/守护没跑 | 看 `security_pc_secure_protect_mode_key`、`persist.sys.pc_mode`、`ps` |
| 查找设备坏账号 | 联想固件没有小米 TEE | 永远不要打开 |
| 系统 OTA 后异常 | 覆盖了移植包 | 不要在设备上点 OTA；重刷 super |

---

## 3. KSU / 模块

| 症状 | 根因 | 修法 |
|---|---|---|
| `su` 没有 | 只文件修补/没开 ADB Root | app 内直接安装 → 重启 → 设置 ADB Root |
| 模块装不上 | zip 结构/ksud 权限 | 看 `ksud module install` 输出；确认 root |
| 模块开机不生效 | `service.sh` 子进程被收割 | 用 `busybox setsid sh` |
| 性能模式无变化 | 没切 HyperOS 性能模式/热档更高 | 看 thermal.log/cpumax.log |
| GPU 锁 500 MHz | 原厂 `skin-msm-therm` 51 ℃ 第 4 档 | 切性能模式或降温；不是模块锁死 |
| CPU 锁 2112 MHz | 原厂 `rear-tof-therm` 46 ℃ 第 4 档 | 同上 |
| Debloat 后应用消失 | 包级卸载/组件冻结 | `restore.sh`/`action.sh` 或卸载模块重启 |
| 停用 Debloat 没恢复 | 停用 ≠ 恢复 | 必须跑 restore/action |
| 共享分区只读 | `mount -o context=` 被 SELinux 拒 | 模块 v1.1 已改 chcon；不要加 context |
| 卸载模块后 bind mount 还在 | 未重启 | 重启 |

---

## 4. Arch 内核 / 启动

| 症状 | 根因 | 修法 |
|---|---|---|
| 模块 vermagic 带 `+` | 没显式 `KERNELRELEASE` | 所有 make 加 `KERNELRELEASE=7.3.0-tb710fu` |
| 刷 boot 后不进 Arch | Image/DTB 不匹配/GKI 错 | 回备份；确认 GKI 6.1.128 |
| 冷启动黑屏/花屏 | 面板 latch/模块加载顺序 | `tb-native-display`、`tb710fu-display.conf` |
| 触摸消失 | `rmmod nvt_36xxx` | 只能重启；换文件后重启 |
| 触摸唤醒不灵 | 固件健康检查/上电时序 | 0017/0009 补丁；换模块后重启 |
| WiFi 休眠后不重连 | STA 未断开/ath12k | 0007 补丁；`tb-wifi.service`（历史脚本，未随仓库发布，可按需手动重载） |
| 蓝牙地址是 `00:03:7F…` | 未应用 0020/地址是占位符 | `set-bt-addr.sh` 改成自己的；重打 DTB |
| 蓝牙 bond 失效 | 地址变了 | 重配键盘/耳机 |
| RTC 1970 | 未启用 SDAM offset | 0014 + `nvmem-cells`；`tb-hwclock-sync.timer` |
| 空闲日志刷屏 | 调试打印 | v35b/v36；`TBMSC7/TBPNL7/TBBL7` 应为 0 |
| 模块加载失败 | vermagic/依赖 | `modinfo`、`depmod -a`、看 `dmesg` |

---

## 5. 显示 / DP / 外接屏

| 症状 | 根因 | 修法 |
|---|---|---|
| 锁屏后背光不灭 | 面板模块 `panel->backlight=NULL` | 用 DPMS 修复版面板模块；只换 `.ko` |
| 熄屏后每 27 s 弹无信号 | `keep_link=Y` | 设 N；DPMS 完整下电 |
| 外接屏无画面 | 链路/模式/线 | `dp_debug`；降 4K30/换线；检查 `p_level` |
| 换向/插拔硬复位 | DP 点亮落在枚举窗口 | v34 `tb_hpd_delay_ms=1000`；换向前 `tb-dp-off` |
| 坞 USB3 插上即断 | QMP COM 重建 | v32/v33；确认 `USB3DP↔USB3ONLY` 不重建 |
| 坞 USB3 只有 480M | SS 端口 polling 被打断 | v33e；换向前停 USB3 PCS |
| DP 音频没有 sink | tplg 缺子图/冷启动竞态 | `tb-dp-audio`；`tb-dp-sink-ensure` 轮询 |
| 切「色彩准确性」后偏色 | KWin 管线未重建 | 锁屏再解锁；OSD 设 sRGB 时不要再套 ICC |
| Night Light 黑屏 | KMS 颜色卸载 EINVAL | `colorPowerTradeoff=PreferAccuracy` |
| `dp_test_*` 一读就 Oops | `msm_dp_test_*_show` 未判空 | 只看 `dp_debug` |
| OS4 带 A27U 重启无信号 | vendor DP 首训时序 | 重启前拔屏；显示器断电 10 s；不要用 hpd debugfs |
| A27U 直连 s2idle 后 hub 掉 | 显示器侧切内置 hub | 拔插/断电；用 HDMI 坞 |

---

## 6. 音频

| 症状 | 根因 | 修法 |
|---|---|---|
| 扬声器无声/路由错 | TDM/功放未初始化 | `tb-audio-init`；`56` 规则；检查 `pcm0p RUNNING` |
| 破音/卡顿 | 无 RTKit → PipeWire 非实时 | 装 `rtkit` + `realtime-privileges`；5 期缓冲 |
| 稳态偶发噼啪 | 机制未移植（SPR/SPV5 + TDM VI） | **待定**；先按 `06-arch-userspace.md` §2 的取证步骤走 |
| 麦克风全零 | `swr2` DAI0 是 playback-only | 用 DAI1（DTS `<&swr2 1>`）；分层判据见 [06 §8.1.1](06-arch-userspace.md#811-麦克风路径tb710fu-mic-path) |
| 采集随播放自动拉起 | pro-audio 同组 auto-link | `59-tb710fu-noautolink.conf` |
| UCM 风暴/硬复位 | UCM ConflictingDevice | 禁 UCM（`.disabled` + `99-tb-no-ucm.conf`） |
| DP 无音频 | 缺 `DISPLAY_PORT_RX_0` 子图 | 追加 tplg + mixer；`tb-dp-audio` |
| 只有扬声器 sink | `tb-dp-sink-ensure` 早于 link-up | 轮询版；临时重启 PipeWire |
| 托盘/设置/wpctl 打架 | limiter 已移除但旧 sink 还在 | 确认唯一硬件 sink；mask keepalive |

---

## 7. 电源 / 充电 / 温控

| 症状 | 根因 | 修法 |
|---|---|---|
| 短按电源键关机 | logind `HandlePowerKey=poweroff` | 改 `ignore`；PowerDevil `PowerButtonAction=32` |
| 充电到 100% | 限充未重写 | `tb-charge-limit` 开机/resume 延迟重写 |
| `current_now` 充电时为负 | `qcom_battmgr` 原样上报，UPower 反判 | 不影响实际充电；看 `charge_now` |
| 关机后自动重启 | 插着 USB 时充电唤醒 | 拔线关机 |
| 电池高温不降频 | 只有 LMH 95 ℃/critical 110 ℃ | v5 纯电池限频；检查 `tb-thermal-guard` |
| 实际频率低于 scaling | LMH 回读 | 看 `cpuinfo_cur_freq`，不要看 `scaling_cur_freq` |
| 睡眠不醒/丢 RTC | deep suspend | 用 s2idle；带坞；不要快速两次 s2idle |
| 睡眠后 USB 不枚举 | xHCI/PHY/hub | v26/v30/v31；A27U 显示器侧需拔插 |
| 快速两次 s2idle 亮屏卡死 | hub 未恢复 → mux 0 → push_idle 超时 | 规避：`tb-dp-off/on`；不要快速反复 |

---

## 8. 内存 / 图形 / Firefox

| 症状 | 根因 | 修法 |
|---|---|---|
| 开浏览器整屏停 10–18 s，声音继续 | `msm_gem_shrinker` 等 GPU fence | v31+ `msm.ko`（非阻塞 shrinker） |
| 单个进程 `gdrv0` 100%、RSS 不动 | Mesa batch cache 32 槽活锁 | `tb-ff-restart`；`watermark_scale_factor=250` |
| GPU 缓冲分配失败 | 内存水位低 | 提高 watermark；关多余标签；earlyoom |
| OOM 杀错进程 | earlyoom dry-run | 去掉 `-n`；`-m 8 -s 5` |
| GUI 卡几秒 | zram 回收抖动 | zstd；PSI/MGLRU；swapfile |
| Discover 卡死/无后端 | portal 单实例 + appstream 无超时 | 用 `flatpak install`；`pkill` 精确 PID |
| Firefox 新标签页白屏 | trainhop 副本遮蔽 | 删 profile 副本 + `disableNewTabAsAddon` |
| Firefox 秒崩（flatpak） | host fontconfig cache 版本 | 自定义 `fonts.conf` 排除 host cache |
| B 站卡顿 | WebGL shader 不兼容/标签假死 | 见原始资料；不要归因 UFS |

---

## 9. 桌面 / 外设

| 症状 | 根因 | 修法 |
|---|---|---|
| 虚拟键盘不弹 | plasma-keyboard 生命周期卡死 | `tb-vk-restart`（v3：+6 s 一次）；托盘输入法图标 |
| 接键盘仍弹虚拟键盘 | KWin 6.8.2 只看 `lastInputHandler` | Never+托盘/改 KWin；不是平板模式问题 |
| krfb 不监听 5900 | `passwordSet` 回归 | 补丁版 krfb；先设密码 |
| VNC 鼠标错位 | RFB 物理坐标 vs portal 逻辑 ×2.25 | 补丁版 `pw.so`/`xdp.so` |
| 中文字形是日/韩 | LANG=C 选到 Noto CJK KR/JP | host + flatpak 加 SC 规则 |
| 密钥环挂死 | 空密码钱包未激活 | 修 `org.freedesktop.secrets`；Chromium 可 `--password-store=basic` |
| ZCode/WorkBuddy 只渲染一半 | XWayland | `--ozone-platform=wayland` |
| 系统监视器无 GPU | ksystemstats 缺 MR/权限 | MR !149 + local fallback + `cap_sys_ptrace` |
| Blender 触摸崩溃 | `wl_pointer_set_cursor(NULL)` | 打触摸补丁重编 |

---

## 10. 双系统 / 共享分区

| 症状 | 根因 | 修法 |
|---|---|---|
| 切换脚本拒绝写入 | `pair.env` 与镜像哈希不一致 | 重新 `make-pair.sh`；同步两侧 |
| 切完进不了系统 | 镜像/DTB/GKI 不匹配 | 回备份 `boot_a`；开机菜单选另一项 |
| `boot_a` 未知哈希 | 从主机刷过新内核 | 更新两侧镜像与 `pair.env`；不要 `--force` |
| OS4 侧 `switch2arch` 找不到设备 | 无线 adb 未连/多设备 | `TB_SERIAL`/`TB_TABLET_IP` |
| 共享分区 OS4 读不了 | SELinux `unlabeled`/权限 | 模块 v1.1；`chcon`；`tb-share-fixperm` |
| 共享分区文件 0600 | Android 保留源权限 | Arch 开机 `chmod -R a+rwX` |
| 切系统后文件损坏 | 拷贝未完成/ext4 日志 | 等拷贝完成；非正常切换可自愈 |
| 小米文件管理器看不到 | 无 root 模式 | MT管理器/MiXplorer/Solid Explorer |

---

## 11. 数据安全

| 症状 | 根因 | 修法 |
|---|---|---|
| PIN 解不开 | 恢复了旧 userdata/TEE 防回滚 | 只能清 data |
| 账号异常 | 开了查找设备/改 TEE | 不要开；必要时重新登录 |
| 刷机后数据没了 | 误加 `--wipe` | 升级永远不加；`--wipe` 单独确认 |
| Arch 起不来但 Android 正常 | boot_a 被写成 Android 默认 | 开机菜单选 Linux，或 OS4 侧 `switch2arch` |
| Android 起不来但 Arch 正常 | super 写坏/分区缺 | 回刷 rollback super |

---

## 12. 取证命令卡

```bash
# 内核
journalctl -k -b | grep -cE 'Oops|BUG:|Call trace'
journalctl -k -b | grep -E 'phy initialization|Host halt|Cannot enable|audio_process'

# DP
cat /sys/class/drm/card1-DP-1/status
cat /sys/kernel/debug/dri/1/DP-1/dp_debug | head -20

# 内存
cat /proc/pressure/memory
cat /sys/kernel/mm/lru_gen/enabled
zramctl

# 音频
wpctl status | grep -E 'TB710FU|HDMI'
grep -c 'state=XRUN' /var/log/tb-audio/watch.log

# 卡死现场
tb-hangdump            # D 状态任务栈
tb-ff-diag             # Firefox 卡死
tb-kmsg-tap            # 0.5 s sync，硬复位不丢日志
```
