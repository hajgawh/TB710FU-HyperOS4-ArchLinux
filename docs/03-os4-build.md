# 03 — 构建 OS4：流水线、包内修复与验收

> 目标：从 `yupei` 4.0.11 解包树 + 冻结的 OS3 vendor/ODM，构建 **数据保留** 的
> `system` / `system_ext` / `product` 三镜像，组装成 super，并跑 61 项包内验收。
> 本文只讲构建；刷入见 [04-os4-install.md](04-os4-install.md)。

---

## 1. 输入检查清单

```text
work/hyperos4_411/x_system/                 yupei system 解包树
work/hyperos4_411/x_system_ext/
work/hyperos4_411/x_product/
work/hyperos4_411/x_mi_ext/
work/port/system_a.img                      OS3 移植包（system 可复用/参考）
work/port/vendor_a.img / odm_a.img
work/port/vendor_dlkm_a.img / system_dlkm_a.img
work/port/x_system_a/system/lwky/            lwky_cover、lwky_smart_charge_hyper
work/port/x_system_a/system/etc/init/init.lwky.rc
work/port/x_product_a/app/PearlBiometric/PearlBiometric.apk
work/patches/miui-services-tb710fu-411.jar  色彩补丁 jar（4.0.11 专用）
work/overlay/TB710FUTetheringOverlay.apk    NCM overlay
work/overlay/TB710FUConnectivityOverlay.apk
hyperos/camera/Aperture.apk                 411d 相机（第三方，必装、自备）
hyperos/camera/CameraParallelServiceStub.apk 相机替身 provider（必装；可自建，见 §3.2.2）
```

缺一项就停下补，不要用「看起来差不多」的文件替代。尤其是：

- 色彩 jar 必须是 **4.0.11** 的 `miui-services.jar` 打的；OS3 的 jar 不能混用。
- 两个 camera APK 不随仓库分发；缺了 `port_build.sh` 会在输入检查阶段直接报错。
- `PearlBiometric` 必须是 OS3 移植包里的版本（软件 2D 人脸）。
- overlay 必须用 `tools/build_overlays.sh` 从 `assets/overlay-src/` 重新构建，
  不要用旧签名/旧包名。

---

## 2. 一条命令

```bash
tools/port_build.sh
```

默认：

```text
TB_PARTS="system system_ext product"
TB_SUPER_NAME=super_fixed.img
TB_SUPER_SIZE=0x4c0000000        # 20.4 GB 物理
TB_CORNER_PADDING=40
```

`TB_PARTS` 只决定 **重跑哪些分区的 staging**，不决定 super 里放什么。super 永远打包
7 个逻辑分区：`system` / `system_ext` / `product` 三件套 + 冻结的
`vendor` / `odm` / `vendor_dlkm` / `system_dlkm`。

首次构建，或 `out/` 里还没有旧的 `system.img` / `system_ext.img` 时，直接跑上面的默认命令
（全量重建三分区），不要只传 `TB_PARTS="product"`。

已经全量构建过、只想迭代 product（411d 就是这样打的）：

```bash
TB_PARTS="product" TB_SUPER_NAME=super_fixed_411d.img tools/port_build.sh
```

> 这条命令只重跑 product 的 staging；`system` / `system_ext` 复用 `out/` 里的旧镜像，
> super 仍然包含全部 7 个分区。脚本层已强制：`port_build.sh` 对未重建分区复用
> `out/<p>.img`，缺失直接报错，不会出现“super 里只剩 product”的包。

只重打 super（三个可重建镜像与四个冻结分区都已存在）：

```bash
python3 tools/make_super.py \
  work/build_os4/out/super_fixed.img 0x4c0000000 \
  system=work/build_os4/out/system.img \
  system_ext=work/build_os4/out/system_ext.img \
  product=work/build_os4/out/product.img \
  vendor=work/port/vendor_a.img \
  odm=work/port/odm_a.img \
  vendor_dlkm=work/port/vendor_dlkm_a.img \
  system_dlkm=work/port/system_dlkm_a.img
```

