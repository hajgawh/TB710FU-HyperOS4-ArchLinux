# patches/

| 目录 | 内容 | 说明 |
|---|---|---|
| `kernel/full/` | vanilla 7.3 → v36 的 27 个补丁 | 推荐从零构建；先改蓝牙地址 |
| `kernel/incremental/` | v25-prod → v36 的 8 个补丁 | 已有 v25 树时用 |
| `arch/` | 面板背光、Blender 触摸 | 历史专题补丁（Arch 桌面） |
| `ksystemstats/` | KDE 系统监视器 GPU 传感器 | MR !149 + local fallback + PKGBUILD |

## kernel/

详细说明（应用顺序、BT 地址、config、校验）见 [kernel/README.md](kernel/README.md)。

## arch/

| 补丁 | 上游 | 用途 |
|---|---|---|
| `panel-backlight-fix.patch` | `panel-nt36532-wqhd-dual-dsi-dsc.c` | 锁屏 DPMS 背光不灭（`devm_of_find_backlight`） |
| `blender-wayland-touch-fix.patch` | Blender `GHOST_SystemWayland.cc` | 无 pointer 时 grab/hide 崩溃 |

这两个补丁属于 Arch 桌面专题（2026-11-01/02），不是 7.3 内核主线补丁；需要时单独应用。

## ksystemstats/

KDE 系统监视器的 GPU 传感器支持：

- `mr149.patch`：上游 MR !149；
- `local-fallback.patch`：本项目补充的本地回退；
- `PKGBUILD`：Arch Linux ARM 打包。

安装后需要 `setcap cap_sys_ptrace=ep` 才能读 kwin 等 non-dumpable 进程。

## 许可证

补丁各自保留上游许可证（GPL-2.0 / LGPL-2.0-or-later / 见上游），详见根目录 `NOTICE.md`。
