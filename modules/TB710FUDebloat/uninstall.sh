#!/system/bin/sh
# uninstall.sh - 模块卸载时自动恢复全部包
# KernelSU 会在删除模块目录前执行本脚本。

case "$0" in
  */*) MODDIR=${0%/*} ;;
  *)   MODDIR=/data/adb/modules/tb710fu_os4_debloat ;;
esac
export MODDIR_OVERRIDE="$MODDIR"

[ -f "$MODDIR/bin/common.sh" ] || exit 0
. "$MODDIR/bin/common.sh"
exec 0</dev/null

# 卸载通常发生在系统运行中；仍做一次等待以防万一
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 30 ]; do
  sleep 2
  i=$((i + 1))
done

if wait_pm; then
  sh "$MODDIR/bin/netblackhole.sh" off >/dev/null 2>&1
  sh "$MODDIR/bin/restore.sh"
else
  log_init "uninstall: PackageManager 未就绪，未能自动恢复"
  echo "警告：PackageManager 未就绪，未自动恢复；开机后请手动执行："
  echo "  pm enable <包名>   （包名见模块 lists/packages.txt）"
fi
