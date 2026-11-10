# 隐私与脱敏说明（发布前必读）

本仓库是从作者自己的 TB710FU 工作区整理出的**公开发布版**。整理时做了两类处理：

1. **删除**：任何官方/第三方二进制、设备备份、日志、账号、密钥、个人路径；
2. **替换**：所有能唯一指向某一台设备的值（MAC、序列号、内网 IP、分区 UUID）
   换成明显的占位符。

**占位符不能直接用于你的设备。** 本文告诉你每个值从哪里来、怎么换成你自己的。

---

## 1. 已替换的标识

| 值 | 仓库中的占位符 | 出现位置 | 说明 |
|---|---|---|---|
| 蓝牙工厂地址 | `02:11:22:33:44:55` | `patches/kernel/full/0020-…`、`incremental/0001-…` | 必须换成你机器的 `bd_addr`，见 §2 |
| DTS 小端字节序 | `[55 44 33 22 11 02]` | 同上 | 与 MAC 同一行，按字节倒序写 |
| 其他设备的蓝牙地址 | 已统一改为 `02:11:22:33:44:55` / `[55 44 33 22 11 02]` | `patches/kernel/full/0001-…` 的其他机型 DTS、`0002-tb-base.patch` 注释 | 上游/旧指南里的真实或示例地址一律不保留 |
| Wi-Fi 工厂地址 | `02:11:22:33:44:56` | 文档中的举例 | 通常 = BT 地址末位 +1，以你机器为准 |
| SoC 序列号推导地址 | `00:03:7F:00:00:00` | 文档中的举例 | 只保留 Qualcomm OUI，去掉后 3 字节 |
| 蓝牙键盘地址 | `02:11:22:33:44:57` | 文档中的举例 | 配对信息，不属于项目数据 |
| 设备序列号 | `<serial>` | 文档、命令示例 | `adb devices` 的序列号 |
| 内网 IP | `<device-ip>` | 文档、`install_switch2arch.sh` | 无线 adb/SSH 用，脚本要求显式设置 |
| 共享分区 UUID | `<share-uuid>` | `docs/08` | `blkid /dev/sda16` 得到 |
| sda15 分区 GUID | `<archlinux-partuuid>` | `docs/08` | `sgdisk --info=15 /dev/sda` 得到 |
| 主机路径 | `<workspace>` 或 `$HOME/tb710fu` | 文档、脚本 | 作者路径已全部删除 |
| VNC 密码 | 不再出现 | `tools/arch-userspace/tools/tb-krfb-start` | 改为提示「自己设置密码」 |

### 1.1 为什么连「另一台机器」的地址也替换

旧指南和上游其他机型的 DTS 里出现过真实或示例蓝牙地址。保留它们既误导读者，也暴露
第三方设备标识；本仓库统一替换为 `02:11:22:33:44:55`（小端数组
`[55 44 33 22 11 02]`），并在补丁注释里注明「换成你自己的地址」。发布前用 §8 的
`local-bd-address` 检查确认没有漏网的字节数组。

### 1.2 仍保留的设备相关值

以下值**不是个人信息**，保留是为了可复现与可校验：

- 机型身份：`ro.product.device=piano`、`ro.product.model=25091RP04C`（小米平板 8 的公开型号，
  移植包故意保留它，商店通道按它识别）；
- 构建哈希：`super dd6cfbb8…`、`Image 37f997fb…`、`boot_a 8c45a8a3…`、各 `.ko` 的 sha256。
  这些是**作者构建产物**的哈希，用来描述基线；你自己的构建结果一定不同。
- 占位符 MAC 的 `02:` 前缀是本地管理地址（locally administered），保证不会与真实厂商地址冲突。

---

## 2. 把蓝牙地址换成你自己的

### 2.1 从哪里读

TB710FU 的工厂蓝牙地址在 `persist` 分区。三种方式任选：

