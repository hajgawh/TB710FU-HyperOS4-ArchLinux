#!/system/bin/sh
# action.sh - KernelSU 模块“操作”按钮：冻结 <-> 恢复 切换
# 冻结状态：state=frozen（重启后继续冻结）
# 恢复状态：state=restored（重启后不再冻结，直到再次点按）

case "$0" in
  */*) MODDIR=${0%/*} ;;
  *)   MODDIR=/data/adb/modules/tb710fu_os4_debloat ;;
esac
export MODDIR_OVERRIDE="$MODDIR"
. "$MODDIR/bin/common.sh"

[ "$(id -u)" = "0" ] || { echo "错误：需要 root"; exit 1; }
exec 0</dev/null

cur=$(get_state)
log_init "action toggle (current=$cur)"

if [ "$cur" = "frozen" ]; then
  echo "当前为冻结状态，开始恢复..."
  sh "$MODDIR/bin/restore.sh"
else
  echo "当前为恢复状态，开始冻结..."
  sh "$MODDIR/bin/freeze.sh"
fi
