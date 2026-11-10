# patches/kernel — 7.3 内核补丁序列

> vanilla Linux 7.3 → `v36-quiet2` 的完整补丁，`git format-patch` 格式。
> 所有补丁为 GPL-2.0；来源与致谢见根目录 `NOTICE.md`。

---

## 1. 目录

```text
patches/kernel/
├── full/             # vanilla 7.3 -> v36 的 27 个补丁（推荐从零构建）
│   ├── 0001-freedom-series-on-7.3.patch
│   ├── 0002-tb-base.patch
│   ├── 0003..0019   # TB710FU 逐项修复
│   ├── 0020-tb710fu-restore-factory-Bluetooth-address.patch
│   ├── 0021..0026   # QMP DP_ONLY / shrinker / WCD F1 / dwc3 quirk / USB1 / initramfs
│   └── 0027-tb710fu-Type-C-DP-orientation-fixes-and-bring-up-log.patch
└── incremental/      # v25-prod -> v36 的 8 个补丁（已有 v25 树时用）
```

`full/` 的补丁编号与提交顺序一致，**不要打乱**。

---

## 2. 应用

```bash
# 1) 在仓库根目录先改蓝牙地址（默认改 0002 + 0020 + incremental/0001）
<repo>/tools/arch-kernel/set-bt-addr.sh AA:BB:CC:DD:EE:FF

# 2) 干净 vanilla 7.3
tar xf linux-7.3.tar.xz && cd linux-7.3
git init -q && git add -A && git -c user.name=tb -c user.email=tb@local commit -qm "vanilla 7.3"

# 3) 顺序应用
git am <repo>/patches/kernel/full/*.patch

# 4) 校验
git log --oneline | head -30
```

或者直接用 `tools/arch-kernel/build-from-series.sh`（自动完成 1–3 并构建）。

`incremental/` 的用法：

```bash
git am <repo>/patches/kernel/incremental/*.patch
# 前提：树已包含 v25-prod（或从 v25-prod 的 bundle 恢复）
```

---

## 3. 蓝牙地址（必须先改）

`0002-tb-base.patch` 在板级 DTS **新增** `local-bd-address`；
`0020-…-Bluetooth-address.patch` 把 kshim DTS 的 `00 00 00 00 00 00` 改成同一地址，
并在 context 里带着板级 DTS 的地址。**两个补丁必须写成同一个值**，否则 0020 会
context mismatch。

```bash
tools/arch-kernel/set-bt-addr.sh 02:11:22:33:44:55
# 默认同时处理 full/0002、full/0020、incremental/0001
```

校验：

```bash
grep -n 'local-bd-address' patches/kernel/full/0002-tb-base.patch \
                           patches/kernel/full/0020-*.patch
```

仓库里的 `02:11:22:33:44:55` / `[55 44 33 22 11 02]` 是**占位符**；不要直接构建。
地址来源与隐私说明见根目录 [PRIVACY.md](../../PRIVACY.md) §2。

---

## 4. 关键提交

| 标签/提交 | 内容 |
|---|---|
| `vanilla 7.3` | kernel.org |
| `freedom series on 7.3` | 0001 |
| `tb-base` | 0002 |
| `v25-prod` | 0019 + 调试打印清理 |
| `v26-prod` | 0020（BT 地址）+ 0021（QMP DP_ONLY） |
| `v31-msm-psi` | 0022（shrinker）+ 0023（WCD F1）+ 0024（dwc3 quirk）+ 0025（USB1）+ 0026（initramfs） |
| `v36-quiet2` | 0027（v33b→v36 Type-C/日志合集） |

作者基线：`f42ba8a84`（`tb710fu: Type-C DP orientation fixes and bring-up log diet`）。
你的提交哈希会不同（`git am` 会保留作者信息但提交时间/父链不同）。

---

## 5. 与 config 的配合

`tools/arch-kernel/config-7.3.0-tb710fu` 必须与补丁一起用：

- `CONFIG_LOCALVERSION="-tb710fu"` → `kernelrelease=7.3.0-tb710fu`；
- `CONFIG_PSI=y`、`CONFIG_LRU_GEN=y`、`CONFIG_ZRAM_BACKEND_{LZO,LZ4,ZSTD}=y`；
- `CONFIG_INITRAMFS_SOURCE="initramfs.list"`；
- `CONFIG_MODULE_SIG` 关闭（自编模块可加载）。

改 config 后：

```bash
make -s LOCALVERSION= KERNELRELEASE=7.3.0-tb710fu olddefconfig
# 必须再 syncconfig，避免被旧 .config 覆盖
```

---

## 6. 校验

```bash
# 补丁可应用（dry-run）
git apply --check patches/kernel/full/*.patch   # 只适用于单补丁；序列请用 git am

# 构建产物
cat out/BUILD-INFO.txt
sha256sum out/Image out/*.dtb out/modules-*.tar

# 运行时
uname -v
modinfo -F vermagic msm
```

期望：`kernelrelease = 7.3.0-tb710fu`；`Image`/DTB/modules 哈希与 `BUILD-INFO.txt` 一致；
`btmgmt info` 显示你自己的地址。

---

## 7. 注意

1. `0001-freedom-series-on-7.3.patch` 很大（约 1.3 MB），包含 SM8650/掌机补丁集；
   其中个别 hunk 是为 7.3 适配的，失败时先确认 tarball 是 7.3。
2. `0020` 的地址是设备唯一值；公开仓库里必须用占位符。
3. `0022` 依赖 `dma_resv_test_signaled()`（7.3 已有）。
4. `0027` 是 v33b/v33c/v33d/v33e/v34/v35b/v36 的最终合集，**不要**再单独套中间版本
   （v33c 是灾难版本，已回退）。
5. 补丁不含任何二进制；`Image`/DTB/modules 由你自己构建。
