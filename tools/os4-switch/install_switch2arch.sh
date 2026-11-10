#!/bin/sh
# install_switch2arch.sh — 在平板运行澎湃OS 4 时，从主机安装/更新 OS4 侧的
# “切换到 Arch”组件（脚本 + KernelSU 模块 tb710fu_switch + 配对 boot_linux.img）。
#
# 用法：
#   TB_SERIAL=<serial> ./install_switch2arch.sh boot_linux.img pair.env
#   （USB adb 不需要 TB_SERIAL；无线 adb 需要先 adb connect <ip>:5555）
#
# 配对文件必须由你自己的两份 boot 镜像生成：
#   tools/make-pair.sh boot_android.img boot_linux.img > pair.env
set -e

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
IMG=${1:-$HERE/boot_linux.img}
PAIR_ENV=${2:-${PAIR_ENV:-$HERE/pair.env}}
SW=$HERE/switch2arch.sh

die() { echo "错误：$*" >&2; exit 1; }

[ -f "$IMG" ] || die "缺镜像 $IMG（先构建 boot_linux.img）"
[ -f "$SW" ] || die "缺 $SW"
[ -r "$PAIR_ENV" ] || die "缺配对文件 $PAIR_ENV（先运行 tools/make-pair.sh）"

# shellcheck disable=SC1090
. "$PAIR_ENV"
EXPECT=${HASH_LINUX:-}
[ -n "$EXPECT" ] || die "$PAIR_ENV 里没有 HASH_LINUX"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -c1-64
  fi
}

GOT=$(sha256_file "$IMG")
echo "boot image: $IMG"
echo "sha256:     $GOT"
[ "$GOT" = "$EXPECT" ] || {
  echo "镜像与 pair.env 的 HASH_LINUX 不一致（$GOT != $EXPECT）" >&2
  exit 1
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '%s  boot_linux.img\n' "$GOT" > "$TMP/boot_linux.img.sha256"

# --- 找设备：TB_SERIAL 指定 > 唯一设备 > 用户提供的无线 adb ---
ADB=adb
if [ -n "${TB_SERIAL:-}" ]; then
  ADB="adb -s $TB_SERIAL"
else
  if [ "$(adb get-state 2>/dev/null)" != device ] && [ -n "${TB_TABLET_IP:-}" ]; then
    adb connect "$TB_TABLET_IP:5555" >/dev/null 2>&1 || true
    sleep 1
  fi
fi
[ "$($ADB get-state 2>/dev/null)" = device ] || {
  echo "找不到 adb 设备：USB 连接，或 adb connect <平板IP>:5555 并设 TB_TABLET_IP；" >&2
  echo "多台 adb 设备时必须设 TB_SERIAL=<serial>。" >&2
  adb devices >&2
  exit 1
}

# 身份守门 1：TB710FU 的 OS4 机型名是 piano（商店身份）。
DEVICE=$($ADB shell getprop ro.product.device 2>/dev/null | tr -d '\r')
case "$DEVICE" in
  piano|TB710FU|tb710fu) : ;;
  *) die "当前 adb 设备 ro.product.device='${DEVICE:-unknown}'，不是 TB710FU。" ;;
esac
echo "adb device: $DEVICE"

# 身份守门 2：SoC 必须是 SM8650*（机型名可能被移植包伪装）。
SOC=$($ADB shell getprop ro.soc.model 2>/dev/null | tr -d '\r')
case "$SOC" in
  SM8650*) : ;;
  *) die "soc.model='${SOC:-unknown}'，TB710FU 应为 SM8650*。" ;;
esac
echo "soc: $SOC"

echo "== push 文件（adb+su，需要 root 授权弹窗时点允许）"
$ADB shell "rm -rf /data/local/tmp/tb_install_stage; mkdir -p /data/local/tmp/tb_install_stage"
$ADB push "$IMG"                       /data/local/tmp/tb_install_stage/boot_linux.img
$ADB push "$TMP/boot_linux.img.sha256" /data/local/tmp/tb_install_stage/boot_linux.img.sha256
$ADB push "$SW"                        /data/local/tmp/tb_install_stage/switch2arch.sh
$ADB push "$PAIR_ENV"                  /data/local/tmp/tb_install_stage/pair.env
$ADB push "$HERE/module.prop"          /data/local/tmp/tb_install_stage/module.prop
$ADB push "$HERE/action.sh"            /data/local/tmp/tb_install_stage/action.sh
$ADB push "$HERE/device_install.sh"    /data/local/tmp/tb_install.sh

echo "== 设备端安装"
$ADB shell su -c "sh /data/local/tmp/tb_install.sh"

echo "== 自检（只读）"
$ADB shell su -c "/data/adb/tbboot/switch2arch.sh --status"
echo "== dry-run（不写入；boot_a 是未知哈希时会拒绝，这是预期）"
$ADB shell su -c "/data/adb/tbboot/switch2arch.sh --dry" || true

cat <<'EOF'

== 完成。之后在澎湃OS里切回 Arch：
  1) KernelSU 管理器 → 模块 → "TB710FU 系统切换" → 执行动作（重启）
  2) 或 adb shell su -c /data/adb/tbboot/switch2arch.sh
  3) 兜底：开机 8 秒菜单手动选 Linux
注意：重新构建内核后，两侧镜像与 pair.env 必须一起更新，否则脚本会拒绝写入。
EOF
