#!/system/bin/sh
# switch2arch — 从澎湃OS 4 切换到 Arch Linux（配对由 pair.env 提供）
#
# 原理：boot_a 是 kShimC 双内核镜像，菜单默认项在打包时固化。本脚本把
#       “默认 Arch” 的变体整块写入 boot_a，回读 sha256 通过后才允许重启。
#
# 配对（与 Arch 侧 switch2os4 必须完全一致）：
#   /data/adb/tbboot/pair.env 由 tools/make-pair.sh 用你自己的两份 boot 镜像生成。
#   Image-00 GKI 必须是你的 OS4 能启动的版本（TB710FU 为 6.1.128）；不要跨版本替换。
#
# 安全边界（本脚本刻意不做的事）：
#   - 不写 misc / bcb；不切 A/B 槽；不写 boot_b（boot_b 全 0）
#   - 不调用 OTA / update_engine；不要在 OS4 里点系统更新
#   - 只依赖 /data/adb/tbboot（本脚本与镜像的安装位置），不碰 /data 其它内容
#
# 用法（root）：
#   switch2arch.sh                 检查 -> 备份 -> 写入 -> 回读 -> 重启
#   switch2arch.sh --yes           跳过重启确认
#   switch2arch.sh --no-reboot     只写 boot_a，不重启
#   switch2arch.sh --dry           全程检查但不写
#   switch2arch.sh --status        只读显示 boot_a/boot_b/misc 状态
#   switch2arch.sh --restore FILE  用已知镜像/备份恢复 boot_a（不自动重启）
#   switch2arch.sh --force         允许覆盖“未知哈希”的 boot_a（谨慎）
set -eu

SHARE=/data/adb/tbboot
IMG=$SHARE/boot_linux.img
SUM=$SHARE/boot_linux.img.sha256
PART=/dev/block/by-name/boot_a
PARTB=/dev/block/by-name/boot_b
MISC=/dev/block/by-name/misc
BAKDIR=$SHARE/backup
PART_SIZE=100663296

# ---------------------------------------------------------------------------
# 配对信息由 /data/adb/tbboot/pair.env 提供（用 tools/make-pair.sh 生成）。
# 本仓库不包含任何作者构建的 boot 镜像，也不硬编码作者的镜像哈希。
# ---------------------------------------------------------------------------
PAIR_ENV=${PAIR_ENV:-/data/adb/tbboot/pair.env}
if [ -r "$PAIR_ENV" ]; then . "$PAIR_ENV"; fi
PAIR_VERSION=${PAIR_VERSION:-local}
HASH_ANDROID=${HASH_ANDROID:-}
HASH_LINUX=${HASH_LINUX:-}
LEGACY_ANDROID=${LEGACY_ANDROID:-}
LEGACY_LINUX=${LEGACY_LINUX:-}
if [ -z "$HASH_ANDROID" ] || [ -z "$HASH_LINUX" ]; then
  echo "缺少配对信息：$PAIR_ENV（先运行 tools/make-pair.sh 生成）" >&2
  exit 1
fi

YES=0
NOREBOOT=0
DRY=0
FORCE=0
RESTORE=

die() { echo "错误：$*" >&2; exit 1; }

sha_of() { sha256sum "$1" | cut -d' ' -f1; }

classify() {
  case "$1" in
    "$HASH_ANDROID") echo android ;;
    "$HASH_LINUX")   echo linux ;;
    *)
      for h in $LEGACY_ANDROID; do [ "$1" = "$h" ] && { echo legacy-android; return; }; done
      for h in $LEGACY_LINUX;   do [ "$1" = "$h" ] && { echo legacy-linux;   return; }; done
      echo unknown ;;
  esac
}

check_part() {
  [ -b "$PART" ] || die "找不到 $PART"
  if command -v blockdev >/dev/null 2>&1; then
    sz=$(blockdev --getsize64 "$PART" 2>/dev/null || true)
    [ -n "$sz" ] || die "读不到 $PART 大小"
    [ "$sz" = "$PART_SIZE" ] || die "$PART 大小 $sz != $PART_SIZE"
  fi
}