```bash
# A. 设备上（root）
xxd -g1 -l6 /dev/block/by-name/persist 2>/dev/null | head
# 若已知布局为 bd_addr.bin：
xxd -g1 -l6 /dev/block/bootdevice/by-name/persist 2>/dev/null

# B. 从 Android 属性（OS4 已移植时）
adb shell getprop ro.odm.lenovo.btaddr

# C. 从原厂 getprop 备份
grep -i btaddr /path/to/getprop_full.txt
```

读到的是 6 字节小端存储，例如文件里是 `55 44 33 22 11 02`，可读地址就是
`02:11:22:33:44:55`。

### 2.2 改补丁

`patches/kernel/full/0020-tb710fu-restore-factory-Bluetooth-address.patch`
（以及 `incremental/0001-…`）里有两处需要同步改：

- 注释中的可读地址：`address 02:11:22:33:44:55 is stored last byte first.`
- DTS 字节数组：`local-bd-address = [55 44 33 22 11 02];`

把可读地址按字节倒序写进数组。也可以用仓库自带脚本：

```bash
tools/arch-kernel/set-bt-addr.sh 02:11:22:33:44:55 \
  patches/kernel/full/0020-tb710fu-restore-factory-Bluetooth-address.patch
```

脚本会校验格式、自动倒序，并同时改注释与数组。**不要**把别人的地址写进自己的 DTB：
蓝牙 bond 与地址绑定，写错会导致键盘/耳机反复重配。

### 2.3 不想要固定地址时

如果不想在 DTB 里写死地址，可以跳过 0020 补丁。零占位时 `btqca` 会用 SoC 序列号
**确定性推导** `00:03:7F:…`，不是每次随机；但地址不可控，可能与旧 bond 不符
（键盘/耳机需要重配）。要固定地址就写自己的工厂地址。

---

## 3. 内网 IP 与设备序列号

- 文档里的 `<device-ip>` 是无线 adb / SSH 的目标地址；请填你自己的内网地址，仓库不提供任何真实 IP。
- `install_switch2arch.sh` **没有默认 IP**：
  - USB adb：直接运行，无需设置；
  - 无线 adb：先 `adb connect <ip>:5555`，或 `TB_TABLET_IP=<ip> ./install_switch2arch.sh …`；
  - 多台设备：`TB_SERIAL=<serial> ./install_switch2arch.sh …`。
- 脚本里的 `<serial>` 不会自动展开；把它替换成 `adb devices` 第一列的值。

---

## 4. 分区 UUID

共享分区与 Arch 分区的 UUID 是**每台设备唯一**的，仓库里不保留作者的值。

```bash
# 共享分区
blkid /dev/sda16          # -> UUID="...."  LABEL="share"
# Arch 分区
sgdisk --info=15 /dev/sda # -> Partition unique GUID: ....
```

`docs/08-dualboot-share.md` 的示例用 `<share-uuid>` / `<archlinux-partuuid>` 代替；
你自己的 `fstab` 请用 `LABEL=share`（推荐，不依赖 UUID），或填入自己的 UUID。

---

## 5. 用户账号与路径

- 用户态脚本默认 `USER_NAME=archlinux`、`USER_HOME=/home/archlinux`。这是
  **ArchLinuxARM 官方镜像的默认用户**，不是作者的个人账号。你的用户名不同就：

  ```bash
  sudo USER_NAME=<your-user> USER_HOME=/home/<your-user> ./install-userspace.sh
  ```

- 少数脚本（`tb-vk-restart`、`tb-krfb-start`、`tb-ff-diag`、温度条 QML）里有
  `/home/archlinux` 与 UID `1001`。它们对应 ALARM 默认值；如果你的用户/UID 不同，
  用 `grep -rl '/home/archlinux' tools/arch-userspace` 找出并替换。
- 作者的主机路径（`/Users/...`、`/home/.../tb710fu-hyperos-steamos`）已全部删除，
  文档统一用 `<workspace>` / `$HOME/tb710fu`。

