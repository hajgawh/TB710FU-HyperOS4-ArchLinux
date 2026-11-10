#!/bin/bash
# Read-only post-flash verification for TB710FU HyperOS 4.
#
# usage: tools/verify_device.sh [ADB_SERIAL]
# env:   ADB_SERIAL
#
# It only reads props/Settings/sysfs and lists modules; it never changes the
# device.  Values that are user preferences (density override, refresh choice)
# are reported as INFO instead of FAIL.
set -u

SERIAL=${1:-${ADB_SERIAL:-}}
if [ -z "$SERIAL" ]; then
  echo "usage: $0 ADB_SERIAL   (or set ADB_SERIAL)" >&2
  echo "connected:" >&2
  adb devices -l >&2
  exit 2
fi
A=(adb -s "$SERIAL")
PASS=0; FAIL=0; WARN=0
sh_() {
  local out
  out=$("${A[@]}" shell "$@" 2>/dev/null) || return 1
  printf '%s\n' "$out" | tr -d '\r'
}
sh_rc() { "${A[@]}" shell "$@" >/dev/null 2>&1; }
ok()   { printf '  OK   %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL %s\n' "$*"; FAIL=$((FAIL+1)); }
info() { printf '  INFO %s\n' "$*"; WARN=$((WARN+1)); }
check_eq() { # actual expected label
  if [ "$1" = "$2" ]; then ok "$3 = $1"; else bad "$3 = '$1' (want '$2')"; fi
}
check_has() { # actual needle label
  case "$1" in *"$2"*) ok "$3 contains '$2'";; *) bad "$3 = '$1' (want '$2')";; esac
}
check_one_of() { # actual "a|b" label
  local a=$1 rest=$2 label=$3 v
  IFS='|' read -r -a vals <<< "$rest"
  for v in "${vals[@]}"; do [ "$a" = "$v" ] && { ok "$label = $a"; return; }; done
  bad "$label = '$a' (want one of $rest)"
}

echo "== device"
INC=$(sh_ getprop ro.build.version.incremental)
DEV=$(sh_ getprop ro.product.device)
MODEL=$(sh_ getprop ro.product.model)
MARKET=$(sh_ getprop ro.product.marketname)
check_has "$INC" 'OS4' 'ro.build.version.incremental'
check_eq "$DEV" 'piano' 'ro.product.device'
info "ro.product.model=$MODEL (piano identity kept for store updates)"
check_has "$MARKET" '联想' 'ro.product.marketname'
check_has "$(sh_ getprop ro.product.odm.marketname)" '联想' 'ro.product.odm.marketname'

echo "== package-level UI defaults"
check_one_of "$(sh_ settings get system font_scale)" '1|1.0' 'font_scale'
check_one_of "$(sh_ settings get system device_font_scale)" '1|1.0' 'device_font_scale'
check_eq "$(sh_ settings get system ui_mode_scale)" '1' 'ui_mode_scale'
check_eq "$(sh_ cmd overlay lookup com.android.systemui com.android.systemui:dimen/rounded_corner_content_padding)" \
  '40.0px' 'rounded_corner_content_padding'
check_one_of "$(sh_ settings get secure back_gesture_inset_scale_left)" 'null|1.0' 'back_gesture_inset_scale_left (stock default)'
check_one_of "$(sh_ settings get secure back_gesture_inset_scale_right)" 'null|1.0' 'back_gesture_inset_scale_right (stock default)'
PEAK=$(sh_ settings get system peak_refresh_rate)
MIUI=$(sh_ settings get system miui_refresh_rate)
USER=$(sh_ settings get system user_refresh_rate)
case "$PEAK" in 120|null|'') ok "peak_refresh_rate=$PEAK (stock 120/未写)";; *) info "peak_refresh_rate=$PEAK (user choice)";; esac
case "$MIUI" in null|'') ok 'miui_refresh_rate not written';; *) info "miui_refresh_rate=$MIUI (unexpected writer)";; esac
case "$USER" in null|'') ok 'user_refresh_rate not written';; *) info "user_refresh_rate=$USER (unexpected writer)";; esac
DENS=$(sh_ settings get secure display_density_forced)
if [ -z "$DENS" ] || [ "$DENS" = null ]; then ok 'no display_density_forced override (440 native)'; else info "display_density_forced=$DENS (legacy 434 user setting)"; fi
sh_ wm size | sed 's/^/  INFO /'
sh_ wm density | sed 's/^/  INFO /'

