#!/system/bin/sh
# service.sh - late_start 阶段执行：等待系统就绪后应用冻结
# state=restored 时跳过，保证“恢复”后重启不会被重新冻结。

case "$0" in
  */*) MODDIR=${0%/*} ;;
  *)   MODDIR=/data/adb/modules/tb710fu_os4_debloat ;;
esac
export MODDIR_OVERRIDE="$MODDIR"

[ -f "$MODDIR/bin/common.sh" ] || exit 0
. "$MODDIR/bin/common.sh"
exec 0</dev/null

# 等 boot_completed（最长约 300s）
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 150 ]; do
  sleep 2
  i=$((i + 1))
done

# 再留一点时间给 PackageManager/系统服务
sleep 3

# 网络层兜底：iptables 规则不持久，按 net_state 重建（默认 on；restore 会写 off）
netst=$(cat "$STATE_DIR/net_state" 2>/dev/null || echo on)
if [ "$netst" = "on" ]; then
  sh "$MODDIR/bin/netblackhole.sh" on >/dev/null 2>&1
fi

if [ "$(get_state)" = "restored" ]; then
  log_init "boot: state=restored, skip"
  exit 0
fi

wait_pm || { log_init "boot: PackageManager 未就绪，本次跳过"; exit 0; }

log_init "boot: apply freeze"
sh "$MODDIR/bin/freeze.sh"
