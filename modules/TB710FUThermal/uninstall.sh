#!/system/bin/sh
# Best-effort rollback when the module is removed. The bind mount would also
# disappear on the next reboot, but this restores the stock file immediately.
case "$0" in
  */*) MODDIR=${0%/*} ;;
  *)   MODDIR=$(pwd) ;;
esac
STATE=${TB710FU_THERMAL_STATE:-/data/adb/tb710fu_thermal}
GPU_TARGET=/vendor/etc/thermal-engine_gpu_0.conf
CPU_TARGET=/vendor/etc/thermal-engine_cpu_0.conf

# Stop the watcher first so it cannot re-apply a profile while we roll back.
if [ -f "$STATE/service.lock/pid" ]; then
  kill "$(cat "$STATE/service.lock/pid" 2>/dev/null)" 2>/dev/null
  sleep 1
fi

if [ "$(getprop init.svc.thermal-engine)" = "running" ]; then
  setprop ctl.stop thermal-engine
  i=0
  while [ "$(getprop init.svc.thermal-engine)" = "running" ] && [ $i -lt 15 ]; do
    sleep 1
    i=$((i+1))
  done
fi

for target in "$GPU_TARGET" "$CPU_TARGET"; do
  if mount | grep -q " $target "; then
    umount "$target" 2>/dev/null || umount -l "$target" 2>/dev/null
  fi
done

setprop ctl.start thermal-engine
rm -f "$STATE/applied"
rm -rf "$STATE"
exit 0