不要手工拼 super，也不要为了省事删掉 `system_ext`。

---

## 3. staging 做什么（按类归并）

`build_os4.py` 把一个分区树复制到 staging，按 B1–B47 的规则改写。核心几类：

### 3.1 字体与显示

- 写入 `/system/etc/tb710fu_bootfix.sh`：每次 `sys.boot_completed=1` 写
  `font_scale=1.0`、`device_font_scale=1.0`、`ui_mode_scale=1`，2 秒复查、失败重试；
- 删除旧包的 1.5 侧滑 Secure 键（回到 framework 默认 1.0）；
- `ro.sf.lcd_density=440`（不能删；删了落 vendor 320，UI 小 27%）；
- 不写 `peak_refresh_rate`/`miui_refresh_rate`/`user_refresh_rate`，不写灵动岛；
- `product` 内保留原厂 `DevicesOverlay.apk`（40px R 角，签名不动）。

### 3.2 身份与相机

- `product/etc/build.prop` 烧入 `ro.product.marketname` 及 system/system_ext/vendor/odm/product
  变体；
- 相机为 Aperture（411d 定稿，横屏 UI 见 §3.2.1）；MiuiCamera 已退役，
  `tools/patch_miuicamera_front.py` 只属于历史基线/回退路径，不是当前构建步骤；
- 补 `SpecialTypesProvider` 替身（见 §3.2.2），避免相册/AGC 查看照片崩溃；
- 保留 `ro.product.device=piano`、`ro.product.model=25091RP04C`（商店通道按它识别）；
- `.DEV` incremental 绕过查找设备状态检查。

#### 3.2.1 Aperture 横屏 UI（411d 定稿）

411d 的相机是 Aperture（`product/app/Aperture`），不是 MiuiCamera。横屏 UI 按官方平板相机
的视觉框架重做，但**不能照搬官方实现**：

- **官方相机为什么不能照搬**：MIUI 官方相机的主 Activity 锁竖屏
  （`screenOrientation="portrait"`），横屏效果靠一套自绘旋转控件；Aperture 没有这套框架，
  照搬会得到锁竖屏窗口 + 内部旋转，文字和控件都会错位。
- **正确改法**：保留 `fullSensor`（小白条在物理底部、EXIF 方向正确），新增
  `res/layout-land/activity_camera.xml`，并让 Activity 在旋转时重建。`CameraActivity` /
  `SecureCameraActivity` 的 `configChanges` 去掉
  `orientation|screenLayout|screenSize|smallestScreenSize`，资源系统才会自动切换横/竖布局；
  竖屏布局保持原版。
- **`rotateViews` 必须 no-op**：上游的图标补偿是给“锁竖屏窗口”设计的；在 `fullSensor` 下
  系统已经旋转了一次，再补偿就是双重旋转。删除 `onCreate` 里的初始调用，方法体直接返回。
- **控件只锚 parent + 固定边距**：不要锚会随模式显隐的容器。锚点 `GONE` 时约束塌缩，
  控件会被甩到别处（实测模式条平移 63px）。变焦条/曝光条/模式条全部锚 parent。
- **模式切换是取景器 fling，不是 ViewPager**：映射表在
  `CameraActivity$gestureDetector$2$1.smali` 的两张 packed-switch；对调两张表即换方向。
  411d 后右划 = 照片→视频→扫描，左划反向。慢拖取景器是原生变焦，快滑才是切模式。
- **已废弃**：2026-10-29 的“旋转整个布局”hack（手写旋转 + fullSensor）是 1x/缩略图躺倒、
  竖屏丢按钮、横竖状态错乱的根源，不要再建议或回装。

成品验收：Aperture `8ff4d7e4…`；横屏取景满屏、快门右中、模式条底部居中、变焦条在模式条
正上方，横↔竖来回切换布局稳定。

