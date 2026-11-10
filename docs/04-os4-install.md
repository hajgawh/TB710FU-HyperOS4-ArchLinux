# 04 — 安装/刷入 OS4：备份、启动链、super、KSU、模块与回退

> 本文是**物理写入**流程。每一步都先读 [AGENT.md](../AGENT.md) 的硬性规则：
> 唯一分区永不写、先备份、每次写入前确认、写后校验。
> 所有命令里的 `<serial>`、`<device-ip>`、`<path>` 都是占位符。

> **先选路径**：已有 OS4 + Arch 的升级只写 `super`（本文 §3/§4），**不要** `--wipe`；
> 从 stock/OS3 第一次安装才走 §5，并且 `--wipe` 只做一次。完整首次安装链（GPT 备份、
> v3 链、NBD 试跑、缩 userdata、建 `sda15`、rsync）见
> [00-install-paths.md](00-install-paths.md) §3。

---

## 1. 刷前检查

### 1.1 主机

- `edl` 可执行；`LOADER` 指向**你自己的** `prog_firehose_ddr-TB710FU.melf`；
- super 的 sha256/大小/manifest 已记录；
- `tools/verify_package.sh` 61/61；
- 磁盘剩余 ≥10 GB（备份 + 回退件）。

### 1.2 设备

- 电量 ≥30%（推荐 ≥50%）；
- 已解锁 BL；
- 当前槽位是 `_a`（`fastboot getvar current-slot` 或 `getprop ro.boot.slot_suffix`）；
- 已备份 GPT（6 个 LUN）、唯一分区、`boot_a`/`init_boot_a`/`dtbo_a`/`vendor_boot_a`/`vbmeta_a`。

---

## 2. 进入 9008/EDL

- 关机拔线 → 长按电源 15–20 秒 → 按住音量 +/− 再插线；
- 或已 root/开 USB 调试：`adb reboot edl`；
- 主机确认：`lsusb`/`ioreg` 出现 `05c6:9008`。

```bash
EDL=tools/venv/bin/edl
LOADER=work/firehose/prog_firehose_ddr-TB710FU.melf
$EDL --loader="$LOADER" --memory=ufs printgpt > work/backup/gpt.txt
```

---

## 3. 刷 super（升级，保留数据）

```bash
EDL=tools/venv/bin/edl \
LOADER=work/firehose/prog_firehose_ddr-TB710FU.melf \
bash tools/flash_super.sh work/build_os4/out/super_fixed.img
```

**不要加 `--wipe`。** `flash_super.sh` 默认只写 `super`，不动 `metadata`/`userdata`。

检查点：

- 输出 `Wrote ... to sector ...`；
- 末尾 `SUPER METADATA OK`；
- 设备自动 reset；
- 能进系统，`sys.boot_completed=1`。

失败处理：

1. 不要重复写；
2. 用 `work/build_os4/rollback_*/` 的三分区重新组 super，再刷；
3. 仍失败 → 写回启动链备份 → 最后 ZUI 救援。

---

## 4. 从 Arch 在线直写 super（免 EDL/数据线）

设备启动到 Arch 后，用包内脚本写，**不要手搓裸 `dd`**：

```bash
# 用法：tools/flash_super_arch.sh <super.img> [root@<device>]
# 默认 HOST=root@tb710fu；可用 CHUNK_MB=512、SKIP_VERIFY=1、SSH=... 覆盖
bash tools/flash_super_arch.sh work/build_os4/out/super_fixed.img root@<device>
```

脚本做的事：

1. **10 GiB 保护**：镜像大小必须是整 MiB，且结束位置 < 10 GiB（kShimC 的 Arch root
   从这里开始）；目标必须是块设备 `/dev/disk/by-partlabel/super`；
2. **身份保护**：设备 `super` 必须正好 20,401,094,656 B，且 `uname -n` /
   `/proc/device-tree/model` 含 `tb710fu`/`piano`（大小写不敏感），否则拒绝写入；
