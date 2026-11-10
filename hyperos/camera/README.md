# hyperos/camera — 411d 相机资产（不含二进制）

`tools/build_os4.py`（411d 版）在 product 分区里做三件事：

1. 删除 `priv-app/MiuiCamera`（联想 HAL 没有 Xiaomi `campostproc`，JPEG 路径不可用）；
2. 安装 `app/Aperture/Aperture.apk`；
3. 安装 `app/CameraParallelServiceStub/CameraParallelServiceStub.apk`，并在
   `etc/default-permissions/` 写入 `default-permissions-aperture.xml`。

## 你需要放进来的文件

| 文件 | 大小/说明 | 从哪里来 |
|---|---|---|
| `Aperture.apk` | 约 9–10 MB；本定稿版包名 `org.lineageos.aperture.dev`（以 `aapt2 dump badging` 为准）；建议用你自己的 key 重签 | 你的 411d 成品包、自己按 `docs/03` §3.2.1 打的横屏定稿版，或 LineageOS 源码构建 |
| `CameraParallelServiceStub.apk` | 约 8.5 KB；提供相册/AGC 依赖的 `SpecialTypesProvider` | **仓库自带最小源码**：[`src/`](src/README.md) + `src/build.sh`（实测构建 8,591 B）；或从你的 411d 成品包里取 |
| `default-permissions-aperture.xml` | 696 B，纯文本，已包含 | 本目录 |

**Aperture 必须自备**（第三方二进制，不随仓库分发）。`tools/port_build.sh` 在输入检查
阶段会直接报错，直到你把它放进本目录。

**`CameraParallelServiceStub.apk` 可以自己构建**（不必再从成品包里抠）：

```bash
KEYSTORE=~/aperture.keystore KS_ALIAS=aperture hyperos/camera/src/build.sh
# -> hyperos/camera/CameraParallelServiceStub.apk
```

> `src/` 是按作者 411d 成品**行为**重写的参考实现（同 authority、`query()` 返回空游标、
> `call()` 返回 null），本机用 JDK 17 + build-tools 36 构建并验签通过，产物 8,591 B，
> 与成品 8.5 KB 同级；**尚未在同一台平板上复测**。成品二进制与自建源码二选一。

## 校验

```bash
apksigner verify --verbose --print-certs hyperos/camera/Aperture.apk
aapt2 dump badging hyperos/camera/Aperture.apk | grep -E 'package:|sdkVersion|targetSdkVersion'
sha256sum hyperos/camera/*.apk
```

`tools/verify_package.sh` 不要求固定哈希：它比对的是**打包进 product 的 APK** 与
**本目录里的源文件**是否一致，确保你构建时用的就是同一份 APK。

## 不要做

- 不要把 Aperture 与 MiuiCamera 同时保留（会抢 camera role）；
- 不要用来源不明的 APK 站包；
- 不要把 `Aperture.apk`/`CameraParallelServiceStub.apk` 提交到公开仓库（`.gitignore` 已挡
  `*.apk`）；`src/` 里的源码与 `build.sh` 应该提交，二进制不该。
- 不要为了“省一步”改 `src/AndroidManifest.xml` 里的 authority 字符串。
