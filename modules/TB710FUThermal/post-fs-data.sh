#!/system/bin/sh
# Early-boot profile selection. Runs before thermal-engine starts, so plain
# bind mounts are enough; no daemon restart is needed here.
#
# Both GPU and CPU files are selected together:
#   /vendor/etc/thermal-engine_gpu_0.conf   SS-GPU-0-3 (+ skin backstop)
#   /vendor/etc/thermal-engine_cpu_0.conf   cpu0-0-0 ... cpu5-0-0 (+ rear-tof backstop)
#
# Performance: GPU uses back_temp, CPU uses back_temp (stock thresholds/actions)
# and each has a high-temperature backstop on the original sensor.
# Balanced: stock copies of both files.
#
# Mode source (first hit wins):
#   $STATE/manual_mode      manual override, never overwritten by this module
#   $STATE/mode             last mode observed by service.sh (survives reboot)
#   persist.sys.tb710fu.thermal.mode
#   balanced
#
# HyperOS stores its settings in ABX binary form, so `settings get` is not
# available at post-fs-data; the cached mode file is what makes this stage work.

case "$0" in
  */*) MODDIR=${0%/*} ;;
  *)   MODDIR=$(pwd) ;;
esac
STATE=${TB710FU_THERMAL_STATE:-/data/adb/tb710fu_thermal}
GPU_TARGET=/vendor/etc/thermal-engine_gpu_0.conf
CPU_TARGET=/vendor/etc/thermal-engine_cpu_0.conf
LOG=$STATE/thermal.log
TAG=post-fs-data

mkdir -p "$STATE" 2>/dev/null

tlog() {
  echo "$(date '+%m-%d %H:%M:%S') [$TAG] $*" >> "$LOG" 2>/dev/null
  sz=$(wc -c < "$LOG" 2>/dev/null)
  [ "${sz:-0}" -gt 65536 ] && mv -f "$LOG" "$LOG.1" 2>/dev/null
}

profile_for() {
  case "$1" in
    performance)
      p=$(cat "$STATE/performance_profile" 2>/dev/null | tr -d ' \r\n')
      case "$p" in
        performance_aggressive) echo performance_aggressive ;;
        *) echo performance ;;
      esac
      ;;
    *) echo balanced ;;
  esac
}

cpu_profile_for() {
  case "$1" in
    balanced) echo balanced ;;
    *) echo performance ;;
  esac
}

apply_file() { # $1=label $2=source $3=target $4=balanced fallback
  label=$1
  src=$2
  target=$3
  fallback=$4

  if [ ! -f "$src" ]; then
    tlog "ERROR missing $label profile $src"
    return 1
  fi
  if ! chcon u:object_r:vendor_configs_file:s0 "$src" 2>>"$LOG"; then
    tlog "ERROR chcon failed on $src; leaving stock $label config untouched"
    return 1
  fi

  if mount | grep -q " $target "; then
    umount "$target" 2>/dev/null || umount -l "$target" 2>/dev/null
  fi
  if mount --bind "$src" "$target"; then
    tlog "bind $label $(basename "$src") -> $target"
    return 0
  fi

  tlog "ERROR bind failed for $label $src; trying stock fallback"
  if [ -f "$fallback" ]; then
    chcon u:object_r:vendor_configs_file:s0 "$fallback" 2>>"$LOG"
    if mount --bind "$fallback" "$target"; then
      tlog "fallback $label $(basename "$fallback") -> $target"
      return 1
    fi
  fi
  tlog "ERROR fallback failed for $label; stock vendor file remains active"
  return 1
}

mode=""
[ -f "$STATE/manual_mode" ] && mode=$(cat "$STATE/manual_mode" 2>/dev/null | tr -d ' \r\n')
[ -z "$mode" ] && [ -f "$STATE/mode" ] && mode=$(cat "$STATE/mode" 2>/dev/null | tr -d ' \r\n')
[ -z "$mode" ] && mode=$(getprop persist.sys.tb710fu.thermal.mode 2>/dev/null)
case "$mode" in performance|balanced) ;; *) mode=balanced ;; esac

profile=$(profile_for "$mode")
cpu_profile=$(cpu_profile_for "$profile")
gpu_src="$MODDIR/profiles/gpu_0.$profile.conf"
cpu_src="$MODDIR/profiles/cpu_0.$cpu_profile.conf"
ok=1

tlog "early boot: mode=$mode gpu=$profile cpu=$cpu_profile"

apply_file gpu "$gpu_src" "$GPU_TARGET" "$MODDIR/profiles/gpu_0.balanced.conf" || ok=0
apply_file cpu "$cpu_src" "$CPU_TARGET" "$MODDIR/profiles/cpu_0.balanced.conf" || ok=0

if [ "$ok" = 1 ]; then
  echo "$profile" > "$STATE/applied"
else
  echo partial > "$STATE/applied"
  tlog "WARN one or more mounts fell back; service.sh will retry"
fi

if [ -x /data/adb/ksu/bin/resetprop ]; then
  /data/adb/ksu/bin/resetprop persist.sys.tb710fu.thermal.profile "$profile" >/dev/null 2>&1
fi

exit 0