3. **512 MiB 分块**（`CHUNK_MB` 可调）：发送端 `dd skip=`，接收端
   `dd seek=... conv=notrunc,fsync iflag=fullblock`；每块最多重试 3 次，
   **按远端打印的 `N bytes copied` 与期望字节数比对**，不看 `dd` 退出码；
4. **回读 sha256**：写完在设备上回读整段（4.0.11 包为 9911 MiB）算 sha256，
   与本机镜像比对，打印 `SUPER VERIFY OK` 才算成功；
5. 结束时提示 `systemctl reboot`，在 kShimC 菜单选 HyperOS。

> 管道里从 stdin 读入的一端（远端或本机）必须 `iflag=fullblock`。ssh 管道一次可能只给
> 32 KiB，`bs=4M` 的 `dd` 会把短读补零成整块并提前退出——**报告“成功”实际可能只写了
> ~800 KB**。脚本按块校验字节数就是为了拦住这种情况。

写前先做两件备份/确认：

```bash
# 1) 备份当前 super 头 + LP manifest（至少头 1 MiB；空间够就整盘备份）
sudo dd if=/dev/disk/by-partlabel/super bs=1M count=1 \
  of=/var/backups/tb710fu/super.head-$(date +%F).img

# 2) 确认 super 没有被 dm-verity/device-mapper 占用（Android 不能在运行）
lsblk -f /dev/disk/by-partlabel/super
sudo dmsetup ls | grep -i super || echo "no super dm device"
```

> **不要在 Android 运行时写 super。** 在线直写的前提是 Arch 里的 `super` 没有被
> `device-mapper`/`dm-verity` 占用，并且已备份分区头/manifest。

### 4.1 裸 dd：只用于理解原理/应急

```bash
sudo dd if=work/build_os4/out/super_fixed.img \
        of=/dev/disk/by-partlabel/super bs=4M conv=fsync status=progress
sudo sync

# 回读校验（至少头 1 MiB；完整校验见脚本）
sudo dd if=/dev/disk/by-partlabel/super bs=1M count=1 | sha256sum
sudo dd if=work/build_os4/out/super_fixed.img bs=1M count=1 | sha256sum
```

> **警告：`dd` 的退出码不可信。** 必须看它打印的 `N bytes copied` 是否等于期望字节数；
> 管道对端（接收端）必须 `iflag=fullblock`，否则 32 KiB 短读会补零、提前退出。应急手写时
> 也要逐块核对字节数，不能只看“命令没报错”。

---

## 5. 首次安装（从 stock/OS3 开始，会清 data）

> 本节只覆盖 **OS4 侧的首次写入**。如果你还要装 Arch，请不要单独照本节做：先按
> [00-install-paths.md](00-install-paths.md) §3 的顺序做 GPT 备份 → v3 链 → NBD 试跑 →
> 缩 userdata/建 `sda15`/rsync → 再回到本节刷 `super --wipe`。这样 Android 只配置一次。

**进入条件**（缺一不可）：