#### 3.2.2 SpecialTypesProvider 替身（相册/AGC）

相册和 AGC 查看照片不是走相机代码，而是硬依赖
`com.xiaomi.camera.parallelservice.provider.SpecialTypesProvider` 这个 authority
（原声明在 MiuiCamera 的清单里）。MiuiCamera 退役后 provider 随之消失，HyperOS 4 相册
（Rust 实现，`libapp_gallery.so`）在 `ExternalPhotoPageActivity` 里直接 unwrap abort：
表现为 Aperture“点开照片 → 系统查看”打不开、AGC 点缩略图闪退。

- 替身 `CameraParallelServiceStub.apk` 约 **8.5 KB**，进 `product/app/`；
- 声明同 authority；`query()` 返回 **7 列空 MatrixCursor**，`call()` 返回 `null`；
- 用 **aperture keystore** 签名；
- 源码在 [`hyperos/camera/src/`](../hyperos/camera/src/README.md)，一条命令构建
  （JDK 17 + Android build-tools，不需要 gradle/联网）：

  ```bash
  KEYSTORE=~/aperture.keystore KS_ALIAS=aperture hyperos/camera/src/build.sh
  # -> hyperos/camera/CameraParallelServiceStub.apk（实测 8,591 B，验签通过）
  ```

  也可以继续用 411d 成品里的那个二进制；两者行为一致，二选一。
- 验收必须走两条路径：Aperture 拍照后点开照片/“系统查看”，以及 AGC 点缩略图；
  两条都正常、`logcat` 无 abort 才算通过。`dumpsys package providers | grep -i
  specialtypes` 应能查到这个 authority。

### 3.3 色彩、亮度、侧滑

- `miui-services.jar` 原位补丁：`mode` 0/2 对调；删除 `oat/*/miui-services.*`，
  否则 ART 继续跑旧代码；
- displayconfig 绑定联想面板 ID：日常 max 0.4509≈516 nit，≥10000 lux 才 HBM 782 nit；
- `panel_direction` 必须跟随屏幕旋转（OS4 索引 = 旋转角/90：横屏 90° 写 **1**，不是 3）、
  `game_edge=0`、`game_mode=2`（移除掌拒）。包内 `tb710fu_paneldir.rc` 仍写死 3，由
  `TB710FUSetRes` v2.0 的 1 秒循环纠正；下次重打包时应直接改 rc。
  > 2026-11-10 更正：旧文档写的“横屏写 3”是 OS3 驱动语义（3→0xBC）；OS4.0.11 已改回
  > 索引=旋转角/90（1→0xBC）。详见 [12-os4-touch-backgesture.md](12-os4-touch-backgesture.md)。

### 3.4 音频、网络、SELinux

- `media.settings.xml` 注释（按需）；
- NCM overlay（Tethering/Connectivity）与笔键位；
- `sepolicy_compat.cil`；
- Joyose 搬家、WPS/CAD mslg 版本门、rootfs 桥（`/data/vendor/rootfs`）。

### 3.5 时间

- OS4 侧 fake-hwclock：`lasttime` 存 `(epoch, RTC raw)` 两行，开机按 raw 增量补时；
  180 s 存档 + NTP 兜底。

---

## 4. super 组装

分区与大小（411d 实测；四舍五入，相加与 super 总大小有少量误差）：

| 分区 | 内容 | 大小 |
|---|---|---|
| `system` | yupei 4.0.11 + lwky + bootfix + sepolicy compat | 0.96 GB |
| `system_ext` | yupei 4.0.11 + 色彩补丁 jar | 0.83 GB |
| `product` | yupei 4.0.11 + piano.xml + PearlBiometric + NCM RRO | 6.76 GB |
| `vendor` | OS3 移植包 | 1.48 GB |
| `odm` | OS3 移植包 | 0.46 GB |
| `vendor_dlkm` | OS3 移植包 | 0.04 GB |
| `system_dlkm` | OS3 移植包 | 0.04 GB |

