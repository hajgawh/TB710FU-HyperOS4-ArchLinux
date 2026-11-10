# hyperos/camera/src — SpecialTypesProvider 最小的可构建替身

这是 `CameraParallelServiceStub.apk` 的**参考实现源码**，用来替代「只能从 411d 成品包里
抠出那个 8.5 KB APK」。构建产物直接落地到 `hyperos/camera/CameraParallelServiceStub.apk`，
也就是 `tools/port_build.sh` 期望的路径。

> **定位**：作者 411d 成品里的同名 APK 已在真机验收过（相册/AGC 两条路径不崩）；
> 本目录是**按相同行为重写的参考实现**，代码量约 60 行，**未经真机复测**。
> 你要么用它构建，要么继续用成品里的那份二进制——两者二选一，不要同时装。

---

## 1. 它解决什么问题

HyperOS 4 相册是 Rust 实现（`libapp_gallery.so`）。照片大图页 `ExternalPhotoPageActivity`
会按 authority

```text
com.xiaomi.camera.parallelservice.provider.SpecialTypesProvider
```

解析 provider。这个 authority 原本声明在 **MiuiCamera.apk** 的清单里；本项目移除了
MiuiCamera（联想 HAL 没有 Xiaomi `campostproc`），provider 随之消失，相册解析不到就
`unwrap` → `abort`：

- Aperture「点开照片 → 系统查看」打不开；
- AGC 点缩略图直接闪退。

替身只做一件事：**让这个 authority 存在，并且 `query()` 不返回 null**。相册不消费任何行。

---

## 2. 构建

```bash
KEYSTORE=~/aperture.keystore KS_ALIAS=aperture ./build.sh
# 非交互：KEYSTORE=... KS_ALIAS=... KS_PASS=... ./build.sh
```

依赖：

| 依赖 | 用途 | 说明 |
|---|---|---|
| Android SDK **build-tools** | `aapt2` / `d8` / `zipalign` / `apksigner` | 用最新版即可 |
| Android SDK **platforms** | `android.jar` | 至少 android-30；默认 minSdk 30 / targetSdk 35 |
| JDK 17+ | `javac` | 只编 Java 8 字节码，不引 AndroidX |
| gradle / 网络 | — | **都不需要** |

可用环境变量覆盖：`OUT`（产物路径）、`MIN_SDK`、`TARGET_SDK`、`ANDROID_SDK_ROOT`。

产物校验：

```bash
apksigner verify --verbose hyperos/camera/CameraParallelServiceStub.apk
aapt2 dump badging hyperos/camera/CameraParallelServiceStub.apk | head -4
```

---

## 3. 行为约定（改代码前先读）

| 方法 | 行为 | 为什么 |
|---|---|---|
| `onCreate()` | `return true` | 不初始化任何东西；返回 false 会让系统认为 provider 启动失败 |
| `query()` | 返回 **0 行** `MatrixCursor`；有 `projection` 就照抄列名 | 调用方按列名查找不会拿到 -1；没有行，所以不会读到假数据 |
| `call()` | `return null` | MiuiCamera 里它是并行服务控制入口；相册只判空 |
| `insert/update/delete` | `null` / `0` | 替身不持有数据，也不该被写入 |
| `openFile()` | `null` | 没有可打开的文件 |
| `getType()` | `null` | 不声明 MIME |

两条不能动的红线：

1. **authority 字符串逐字节一致**（见 `AndroidManifest.xml` 注释）。改一个字符 = 等于没装。
2. **`android:exported="true"`**。相册是另一个 UID，不导出就解析不到。

---

## 4. 装进去之后怎么验收

```bash
# 1) provider 是否真的注册上了（在 OS4 里执行）
adb shell dumpsys package providers | grep -i specialtypes
#    期望：看到 authorities=com.xiaomi.camera.parallelservice.provider.SpecialTypesProvider
#          以及你的包名 CameraParallelServiceStub

# 2) 两条路径都要走（缺一不可）
#    a. Aperture 拍一张 → 点开照片 → 「系统查看」→ 能进相册大图页
#    b. AGC 打开 → 点缩略图 → 不闪退

# 3) 崩溃日志应为空
adb logcat -d | grep -iE 'SpecialTypesProvider|app_gallery|abort' | head
```

`logcat` 里出现 `No content provider: com.xiaomi.camera.parallelservice.provider...`
说明 APK 没进 product 或 authority 写错了，不是相册的问题。

---

## 5. 不要做

- 不要把 `CameraParallelServiceStub.apk` 提交到公开仓库（`.gitignore` 已挡 `*.apk`）；
  源码和 `build.sh` 可以提交，二进制不行。
- 不要把它当成相机/相册的替代品去加功能；它只是消 `abort` 的桩。
- 不要用与 Aperture 不同的 keystore 签名后再指望系统把它们当同一来源（见 `docs/03` §3.2.2）。
- 不要同时保留 `priv-app/MiuiCamera`：会和 Aperture 抢 camera role，`build_os4.py` 已负责删除。