check_image() {
  [ -f "$IMG" ] || die "缺少镜像 ${IMG}；请用 Mac 的 install_switch2arch.sh 安装"
  sz=$(wc -c < "$IMG" | tr -d ' ')
  [ "$sz" = "$PART_SIZE" ] || die "镜像大小 $sz != $PART_SIZE"
  a=$(sha_of "$IMG")
  # sidecar 可选；pair.env 的 HASH_LINUX 才是权威。
  if [ -f "$SUM" ]; then
    e=$(cut -d' ' -f1 "$SUM")
    [ "$a" = "$e" ] || die "镜像与 $SUM 不一致（$a != ${e}）"
  fi
  [ "$a" = "$HASH_LINUX" ] || die "镜像不是 $PAIR_VERSION 的 Arch 默认变体（${a}）"
  [ "$(head -c 8 "$IMG")" = "ANDROID!" ] || die "镜像不是 Android boot image"
  if command -v od >/dev/null 2>&1; then
    rsz=$(od -An -tu4 -j 12 -N 4 "$IMG" 2>/dev/null | tr -d ' ' || true)
    hv=$(od  -An -tu4 -j 40 -N 4 "$IMG" 2>/dev/null | tr -d ' ' || true)
    [ -z "$rsz" ] || [ "$rsz" = 0 ] || die "ramdisk_size=${rsz}（应为 0）"
    [ -z "$hv"  ] || [ "$hv"  = 4 ] || die "header_version=${hv}（应为 4）"
  fi
  [ "$(tail -c 64 "$IMG" | head -c 4)" = "AVBf" ] || die "镜像末尾缺 AVB footer"
  grep -a -q 'Linux version 6\.1\.128-android14' "$IMG" \
    || die "Image-00 不是 6.1.128 GKI（OS4 会卡启动界面）"
  if grep -a -q 'Linux version 6\.1\.112' "$IMG"; then
    die "镜像含 6.1.112（v15 事故 GKI），拒绝写入"
  fi
  grep -a -q 'Linux version 7\.3\.0-tb710fu' "$IMG" || die "缺 Image-01 Linux 7.3.0-tb710fu"
}

show_status() {
  [ "$(id -u)" = 0 ] || die "需要 root 读取 $PART"
  [ -b "$PART" ] || die "找不到 $PART"
  l=$(sha_of "$PART")
  st=$(classify "$l")
  case "$st" in
    android)        echo "boot_a = $PAIR_VERSION HyperOS 默认变体 ($l)" ;;
    linux)          echo "boot_a = $PAIR_VERSION Arch 默认变体 ($l)" ;;
    legacy-android) echo "boot_a = 旧版 HyperOS 变体 ($l)；切换后会升级到 $PAIR_VERSION" ;;
    legacy-linux)   echo "boot_a = 旧版 Arch 变体 ($l)；切换后会升级到 $PAIR_VERSION" ;;
    *)              echo "boot_a = 未知镜像 ($l)" ;;
  esac
  echo "配对   = $PAIR_VERSION  android=$(echo "$HASH_ANDROID" | cut -c1-8)…  linux=$(echo "$HASH_LINUX" | cut -c1-8)…"
  if [ -f "$IMG" ]; then
    echo "待写   = $IMG ($(wc -c < "$IMG" | tr -d ' ') B, sha256=$(sha_of "$IMG"))"
  else
    echo "待写   = 缺失 $IMG"
  fi
  [ -f "$SUM" ] && echo "sidecar= $(cut -d' ' -f1 "$SUM")" || true
  if [ -b "$PARTB" ]; then
    if command -v od >/dev/null 2>&1; then
      z=$(dd if="$PARTB" bs=4096 count=1 2>/dev/null | od -An -tx1 -v | tr -d ' \n' || true)
      case "$z" in
        ""|*[!0]*) echo "boot_b = 非全 0（脚本不写 B 槽，不要依赖它回退）" ;;
        *)         echo "boot_b = 头部全 0（不是可用回退槽）" ;;
      esac
    else
      echo "boot_b = 存在（脚本不写 B 槽）"
    fi
  fi
  if [ -b "$MISC" ]; then
    bcb=$(dd if="$MISC" bs=1 count=32 2>/dev/null | tr -d '\000' || true)
    case "$bcb" in
      "")         echo "misc   = 空（脚本不修改）" ;;
      bootonce-*) echo "misc   = BCB '$bcb'（历史遗留；脚本不修改 misc）" ;;
      *)          echo "misc   = '$bcb'（脚本不修改）" ;;
    esac
  fi
}

backup_boot() {
  mkdir -p "$BAKDIR" || die "无法创建 $BAKDIR"
  chmod 700 "$BAKDIR" 2>/dev/null || true
  avail=$(df -Pk /data | sed -n '2p' | sed 's/^ *//' | tr -s ' ' | cut -d' ' -f4)
  [ "${avail:-0}" -ge 120000 ] || die "/data 剩余空间不足 120 MiB"
  BAK="$BAKDIR/boot_a.$(date +%Y%m%d-%H%M%S).$L.img"
  dd if="$PART" of="$BAK" bs=4M 2>/dev/null || die "备份 boot_a 失败"
  [ "$(sha_of "$BAK")" = "$L" ] || die "备份校验失败：$BAK"
  ls -t "$BAKDIR"/boot_a.*.img 2>/dev/null | tail -n +4 | while IFS= read -r f; do
    rm -f "$f"
  done || true
  echo "已备份 boot_a -> $BAK"
}

write_image() { # SRC EXPECT
  src=$1
  expect=$2
  n=1
  while [ "$n" -le 2 ]; do
    dd if="$src" of="$PART" bs=4M 2>/dev/null || true
    command -v blockdev >/dev/null 2>&1 && blockdev --flushbufs "$PART" 2>/dev/null || true
    sync
    l2=$(sha_of "$PART")
    [ "$l2" = "$expect" ] && return 0
    echo "回读不一致（第 $n 次）：$l2" >&2
    n=$((n + 1))
  done
  return 1
}

