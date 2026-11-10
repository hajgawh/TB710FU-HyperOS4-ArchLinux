# modules/

六个在用的 KernelSU-Next 模块源码。**不包含 zip**；用 `build_modules.sh` 现场打包。

| 目录 | 模块 ID | 版本 | 作用 |
|---|---|---|---|
| `TB710FUSetRes/` | `tb710fu_setres_noop` | v2.0 | lwky 开关桥（`game_mode=2`/`edge=0`）、`panel_direction` 跟随 `sys.tp.grip_enable`（横屏 90→1）、`post-fs-data` bind-mount 横屏 letterbox 列表、原生电池保护→`pc_mode`、WPS/CAD mslg rootfs、3198/wmhp 遗留清理、离线时间 fake-hwclock（`tb_loops.sh` + `setsid`，锚点 = epoch + RTC raw） |
| `TB710FUThermal/` | `tb710fu_thermal` | v1.1 | 性能/均衡双模式 GPU+CPU 温控，bind mount `thermal-engine_{gpu,cpu}_0.conf` |
| `TB710FUCPUMax/` | `tb710fu_cpumax` | v1.2 | 性能模式四簇满频；均衡/省电与 Scene/澎湃做交接 |
| `TB710FUDebloat/` | `tb710fu_os4_debloat` | v1.5.2 | 三级精简：包级冻结 30 个包、组件级冻结 6 个反诈组件、DNS 黑洞 4 个上报域名；restore/action/卸载一键恢复 |
| `TB710FUDPWidebusOff/` | `tb_dp_widebus_off` | v1.3 | A27U 外接屏关闭 vendor `sde_dp` widebus；**只写 `widebus=N`**，不做 HPD/altmode 操作 |
| `TB710FUShareMount/` | `tb710fu_share_mount` | v1.1 | 开机把 `sda16`（GPT 名 `share`，ext4）挂到 `/mnt/share`；无 `context=` + 挂载后 `chcon` |

## 构建

```bash
modules/build_modules.sh
# -> work/ksu-modules/TB710FUSetRes.zip
# -> work/ksu-modules/TB710FUThermal.zip
# -> work/ksu-modules/TB710FUCPUMax.zip
# -> work/ksu-modules/TB710FUDebloat.zip
# -> work/ksu-modules/TB710FUDPWidebusOff.zip
# -> work/ksu-modules/TB710FUShareMount.zip
```

## 安装

```bash
adb -s <serial> push work/ksu-modules/TB710FUSetRes.zip /data/local/tmp/
adb -s <serial> shell "ksud module install /data/local/tmp/TB710FUSetRes.zip"
# 同理其他五个
adb -s <serial> reboot
```

刷后一次性安装/清理用 `tools/post_flash_modules.sh <serial>`。

## 跨模块约束

- 需要跨 `service.sh` 退出后继续运行的常驻循环，应使用 `busybox setsid sh <script>` 另起会话；ksud 会收割
  `service.sh` 退出时留下的子进程。`TB710FUSetRes` 的 `tb_loops.sh` 就是这种模式。
- 运行时 bind mount 的源文件要先 `chcon u:object_r:vendor_configs_file:s0`；thermal-engine 持有配置
  时 `umount` 会 EBUSY，必须先停守护再换挂载。
- `TB710FUDPWidebusOff` 只写 `widebus=N`，不要用 `hpd` debugfs 做重连；`TB710FUShareMount` 不用
  `mount -o context=`，挂载后 `chcon`。
- **Debloat 会改变应用状态**：停用模块 ≠ 恢复；必须跑 `restore.sh`/`action.sh` 或卸载后重启。
- **SetRes 的卸载残留**要单独清：`ksud module uninstall` 不回滚 `/data/vendor/rootfs`
  符号链接、`/data/rootfs` 的 `0555`、时间锚点和 WPS/CAD 镜像。用
  `TB710FUSetRes/uninstall.sh --yes`（先不带参数预览）。

## 不再随包发布的模块

`TB710FUFont100`、`TB710FUCorner40`、`TB710FUIdentity` 不再发布：

- 字体 100% 与侧滑 1.0 由包内 `/system/etc/tb710fu_bootfix.sh`；
- 40px R 角由包内原厂 `DevicesOverlay.apk`；
- marketname 由包内 product build.prop。

从旧包升级时 `post_flash_modules.sh` 会尝试卸载它们。

## 说明

- 每个模块的详细逻辑见各自 `README.md`；行为与验收见
  [docs/09-runtime-modules.md](../docs/09-runtime-modules.md)。
- `TB710FUThermal/profiles/` 是测试机（ZUXOS 1.5.04.428）vendor 配置的参考/修改版；
  你的 vendor 版本不同则重新校准。
- 模块不写 boot/super；只做运行时 bind mount / sysfs / Settings 桥 / pm / iptables。
