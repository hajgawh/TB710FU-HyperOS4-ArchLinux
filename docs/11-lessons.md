# 11 — 经验与「不要做」

> 这些结论都是真机踩出来的；括号里是证据类型（真机 A/B、日志、源码、上游文档）。
> 新结论请按同样格式追加，不要只写「试过可以」。

---

## 1. OS4 移植

1. **vendor 不要换。** OS4 的 yupei vendor 是 SM8735P 的；联想硬件适配都在 OS3 vendor/ODM。
2. **升级只写 super、不 `--wipe`。** `/data`、KSU、Arch、账号、共享分区都在。
3. **`ro.sf.lcd_density=440` 不能删。** 删了落 vendor 320，整个 UI 小 27%。
4. **不要在线 `wm density`/`wm size`。** SystemUI 会冻结截图；只改 Settings/prop，重启生效。
5. **字体 0.85 是陷阱。** 字体页只有 90/100/110/…，0.85 显示成 90%，且 90→100 会因
   `uiMode&15` 已是 1 提前 return。包内 bootfix 每次开机写 1.0。
6. **R 角只差一个资源。** `DevicesOverlay.apk` 的 `rounded_corner_content_padding`：
   原厂 40px，旧 OS3/piano 10px；硬件圆角两台机器都是 54px。
7. **色彩反了是 vendor 语义对调。** 改 `miui-services.jar` 的 mode 映射，并删旧 oat。
8. **右边缘侧滑是多层叠加 + 一个 launcher 竞态。** `panel_direction` 跟随旋转
   （OS4 横屏 90° 写 1，不是 3）+ `game_edge=0` + `game_mode=2`；lwky 的 4/4 是错的。
   横屏 App 若在居中 letterbox 里，手势 stub 跨“桌面→App”边界会丢 MOVE，需要
   `landscape_fullscreen_list.xml`（SetRes v2.0）。见
   [12-os4-touch-backgesture.md](12-os4-touch-backgesture.md)。
9. **前置相机是 role tag 缺失。** MiuiCamera 只读小米 `com.xiaomi.cameraid.role.*`；
   QTI HAL 不发布，default -1→1 即可；最终改用 Aperture。
10. **相册查看崩溃 ≠ 相机问题。** 是 `SpecialTypesProvider` 缺失；替身 provider 可修。
11. **亮度/HBM 要 displayconfig 命中面板 ID。** 否则手动滑条能推满 782 nit 且 HBM 不触发。
12. **lwky 执行器有了不等于开关有了。** OS4 没有 OS3 SystemUI 的 PropObserver；
    `persist.sys.*` 要由 root 守护桥同步。lwky 只认数字。
13. **电池保护三档是真的在写充电节点。** `pc_mode=1` 亮屏停充/息屏恢复；
    `pc_mode=2` >79% 停充；`charge_control_limit=12` + `charging_enable=0`。
14. **WPS/CAD「环境异常」是代差。** OS4 Launcher 要 `/data/vendor/rootfs` 和版本
    ≥26.01.01；OS3 ODM 只服务 `/data/rootfs`。桥在 `TB710FUSetRes`。
15. **升级路径不 wipe，但 system_ext 不能漏。** 只重建两个分区会导致 Android 起不来
    （411b 事故）；三分区一起验收。
16. **永远不要打开「查找设备」。** 联想固件没有小米 TEE。
17. **不要在设备上点系统 OTA。**
18. **不要在低电量下刷机。**

---

## 2. Arch 内核

19. **内核跨版本的结论要重验。** 7.2.6 的 `battery-current-inverted` 在 7.3 上反向制造
    充电显示 bug；升级内核后以当版实测为准。
20. **必须显式 `KERNELRELEASE=7.3.0-tb710fu`。** 否则模块 vermagic 带 `+`，拒载。
21. **DTB 与 Image 必须同源。** 只换 `.ko` 不会更新 DTB；改 DTS 必须重打 boot。
22. **6 核要用 `status="fail"` 而不是 `disabled`**（PSCI 只认 0x0/0x300–0x700）；
    还要 4 个 cpu-map，否则调度器仍按 8 核。
23. **`devm_of_find_backlight()` 不能依赖空桩。** `CONFIG_DRM=y + BACKLIGHT=m` 时
    `drm_panel_of_backlight()` 是空桩，`panel->backlight=NULL`，DPMS 背光不灭。
