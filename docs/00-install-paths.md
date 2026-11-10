# 00 — 首次安装 vs 升级：先选路径

> **这是整套文档的入口。** 01–12 是按主题拆的细节，不按安装顺序；第一次装机从本文
> §1 的决策表开始。本文只讲「走哪条路、先做什么、哪些步骤只做一次」，具体构建/刷写
> 命令仍以 02–06 为准。
>
> 前提：**设备已解锁 Bootloader**。解锁会清空设备且不可逆，本仓库不提供解锁方法；
> 下文所有命令都假设你能进 9008/EDL、能恢复自己的 `boot_a`/`vbmeta_a`。

---

## 0. 三条硬规则

| 场景 | 只允许写 | 绝对不要做 |
|---|---|---|
| 已有 OS4 + Arch，升级 OS4 | `super`（04 §3）或 Arch 在线直写 `super`（04 §4） | `--wipe`、重建/格式化 `sda15`、重跑 rsync |
| 已有 OS4 + Arch，升级 Arch | `boot_a`、内核模块、`pacman -Syu` | 删/格式化 `sda15`、重跑首次分区、`mkfs` |
| 首次安装 / 加装 Arch | v3 启动链、`super --wipe`（仅首次 OS4）、`sda15` | 在 Android 运行时改 GPT、在 NBD 根盘上测 s2idle |

**一句话**：`--wipe` 和「缩 userdata」是两件事，都会清 Android 数据；升级路径两件都不做。

---

## 1. 决策表（先对号入座）

| 你的现状 | 目标 | 路径 | `super --wipe` | 缩 userdata（会清 Android 数据） | 建 `sda15` | 入口 |
|---|---|---|---|---|---|---|
| 原厂 ZUI / OS3 / 其它系统，没有本项目的 OS4 | OS4 + Arch 双系统 | **首次安装** | 是，一次 | 是 | 是 | §3（先确认 testkey recovery/vbmeta_system） |
| 原厂 ZUI / OS3，只要 OS4 | 单 Android | **首次安装（仅 OS4）** | 是，一次 | 否 | 否 | §3.1、§3.2、§3.6 |
| 已刷本项目 OS4，没有 Arch | 加装 Arch | **加装 Arch** | 否 | **是（Android 数据仍会丢）** | 是 | §4 |
| 已有 OS4 + Arch，`sda15` 存在 | 升级 OS4 | 升级 | 否 | 否 | 否 | §2 + 04 §3/§4 |
| 已有 OS4 + Arch，`sda15` 存在 | 升级 Arch 内核/用户态 | 升级 | 否 | 否 | 否 | §2 + 05/06 |
| 旧版 `steamos` 双系统（分区名 `steamos`/ext4） | 迁移到本仓库 `archlinux`/btrfs | 迁移 | 否 | 否 | 已有（改名） | §2 迁移注 |
| 已有 OS4 + Arch | 加/改共享分区 `sda16` | 维护 | 否 | 否 | 否（已有） | §2 + 08 §1.1 |

判断「已有 Arch」的唯一标准：`sgdisk -p /dev/sda` 里有 15 号分区、名字 `archlinux`，
并且从 kShimC 菜单能启动 Arch。**只有分区没有 rootfs 不算；只有 rootfs 没有启动项也不算。**

> **硬约束**：TB710FU 原厂盘是分满的，`userdata` 是 f2fs + FBE，不能在线缩小。只要盘尾
> 没有现成的未分配空间，加装 Arch 就必须离线缩小 `userdata`（在 NBD 救援系统里改 GPT）。
> 这会强制 Android 重新格式化 `userdata`，**账号、应用、KSU 模块、内部存储全部丢失**，
> 即使你没有加 `--wipe`。想保留 Android 数据，就不要在已分满的盘上加 Arch。

---

## 2. 已有 `sda15`：升级与维护

这条路径**不重装、不分区、不 rsync**。日常切换/配对/共享分区直接按
[08-dualboot-share.md](08-dualboot-share.md)；要更新某一层，按下面选：