约束：

- **`used_end < 10 GiB`**：`make_super.py` / `flash_super_arch.sh` 的历史硬保护线
  （super 内 10 GiB 处曾放 Linux root）；当前 `sda15` 在 userdata 尾部（约 106 GiB），
  但不要因此放宽这个限制；
- 如果超了，先精简 product（大头是预装应用/媒体），不要缩 Arch。

---

## 5. 验收

### 5.1 主机侧

```bash
# 1) super 哈希/大小
shasum -a 256 work/build_os4/out/super_fixed.img
# 2) 7 分区与 manifest
python3 tools/check_super.py work/build_os4/out/super_fixed.img
# 3) 61 项包内验收
tools/verify_package.sh
# 期望：== summary: 61 passed, 0 failed
```

61 项覆盖：

| 类别 | 例子 |
|---|---|
| EROFS/分区 | 三镜像可读、`/system/etc` 路径、manifest |
| 字体/R 角 | bootfix 存在、`font_scale` 默认、`DevicesOverlay` 40px |
| 身份 | `marketname` 五个变体、`ro.sf.lcd_density` |
| 相机/相册 | Aperture（与 `hyperos/camera/Aperture.apk` 一致；作者定稿参考 `8ff4d7e4…`）、MiuiCamera 不在包内、stub provider |
| 色彩/亮度 | 补丁 jar 哈希、旧 oat 已删、displayconfig ID |
| lwky/手势 | lwky 二进制、`init.lwky.rc`、props |
| 音频/网络 | `media.settings.xml`、NCM overlay、笔键位 |
| 时间/SELinux | fake-hwclock、`sepolicy_compat.cil` |

### 5.2 产物清单

```text
work/build_os4/out/
├── super_fixed.img
├── system.img
├── system_ext.img
├── product.img
└── super_fixed.img.manifest.json
```

把 `<super>.manifest.json` 与两份 `.sha256` 和刷机记录一起存档（构建脚本不生成
`BUILD-INFO.txt`；需要时自己记录）。

---

## 6. 构建错误表

| 现象 | 原因 | 处理 |
|---|---|---|
| `mkfs.erofs: unrecognized option` | erofs-utils 太旧 | 升级 ≥1.9 |
| staging 缺 `lwky` | OS3 包不完整 | 补 `x_system_a/system/lwky` |
| `PearlBiometric` 缺失 | 路径大小写/版本不对 | 从 OS3 product 解包 |
| 色彩 jar 应用后开机仍反色 | 旧 oat 未删 | 删 `oat/*/miui-services.*` |
| super 超过 10 GiB | product 太大 | 精简 product；不要踩 Arch |
| `check_super.py` manifest 不匹配 | 分区重建后未重新组装 | 重跑 `make_super.py` |
| 61 项里字体 FAIL | bootfix 未写入/权限错 | 检查 `/system/etc/tb710fu_bootfix.sh` 0755 |
| 61 项里 R 角 FAIL | 用了 piano 10px overlay | `TB_CORNER_PADDING=40` |
| `fsck.erofs` 报 `system_ext` 缺 / 安卓起不来 | 411b 事故：`TB_PARTS` 只重建 system+product，漏了 system_ext | super 必须含 7 个逻辑分区；三分区一起重建并重跑验收 |
| 构建磁盘不足（ENOSPC）/ `product.img` 显示 2 TB | 换 super 前未删旧 super；磁盘写满后留下稀疏假文件 | 先删旧 `out/super_*.img`；`ls -la` 看 apparent size，删掉 2 TB 假 `product.img` 后重跑；不要删 `system_ext` |
| 刷后卡动画 | super 与 /data 不兼容/启动链不匹配 | 回刷 `rollback_*` |

---

## 7. 411b / 411c / 411d 三代包（口径）