24. **触摸模块禁止 `rmmod`。** 卸载 Oops；只能换文件后重启。
25. **`qcom_iris` 严禁 `rmmod`。** D 状态死锁，能卡死关机流程。
26. **PSI/MGLRU 会被旧 config 覆盖。** 两份 canonical config 要同步 + `syncconfig`；
    构建断言 `CONFIG_PSI/LRU_GEN/ZRAM_BACKEND`。
27. **zram 后端要一起编。** 只编 lzo 的模块会让 zstd zram0 创建失败。
28. **LMH 回读才是实际频率。** `scaling_cur_freq`/htop 是请求值；95 ℃ 下 X4 只给
    ~2.3–2.6 GHz。
29. **CPU 温区没有 passive trip。** 只有 110 ℃ critical；用户态限频只能按电池温度。

---

## 3. Type-C / DP / USB

30. **插拔硬复位有三层。** WCD939x 全断全建、QMP combo 在 DP_ONLY 下初始化、msm PHY
    引用计数不配对；修完 v32/v33 还要处理「DP 点亮早于 USB/SS 枚举」（v34）。
31. **坞 USB3「插上即断」是 COM 块重建。** 伪拆除 `mux 0x5→0x1` 触发
    `com_exit+com_init`；两簇 `apply_mode` 都落在 `new SuperSpeed` 后 4–16 ms、
    `hub found` 前约 80 ms，SS 在枚举后 0.348–0.358 s 掉线（11-07 的同样两簇在
    `hub found` 后 122 ms，所以存活）。
32. **用户态守门抢不过 KWin。** `kscreen-doctor disable` 在 detach 时 16/16 `not found`；
    必须在生产者 altmode 延迟上报。
33. **`keep_link` 必须是 N。** 否则 DPTX 一直驱动主链路，A27U 无法真正待机，
    每 27 s 弹「无信号」。
34. **4L HBR3 + 30bpp 不作日常默认。** 稳态能跑，DPMS 唤醒后 sink 锁不住。
35. **不要用 `hpd` debugfs 做重连。** 会把 WCD939x 切到 USB 模式，连带丢 USB。
36. **不要读 `dp_test_*`。** `msm_dp_test_*_show` 未判空，NULL deref Oops。
37. **A27U 直连 s2idle 后 hub 掉是显示器侧。** 端口重扫/root hub 重绑无效，需拔插。
38. **坞的 USB2/USB3 能跨 s2idle 是 v30 quirk 的功劳。** 不要回退
    `qcom,skip-glue-pm-on-suspend`。
39. **快速两次 s2idle 会触发老平台竞态。** 规避 `tb-dp-off/on`。

---

## 4. 音频

40. **先查实时调度，不要一口咬定 DSP。** 本机从没装 RTKit，PipeWire 静默退回
    SCHED_OTHER，3×20 ms 缓冲欠载 → TDM/DSP 图重启 → 四颗 AW882xx 重锁。
41. **UCM 是硬复位元凶。** ConflictingDevice 触发 PCM-open 风暴 → ADSP 断言；
    禁 UCM，走 pro-audio。
42. **SoundWire 采集 DAI 选错就静默全零。** `swr2` DAI0 只有 playback，采集用 DAI1。
43. **`pkill -f "yes"` 会杀 p11-kit。** 它的 argv 含 `write-protected=yes`；
    用 `pkill -x yes` 或按 PID。
44. **稳态噼啪不要宣称已修。** 卡顿/XRUN 已修；噼啪缺客观验证，口径「待定」。

---

## 5. 内存 / 图形

45. **整屏卡死 ≠ DPU。** 先看 `kswapd0` 与 `msm_gem_shrinker`：回收路径等 GPU fence
    会把全系统钉死。C 补丁改成 `dma_resv_test_signaled()`。
46. **单进程 `gdrv0` 100% 是 Mesa batch cache 活锁。** RSS 不动、GPU 空闲、无 D 状态；
    只能 `tb-ff-restart`。
47. **提高 watermark 只是降概率。** 250 让 Normal low/high=184.4/331.5 MB，
    大于双屏 swapchain 突发；根治要上游 Mesa 补丁。
48. **UFS MCQ 不值得开。** 冻结现场 UFS busy 0.16%，瓶颈是 GEM shrinker。
49. **不要用 `pkill -f` 清理负载。** 会误杀 flatpak 的 p11-kit，之后所有 flatpak 秒退。
50. **Firefox 新标签页白屏 ≠ 触控。** trainhop 副本遮蔽内置 newtab；删副本 + 设
    `browser.newtabpage.disableNewTabAsAddon=true`。