- 设备已解锁，`_a` 槽，电量 ≥50%；
- [00 §3.1](00-install-paths.md#31-先备份任何写入之前) 的 GPT + 唯一分区备份已完成并复制到另一块盘；
- v3 启动链五件已生成（`work/v3/`），并且**先写链、后写 super**；
- 用户明确确认 `/data` 会清空。

步骤：

1. **写 v3 启动链五件**（`boot_a`/`init_boot_a`/`dtbo_a`/`vendor_boot_a`/`vbmeta_a`），
   逐件回读 sha256；v3 链是后续 kShimC 的 AVB 底座，**只写一次**：

   ```bash
   EDL=tools/venv/bin/edl
   LOADER=work/firehose/prog_firehose_ddr-TB710FU.melf
   L=(--loader="$LOADER" --memory=ufs)
   for p in boot init_boot dtbo vendor_boot vbmeta; do
     "$EDL" w "${p}_a" "work/v3/${p}.img" "${L[@]}"
   done
   ```

2. **首次 super**（`--wipe` 只这一次）：

   ```bash
   EDL=tools/venv/bin/edl \
   LOADER=work/firehose/prog_firehose_ddr-TB710FU.melf \
   bash tools/flash_super.sh work/build_os4/out/super_fixed.img --wipe
   ```

3. 开机进向导：**不登小米账号、不开查找设备**，完成向导后开 USB 调试；
4. 如果向导卡激活检查：用 `TB_NO_FINDDEVICE=1` 构建的 super 过向导，再脏刷正常 super
   （不加 `--wipe`）；
5. 按 §6 装 KernelSU-Next，按 §7 装模块，按 §8 验收。

> `--wipe` 会清 `metadata` 与 `userdata` 头部（等价于恢复出厂），**不碰唯一分区**；
> 如果你已经按 00 §3.5 缩过 userdata，这里只是再清一次头，最终 Android 会在缩小后的
> 分区上格式化。**升级路径永远不要加 `--wipe`**，也不要因为「想干净」而 wipe。
>
> `--wipe` 不是「首次安装」的同义词：首次安装 = v3 链 + `--wipe` + 向导；只刷 super
> 不加链，会卡 fastboot/开机动画；只加链不 wipe，可能卡解密/循环开机。

---

## 6. KernelSU-Next

1. 安装 KernelSU-Next APK；
2. app 内「安装」→「直接安装」（写 `init_boot_a`）；
3. 重启；
4. 设置里开「ADB Root」。

验收：

```bash
adb -s <serial> shell su -c id
# uid=0(root) ... context=u:r:ksu:s0
```

失败：只做文件修补/fastboot 修补有时不完整；回到 app 内直接安装。

> KSU 会改 `init_boot_a`（并可能更新 vbmeta）；若重启落 fastboot，先写回 §9.2 的
> `init_boot_a`/`vbmeta_a` 备份，再按 app 内流程重试。

---

## 7. 模块

```bash
modules/build_modules.sh
tools/post_flash_modules.sh <serial>
adb -s <serial> reboot
```

`post_flash_modules.sh` 会：

- 安装/更新 `tb710fu_thermal`、`tb710fu_cpumax`、`tb710fu_setres_noop`；
- 卸载退役的 `Font100`/`Corner40`/`Identity`；

按需手动装：

```bash
adb -s <serial> push work/ksu-modules/TB710FUDebloat.zip /data/local/tmp/
adb -s <serial> shell "ksud module install /data/local/tmp/TB710FUDebloat.zip"
# 同理 TB710FUDPWidebusOff / TB710FUShareMount
adb -s <serial> reboot
```

> Debloat 会冻结/卸载应用，**必须用户明确同意**；停用模块 ≠ 恢复，见
> [09-runtime-modules.md](09-runtime-modules.md) §3.3。

---

## 8. 验收

```bash
tools/verify_device.sh <serial>
# 期望：0 failed（passed/info 数随刷新率、WPS/CAD、Arch 分区等现场状态变化）
```

覆盖：

- 字体 1.0、R 角 40px、密度 440；
- 刷新率/灵动岛未被写；
- lwky props、`/proc/gesture_control`、`game_mode=2`、`game_edge=0`、`support_pen=1`；
- `panel_direction` 可读（0/1/2/3）；SetRes v2.0 每秒跟随 `sys.tp.grip_enable`，横屏 90
  应为 `Right Up Direction!(90 degree)`/1，不再期望固定 3；
- lwky 守护、thermal-engine、WPS/CAD rootfs；
- 模块清单、Arch 分区、共享分区。

人工确认：字体页 100%、R 角、色彩、双击亮屏、保护套、电池保护三档、WPS/CAD、
性能/均衡、前置相机、右边缘侧滑、亮度/HBM。

---

## 9. 回退

### 9.1 super

`tools/port_build.sh` 每次构建前会把上一版 `system/system_ext/product` 三分区复制到
`work/build_os4/rollback_prev/`（不复制 10 GB 的 super）；首次构建没有上一版。用它重组：

```bash
# 用 rollback 三分区重组（位置参数：OUT.img SIZE name=img ...）
python3 tools/make_super.py \
  work/build_os4/rollback_prev/super.img 0x4c0000000 \
  system=work/build_os4/rollback_prev/system.img \
  system_ext=work/build_os4/rollback_prev/system_ext.img \
  product=work/build_os4/rollback_prev/product.img \
  vendor=work/port/vendor_a.img \
  odm=work/port/odm_a.img \
  vendor_dlkm=work/port/vendor_dlkm_a.img \
  system_dlkm=work/port/system_dlkm_a.img
bash tools/flash_super.sh work/build_os4/rollback_prev/super.img
```

### 9.2 启动链

```bash
# 设备在 9008；先定义 EDL/LOADER（与 §2 相同）
EDL=tools/venv/bin/edl
LOADER=work/firehose/prog_firehose_ddr-TB710FU.melf
L=(--loader="$LOADER" --memory=ufs)

# 回到 Android-only 的原厂/v3 链（五件都要，否则 AVB 链不完整）
"$EDL" w boot_a        work/stock/boot_a.img        "${L[@]}"
"$EDL" w init_boot_a   work/stock/init_boot_a.img   "${L[@]}"
"$EDL" w dtbo_a        work/stock/dtbo_a.img        "${L[@]}"
"$EDL" w vendor_boot_a work/stock/vendor_boot_a.img "${L[@]}"
"$EDL" w vbmeta_a      work/stock/vbmeta_a.img      "${L[@]}"
```

> `work/stock/` 应该是**写 KSU/kShimC 之前的**那份启动链备份。不要用当前的 kShimC
> `boot_a` 当回退件（它已经是多内核载荷）。

### 9.3 模块

```bash
adb -s <serial> shell "ksud module uninstall tb710fu_thermal"
adb -s <serial> shell "ksud module uninstall tb710fu_cpumax"
adb -s <serial> shell "ksud module uninstall tb710fu_setres_noop"
adb -s <serial> reboot
```

### 9.4 最后手段

- 回刷联想 ZUI 救援包；
- 不要恢复旧 `userdata` 整盘镜像（TEE 防回滚，PIN 可能永远解不开）。

---

## 10. A/B 槽位警告

- 当前 `_a`；
- super 的 `_b` 全是 0 extent；
- `boot_b` 与 `boot_a` 不同，**不要切 B**；
- 不要 `fastboot --set-active=b`，也不要用 `bootctl` 切槽。

### 10.1 不要为 RTC 改 dtbo / vbmeta（首次 v3 链写入见 00 §3.2）

- **ABL 拒绝修改过的 dtbo**：给 `dt_table` 追加 overlay（例如 RTC `allow-set-time`）并重签
  `vbmeta` 后，设备直接落 fastboot（两次复现）；换回原版 `dtbo`/`vbmeta` 秒恢复。
- 因此 **Android 侧 RTC 只能 NTP + fake-hwclock**；Arch 侧走自有 kshim DTS 的 nvmem offset
  （见 [05-arch-kernel.md](05-arch-kernel.md) §6）。
- **不要为 RTC 改 dtbo/vbmeta**，也不要重签这两个分区。

---

## 11. 刷机记录模板

```text
日期：
设备：TB710FU / 当前槽位 _a / 电量 __%
super：<名称> / <大小> / sha256
verify_package：__/61
启动链：boot_a <sha256> / init_boot_a <sha256> / vbmeta_a <sha256>
KSU：<版本>
模块：<列表>
刷入方式：EDL / Arch 在线
结果：SUPER METADATA OK / 进系统 / boot_completed=1
回退件：<路径>
```