---

## 6. VNC / SSH / 账号

- **VNC**：`tb-krfb-start` 不再打印任何密码。先在 KDE「系统设置 → 共享 → 桌面共享」
  里设置你自己的密码，再启动脚本。仓库里没有 `kwallet`、`krfb` 配置或密码文件。
- **SSH**：仓库不含任何 `authorized_keys`、私钥、`known_hosts`、sudo 免密配置中的用户名。
  `tools/arch-side/tb-switch.sudoers` 用的是 `%wheel` 组，不含具体用户；只放行 `--status`/`--dry`/`--no-reboot` 等固定参数，`--restore`/`--force` 需要真实 root 密码。
- **账号**：不含小米账号、Google 账号、WPS/CAD 账号、ADB 授权文件、cookie/token。
- **日志**：不含 `dmesg`/`journalctl`/`logcat` 原始日志；`docs/` 只保留结论与计数。
  设备日志里常见的 MAC/序列号/IP 不会出现在本仓库。

---

## 7. 本仓库不包含的二进制

- 小米 OTA、`system`/`system_ext`/`product`/`mi_ext` 镜像；
- 社区 OS3 移植包、`super.img`、`vendor`/`ODM`/`dlkm`、`lwky`；
- 修改后的 `miui-services.jar`、`PearlBiometric.apk`、`VoiceAssistAndroidT.apk`、
  `DevicesOverlay.apk`、Aperture/WPS/CAD APK；
- 联想 ZUI 固件、firehose programmer、`boot`/`init_boot`/`dtbo`/`vendor_boot`/`vbmeta`；
- 任何 `.img`、`.ko`、`.tar`、`.zip`、`.bundle` 二进制。

`patches/` 是源码补丁；`modules/` 是 shell/配置源码；`tools/` 是构建/验收脚本。

---

## 8. 发布前自检

在仓库根目录执行（macOS/Linux 均可）：

```bash
# 1) 真实 MAC（排除示例占位符 02:11:22:33:44:* 与 00:03:7F:00:00:00）
rg -n --no-heading -e '\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b' . \
  | grep -viE '02:11:22:33:44|00:03:7F:00:00:00|02:00:00|00:00:00:00:00:00' || echo "OK: no real MAC"

# 2) 内网 IP
rg -n --no-heading -e '\b192\.168\.|\b10\.[0-9]+\.|\b172\.(1[6-9]|2[0-9]|3[01])\.' . \
  | grep -viE '<device-ip>|172\.16\.42\.' || echo "OK: no LAN IP"

# 2b) DTS 小端蓝牙地址数组（白名单占位符/全零）
rg -n --no-heading -e 'local-bd-address[[:space:]]*=[[:space:]]*\[' . \
  | grep -v '55 44 33 22 11 02' | grep -v '00 00 00 00 00 00' \
  || echo "OK: no real bd-address array"

# 3) 作者路径
rg -n --no-heading -e '/Users/|/home/[a-z]+/Desktop' . || echo "OK: no host path"

# 4) 设备序列号样式（8 位大写字母数字）
rg -n --no-heading -e '\b[A-Z]{2}[0-9]{2}[A-Z]{4}\b' . | grep -v '<serial>' || echo "OK: no serial"

# 5) 密码/密钥
rg -n --no-heading -i -e 'password\s*[:=]\s*[^ <]|BEGIN [A-Z ]*PRIVATE KEY|api[_-]?key' . \
  | grep -viE 'passwordSet|password-store|<path>|示例' || echo "OK: no secret"
```

> `172.16.42.x` 是 initramfs 的 NBD/USB-NCM 固定网段（`usb0`），不是个人网络，
> 因此保留。`223.5.5.5` 之类公共 DNS 也不属于隐私。

如果新增了文档/脚本，请把上面六条再跑一遍；发现真实值就替换成占位符，并在本表登记。
