# 07 — Type-C / DisplayPort / USB Hub 专项

> 这一层是 TB710FU 最复杂的部分：WCD939x（Type-C/音频）、QMP combo PHY（USB3+DP）、
> dwc3/xHCI、pmic_glink altmode、msm DP 驱动、sink 侧显示器，任何一环时序错都会
> 表现为「黑屏 / 硬复位 / USB3 掉 / 无音频」。
> 本文给最终状态、根因与调参入口；逐日实验记录在原始资料索引里。

---

## 1. 最终状态（2026-11-09）

| 场景 | 链路 | 结果 |
|---|---|---|
| A27U 直连 | 4 lanes @ 540000（HBR2），594000，bpp24，bw_code20，p_level0 | 4K60 8bpc 稳定 |
| HDMI 坞 | 2 lanes @ 810000（HBR3），535680，bpp24 | 4K60 + USB3 5000M 同时 |
| 换向/插拔（出图） | v34 `tb_hpd_delay_ms=1000` | 8 轮 0 复位 |
| 坞 USB3「插上即断」 | v32 跳过 QMP COM 重建 | 正常方向 5/5 通过 |
| 熄屏 | `keep_link=0` | 显示器不弹「无信号」 |
| 带坞 s2idle | v30 quirk + v34 | hub 原样存活 |
| A27U 直连 s2idle | — | 显示器侧 USB2 hub 掉，需拔插 |
| DP 音频 | tplg 子图 + mixer | 双 sink，0 XRUN |

---

## 2. 四层栈与各自的坑

### 2.1 WCD939x（Type-C mux / USBSS / 音频）

- 每次 `set()` 全断全建会导致插拔硬复位；
- v2 修复：AUX/DPDM 常开，只在真 detach 时写 deferred 开关；
- F1（0023）：`tb_apply_work()` 加 `orientation == NONE` 门控，插线时的伪 teardown
  （`mux 0x5 → 0x1`）不再写 `dp=0`；
- 模块哈希会随整包重建变化，看 `.text` 是否相同，不要只看 sha。

### 2.2 QMP combo PHY（USB3 + DP 共用）

- `qmp_combo_apply_mode()` 对 `USB3DP ↔ USB3ONLY` 会 `usb_power_off → com_exit →
  com_init → usb_power_on`；
- 这个重建若落在 SS hub 枚举窗口（`hub found` 前后几十 ms），348 ms 后 SS 掉线；
- **v32（0027 的一部分）**：`USB3DP ↔ USB3ONLY` 且 `usb_init_count > 0` 时只更新 mode，
  不重建 COM；
- **v33b**：`typec_switch_set()` 只记 orientation，不再整块重建；
- **v33e**：写 `TYPEC_CTRL` 前先 `usb_power_off → com_set_mode → usb_power_on`，
  停 USB3 PCS；
- 换向仍会走 `qmp_combo_typec_switch_set()` 全量重建（残余风险，v34 用延迟规避）。

### 2.3 msm DP / PHY 引用计数

- `phy_power_refs` 不配对会让 resume 跳过 `phy_init()`，第一次 AUX 永远超时；
- 系统 suspend 强制 `off_link + phy_exit`；AUX 总预算 `tb_link_budget_ms=3000`；
- `keep_link=0`：DPMS off 走 D3 + off_link + phy_exit，下次 enable 完整 re-init。

### 2.4 pmic_glink altmode

- `drm_bridge_connector_handle_hpd()` 在 `msm_dp_bridge_hpd_notify()` 之前就把 connector
  置 connected 并立即发 hotplug；msm_dp 侧压不住第一次事件；
- **v34**：在生产者 `pmic_glink_altmode` 把 DP 连接上报延后 `tb_hpd_delay_ms`（默认 1000），
  让 KWin 在 USB/SS 枚举结束后才看到连接器；
- 拔出/ACK 不延后；到点复核，已拔出则丢弃。

---

## 3. 为什么用户态守门不够

`tb-flip-guard` 监听 orientation，DP 亮着时「关→等 3 s→开」。实测 16 轮 0 复位，
但 16/16 都走了「KWin 抢先点亮 → 150 ms 补关」的退化路径：

- KWin 一断线就把输出移出运行时列表；
- `kscreen-doctor output.DP-1.disable` 在 detach 时 16/16 返回 `not found`；
- 只能在 attach 后补关，抢不过 KWin 自己在 hotplug 里的 enable。

**结论**：守门只能缓解，v34 上线后已停用（unit 保留）。

---

## 4. HBR2 / HBR3 策略

| 场景 | 推荐 | 原因 |
|---|---|---|
| A27U 直连 | 4L HBR2 / 24bpp | 4L HBR3+30bpp 稳态可跑，但 DPMS 唤醒后 sink 锁不住（`p_level=1`） |
| HDMI 坞 | 2L HBR3 / 24bpp（CVT-RB） | 带宽 99.2%，余量薄；出问题先 4K30/换线 |
| 4K60 10bit | 不作日常默认 | 已试跑并回退 |

不要移除 4-lane clamp；不要再做「4L HBR3 + 30bpp」的默认化尝试。
若再研究，先做 4L HBR3 + 24bpp 的 DPMS A/B。

---

## 5. DP 音频

- tplg 缺 `DISPLAY_PORT_RX_0` 子图时，`pro-output-1` 不出现；
- 追加子图 + mixer 开关后，`hw:0,1` 可打开；
- **不要恢复 UCM**：UCM 的 ConflictingDevice 会触发 PCM-open 风暴 → ADSP 断言 → 硬复位；
- 冷启动竞态：WirePlumber 可能先枚举声卡（link 未 up），只有 `pro-output-0`；
  `tb-dp-sink-ensure` 轮询 60 s，必要时重启一次 PipeWire。

