#!/bin/sh
# make-pair.sh — 用你自己的两份 boot 镜像生成双系统配对文件 pair.env。
#
# 用法：
#   tools/make-pair.sh boot_android.img boot_linux.img > pair.env
#   tools/make-pair.sh boot_android.img boot_linux.img --out tools/os4-switch/pair.env
#
# boot_android.img = kShimC 打包的“默认 HyperOS”变体（含 GKI + Linux + DTB）
# boot_linux.img   = 同一内核、同一 DTB 的“默认 Arch”变体
# 两者必须来自同一次 kshim_variants.sh 打包，否则切换后模块与内核不匹配。
#
# 生成后把 pair.env 同时装到：
#   Arch:  /usr/local/share/tbboot/pair.env
#   OS4:   /data/adb/tbboot/pair.env
set -eu

die() { echo "错误：$*" >&2; exit 1; }

[ $# -ge 2 ] || die "用法: $0 boot_android.img boot_linux.img [--out FILE]"
A=$1
L=$2
OUT=
[ "${3:-}" = "--out" ] && { OUT=${4:?--out 需要文件路径}; }

[ -f "$A" ] || die "缺 $A"
[ -f "$L" ] || die "缺 $L"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -c1-64
  fi
}

sha() { sha256_file "$1"; }
size() { wc -c < "$1" | tr -d ' '; }

HA=$(sha "$A")
HL=$(sha "$L")
SA=$(size "$A")
SL=$(size "$L")
VER=${PAIR_VERSION:-local-$(date +%Y%m%d)}

# boot 分区在 TB710FU 上是 96 MiB；两份镜像必须同尺寸，否则切换后可能写坏/不匹配。
[ "$SA" = "100663296" ] || die "$A 大小 $SA != 100663296（96 MiB）"
[ "$SL" = "100663296" ] || die "$L 大小 $SL != 100663296（96 MiB）"
[ "$SA" = "$SL" ] || die "两份镜像大小不同（$SA vs $SL）；必须来自同一次 kshim_variants.sh 打包"

gen() {
  cat <<EOF
# 由 tools/make-pair.sh 生成于 $(date -u +%Y-%m-%dT%H:%M:%SZ)
# 修改镜像后必须重新生成，并同步两侧文件。
PAIR_VERSION=$VER
HASH_ANDROID=$HA
HASH_LINUX=$HL
ANDROID_SIZE=$SA
LINUX_SIZE=$SL
EOF
}

if [ -n "$OUT" ]; then
  gen > "$OUT"
  echo "写入 $OUT" >&2
  cat "$OUT"
else
  gen
fi
