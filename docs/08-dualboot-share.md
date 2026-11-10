# 08 — 双系统切换与共享分区

> 原理一句话：`boot_a` 是一个 kShimC 镜像，里面同时有 GKI（HyperOS）、Linux 7.3（Arch）
> 和 DTB，菜单默认项在打包时固化。**切换 = 把对应默认变体写回 `boot_a` + 回读校验**，
> 没有运行时「下次启动选择」。
> 本仓库不包含任何 boot 镜像；配对哈希由 `tools/make-pair.sh` 用你自己的镜像生成。

> **本文不是首次安装手册。** 它假设 `sda15 archlinux` 已经存在且 Arch 能启动，只讲
> 配对、切换、共享分区。盘上还没有 `sda15`、或你要从 stock/OS3 第一次装双系统，先看
> [00-install-paths.md](00-install-paths.md) §3/§4；不要对不存在的 15 号分区执行
> `sgdisk -d 15`。

---

## 1. 分区布局

| 分区 | 大小 | 用途 | 备注 |
|---|---|---|---|
| `sda14 userdata` | 86.7 GiB | Android FBE f2fs | 不动；两边都读不了 |
| `sda15 archlinux` | **120 GiB**（原 128） | Arch btrfs `/` | 在线缩 8 GiB，GUID 保留 |
| `sda16 share` | **8 GiB** | ext4，两侧共用 | `LABEL=share` |

> **本节扇区号是作者机器的示例**（`sgdisk -p /dev/sda` 得到）。你的机器布局可能不同，
> 必须把 `27836416` / `61390842` / `+120GiB` 换成你自己的值；改之前先备份 GPT。
> `sda15` 在 **`userdata` 之后**（不是紧贴 `super`）：`super` 物理约 20.4 GB（约 19 GiB），
> `userdata` 从约 19.5 GiB 到盘尾，`sda15` 是从 `userdata` 尾部切出来的（约 106 GiB 处）。

盘是 4 KiB 逻辑扇区、共 61,390,848 扇区（234.2 GiB），原先已分满。`userdata` 是 f2fs
且 FBE 加密，**不能在线缩**；已经有 `sda15` 时，唯一可动的是 btrfs 的 `sda15`。第一次
从原厂布局建 `sda15` 必须在 NBD 救援系统里离线缩 `userdata`，见
[00-install-paths.md](00-install-paths.md) §3.5。

### 1.1 创建共享分区（Arch 侧）

> ⚠️ **这是全项目唯一一处“改分区表”的操作，做错会删掉 Arch 根分区。** 它只在线缩
> btrfs 的 `sda15` 尾部 8 GiB 给 `sda16`，不碰 `super`/`userdata`。执行前必须同时满足：
>
> 1. `sgdisk -p /dev/sda` **能看到 15 号分区**（盘上已有 `sda15`）；没有就停，先回
>    [00-install-paths.md](00-install-paths.md) §3 做首次安装；
> 2. `btrfs filesystem resize -8G /` 已经成功（`btrfs filesystem usage /` 出现
>    `Device slack 8.00GiB`）；
> 3. GPT 已备份（`sgdisk --backup=work/backup/sda.gpt /dev/sda`）。
>
> **`sgdisk -d 15` 只能执行一次，且只在“确认 15 号存在、准备原参数重建”时执行。**
> 如果 `partx -u` 之后 `/dev/sda16` 没出现，说明 **GPT 已经写成功了**——这时候再执行一次
> `sgdisk -d 15`，删掉的是刚重建的 15 号（等于把 Arch 根分区的 GPT 记录删了）。正确动作是
> **重启**，然后只补 `mkfs.ext4`。
>
> 逐步判定（Agent 每步前都要回读，不要连跑脚本）：
>
> | `sgdisk -p` / 设备节点 | 含义 | 动作 |
> |---|---|---|
> | 有 16 号，`/dev/sda16` 存在 | 已经建好 | 跳过本节 |
> | 有 16 号，`/dev/sda16` 不存在 | GPT 写了、内核没刷新 | **重启** → `mkfs.ext4 -q -L share -m 0 /dev/sda16` |
> | 没有 16 号 | 还没做 | 从 `btrfs filesystem resize -8G /` 开始 |
> | `sgdisk -d 15` 报 `Could not delete partition 15` | 15 号不存在或忙 | **停止**，不要重试；先 `sgdisk -p` 看清再决定 |