| 包 | 定稿内容 | 结果 |
|---|---|---|
| **411b** | 只重建 `system` + `product` 两个分区，漏了 `system_ext` | super 缺 `system_ext_a`，first-stage mount 失败，Android 起不来（Arch 正常） |
| **411c** | 补 `SpecialTypesProvider` 替身 + NTP（`ntp.aliyun.com`） | 相册/AGC 可查看照片，联网后时间可自动同步 |
| **411d** | Aperture 横屏 UI 定稿（`layout-land` + `fullSensor` + 旋转重建 + fling 换向） | 包内验收 **61/61**，当前基线 |

411b 不是“`system_ext` 镜像坏了”，而是 `TB_PARTS` 收窄后 super 的 LP 元数据里根本没有
`system_ext_a`；`vendor_boot` 首阶段 fstab 又要求 `first_stage_mount`，所以 Android 必然起不来。
411c 的修复重点是相册 provider 与 NTP，**不是“补回 system_ext”**；三分区齐全从 411b 之后
就是所有包的硬前提。

**规则**：

- `TB_PARTS="product"` 只重跑 product 的 staging；super 必须始终包含
  `system` / `system_ext` / `product` 三件套，再加 `vendor` / `odm` / `vendor_dlkm` /
  `system_dlkm`，共 **7 个逻辑分区**；
- 跨版本混用分区会在 `verify_package.sh` 的 manifest 检查里暴露——不要跳过验收；
- `verify_package.sh` 的「super packs all 7 logical partitions」是硬断言；manifest 由镜像反推，
  单看 manifest 查不出漏包，必须靠这条断言。

---

## 8. 只重跑 product staging 的最短路径

前提：`out/` 里已经有**同一次基线**的 `system.img` 与 `system_ext.img`。没有就退回 §2
全量构建；不要删 `system_ext`，也不要手工拼 super。

```bash
# 0) 磁盘：换 super 前先删旧 super。
#    单轮 out 约 18 GB（product 6.6G + super 10.4G + stage）；含解包/临时树峰值约 30 GB。
df -h .
rm -f work/build_os4/out/super_fixed.img work/build_os4/out/super_fixed.img.sha256
#    重打 411d 时同样删旧文件：
#    rm -f work/build_os4/out/super_fixed_411d.img work/build_os4/out/super_fixed_411d.img.sha256
#    确认没有被 ENOSPC 写坏的稀疏假 product.img（ls -la 的 apparent size 会显示 2 TB）
ls -la work/build_os4/out/system.img work/build_os4/out/system_ext.img work/build_os4/out/product.img

# 1) 只重跑 product staging；super 仍打 system/system_ext/product + 4 个冻结分区
TB_PARTS="product" TB_SUPER_NAME=super_fixed_411d.img tools/port_build.sh

# 2) 验收（必须看到 7 分区断言与 61/61）
python3 tools/check_super.py work/build_os4/out/super_fixed_411d.img
tools/verify_package.sh

# 3) 刷入（二选一）
#    EDL：见 04-os4-install.md §3
#    Arch 在线：见 04-os4-install.md §4
```

说明：

- `TB_PARTS="product"` 不会把 super 变成“只有 product”。脚本层已强制
  `port_build.sh` 对未重建的分区复用 `out/<p>.img`，并在 `system.img` / `system_ext.img`
  缺失时报错；super 始终是 7 个逻辑分区。
- 如果 `product.img` 是 ENOSPC 留下的 2 TB 稀疏假文件，先 `rm` 掉它再重跑；
  不要用 `du` 的 0 字节判断（`ls -la` 看 apparent size）。
- 回退用的旧分区镜像放 `work/build_os4/rollback_prev/`，不要占着 `out/`。

---

## 9. 构建记录模板

