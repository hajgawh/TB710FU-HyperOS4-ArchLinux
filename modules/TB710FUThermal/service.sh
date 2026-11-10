#!/system/bin/sh
# Runtime watcher. Maps HyperOS system power mode to the GPU and CPU thermal
# profiles:
#   POWER_PERFORMANCE_MODE_OPEN=1 -> performance
#       GPU: back_temp + skin-msm-therm backstop
#       CPU: back_temp (stock thresholds/actions) + rear-tof-therm backstop
#   0 / unset                    -> balanced (stock copies of both files)
#
# thermal-engine keeps the config files open, so a running engine makes umount
# fail with EBUSY. Every runtime switch therefore stops the engine, swaps both
# mounts, then starts it again.
#
# The watcher runs in a background subshell: KernelSU's service stage executes
# this file synchronously, and an endless foreground loop would block the
# remaining modules. The parent returns immediately.

case "$0" in
  */*) MODDIR=${0%/*} ;;
  *)   MODDIR=$(pwd) ;;
esac
STATE=${TB710FU_THERMAL_STATE:-/data/adb/tb710fu_thermal}
GPU_TARGET=/vendor/etc/thermal-engine_gpu_0.conf
CPU_TARGET=/vendor/etc/thermal-engine_cpu_0.conf
LOG=$STATE/thermal.log
TAG=service
ONESHOT=${ONESHOT:-0}

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

te_running() { [ "$(getprop init.svc.thermal-engine)" = "running" ]; }

stop_te() {
  te_running || return 0
  setprop ctl.stop thermal-engine
  i=0
  while te_running && [ $i -lt 15 ]; do
    sleep 1
    i=$((i+1))
  done
  te_running && tlog "WARN thermal-engine did not stop within 15s"
}

start_te() {
  if te_running; then
    setprop ctl.restart thermal-engine
  else
    setprop ctl.start thermal-engine
  fi
  sleep 1
  if te_running; then
    tlog "thermal-engine running pid=$(getprop init.svc_debug_pid.thermal-engine)"
  else
    tlog "ERROR thermal-engine is not running after start"
  fi
}

apply_mount() { # $1=source $2=target $3=balanced fallback $4=label
  src=$1
  target=$2
  fallback=$3
  label=$4

  if mount | grep -q " $target "; then
    umount "$target" 2>/dev/null || {
      sleep 1
      umount -l "$target" 2>/dev/null
    }
  fi
  if mount --bind "$src" "$target"; then
    tlog "mount $label $(basename "$src") -> $target"
    return 0
  fi

  tlog "ERROR mount failed for $label $src; trying stock fallback"
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

apply_profile() { # $1=profile, $2=1 for runtime switch
  prof=$1
  runtime=${2:-0}
  cpu_prof=$(cpu_profile_for "$prof")
  gpu_src="$MODDIR/profiles/gpu_0.$prof.conf"
  cpu_src="$MODDIR/profiles/cpu_0.$cpu_prof.conf"

  if [ ! -f "$gpu_src" ] || [ ! -f "$cpu_src" ]; then
    tlog "ERROR missing profile (gpu=$gpu_src cpu=$cpu_src); keeping current config"
    return 1
  fi
  # Label both sources before stopping the engine, so a chcon failure cannot
  # leave the system without a thermal daemon.
  if ! chcon u:object_r:vendor_configs_file:s0 "$gpu_src" 2>>"$LOG" || \
     ! chcon u:object_r:vendor_configs_file:s0 "$cpu_src" 2>>"$LOG"; then
    tlog "ERROR chcon failed; keeping current config"
    return 1
  fi

  [ "$runtime" = 1 ] && stop_te

  ok=1
  apply_mount "$gpu_src" "$GPU_TARGET" "$MODDIR/profiles/gpu_0.balanced.conf" gpu || ok=0
  apply_mount "$cpu_src" "$CPU_TARGET" "$MODDIR/profiles/cpu_0.balanced.conf" cpu || ok=0

  if [ "$ok" = 1 ]; then
    echo "$prof" > "$STATE/applied"
    tlog "applied gpu=$prof cpu=$cpu_prof runtime=$runtime"
  else
    echo partial > "$STATE/applied"
    tlog "WARN partial apply (gpu=$prof cpu=$cpu_prof); will retry"
  fi

  [ "$runtime" = 1 ] && start_te
}

restore_stock() {
  tlog "restoring stock config (module disabled or removed)"
  stop_te
  for target in "$GPU_TARGET" "$CPU_TARGET"; do
    if mount | grep -q " $target "; then
      umount "$target" 2>/dev/null || umount -l "$target" 2>/dev/null
    fi
  done
  rm -f "$STATE/applied"
  start_te
}

run_watcher() {
  # One watcher per boot. A stale lock from the previous boot must not be
  # trusted: PIDs are reused after reboot, so compare boot_id as well.
  LOCK=$STATE/service.lock
  BOOTID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
  if ! mkdir "$LOCK" 2>/dev/null; then
    old_boot=$(cat "$LOCK/boot_id" 2>/dev/null)
    old=$(cat "$LOCK/pid" 2>/dev/null)
    if [ -n "$BOOTID" ] && [ "$old_boot" = "$BOOTID" ] && [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
      tlog "another watcher ($old) is running; exit"
      exit 0
    fi
    rm -rf "$LOCK"
    mkdir "$LOCK" 2>/dev/null || exit 0
  fi
  echo $$ > "$LOCK/pid"
  echo "$BOOTID" > "$LOCK/boot_id"
  trap 'rm -rf "$LOCK"' EXIT

  i=0
  while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 120 ]; do
    sleep 2
    i=$((i+1))
  done
  sleep 5

  while :; do
    if [ ! -f "$MODDIR/module.prop" ] || [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]; then
      restore_stock
      exit 0
    fi

    sys_mode=""
    raw=$(settings get system POWER_PERFORMANCE_MODE_OPEN 2>/dev/null | tr -d ' \r\n')
    case "$raw" in
      1) sys_mode=performance ;;
      0) sys_mode=balanced ;;
    esac
    if [ -n "$sys_mode" ]; then
      prev_mode=$(cat "$STATE/mode" 2>/dev/null | tr -d ' \r\n')
      if [ "$prev_mode" != "$sys_mode" ]; then
        echo "$sys_mode" > "$STATE/mode"
        if [ -x /data/adb/ksu/bin/resetprop ]; then
          /data/adb/ksu/bin/resetprop persist.sys.tb710fu.thermal.mode "$sys_mode" >/dev/null 2>&1
        fi
      fi
    else
      sys_mode=$(cat "$STATE/mode" 2>/dev/null | tr -d ' \r\n')
      case "$sys_mode" in performance|balanced) ;; *) sys_mode=balanced ;; esac
    fi

    manual=$(cat "$STATE/manual_mode" 2>/dev/null | tr -d ' \r\n')
    case "$manual" in performance|balanced) mode=$manual ;; *) mode=$sys_mode ;; esac

    want=$(profile_for "$mode")
    applied=$(cat "$STATE/applied" 2>/dev/null | tr -d ' \r\n')
    gpu_mounted=0
    cpu_mounted=0
    mount | grep -q " $GPU_TARGET " && gpu_mounted=1
    mount | grep -q " $CPU_TARGET " && cpu_mounted=1

    if [ "$want" != "$applied" ] || [ "$gpu_mounted" != 1 ] || [ "$cpu_mounted" != 1 ]; then
      tlog "switch: sys=$sys_mode manual=${manual:-none} want=$want applied=${applied:-none} gpu_mount=$gpu_mounted cpu_mount=$cpu_mounted"
      apply_profile "$want" 1
    fi

    [ "$ONESHOT" = 1 ] && exit 0
    sleep 10
  done
}

if [ "$ONESHOT" = 1 ]; then
  run_watcher
elif [ "${TB710FU_WATCHER_DAEMON:-}" = 1 ]; then
  run_watcher
else
  # ksud reaps the service.sh process group after it exits; detach into a new
  # session so the watcher survives (same trick as TB710FUSetRes).
  if [ -x /data/adb/ksu/bin/busybox ]; then
    TB710FU_WATCHER_DAEMON=1 /data/adb/ksu/bin/busybox setsid sh "$MODDIR/service.sh"       >/dev/null 2>&1 </dev/null &
  else
    TB710FU_WATCHER_DAEMON=1 setsid sh "$MODDIR/service.sh" >/dev/null 2>&1 </dev/null &
  fi
  exit 0
fi