restore_boot() {
  [ -n "${BAK:-}" ] && [ -f "$BAK" ] || return 1
  dd if="$BAK" of="$PART" bs=4M 2>/dev/null || true
  command -v blockdev >/dev/null 2>&1 && blockdev --flushbufs "$PART" 2>/dev/null || true
  sync
  [ "$(sha_of "$PART")" = "$L" ]
}

do_write() {
  [ "$DRY" = 1 ] && { echo "--dry：检查通过，不写入"; exit 0; }
  backup_boot
  if ! write_image "$IMG" "$HASH_LINUX"; then
    echo "写入/回读失败，尝试恢复备份 …" >&2
    if restore_boot; then
      die "已恢复原 boot_a（${L}）；未重启。请检查后重试。"
    else
      die "恢复失败！不要重启；请用 EDL 写回 $BAK"
    fi
  fi
  echo "boot_a = $PAIR_VERSION Arch 默认变体（${HASH_LINUX}），回读校验通过。"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --yes) YES=1 ;;
    --no-reboot) NOREBOOT=1 ;;
    --dry) DRY=1 ;;
    --status) show_status; exit 0 ;;
    --force) FORCE=1 ;;
    --restore)
      [ $# -ge 2 ] || die "--restore 需要文件参数"
      RESTORE=$2
      shift ;;
    --restore=*) RESTORE=${1#*=} ;;
    -h|--help)
      cat <<'EOF'
用法: switch2arch.sh [--yes] [--no-reboot] [--dry] [--status] [--force] [--restore FILE]
  --yes           跳过重启确认
  --no-reboot     只写 boot_a，不重启
  --dry           全程检查但不写
  --status        只读显示 boot_a/boot_b/misc 状态
  --restore FILE  用已知镜像/备份恢复 boot_a（不自动重启）
  --force         允许覆盖“未知哈希”的 boot_a（谨慎）
EOF
      exit 0 ;;
    *) echo "用法: switch2arch.sh [--yes] [--no-reboot] [--dry] [--status] [--force] [--restore FILE]" >&2; exit 2 ;;
  esac
  shift
done

[ "$(id -u)" = 0 ] || die "需要 root：adb shell su -c /data/adb/tbboot/switch2arch.sh"

if [ -n "$RESTORE" ]; then
  [ -f "$RESTORE" ] || die "找不到 $RESTORE"
  rsz=$(wc -c < "$RESTORE" | tr -d ' ')
  [ "$rsz" = "$PART_SIZE" ] || die "$RESTORE 大小 $rsz != $PART_SIZE"
  rhash=$(sha_of "$RESTORE")
  case $(classify "$rhash") in
    android|linux|legacy-android|legacy-linux) ;;
    *) [ "$FORCE" = 1 ] || die "$RESTORE 哈希未知（${rhash}）；确需恢复请加 --force" ;;
  esac
  check_part
  L=$(sha_of "$PART")
  [ "$DRY" = 1 ] && { echo "--dry：将写入 ${RESTORE}（${rhash}），不写入"; exit 0; }
  backup_boot
  if ! write_image "$RESTORE" "$rhash"; then
    echo "恢复写入失败，尝试写回刚才的备份 …" >&2
    restore_boot || die "写回备份也失败！不要重启"
    die "已写回原 boot_a（${L}）"
  fi
  echo "已写入 ${RESTORE}（${rhash}），回读校验通过；手动重启生效。"
  exit 0
fi

check_part
check_image
L=$(sha_of "$PART")
state=$(classify "$L")

case "$state" in
  linux)
    echo "boot_a 已是 $PAIR_VERSION Arch 默认变体（哈希一致），无需写入。"
    ;;
  android|legacy-android)
    [ "$state" = legacy-android ] && echo "注意：boot_a 是旧版 HyperOS 变体，将升级到 ${PAIR_VERSION}。"
    do_write
    ;;
  *)
    [ "$FORCE" = 1 ] || die "boot_a 当前哈希 $L 不在已知表内。先用 --status 核对；确认后加 --force。"
    echo "警告：--force 覆盖未知 boot_a（${L}）"
    do_write
    ;;
esac

[ "$DRY" = 1 ] && { echo "--dry：到此为止"; exit 0; }
if [ "$NOREBOOT" = 1 ]; then
  echo "--no-reboot：未重启。下次开机菜单默认进 Arch（8 秒内可改选 HyperOS）。"
  exit 0
fi
if [ "$YES" != 1 ]; then
  printf "现在重启进入 Arch Linux？[y/N] "
  read -r R
  case "$R" in y|Y|yes|Yes) ;; *) echo "已取消（boot_a 已写好，下次重启生效）。"; exit 0 ;; esac
fi
echo "重启中……"
reboot