---

## 6. 睡眠与唤醒

### 6.1 带 HDMI 坞

- v30 `qcom,skip-glue-pm-on-suspend` + v31 DTS `wakeup-source`；
- `failed_resume=0`、无 `phy init -110`、xHCI 不 `Host halt failed`；
- 坞的两级 USB2/USB3 hub 完整存活（`SS.Port0x` CCS=1）。

### 6.2 A27U 直连

- 显示器侧在 suspend 时切内置 hub，resume 不重新枚举；
- 端口重扫/DPMS 循环/root hub 重绑都无效；
- 规避：拔插一次，或给显示器断电 10 s。

### 6.3 快速两次 s2idle

- A27U 在位快速两次 s2idle → resume hub 未恢复 → alt-mode mux `0x0` → `push_idle`
  30 ms 超时 → pmic_glink `-110`（假 0% 电量）+ KWin pageflip 超时 → 整屏定格；
- 归因老平台竞态（非 v31 回归，80% 置信）；
- 规避：suspend 前 `tb-dp-off`、resume 后 `tb-dp-on`；不要快速反复 s2idle。

### 6.4 坞硬复位后的端口 latch

DP 出流时换向等硬复位后，端口状态可能被锁住：

- `typec orientation=unknown`、`port0-partner` 为空；
- `qcom-battmgr-usb online=0`，没有 UCSI 插拔事件，USB 设备列表全空；
- 反复拔插坞、给坞断电都不恢复。

这是 PMIC/UCSI/PD 的端口状态 latch，不是 DP/QMP 驱动问题。恢复方式是**带坞重启**：
重启前把坞按目标方向插好，开机后端口重新枚举，DP link 在启动早期建立（会话恢复也不再
等 ~30 s），通常立即出图。**不要反复拔插坞**；需要换向时也按这个流程做。

---

## 7. OS4 侧：A27U 带屏重启无信号

- 根因：vendor DP 在 USB-C/PD/alt-mode 未稳时约 11 s 首训，把 A27U RX 带到 `p_level=1`；
- 失败签名：`dp_debug` = `p_level=1` + `test_req=unknown`；系统仍显示 connected/enabled；
- 规避：
  1. 重启前拔显示器，进系统后再接；
  2. 已黑屏时给显示器断电 10 s；
  3. 不要用 `hpd` debugfs（会把 WCD939x 硬件切到 USB 模式，连带丢 USB，冷启动才恢复）；
- `TB710FUDPWidebusOff` v1.3 只写 `widebus=N`，不做 HPD cycle/altmode unbind。

---

## 8. 调参入口

```bash
# HPD 延迟（v34）
cat /sys/module/pmic_glink_altmode/parameters/tb_hpd_delay_ms
echo 0 | sudo tee /sys/module/pmic_glink_altmode/parameters/tb_hpd_delay_ms

# msm DP
cat /sys/module/msm/parameters/keep_link          # 必须 N
cat /sys/module/msm/parameters/tb_link_budget_ms  # 3000
cat /sys/kernel/debug/dri/1/DP-1/dp_debug

# 状态
cat /sys/class/drm/card1-DP-1/status
cat /sys/class/drm/card1-DSİ-1/status 2>/dev/null || cat /sys/class/drm/card1-DSI-1/status

# 坞 USB
lsusb -t
cat /sys/bus/usb/devices/2-1/speed 2>/dev/null
```

> **不要读** `dp_test_active`/`dp_test_data`/`dp_test_type`：`msm_dp_test_*_show` 未判空，
> 会 NULL deref Oops。只看 `dp_debug`。

---

## 9. 不要做

1. 不要 `rmmod qcom_iris` / `nvt_36xxx` / `sy7758` / `msm`（D 状态或 Oops）；
2. 不要用 `hpd` debugfs 做「重连」；
3. 不要移除 4-lane clamp；
4. 不要把 `keep_link` 设 Y；
5. 不要在用户态 `pkill` 宽泛匹配（会误杀 p11-kit / 会话）；
6. 不要用 `kscreen-doctor` 在 root 下抢 KWin（缺 `WAYLAND_DISPLAY` 必崩）；
7. 不要在 suspend 前插着 A27U 快速反复 s2idle；
8. 不要把 `tb-phy58.service` 启用（已证伪，与坞 USB3 无关）；
9. 不要用反复拔插坞/给坞断电来恢复端口 latch（`orientation=unknown`、USB 全空）；用「带坞重启」。

---

## 10. 排错速查

| 现象 | 先看 | 处理 |
|---|---|---|
| 无画面 | `card1-DP-1/status`、`dp_debug` | 拔插/换线/降 4K30；查 `p_level` |
| 硬复位 | `dmesg | grep -E 'switch_set|com_init|Host halt'` | v34；`tb_hpd_delay_ms` |
| 坞 USB3 掉 | `dmesg | grep -E '2-1|SuperSpeed|Cannot enable'` | v32+；查 COM 重建 |
| USB2 掉 | `lsusb -t` | 拔插；查显示器 hub |
| 无音频 | `wpctl status`、mixer 控件 | `tb-dp-audio`；`tb-dp-sink-ensure` |
| 熄屏弹无信号 | `keep_link` | 设 N |
| 睡眠不醒 | `boot_id`、`failed_resume` | 带坞；避免 A27U 快速两次 |
| 换向复位 | orientation 日志 | v34；或换向前 `tb-dp-off` |