```sh
swapoff /swap/swapfile 2>/dev/null || true
btrfs filesystem resize -8G /

# 记下 sda15 的 GUID，删掉重建（起始扇区/类型/名称/GUID 不变），再建 sda16
GUID=$(sgdisk --info=15 /dev/sda | awk '/Partition unique GUID/{print $4}')
sgdisk -a 1 -d 15 -n 15:27836416:+120GiB -u 15:"$GUID" -c 15:archlinux -t 15:8300 \
       -n 16:0:0 -c 16:share -t 16:8300 /dev/sda
partx -u /dev/sda
mkfs.ext4 -q -L share -m 0 /dev/sda16
swapon /swap/swapfile 2>/dev/null || true
```

注意：

- 缩完 `btrfs filesystem usage` 会显示 `Device slack 8.00GiB`，重启即消失；
- **内核忙时 `partx -u` 可能不刷新分区表**（分区正被 mount/使用）：此时 GPT 已写成功，
  重启一次再 `mkfs.ext4 -q -L share -m 0 /dev/sda16`。**不要重复 `sgdisk -d 15`**，
  也不要 `partx -a` 反复试——见本节开头的判定表；
- GPT 改写只动 sda15 尾部 + 新增 sda16，**不碰 super/userdata**；
- `sgdisk -v` 校验；
- 你自己的 UUID/GUID 用 `blkid`/`sgdisk` 读，文档里的 `<share-uuid>`/`<archlinux-partuuid>`
  都是占位符。

---

## 2. 生成配对文件

```bash
# boot_android.img / boot_linux.img 从 tools/kshim_variants.sh 得到（同一次打包）
tools/make-pair.sh boot_android.img boot_linux.img > pair.env
cat pair.env
```

`pair.env` 内容：

```text
PAIR_VERSION=local-YYYYMMDD
HASH_ANDROID=<64 位>
HASH_LINUX=<64 位>
ANDROID_SIZE=100663296
LINUX_SIZE=100663296
```

**两边必须用同一个 `pair.env`。** 重新构建内核/重打 boot 后必须重新生成并同步两侧，
否则切换脚本会拒绝写入（这是防呆，不要 `--force`）。

---

## 3. Arch 侧安装

```bash
# 目录
sudo mkdir -p /usr/local/share/tbboot/backup
sudo install -m 755 tools/arch-side/switch2os4 /usr/local/bin/switch2os4
sudo install -m 644 pair.env /usr/local/share/tbboot/pair.env
sudo install -m 600 boot_android.img /usr/local/share/tbboot/boot_android.img
sudo install -m 600 boot_linux.img   /usr/local/share/tbboot/boot_linux.img
printf '%s  boot_android.img\n' "$(grep '^HASH_ANDROID=' pair.env | cut -d= -f2)" \
  | sudo tee /usr/local/share/tbboot/boot_android.img.sha256
```

可选桌面项：

```bash
sudo install -m 440 tools/arch-side/tb-switch.sudoers /etc/sudoers.d/tb-switch
sudo install -m 755 tools/arch-side/tb-switch2os4.desktop /usr/share/applications/
```

`tb-switch.sudoers` 用 `%wheel` 组，不含具体用户名；只放行无参数/`--status`/`--dry`/
`--no-reboot` 四种固定调用，`--restore`/`--force` 仍需真实 root 密码。如你的用户不在
wheel，自行调整。

### 3.1 切换（Arch → OS4）

```bash
sudo switch2os4 --status      # 只读：boot_a 是哪个变体
sudo switch2os4 --dry         # 全程检查但不写
sudo switch2os4               # 备份 -> 写 boot_a -> 回读 -> 询问后重启
sudo switch2os4 --no-reboot   # 只写不重启
```

写入前会：

- 校验 `boot_android.img` 的 sha256 等于 `pair.env` 的 `HASH_ANDROID`；
- 备份当前 `boot_a` 到 `backup/`（保留最近 3 份）；
- 只写 `/dev/disk/by-partlabel/boot_a`。

---

## 4. OS4 侧安装

```bash
TB_SERIAL=<serial> tools/os4-switch/install_switch2arch.sh boot_linux.img pair.env
```

安装器会：

1. 校验 `boot_linux.img` 的 sha256 等于 `pair.env` 的 `HASH_LINUX`；
2. 身份守门：`ro.product.device` ∈ {piano, TB710FU, tb710fu}，`ro.soc.model` = SM8650*；
3. push 到 `/data/local/tmp`，由 `device_install.sh` 落到：
   - `/data/adb/tbboot/{boot_linux.img,boot_linux.img.sha256,switch2arch.sh,pair.env}`
   - `/data/adb/modules/tb710fu_switch/{module.prop,action.sh}`