echo "== lwky switches"
check_one_of "$(sh_ getprop persist.sys.gesture_wakeup)" '2|0' 'persist.sys.gesture_wakeup'
check_one_of "$(sh_ getprop persist.sys.device_case_enabled)" '1|0' 'persist.sys.device_case_enabled'
check_one_of "$(sh_ getprop persist.sys.high_touch_sampling_rate.enable)" '1|0' 'persist.sys.high_touch_sampling_rate.enable'
check_one_of "$(sh_ getprop persist.sys.stylus.enable)" '1|0' 'persist.sys.stylus.enable'
check_one_of "$(sh_ getprop persist.sys.pc_mode)" '0|1|2' 'persist.sys.pc_mode'
check_has "$(sh_ cat /proc/gesture_control)" '1' '/proc/gesture_control'
check_eq "$(sh_ cat /proc/game_mode)" '2' '/proc/game_mode'
check_eq "$(sh_ cat /proc/game_edge)" '0' '/proc/game_edge'
check_eq "$(sh_ cat /proc/support_pen)" '1' '/proc/support_pen'
check_eq "$(sh_ getprop init.svc.lwky_cover)" 'running' 'lwky_cover service'
check_eq "$(sh_ getprop init.svc.lwky_smart_charge)" 'running' 'lwky_smart_charge service'
if sh_ ps -A | grep -q thermal-engine; then ok 'thermal-engine running'; else bad 'thermal-engine not running'; fi
if sh_ mount | grep -q 'thermal-engine_gpu_0.conf'; then ok 'thermal GPU profile bind-mounted'; else info 'thermal GPU profile is stock (balanced/unmounted)'; fi
if sh_ mount | grep -q 'thermal-engine_cpu_0.conf'; then ok 'thermal CPU profile bind-mounted'; else info 'thermal CPU profile is stock (balanced/unmounted)'; fi

echo "== mslg / WPS / CAD"
check_eq "$(sh_ getprop ro.vendor.mslg.rootfs.version)" 'rootfs-26.01.01.tgz' 'ro.vendor.mslg.rootfs.version'
LINK=$(sh_ ls -ld /data/vendor/rootfs 2>/dev/null)
case "$LINK" in *'->'*) ok "/data/vendor/rootfs -> $(echo "$LINK" | sed 's/.*-> //')";; *) bad "/data/vendor/rootfs is not a symlink ($LINK)";; esac
for f in kingsoft.txt zwcad2025.txt; do
  if sh_rc test -f "/data/rootfs/$f"; then ok "/data/rootfs/$f present"; else info "/data/rootfs/$f missing (WPS/CAD may redeploy on first launch)"; fi
done

echo "== modules"
if sh_rc ksud module list; then
  sh_ ksud module list 2>/dev/null | sed 's/^/  INFO /'
else
  info 'ksud module list unavailable'
fi
for id in tb710fu_thermal tb710fu_cpumax tb710fu_setres_noop; do
  if sh_rc test -d "/data/adb/modules/$id"; then ok "module $id installed"; else bad "module $id missing"; fi
done
for id in tb710fu_font100 TB710FUFont100 tb710fu_corner40 TB710FUCorner40 tb710fu_identity TB710FUIdentity; do
  if sh_rc test -d "/data/adb/modules/$id" || sh_rc test -d "/data/adb/modules_update/$id"; then
    info "legacy module $id still installed (package now covers it)"
  else
    ok "legacy module $id removed"
  fi
done

echo "== data / partitions"
sh_ df -h /data | tail -1 | sed 's/^/  INFO /'
ARCH=$(sh_ ls -l /dev/block/by-name/archlinux 2>/dev/null)
if [ -n "$ARCH" ]; then info "Arch partition present: $ARCH"; else info 'no archlinux by-name entry (Arch partition unaffected)'; fi
PD=$(sh_ cat /proc/panel_direction 2>/dev/null || true)
case "$PD" in
  0|1|2|3) ok "panel_direction readable: $PD (SetRes v2.0 follows rotation)" ;;
  *) info "panel_direction not readable ($PD)" ;;
esac
SHARE=$(sh_ grep -E ' /mnt/share ' /proc/mounts 2>/dev/null || true)
if [ -n "$SHARE" ]; then ok "share mounted: $SHARE"; else info 'share not mounted (module optional)'; fi
info "build $(sh_ getprop ro.build.version.incremental)"

echo
echo "== summary: $PASS passed, $WARN info, $FAIL failed"
[ "$FAIL" = 0 ]