| 要更新什么 | 做法 | 注意 |
|---|---|---|
| OS4 `super` | [04 §3](04-os4-install.md#3-刷-super升级保留数据)（EDL）或 [04 §4](04-os4-install.md#4-从-arch-在线直写-super免-edl数据线)（Arch 在线） | 不加 `--wipe`；先备份 `super` 头/manifest；Android 不能在运行 |
| Arch 内核 / 模块 / `boot_a` | [05 §8](05-arch-kernel.md#8-安装模块与-boot) | 先备份 `boot_a`；只写 `boot_a`；重打 boot 后重生成 `pair.env` |
| Arch 用户态修复 | [06 §1](06-arch-userspace.md#1-安装与重刷后补装) | 先做 btrfs 快照；`IgnorePkg` 不能丢 |
| 双系统切换 / 共享分区 | [08](08-dualboot-share.md) | 只写 `boot_a`；`pair.env` 两侧必须同一份 |
| KSU 模块 | [09](09-runtime-modules.md) | Debloat 必须用户明确同意；停用模块 ≠ 恢复 |

**不要**因为「想干净」而 wipe 或重建 `sda15`。升级失败的正确顺序是：回退上一版
`super`/`boot_a` → 查 [10](10-troubleshooting.md) → 最后才是重装。

> **从旧版 `steamos` 布局迁移**：旧发布仓库的分区名可能是 `steamos`、ext4 标签
> `steamos-root`、NBD 导出名 `steamos`；本仓库的 initramfs 只认 `PARTNAME=archlinux` +
> `LABEL=archlinux-root`（btrfs `@` 或 ext4）。保留数据的最小迁移：
>
> ```bash
> # 只改分区名，不动起始扇区/唯一 GUID
> sgdisk -c 15:archlinux /dev/sda
> # ext4 根：
> e2label /dev/sda15 archlinux-root
> # 或 btrfs 根（已挂载也可）：
> btrfs filesystem label /dev/sda15 archlinux-root
> # 改 /etc/fstab 的根行；并换成本仓库的 boot/initramfs（旧 boot 可能还在找 steamos）
> ```
>
> NBD 导出名同步改成 `archlinux`。改完先 `sgdisk -v` + `blkid` 核对，再重启。

---

## 3. 从 stock/OS3 开始：首次安装（完整链）

> 这一节就是旧版发布文档里「首次安装」+「§3.2 分区」+「§3.3 NBD 试跑」的合并版。
> **只装 OS4、不装 Arch**：只做 §3.1 → §3.2 → §3.6，跳过 §3.3–§3.5、§3.7。
> OS4 super 的构建（03）和 Arch 内核（05）可以在任何物理写入之前先做好；本文只标出
> 设备侧写入的顺序。历史实测（2026-10-25）先刷 OS4、root 后收集固件，再从 NBD 建 Arch；
> 本文采用**先建 Arch 分区、再刷 OS4** 的顺序（旧文档 §3.2/§3.3 的顺序），原因是：
> `userdata` 缩小会让 Android 恢复出厂，放在 OS4 首次配置之前做，Android 只需要配置
> 一次。没有本机固件时，用 `tb710fu-firmware-*.tar.gz` 代替（§3.3）。两种顺序最终状态
> 相同，见 §3.9。

### 3.1 先备份（任何写入之前）

**没有备份不要改 GPT。** 解锁后、刷任何东西之前，进 9008 做下面几件事：

```bash
EDL=tools/venv/bin/edl
LOADER=work/firehose/prog_firehose_ddr-TB710FU.melf
L=(--loader="$LOADER" --memory=ufs)
mkdir -p work/backup/gpt work/backup/parts

# 1) 6 个 LUN 的 GPT 全打印（LUN 数按你的机器为准）
for lun in 0 1 2 3 4 5; do
  "$EDL" printgpt --lun=$lun "${L[@]}" > "work/backup/gpt/lun$lun.txt"
done

# 2) 可机读的 GPT 备份（能用来恢复分区表）
"$EDL" gpt work/backup/gpt --genxml "${L[@]}"

# 3) 唯一分区（约 3–5 GB；userdata/super 不背）
"$EDL" rl work/backup/parts --skip=userdata,super "${L[@]}"

# 4) 记录校验和，并把 work/backup 复制到另一块盘（Linux 用 sha256sum）
find work/backup/parts -type f -size 0 -print    # 应该没有输出
shasum -a 256 work/backup/parts/*.bin > work/backup/parts.sha256
```

必须包含：`persist`、`modemst1/2`、`fsg`、`fsc`、`devinfo`、`frp`、`keystore`、`ssd`、
`secdata`、`uefivarstore`、`cdt`、`ddr`。这些丢了 IMEI/校准/密钥就永久没了。

> **恢复是例外操作**：只在 GPT/唯一分区确实损坏、且备份 sha256 匹配时，才用 EDL 逐件
> `w` 写回（每件先核对 `work/backup/parts.sha256`）。日常安装/升级永远不写这些分区。

再额外保存一份**当前能启动的 Android 启动链**（只用于回退；kShimC 的底座是 §3.2 的 v3 链）：

```bash
# 已 root / 已开 USB 调试时（用 exec-out，避免 PTY 把二进制转成 CRLF）
adb exec-out "su -c 'dd if=/dev/block/by-name/boot_a'"    > work/stock/boot_a.img
adb exec-out "su -c 'dd if=/dev/block/by-name/vbmeta_a'"  > work/stock/vbmeta_a.img
adb exec-out "su -c 'dd if=/dev/block/by-name/init_boot_a'" > work/stock/init_boot_a.img
adb exec-out "su -c 'dd if=/dev/block/by-name/dtbo_a'"    > work/stock/dtbo_a.img
adb exec-out "su -c 'dd if=/dev/block/by-name/vendor_boot_a'" > work/stock/vendor_boot_a.img

# 没有 root 时，9008 里直接读（分区名以 printgpt 为准）
for p in boot_a vbmeta_a init_boot_a dtbo_a vendor_boot_a; do
  "$EDL" r "$p" "work/stock/${p}.img" "${L[@]}"
done
```

### 3.2 写 v3 启动链（A 槽，只写一次）

v3 链是**后面所有 kShimC 变体的 AVB 底座**：testkey、`vbmeta flags=1`、链 `boot`/
`recovery`/`vbmeta_system`。第一次安装必须先写它；升级用户不要重写。

**先做 §3.2.1 的判定，再执行本节命令。** 纯原厂起步跳过判定直接写 v3，最常见的结果是
写完掉 fastboot。

#### 3.2.1 前置判定：`recovery_a`/`vbmeta_system_a`/`pvmfw_a` 必须是 testkey 版

AVB 是**一条链**，不是逐分区独立校验：

```text
vbmeta_a（本节要写，testkey 签）
  └─ chain descriptor（公钥 + rollback index）
       └─> vbmeta_system_a（分区里原有的，必须也是 testkey 签）
             └─> system / system_ext / product
```

`make_v3_bootchain.py` 用 **AOSP testkey** 重签 `boot`/`recovery`/`vbmeta_system`，并把
`vbmeta_a` 里 chain 的公钥写成 testkey。如果 `vbmeta_system_a` 还是**联想官方签名**，
链的下一环公钥对不上 → AVB 失败 → 写完直接掉 fastboot/9008。`pvmfw_a`、`recovery_a`
另带防回滚索引（rollback index），不能自己重签，只能整件换。

**判定表：**

| 你的现状 | 判据 | 动作 |
|---|---|---|
| 已在跑 OS3 移植包（兰微卡鱼 428/414） | 这些分区来自移植包 | 已经是 testkey，直接做 §3.2 |
| 纯原厂 ZUI（366/428/495 带 UBL） | 官方签名 | 先刷 `495_WITHOUT_UBL` 的 `recovery`/`vbmeta_system`/`pvmfw` 三件（**不刷 vendor**），重启确认还能开机，再做 §3.2 |
| 不确定 / 接手别人的机器 | 用下面任一方法判 | 判完再决定 |

**方法 A（最可靠）：和 `495_WITHOUT_UBL` 包里的同名镜像逐件比 sha256**

```bash
# 1) 回读设备上的三个分区（没有 root 时在 9008 里用 edl r）
for p in recovery_a vbmeta_system_a pvmfw_a; do
  adb exec-out "su -c 'dd if=/dev/block/by-name/$p'" > "work/stock/$p.img"
  shasum -a 256 "work/stock/$p.img"          # Linux 用 sha256sum
done

# 2) 从 495_WITHOUT_UBL 包里解出同名镜像（包内文件名以 7z l 的结果为准）
7z l 1.5.04.495_WITHOUT_UBL_*.7z | grep -Ei 'recovery|vbmeta_system|pvmfw'
7z x 1.5.04.495_WITHOUT_UBL_*.7z -o work/rescue495/ \
     recovery.img vbmeta_system.img pvmfw.img
shasum -a 256 work/rescue495/*.img
```

三个都 **MATCH** → 已经是 495 基线，直接做 §3.2；任一 **DIFF** → 只刷那一件到对应的
`*_a`，刷完**重启确认还能进系统**，再回来做 §3.2。

**方法 B（没有 495 包时）：看签名公钥**

```bash
# 需要 tools/avb/（镜像地址与 sha256 校验见 02 §2.1.1）
python3 tools/avb/avbtool.py info_image --image work/stock/vbmeta_system_a.img | head -20
#   关注 Algorithm（期望 SHA256_RSA4096）和 "Public key (sha256)"

python3 tools/avb/avbtool.py verify_image --image work/stock/vbmeta_system_a.img \
        --key tools/avb/testkey_rsa4096.pem && echo "testkey OK"
```

`verify_image --key` 退出码 0 = 该镜像确实由这把 testkey 签名，可以继续；非 0 = 官方
签名，先按方法 A 换 495 的三件。

> `pvmfw_a` 不一定带标准 AVB footer，`info_image` 可能直接报错。这种时候只能走方法 A
> 的 sha256 比对——不要用“看起来像”的签名信息下结论。

> **只刷这三件，不要混 vendor。** 495 的 vendor 与 428 基线不同（温度阈值、节点名、
> mslg 路径），混进去会引入新的一批不一致；本项目基线仍是 428。见
> [02 §4.2/§4.3](02-materials.md)。

```bash
# 输入：OS3 移植包作者原版 boot/init_boot/dtbo/vendor_boot.img（放 work/author/，见 02 M2/M5；
# 包里没有就从现役 OS3 设备回读，必须是本机型 + GKI 6.1.128）
python3 tools/make_v3_bootchain.py work/author work/v3
# 需要 tools/avb/avbtool.py + testkey_rsa4096/2048.pem，见 02 §2.1.1（含 GitHub 镜像）
# 产物：work/v3/{boot,init_boot,dtbo,vendor_boot,vbmeta}.img

# 逐件写 A 槽（先链后 super）
for p in boot init_boot dtbo vendor_boot vbmeta; do
  "$EDL" w "${p}_a" "work/v3/${p}.img" "${L[@]}"
done
```

写后核对：五件的 sha256 与 `work/v3` 一致；`vbmeta` 的 flags 含 1。**不要写 B 槽**。
本步骤**不要动** `vbmeta_system_a`/`pvmfw_a`/`recovery_a`（它们带防回滚索引，改动方式见
§3.2.1 的判定表）。

```bash
# 回读校验（设备还在 9008；Linux 用 sha256sum）
for p in boot init_boot dtbo vendor_boot vbmeta; do
  "$EDL" r "${p}_a" "/tmp/${p}.readback" "${L[@]}"
  shasum -a 256 "work/v3/${p}.img" "/tmp/${p}.readback"
done
```

> **前置条件（已在上文 §3.2.1 判定）：** `recovery_a`、`vbmeta_system_a`、`pvmfw_a` 必须是
> OS3/WITHOUT_UBL（ZUI 495 基线）的 testkey 分区。三个都核对过 MATCH 才往下写；任何一件
> 是官方签名都会让这条链在 AVB 上断开，写完掉 fastboot。解锁 BL 不保证绕过这三个分区的
> 校验。
>
> 这一步之后原厂 Android 可能已经不能启动（boot/vbmeta 换成了移植链），这是预期的。
> 如果 NBD/Arch 准备失败，用 §3.1 的备份写回 `boot_a`/`init_boot_a`/`dtbo_a`/
> `vendor_boot_a`/`vbmeta_a` 即可回到原厂。

### 3.3 准备 Arch：NBD 镜像 + 内核 + boot

**a. rootfs 镜像（在主机上做，arm64 容器）**

```bash
IMG=work/arch/archlinux-tb710fu.img
truncate -s 32G "$IMG"          # 稀疏文件；装 Plasma/开发工具建议 48G
# 容器内（arm64 Debian/Arch；需要 parted/dosfstools/btrfs-progs；
# losetup/mount 需要 docker --privileged）：
parted -s "$IMG" mklabel msdos
parted -s "$IMG" mkpart primary fat32 1MiB 513MiB
parted -s "$IMG" mkpart primary 513MiB 100%
LOOP=$(losetup -fP --show "$IMG")
mkfs.vfat "${LOOP}p1"
mkfs.btrfs -q -f -L archlinux-root "${LOOP}p2"
mount "${LOOP}p2" /mnt
btrfs subvolume create /mnt/@
umount /mnt
mount -o subvol=@,compress=zstd "${LOOP}p2" /mnt
tar --xattrs --numeric-owner -xpf ArchLinuxARM-aarch64-latest.tar.gz -C /mnt
```

在 chroot 里至少装（先 `mount --bind /proc /sys /dev`，或直接用 `arch-chroot /mnt`）：

```bash
pacman-key --init && pacman-key --populate archlinuxarm
# 先锁内核/固件，避免 ALARM tarball 自带的 linux-aarch64 被 -Syu 升级
grep -q '^IgnorePkg' /etc/pacman.conf \
  || echo 'IgnorePkg = linux linux-aarch64 linux-firmware' >> /etc/pacman.conf
pacman -Syu --needed base sudo openssh networkmanager kmod btrfs-progs rsync gdisk
systemctl enable sshd NetworkManager
# 至少建一个 wheel 用户（SSH 登录用；用户名/密码按你的习惯）
U=youruser
useradd -m -G wheel "$U" && passwd "$U"
# 防止 NetworkManager 接管 NBD 救援链路 usb0
mkdir -p /etc/NetworkManager/conf.d
printf '[keyfile]\nunmanaged-devices=interface-name:usb0\n' \
  > /etc/NetworkManager/conf.d/90-tb710fu-usb0.conf
# 桌面可稍后再装；要现在装就加 plasma sddm konsole plasma-nm
# 若 ALARM latest 的 local DB 不全，按 06 §7.1 先补 DB；不要长期 -Sy 部分升级
# fresh rootfs 的 /etc/resolv.conf 可能是悬空符号链接；联网前 rm 后写 1.1.1.1
```

再把**内核模块、固件、用户态修复**装进镜像（否则 NBD 试跑看不到屏幕/触摸/WiFi/音频）。
下面的命令在**容器/主机**执行，不在 chroot 里；如果还停在 chroot，先 `exit`：

```bash
# 模块（05 的产物）
mkdir -p /mnt/lib/modules
tar xf work/kernel73/out/modules-7.3.0-tb710fu.tar -C /mnt/lib/modules
chroot /mnt depmod -a 7.3.0-tb710fu

# 固件二选一：
#   a) tb710fu-linux 的 firmware 包（推荐，含 ath12k/novatek/adsp/cdsp/zap/tplg）
tar xf <path>/tb710fu-firmware-*.tar.gz -C /mnt
#   b) 从已 root 的 HyperOS 收集（更贴近本机，但需要先有 root）
#      tools/collect_firmware.sh work/firmware && cp -a work/firmware/. /mnt/lib/firmware/

# 用户态服务/配置（音频/电源/温控/显示/键盘等）
U=youruser    # 与 chroot 里创建的用户一致
sudo ROOT=/mnt USER_NAME="$U" tools/arch-userspace/install-userspace.sh

# 收尾：卸载并释放 loop，镜像交给 nbd-server
sync; umount -R /mnt; losetup -d "$LOOP"
```

> 没有固件时，NBD 试跑只能验证 SSH/存储/基础命令；WiFi、音频、GPU、触摸固件都会失败，
> 不要把它当成“硬件没问题”。用 `dmesg | grep -i firmware` 确认没有 load 失败。

**三条禁令**（否则 UFS 上的 Arch 起不来）：

1. 不装 `linux` / `linux-aarch64`——内核由 `boot_a` 提供；
2. 不装 `linux-firmware`——固件用 `tb710fu-firmware-*.tar.gz` 或从本机收集的
   `work/firmware/`（[02](02-materials.md) M7/§4.7）；
3. 不装 dkms / 任何内核模块包——模块在 `modules-7.3.0-tb710fu.tar` 里。

确认 `/etc/pacman.conf` 已有 `IgnorePkg = linux linux-aarch64 linux-firmware`，且
`/sbin/init` 存在且可执行。

**b. 内核 + boot**

按 [05](05-arch-kernel.md) 构建 `Image`、`DTB`、`modules-7.3.0-tb710fu.tar`（默认在 `work/kernel73/out/`），然后打包
两个菜单默认变体：

```bash
# STOCK_BOOT 必须指向 §3.2 的 v3 Android-only boot，不要用当前 kShimC boot_a
# kShimC.bin 的构建见 02 §4.9；产物复制到 work/kshim/
STOCK_BOOT=work/v3/boot.img VBMETA=work/v3/vbmeta.img \
SHIM=work/kshim/kShimC.bin OUT=work/boot \
tools/kshim_variants.sh v36 work/kernel73/out/Image work/kernel73/out/sm8650-lenovo-tb710fu-kshim.dtb
# -> work/boot/current/boot_android.img（默认 HyperOS）
# -> work/boot/current/boot_linux.img  （默认 Arch）
```

> VBMETA 默认用 §3.2 的 `work/v3/vbmeta.img`；如果设备已经装过 KSU/Magisk（历史顺序或
> §4 加装 Arch），改用当前设备回读的 `vbmeta_a`（KSU 可能改过它）：
> `adb exec-out "su -c 'dd if=/dev/block/by-name/vbmeta_a'" > work/stock/vbmeta_a.img`。
> `STOCK_BOOT` 始终用 `work/v3/boot.img`，不能用当前的 kShimC `boot_a`（它已经是多内核载荷）。

> **NBD 不需要另打变体**：kshim DTB 的 `/chosen/bootargs` 默认带
> `tb710fu.nbd nbd.max_part=8`。第一次安装盘上还没有 `sda15`，`boot_linux` 的 initramfs
> 会先找 `PARTNAME=archlinux`，找不到就自动走 NBD。`tools/kshim_variants.sh` 会用
> `tools/avb/` 校验 AVB；缺 `tools/avb` 先按 [02 §2.1/§2.2](02-materials.md) 准备。

**c. NBD 服务（Mac/Linux 主机）**

`nbdroot.sh` 固定：USB NCM 网段 `172.16.42.0/24`、平板 `172.16.42.1`、端口 `10809`、
导出名 `archlinux`。主机上准备：

```ini
# work/arch/nbd.conf
[generic]
    user = root
    group = root
    allowlist = true
[archlinux]
    exportname = /img/archlinux-tb710fu.img
    flush = true
```

```bash
# 任选其一：主机已装 nbd-server；或 Debian 容器（macOS Docker 用 -p，不要 --network host）
docker run -d --name tb-nbd-server -p 10809:10809 \
  -v "$PWD/work/arch":/img \
  -v "$PWD/work/arch/nbd.conf":/etc/nbd-server/config:ro \
  debian:trixie \
  sh -c 'apt-get update -qq && apt-get install -y -qq nbd-server && \
         nbd-server -C /etc/nbd-server/config; exec sleep infinity'

# macOS 试跑期间别让主机睡
caffeinate -dims &
```

> `nbd-server -d` 只服务一个连接就退出，必须用上面的常驻模式。镜像必须是
> **512 字节扇区 MBR**（`nbd-client -b 512` 固定）；p2 是根。initramfs 用 busybox 的
> `nbd-client`/`udhcpd`/`nc`；Debian trixie 的 busybox 1.37 已包含，太旧的 busybox 会失败。

### 3.4 NBD 试跑（不改设备存储）

先把 `boot_linux`（默认 Arch）写到 `boot_a`（保留当前 `boot_a` 备份），重启。下面的
`$EDL`/`${L[@]}` 沿用 §3.1 的定义：

```bash
"$EDL" r boot_a work/backup/boot_a.before-nbd.img "${L[@]}"   # 备份当前 boot_a
$EDL w boot_a work/boot/current/boot_linux.img "${L[@]}"
```

initramfs 会建 USB NCM、跑 udhcpd、扫描 `172.16.42.2–.10:10809`，用
`nbd-client -b 512 -N archlinux ... /dev/nbd0` 挂 `nbd0p2` 的 `@`。看到
`nbdroot: root on /dev/nbd0p2` 后，在平板上逐项验收：

> 主机侧确认 USB NCM 网卡拿到了 `172.16.42.x`（macOS 自动 DHCP；Linux 可
> `sudo dhclient <iface>`）。主机连的是平板的 `172.16.42.1`，不是家里路由器网段。

- [ ] SSH 能登录（`ssh <user>@172.16.42.1`）；
- [ ] WiFi 能连（`ip link` 有 `wlan0`，`nmcli device status` 能连上你的 AP）；
- [ ] 触摸可用，`cat /sys/class/power_supply/*/capacity` 有正常电量；
- [ ] 扬声器出声（`aplay` 或桌面音量条），WirePlumber 不卡死；
- [ ] 屏幕亮度可调，没有花屏/黑屏；
- [ ] 你的桌面/输入法/网络工具能启动。

**不要在 NBD 根盘上测 `s2idle`**：USB 断链会让 NBD 上的 btrfs 数据块 EIO，缓存可重建但
试跑会中断。s2idle 留到 UFS 安装后测。试跑期间**不能拔线、不能让主机睡**。

任何一项不过 → 停在 NBD 修，修好后可以反复重试，**不要进 §3.5**。

### 3.5 缩 userdata、建 `sda15`、rsync（在 NBD Arch 里执行）

> 这一步会改 GPT、清 `userdata` 头，**Android 数据从这一刻起不可恢复**。执行前确认
> §3.1 的 GPT/唯一分区备份已经复制到另一块盘。

下面的扇区号只适用于 **256 GB 机型**（`sda14 userdata = 5105064..61390842`，4 KiB
逻辑扇区）。其它容量先用 `sgdisk -p /dev/sda` 自己算，不要照抄。

```bash
D=/dev/sda
M=11    # metadata 分区号（作者机器）；用 sgdisk -p 确认你的编号
[ "$(blockdev --getss $D)" = 4096 ] || { echo "不是 4K 扇区，停止"; exit 1; }
sgdisk -i 14 $D | grep -q "Partition name: 'userdata'" || { echo "sda14 不是 userdata"; exit 1; }
sgdisk -i 14 $D | grep -q "Last sector: 61390842" || { echo "布局不是原厂 256GB，先自己算"; exit 1; }
# metadata 在作者机器上是 sda11；你的机器不一定，先用 sgdisk -p 找到名字为 metadata 的编号
sgdisk -i $M $D | grep -q "Partition name: 'metadata'" || { echo "sda$M 不是 metadata"; exit 1; }
for p in $M 14; do
  ! grep -q "^/dev/sda$p " /proc/mounts || { echo "sda$p 还被挂载，停止"; exit 1; }
done

# 1) 备份 GPT（二进制，可恢复；改完立刻 scp 回主机留档）
#    恢复（只在分区表损坏时，在 NBD/救援 Linux 里）：
#    sgdisk --load-backup=/path/gpt-before-install.bin $D && partx -u $D
sgdisk --backup=/tmp/gpt-before-install.bin $D

# 2) 缩小 sda14，新建 sda15 archlinux；名称/类型/唯一 GUID 保留
#    -a 1 保持原始 5105064 起始扇区，不让 sgdisk 自动对齐挪动
G=$(sgdisk -i 14 $D | sed -n 's/^Partition unique GUID: //p')
T=$(sgdisk -i 14 $D | sed -n 's/^Partition GUID code: \([0-9A-Fa-f-]*\).*/\1/p')
[ -n "$G" ] || { echo "读不到 userdata GUID"; exit 1; }
[ -n "$T" ] || T=1B81E7E6-F50D-419B-A739-2AEEF8DA3335
sgdisk -a 1 -d 14 \
  -n 14:5105064:27836415 -c 14:userdata \
  -t 14:"$T" -u 14:"$G" \
  -n 15:27836416:61390842 -c 15:archlinux -t 15:8300 $D
sgdisk -v $D | tail -2
partx -u $D || partprobe $D
sleep 2
[ -b /dev/sda15 ] || { echo "sda15 没出现，停止"; exit 1; }
sgdisk -i 14 $D | grep -E "name|First|Last|unique"
sgdisk -i 15 $D | grep -E "name|First|Last"

# 3) 清 userdata / metadata 头，让 Android 在缩小的分区上重新格式化
dd if=/dev/zero of=/dev/sda14 bs=1M count=64 conv=fsync status=none
dd if=/dev/zero of=/dev/sda$M bs=1M conv=fsync status=none

# 4) btrfs + 子卷 @
mkfs.btrfs -q -f -L archlinux-root /dev/sda15
mkdir -p /mnt/archlinux
mount -o compress=zstd /dev/sda15 /mnt/archlinux
btrfs subvolume create /mnt/archlinux/@
umount /mnt/archlinux
mount -o subvol=@,compress=zstd /dev/sda15 /mnt/archlinux

# 5) 把当前 NBD 根完整复制到 @（-x 不跨 /proc /sys /dev /mnt）
rsync -aHAXx --numeric-ids --info=stats1 / /mnt/archlinux/
mkdir -p /mnt/archlinux/{proc,sys,dev,run,tmp,boot,mnt}
echo 'LABEL=archlinux-root  /  btrfs  subvol=@,compress=zstd,noatime  0 0' \
  > /mnt/archlinux/etc/fstab
sync; df -h /mnt/archlinux; umount /mnt/archlinux
echo INSTALL-OK
```

**检查点**：`INSTALL-OK`；`sgdisk -p /dev/sda` 里 14 号是 `userdata`、15 号是 `archlinux`；
`blkid /dev/sda15` 的 LABEL 是 `archlinux-root`。失败不要反复 `mkfs`，先看
[10](10-troubleshooting.md)。

> 这里建的是 **128 GiB** 的 `sda15`；如果你之后要建 8 GiB 共享分区，按
> [08 §1.1](08-dualboot-share.md) 在线缩到 120 GiB + `sda16`。

### 3.6 首次刷 OS4（`--wipe` 只这一次）

v3 链已经在 §3.2 写好，这里主要写 super。**双系统**用户先把 `boot_a` 切回默认
HyperOS（`boot_android`），方便首启进 Android 向导；**只装 OS4、不装 Arch** 的用户
没有 `boot_android`，保持 §3.2 的 v3 `boot_a` 不动即可：

```bash
# 沿用 §3.1 的 EDL/LOADER/L
if [ -f work/boot/current/boot_android.img ]; then
  "$EDL" w boot_a work/boot/current/boot_android.img "${L[@]}"
else
  echo "only-OS4: keep the v3 boot_a (Android-only); skip kShimC"
fi

# 设备进 9008/EDL；显式传 EDL/LOADER，避免脚本默认找 PATH 里的 edl
EDL=tools/venv/bin/edl \
LOADER=work/firehose/prog_firehose_ddr-TB710FU.melf \
bash tools/flash_super.sh work/build_os4/out/super_fixed.img --wipe
```

`--wipe` 会再清一次 `metadata` + `userdata` 头（`--wipe` 只这一次；如果前面按 §3.5
缩过 userdata，那是另一次数据清除，不算 `--wipe`）。super 构建见
[03](03-os4-build.md)；刷入检查点见 [04 §5](04-os4-install.md#5-首次安装从-stockos3-开始会清-data)。

> OS4 构建需要 `hyperos/camera/{Aperture.apk,CameraParallelServiceStub.apk}`（第三方，
> 不随仓库分发，见 [02 M13](02-materials.md) / `hyperos/camera/README.md`）。`port_build.sh`
> 会在输入检查阶段报错，不会静默跳过。

首次开机向导：

1. **不要登录小米账号**，**不要打开「查找设备」**；
2. 完成向导，打开开发者选项 + USB 调试；
3. 如果卡激活检查：用 `TB_NO_FINDDEVICE=1` 构建的 super 过向导，再脏刷正常 super
   （不加 `--wipe`）；
4. 装 KernelSU-Next APK → app 内「安装」→「直接安装」（写 `init_boot_a`）→ 重启 →
   设置里开 ADB Root；
   > KSU 会改 `init_boot_a`，可能同时更新 vbmeta；不要手工只改文件。若重启落 fastboot，
   > 先写回 §3.1 的 `init_boot_a`/`vbmeta_a` 再按 app 内流程重试。
5. `modules/build_modules.sh` → `tools/post_flash_modules.sh <serial>` → 重启；
6. `tools/verify_device.sh <serial>`，期望 0 failed。

> 不要在这一步重写 `init_boot_a` 的 v3 链，否则 KSU 会被覆盖。以后所有 boot 重打都用
> `work/v3/boot.img` 作底座，**不要**用当前的 kShimC `boot_a`。

### 3.7 写 kShimC 配对 boot，首启 Arch

```bash
# 沿用 §3.1 的 EDL/LOADER/L 定义
# §3.6 已经写过 boot_android 的话，这一步可跳过；否则补写
$EDL w boot_a work/boot/current/boot_android.img "${L[@]}"
```

> 如果 KSU 改过 `vbmeta_a`，先用当前回读的 `vbmeta_a` 按 §3.3b 重跑
> `kshim_variants.sh`，再写 `boot_a`；不要拿 KSU 之前的旧 boot 镜像硬写。

重启确认 kShimC 菜单能进 OS4；然后按 [08](08-dualboot-share.md) 生成 `pair.env`、装
`switch2os4`/`switch2arch`，或直接把 `work/boot/current/boot_linux.img` 写 `boot_a`
首启 Arch。首次 Arch 黑屏 2–3 分钟是正常的（内核 + 根盘冷启动）。

首启 Arch 后：

```bash
# 确认根盘
df -h /
# 期望 /dev/sda15

# 装用户态修复（音频/电源/温控/内存/桌面）
# NBD 阶段已经用 ROOT=/mnt 装过的话，这里可以跳过；重跑也是幂等的
sudo tools/arch-userspace/install-userspace.sh
# 重启后按 06 §1 的清单验收
```

> **Arch 起不来时的救援**：主机重新起 NBD 服务，`boot_a` 写 `boot_linux`；initramfs 会先
> 试 `sda15`，挂不上或没有 `/sbin/init` 就自动走 NBD，进去修 `sda15`。只想先回 Android：
> 写回 `boot_android` 或 §3.1 的 `work/v3/boot.img`。

### 3.8 首次验收清单

- [ ] `adb shell getprop ro.boot.slot_suffix` = `_a`（或 fastboot `current-slot` = `a`）；没有切过 B；
- [ ] OS4：`sys.boot_completed=1`、USB 调试、KSU `su -c id`；
- [ ] Arch：`df /` = `/dev/sda15`、`uname -r` = `7.3.0-tb710fu`；
- [ ] 双系统：`sudo switch2os4 --status` / `adb shell su -c /data/adb/tbboot/switch2arch.sh --status` 能读 `pair.env`；
- [ ] 重启选 Arch 能进；选 HyperOS 能进 OS4；
- [ ] 共享分区（可选）：按 [08 §1.1](08-dualboot-share.md) 建 `sda16`，双向读写通过；
- [ ] 备份：`work/backup/`、`work/v3/`、`work/boot/`、`pair.env` 已复制到另一块盘；升级时还有 `work/build_os4/rollback_prev/`。

### 3.9 顺序说明：为什么先建 Arch 分区

历史实测（2026-10-25）用的是另一种顺序：**先刷 OS4（`--wipe`）→ 配置 Android →
再从 NBD 缩 userdata/建 `sda15`**。这样 Android 会被重置两次（首次 `--wipe` 一次，
缩 userdata 又一次），所以本文把 Arch 分区提前到 OS4 首次配置之前：

```text
本文顺序：备份 → v3 链 → NBD 试跑 → 缩 userdata/建 sda15/rsync → 首次刷 OS4 --wipe → 配置 Android
历史顺序：备份 → 首次刷 OS4 --wipe → 配置 Android/root/收集固件 → 打 kShimC → NBD 试跑
          → 缩 userdata/建 sda15/rsync → 再配置一次 Android
```

两种顺序的最终状态一致。选历史顺序也可以，但要把 §3.6 移到 §3.3 之前，并且记住
§3.5 仍会清一次 Android 数据；之后不需要再 `--wipe`。历史顺序的好处是能先用
`collect_firmware.sh` 从已 root 的本机收集固件；本文顺序则用
`tb710fu-firmware-*.tar.gz` 代替（见 §3.3）。

---

## 4. 已刷本项目 OS4、没有 Arch：加装 Arch

这条路**不需要**改 `super`、不需要 `super --wipe`，通常也不需要重写 v3 链；但**需要缩
userdata**，所以 Android 数据仍会丢（见 §1 的硬约束）。步骤：

1. 确认 `work/v3/` 还在。如果当前 `boot_a` 还是 **Android-only**（没装 kShimC），可以直接
   EDL 回读 `boot_a`/`init_boot_a`/`dtbo_a`/`vendor_boot_a` 到 `work/author/`（重命名为
   `boot.img`/`init_boot.img`/`dtbo.img`/`vendor_boot.img`），再跑 `make_v3_bootchain.py`
   重建 `work/v3/`（仅当当前链是本项目/OS3 的 Android-only testkey 链；原厂链不要直接重签）；
   如果 `boot_a` 已经是 kShimC，找当时的旧备份。
   **不要**在 KSU 装好之后重写 `init_boot_a`，否则 root 丢失；
2. 按 §3.3 准备 NBD 镜像、内核、boot；
3. 按 §3.4 做 NBD 试跑；
4. 按 §3.5 缩 userdata、建 `sda15`、rsync；
5. 按 §3.7 写 kShimC 配对 boot；
6. 首启 Arch，按 §3.7 末尾装用户态。

如果你已经有 `sda15` 且 Arch 能启动，不要走本节——直接看 §2。

---

## 5. 时间、空间与风险

| 项 | 量级 |
|---|---|
| 主机空闲磁盘 | ≥100 GB（OS4 解包/构建 + Arch 32 GB 镜像 + 备份） |
| 9008 备份 | 约 3–5 GB；必须复制到另一块盘 |
| OS4 构建 | 2–4 h（视机器） |
| Arch 内核构建 | 20–40 min |
| NBD rootfs + 基础包 | 10–15 GB；加 Plasma/开发工具 20–30 GB；镜像 32 GB 起步 |
| 首次安装总时间 | 半天到一天（含构建）；用现成产物 1–2 h |

风险与红线：

- 解锁清数据、失保修；本项目从「已解锁」开始；
- 改 GPT 不可逆（除非有备份）；扇区号只适用于 256 GB；
- `--wipe` 和缩 userdata 都会清 Android 数据；升级永远不做；
- 只写 A 槽；`super _b` 全 0 extent，`boot_b` 不是备份；
- 不恢复旧 `userdata` 整盘镜像（TEE 防回滚，PIN 可能永远解不开）；
- 不在 OS4 里点系统 OTA；不用 `fastboot set_active b`；
- NBD 试跑期间不拔线、不睡眠；不在 NBD 根盘上测 s2idle；
- 每次物理写入前确认分区名；`persist`/`modemst*`/`fsg`/`fsc`/`devinfo`/`frp`/`keystore`/
  `ssd`/`secdata`/`uefivarstore`/`cdt`/`ddr` 永不写。

---

## 6. 旧文档映射

| 旧版文档 | 内容 | 本文对应 |
|---|---|---|
| 旧 `docs/03-install.md` §1「两种路径」 | 升级 vs 首次安装 | §1 决策表 |
| 旧 `docs/03-install.md` §2.2 | GPT/唯一分区备份 | §3.1 |
| 旧 `docs/03-install.md` §4.1–§4.2 | v3 链 + `super --wipe` | §3.2、§3.6 |
| 旧 `docs/06-linux-arch.md` §3.2 | 缩 `sda14`、建 `sda15` | §3.5 |
| 旧 `docs/06-linux-arch.md` §3.3 | NBD 试跑 + rsync | §3.3、§3.4、§3.5 |

旧版的 `steamos` 分区名/ext4 标签/`-N steamos` 导出名已全部作废；本仓库统一为
`archlinux` + btrfs `archlinux-root` + `-N archlinux`。