```text
日期：
底包：yupei OS4.0.11.0.XPZCNXM
OS3 包：<版本/来源>
TB_PARTS：
super：<名称> / <大小> / sha256
system：sha256
system_ext：sha256
product：sha256
verify_package：__ passed, __ failed
check_super：__ partitions match
备注：
```

---

## 10. 升级到新的 OS4 OTA

只在主机上处理下载好的全量 OTA；**不要在设备上点系统 OTA**。系统 OTA 会直接覆盖当前
super、破坏数据保留与启动链，包内修复（bootfix、色彩 jar、overlay、Aperture、provider 替身）
也会全部失效。

流程：

1. 下载 yupei 全量 OTA（同版本或更高），从 `payload.bin` 提取
   `system` / `system_ext` / `product` / `mi_ext` 四个分区；
2. 解包到新目录 `work/hyperos4_<tag>/x_*`，`img/` 留原镜像供 `erofs_meta` 缓存；
3. `TB_OS4_DIR=$PWD/work/hyperos4_<tag> tools/port_build.sh` 全量构建；
4. 每次换 OTA 逐项重核下表，任何一项变了都要重做对应补丁，不能直接复用旧产物：

| 必核项 | 查什么 | 变了怎么办 |
|---|---|---|
| `DevicesOverlay.apk` 的 40px R 角 | `rounded_corner_content_padding` 是否仍为 40px；原厂哈希是否变化 | 用 `patch_apk_res.py` 原位改 ARSC 到 40px，保持签名；不要用旧 APK 覆盖 |
| `piano.xml` 键位 | `support_tee_face_unlock`、`support_face_unlock_region_dom`、`support_mi_keyboard`、`support_max_fps`、`fpsList` 是否还在、值是否原厂 | 按 §3 staging 的键位重新补；不要整份替换成旧 `piano.xml` |
| `VoiceAssistAndroidT.apk` 白名单 asset 长度 | `assets/voiceassist.ai.voice.trigger.config` 的名字与长度 | 长度变了要重做等长 deflate 补丁；不要重打包 APK |
| `miui-services.jar` 色彩补丁 | 新 OTA 的 jar 版本 | 按新版本重打 `miui-services-tb710fu-<tag>.jar`；没有就退出，不要混用旧版本；同时删旧 `oat/*/miui-services.*` |
| `media.settings.xml` 注释 | system `build.prop` 是否仍指向 vendor 缺失的 `media_profiles_vendor.xml` | 继续注释该行，否则 zygote 在 MediaProfiles abort |
| `sepolicy_compat.cil` | Android 平台是否仍缺 API 34 vendor 使用的类型 | 继续把 `hyperos/sepolicy_compat.cil` 追加进 `product_sepolicy.cil`；平台升级后重核类型名 |
| Aperture 替换路径/类名 | OTA 里相机 APK 的实际路径；`CameraActivity`、`SecureCameraActivity`、`CameraActivity$gestureDetector$2$1` 是否还在 | 路径变了改 staging 目标；类名变了重新定位 `layout-land`、`configChanges`、`rotateViews`、fling 两张 packed-switch |
| displayconfig 面板 ID | 联想面板的 `physicalDisplayId` 是否仍命中 `display_id_*.xml` / `display_port_131.xml` | 不命中就按新 ID 改名/复制；继续核对 `transitionPoint=0.4509`、`minimumLux=10000` |
| 其他包内替换 | PearlBiometric、NCM overlay、笔键位、Joyose、bootfix 的 NTP | 按 §3 逐项重跑；不要直接拿旧 product 覆盖新 OTA |

5. `tools/verify_package.sh` 全部通过（当前基线 **61/61**），且 7 分区断言通过；
6. 无 wipe 刷入（见 [04-os4-install.md](04-os4-install.md)），刷前备份当前 super 头/manifest；
7. 重申：**不要在设备上点系统 OTA**。

> `vendor` / `odm` / `vendor_dlkm` / `system_dlkm` 继续使用冻结的 OS3 移植包，不要跟着 OTA 换。