---

## 6. 桌面

51. **虚拟键盘三类失效：boot 风暴/resume/锁屏解锁。** 入口是托盘输入法图标；
    v3 只 +6 s 切一次，避免 KWin 卡 10 s。
52. **autostart 用 `.desktop`。** systemd 也会执行 `.desktop.disabled`。
53. **接键盘仍弹虚拟键盘是 KWin 6.8.2 的 `lastInputHandler`。** 不是平板模式；
    Never 也不绝对。
54. **VNC 鼠标错位是坐标缩放。** RFB 物理 vs portal 逻辑 ×2.25；补丁后才能点准。
55. **krfb 不监听是 `passwordSet` 回归 + portal 竞态。** 先订阅再调用。
56. **CJK 字形选错是 LANG=C。** host + flatpak 都要 SC 规则。
57. **Waydroid 的硬阻塞是策略路由。** 不是 GPU；要重编内核。
58. **Wine 11 + box64 不可用。** `set_mem_area_state` 断言；等上游。
59. **Moonlight 不要维护「低延迟版」。** 净差在噪声内；主机编码才是大头。
60. **OBS 没有 aarch64 官方包。** 用 AUR `obs-studio-tytan652`；升级要重打 ffmpeg 补丁。

---

## 7. 双系统 / 共享

61. **切换 = 配对镜像，没有运行时「下次启动选择」。** 两个变体同 Image/DTB，
    只是菜单默认项不同。
62. **两侧 `pair.env` 必须一致。** 重新构建内核后一起更新；不要 `--force`。
63. **只写 `boot_a`。** 不写 `boot_b`/`misc`；不切 A/B。
64. **共享分区用 `LABEL=share`，不要写死 UUID。** UUID 每台设备不同。
65. **OS4 侧不要用 `mount -o context=`。** SELinux `associate` 只有 vold/init 有；
    无 context 挂载 + `chcon`。
66. **Android 拷出的文件保留源权限。** Arch 侧开机 `chmod -R a+rwX`。
67. **不要 exFAT。** 7.3 内核没编 `exfat` 模块；ext4 断电可自愈。

---

## 8. 流程与安全

68. **每次物理写入前确认目标分区。** 唯一分区列表见 `AGENT.md` §1。
69. **先备份，再写入；写后读回。**
70. **升级默认不 wipe；`--wipe` 单独确认。**
71. **不要恢复旧 userdata 整盘镜像。** TEE 防回滚，PIN 可能永远解不开。
72. **不要把作者的 MAC/IP/序列号/哈希当成自己的。** 本仓库全部是占位符；
    按 `PRIVACY.md` 换成自己的。
73. **不要把 `work/`、二进制、日志、个人数据提交到公开仓库。**
74. **进程管理按 PID，不用 `pkill -f`/`killall`。**
75. **不确定后果的命令不要执行。** 停下来问。

---

## 9. 2026-11-09 补遗

> 编号接续 1–75；原有条目不重新编号。

### 9.1 OS4 移植

76. **APK 原位补丁的边界。** ARSC 只改 24.8 定点数，deflate 条目必须等长替换；一旦重打包或
    `zip -u`，APK Signing Block 就丢了。JAR 可以整体重打，但必须删 `oat/*` 与 `.fsv_meta`；
    不重签 system UID，也不要把补丁包放进 `/data/app`。
77. **`sepolicy_compat.cil` 必须随包。** Android 17 平台删掉的类型，冻结的 API 34 vendor
    仍在引用；不加会让 vendor 策略缺这些类型。
78. **`.DEV` incremental 只用于绕过 FindDevice 检查。** 小米账号看到 `.DEV` 会忽略
    「查找设备」状态校验；TEE 缺失是硬件事实，仍然不要打开查找设备。
79. **不要装 `set_res.sh` 的 2000×3198。** 在 3200×2000 面板上就是削边；新包已删，
    旧 `/data` 残留由 SetRes 开机清。
80. **不要装 `wmhp` 完美横屏规则。** 4 份 `cloudFeature_*_list.xml` 按 320 密度调，
    在 434/440 下会与桌面日历重叠。
81. **刷新率/灵动岛保持原厂。** 不写 `peak_refresh_rate`/`miui_refresh_rate`/
    `user_refresh_rate`，也不给 `fpsList` 加 144；原厂就是「最高 144、多数 App 实际 120」。
