#!/bin/bash
# build-from-series.sh — 从 kernel.org Linux 7.3 + 本仓库补丁序列重建 TB710FU 内核。
#
# 在 kernel-build 容器里运行（aarch64 原生编译，无需交叉工具链）：
#
#   docker run --rm \
#     -v tb-kwork:/w \
#     -v "$PWD":/src:ro \
#     -v "$PWD/out":/out \
#     kernel-build:latest bash /src/tools/arch-kernel/build-from-series.sh
#
# 输入（相对本仓库根目录）：
#   patches/kernel/full/0001..0027            vanilla 7.3 → v36 的 27 个补丁
#   tools/arch-kernel/config-7.3.0-tb710fu    canonical config
#   tools/arch-kernel/initramfs/              init / diag.sh / nbdroot.sh
#
# 输出（/out）：
#   Image, sm8650-lenovo-tb710fu-kshim.dtb, modules-7.3.0-tb710fu.tar, BUILD-INFO.txt
#
# 注意：
#   - 应用前先用 tools/arch-kernel/set-bt-addr.sh 把 0020 里的占位符 MAC
#     换成你自己的工厂地址；否则蓝牙会拿到一个假地址。
#   - 必须保留 CONFIG_LOCALVERSION="-tb710fu"，最终 kernelrelease = 7.3.0-tb710fu。
set -euo pipefail

SRC=${SRC:-/src}
OUT=${OUT:-/out}
TREE=${TREE:-/w/tb710fu-build}
CONFIG=${CONFIG:-$SRC/tools/arch-kernel/config-7.3.0-tb710fu}
PATCHES=${PATCHES:-$SRC/patches/kernel/full}
INITRAMFS=${INITRAMFS:-$SRC/tools/arch-kernel/initramfs}
KREL=${KREL:-7.3.0-tb710fu}

mkdir -p "$OUT"
[ -n "$TREE" ] && [ "$TREE" != "/" ] && [ "$TREE" != "/w" ] \
  || { echo "ERROR: refusing to rm -rf TREE='$TREE'" >&2; exit 1; }
rm -rf "$TREE"

# ---------------------------------------------------------------------------
# 1) vanilla 7.3
# ---------------------------------------------------------------------------
V=7.3
mkdir -p "$TREE"
cd "$TREE"
if [ ! -f "linux-$V.tar.xz" ]; then
  curl -fLO "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-$V.tar.xz"
fi
tar -xf "linux-$V.tar.xz"
cd "linux-$V"
git init -q
git -c user.name=tb -c user.email=tb@local add -A
git -c user.name=tb -c user.email=tb@local commit -qm "vanilla $V"

# ---------------------------------------------------------------------------
# 2) 27 个补丁（git am 保持提交边界；顺序不能乱）
# ---------------------------------------------------------------------------
git -c user.name=tb -c user.email=tb@local am -q "$PATCHES"/*.patch

# ---------------------------------------------------------------------------
# 3) 防御性检查：占位符 MAC 是否还在
# ---------------------------------------------------------------------------
if grep -q '02:11:22:33:44:55\|55 44 33 22 11 02' \
     arch/arm64/boot/dts/qcom/sm8650-lenovo-tb710fu-kshim.dts 2>/dev/null; then
  if [ "${TB_ALLOW_PLACEHOLDER_BT:-}" = 1 ]; then
    echo "警告：DTS 里仍是占位符蓝牙地址（TB_ALLOW_PLACEHOLDER_BT=1 已放行）。" >&2
  else
    echo "ERROR: DTS 里仍是占位符蓝牙地址；先在仓库根运行 set-bt-addr.sh，或设 TB_ALLOW_PLACEHOLDER_BT=1。" >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# 4) initramfs（config 里 CONFIG_INITRAMFS_SOURCE="initramfs.list"）
# ---------------------------------------------------------------------------
rm -rf /tmp/initramfs
mkdir -p /tmp/initramfs
cp -a "$INITRAMFS"/. /tmp/initramfs/
cp /bin/busybox /tmp/initramfs/busybox 2>/dev/null || cp /usr/bin/busybox /tmp/initramfs/busybox
cat > initramfs.list <<'LIST'
dir /dev 755 0 0
nod /dev/console 600 0 0 c 5 1
dir /bin 755 0 0
dir /proc 755 0 0
dir /sys 755 0 0
dir /tmp 1777 0 0
dir /run 755 0 0
dir /newroot 755 0 0
file /bin/busybox /tmp/initramfs/busybox 755 0 0
file /init /tmp/initramfs/init 755 0 0
file /diag.sh /tmp/initramfs/diag.sh 755 0 0
file /nbdroot.sh /tmp/initramfs/nbdroot.sh 755 0 0
LIST

# ---------------------------------------------------------------------------
# 5) 构建（KERNELRELEASE 必须显式给，否则模块 vermagic 带 '+'）
# ---------------------------------------------------------------------------
cp "$CONFIG" .config
make -s LOCALVERSION= KERNELRELEASE="$KREL" olddefconfig
make -j"$(nproc)" LOCALVERSION= KERNELRELEASE="$KREL" Image dtbs modules

rm -rf /tmp/modstage
make -s LOCALVERSION= KERNELRELEASE="$KREL" \
     INSTALL_MOD_PATH=/tmp/modstage INSTALL_MOD_STRIP=1 modules_install
KV=$(make -s LOCALVERSION= KERNELRELEASE="$KREL" kernelrelease)
[ "$KV" = "$KREL" ] || { echo "kernelrelease=$KV != $KREL" >&2; exit 1; }
rm -f /tmp/modstage/lib/modules/"$KV"/{build,source}

cp arch/arm64/boot/Image "$OUT/Image"
cp arch/arm64/boot/dts/qcom/sm8650-lenovo-tb710fu-kshim.dtb "$OUT/"
tar cf "$OUT/modules-$KV.tar" -C /tmp/modstage/lib/modules "$KV"

{
  echo "kernel: $KV"
  echo "date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "source: kernel.org linux-$V + patches/kernel/full (27)"
  echo "Image: $(sha256sum "$OUT/Image" | awk '{print $1}')"
  echo "DTB: $(sha256sum "$OUT/sm8650-lenovo-tb710fu-kshim.dtb" | awk '{print $1}')"
  echo "modules: $(sha256sum "$OUT/modules-$KV.tar" | awk '{print $1}')"
} > "$OUT/BUILD-INFO.txt"

cat "$OUT/BUILD-INFO.txt"
echo "BUILD-FROM-SERIES-OK"