4. 跑 `--status` / `--dry` 自检。

切换：

```bash
# KernelSU 管理器 -> 模块 -> "TB710FU 系统切换" -> 执行动作
# 或
adb shell su -c /data/adb/tbboot/switch2arch.sh --yes
```

写入前同样备份 `boot_a` 并回读校验；失败自动回滚。

---

## 5. 共享分区

### 5.1 Arch 侧

```conf
# /etc/fstab
LABEL=share  /mnt/share  ext4  rw,noatime,nofail  0 2
```

- 根目录 `0777` + 默认 ACL；
- `~/Share -> /mnt/share` 软链；
- `tb-share-fixperm.service`（oneshot，`multi-user.target`）：

```ini
[Service]
Type=oneshot
ExecStart=-/usr/bin/chmod -R a+rwX /mnt/share
RemainAfterExit=yes
```

为什么需要：Android 拷出的文件保留源权限（`0660`/`0600`），Arch 用户读不了；
开机扫一遍即可覆盖「Android 里拷完就切回 Arch」的场景。

### 5.2 OS4 侧

模块 `TB710FUShareMount` v1.1（源码 `modules/TB710FUShareMount/`）：

```sh
DEV=/dev/block/by-name/share; [ -b "$DEV" ] || DEV=/dev/block/sda16
mkdir -p /mnt/share
grep -qs " /mnt/share " /proc/mounts && exit 0
[ "$(blockdev --getro "$DEV" 2>/dev/null)" = "1" ] && blockdev --setrw "$DEV"
mount -t ext4 -o rw,noatime "$DEV" /mnt/share || exit 0
chcon u:object_r:media_rw_data_file:s0 /mnt/share 2>/dev/null
chmod 0777 /mnt/share 2>/dev/null
```

两个坑：

| 坑 | 现象 | 根因 | 解法 |
|---|---|---|---|
| `mount -o context=` | 报误导性 `read-only` + `Permission denied` | SELinux 要求 `associate`，只有 vold/init 有 | 去掉 `context=`，挂载后 `chcon` |
| 无 `context=` | 挂载点是 `unlabeled` | `/mnt/share` 不在策略里 | `chcon` 挂载点，新文件继承标签 |

Android 的 `fs_mgr` 可能把非 fstab 分区置只读，`blockdev --setrw` 兜底。

### 5.3 验收

```bash
# OS4 写
adb shell su -c 'echo hello > /mnt/share/probe_os4.txt'
# Arch 读
cat /mnt/share/probe_os4.txt
# Arch 写
echo hi > /mnt/share/probe_arch.txt
# OS4 读
adb shell su -c 'cat /mnt/share/probe_arch.txt'
```

`ls -Z /mnt/share` 应为 `media_rw_data_file`；0600 文件在 `tb-share-fixperm` 后可读。

---

## 6. 回退

```sh
# OS4：卸共享模块
su -c 'ksud module uninstall tb710fu_share_mount'

# OS4：卸切换模块
su -c 'ksud module uninstall tb710fu_switch'

# Arch：取消挂载/权限扫描
systemctl disable --now tb-share-fixperm.service
umount /mnt/share

# 彻底恢复 128 GiB（删除 sda16 后把 sda15 长回去）
sgdisk -d 16 /dev/sda
GUID=$(sgdisk --info=15 /dev/sda | awk '/Partition unique GUID/{print $4}')
sgdisk -a 1 -d 15 -n 15:27836416:61390842 -u 15:"$GUID" -c 15:archlinux -t 15:8300 /dev/sda
partx -u /dev/sda && btrfs filesystem resize max /
sed -i '/LABEL=share/d' /etc/fstab
```

> 如果 `partx -u` 后 `/dev/sda15` 仍是 120 GiB（分区忙），重启后再执行
> `btrfs filesystem resize max /`。

---

## 7. 红线

1. 只写 `boot_a`；**不写 `boot_b`**（super `_b` 全 0 extent，boot B 与 A 不同）；
2. 不写 `misc`/`bcb`；不调用 OTA/`update_engine`；
3. 不在 OS4 里点系统更新；
4. 切换前等文件拷贝完成；
5. 不用 `--force` 绕过 `pair.env` 校验；
6. 不把共享分区改成 exFAT（7.3 内核没编 `exfat` 模块），也不塞进 `/sdcard` 的 FUSE 视图；
7. 小米文件管理器没有 root 模式，看不到 `/mnt/share`；用 MT管理器/MiXplorer/Solid Explorer。