82. **Scene 默认 fast 与 CPUMax 性能模式不是一回事。** Scene fast 把大核/超大核压在
    2841600/2995200；CPUMax 性能模式抬到 2265600/2956800/2956800/3302400，
    均衡/省电只交接一次。
83. **`game_edge` 只接受 0..3，`game_mode` 是逻辑重排。** 映射为 0→0、1→2、2→4、3→1、
    4→3、5→5；右侧返回要 2 不是 4，4 仍保留掌拒。
84. **`panel_direction` 的映射在两代驱动上相反，别背 OS3 的答案。**
    OS3：SET 与 SHOW 标签相反，横屏 90° 要写 3（读回却是 270°）；
    **OS4.0.11：索引 = 旋转角/90，横屏 90° 写 1（读回 Right Up/90°）**。写死 3 在 OS4 上
    等于 270°，防误触/握持模型反 180°，右侧侧滑变钝。正解是跟随 `sys.tp.grip_enable`
    （0/90/180/270 → 0/1/2/3），不要硬编码。
85. **1.5 倍侧滑不是必需。** 修正 `panel_direction`/`game_edge`/`game_mode` 与横屏窗口后
    1.0 已够用；1.5 反而扩大误触区。`back_gesture_inset_scale_*` 对 OS4 launcher 的 56px
    stub 也无效。
86. **横屏 letterbox 会让侧滑“看起来像驱动坏”。** OS4 平板策略把未列入
    `/product/etc/landscape_fullscreen_list.xml` 的 App 放进居中 1639×2000 窗口，左右各
    约 780px 桌面；从物理边缘起手的手势 stub 在跨边界时收到 `ACTION_CANCEL`、
    `offset_x=0`。把包名加入列表（bind mount，`post-fs-data` 最早）后 App 变
    `miui-magic-windows` 右贴边，手势恢复。注意它不是真 3200×2000 全屏。
87. **Aperture 横屏四条铁律。** 保留 fullSensor、横屏用 `layout-land`、旋转时重建 Activity、
    `rotateViews` 必须 no-op；控件只锚 parent + 固定边距，模式切换对调取景器 fling 映射表
    （构建侧见 [03-os4-build.md](03-os4-build.md) §3.2.1）。

### 9.2 Arch 内核

88. **仓库 config ≠ 运行内核 config。** 排障第一步永远是 `zcat /proc/config.gz`；
    历史上 Landlock/PSI/MGLRU 配置早已提交，运行 Image 却可能是加配置之前编的。
89. **NBD 根盘上睡眠会断 USB。** btrfs 随后 EIO（缓存可重建、系统本体无损）；
    验证 s2idle 必须换 UFS 本地盘再测。

### 9.3 内存 / 图形 / 桌面

90. **双浏览器「打开就卡」是启动尖峰，不是 OOM。** 7 GB 占用下新浏览器 18 个进程 spawn
    会让 PSI `some avg60` 冲到 7% 再回落；优先收敛标签/关后台，而不是继续加 swap。
91. **KDE 密钥环挂死先查三处。** 空密码钱包必须预先创建、KWallet 的 SHA1 是非标准实现、
    Arch 包缺 `org.freedesktop.secrets` 激活文件；Chromium 保留 `--password-store=basic`
    做隔离。
92. **krfb 补丁要同时换两个插件。** 只替换 `krfb` 二进制无效，必须替换
    `framebuffer/pw.so` 与 `events/xdp.so`；krfb 是单实例，测试前先停旧实例。
93. **Firefox 硬解别信 `init successful`。** V4L2-M2M 在 iris 上打印成功后第 1 帧即被拒，
    然后静默回软解；用 `MOZ_LOG=PlatformDecoderModule:5,FFmpegVideo:5` 和 RDD CPU
    看真实路径。

### 9.4 流程与安全

94. **构建 ENOSPC 会留下 2 TB 稀疏假 `product.img`。** `ls -la` 看表观大小即可识别；
    换 super 前先删旧 super；单轮 out 约 18 GB，含解包/临时树峰值约 30 GB（见 02 §5.1）。
95. **在线直写 super 的 dd 管道对端必须 `iflag=fullblock`。** 否则 32 KiB 短读被补零成整块、
    dd 提前退出；dd 退出码不可信，必须按打印的 `N bytes copied` 逐块校验。
96. **ABL 拒绝修改过的 dtbo。** 给 dt_table 追加 RTC overlay 再重签 vbmeta 会直接落
    fastboot（两次复现）；RTC 不要动 dtbo/vbmeta。
