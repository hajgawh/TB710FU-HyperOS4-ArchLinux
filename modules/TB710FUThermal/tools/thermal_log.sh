#!/system/bin/sh
# Calibration logger. Run manually while gaming, then pull the CSV:
#   adb shell "sh /data/adb/modules/tb710fu_thermal/tools/thermal_log.sh 900"
#   adb pull /data/adb/tb710fu_thermal/calibration.csv
#
# The first argument is the run time in seconds (0 or omitted = until Ctrl-C).

STATE=${TB710FU_THERMAL_STATE:-/data/adb/tb710fu_thermal}
OUT=$STATE/calibration.csv
DUR=${1:-0}
mkdir -p "$STATE" 2>/dev/null

zone_of() {
  zt=""
  for z in /sys/class/thermal/thermal_zone*; do
    [ "$(cat "$z/type" 2>/dev/null)" = "$1" ] && { zt=${z##*thermal_zone}; break; }
  done
  echo "$zt"
}

read_zone() {
  [ -n "$1" ] && cat "/sys/class/thermal/thermal_zone$1/temp" 2>/dev/null | tr -d '\r\n'
}

cpu_val() { # $1=policy $2=max|cur
  cat "/sys/devices/system/cpu/cpufreq/policy$1/scaling_$2_freq" 2>/dev/null | tr -d '\r\n'
}

Z_BACK=$(zone_of back_temp)
Z_UBACK=$(zone_of user_back_temp)
Z_UFRONT=$(zone_of user_front_temp)
Z_FRONT=$(zone_of front_temp)
Z_SKIN=$(zone_of skin-msm-therm)
Z_REAR=$(zone_of rear-tof-therm)
Z_CPUSS=$(zone_of cpuss-0)
Z_GPUSS=$(zone_of gpuss-0)

echo "time,back_temp,user_back_temp,user_front_temp,front_temp,skin,rear_tof,cpuss0,gpuss0,gpuclk,max_pwrlevel,max_freq,c0_max,c1_max,c2_max,c3_max,c0_cur,c1_cur,c2_cur,c3_cur,power_mode" > "$OUT"
echo "sensors: back=$Z_BACK uback=$Z_UBACK ufront=$Z_UFRONT front=$Z_FRONT skin=$Z_SKIN rear=$Z_REAR cpuss0=$Z_CPUSS gpuss0=$Z_GPUSS"
echo "writing $OUT"

START=$(date +%s)
while :; do
  NOW=$(date +%s)
  MODE=$(settings get system POWER_PERFORMANCE_MODE_OPEN 2>/dev/null | tr -d ' \r\n')
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$(date '+%H:%M:%S')" \
    "$(read_zone "$Z_BACK")" \
    "$(read_zone "$Z_UBACK")" \
    "$(read_zone "$Z_UFRONT")" \
    "$(read_zone "$Z_FRONT")" \
    "$(read_zone "$Z_SKIN")" \
    "$(read_zone "$Z_REAR")" \
    "$(read_zone "$Z_CPUSS")" \
    "$(read_zone "$Z_GPUSS")" \
    "$(cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null | tr -d '\r\n')" \
    "$(cat /sys/class/kgsl/kgsl-3d0/max_pwrlevel 2>/dev/null | tr -d '\r\n')" \
    "$(cat /sys/class/kgsl/kgsl-3d0/devfreq/max_freq 2>/dev/null | tr -d '\r\n')" \
    "$(cpu_val 0 max)" "$(cpu_val 1 max)" "$(cpu_val 3 max)" "$(cpu_val 5 max)" \
    "$(cpu_val 0 cur)" "$(cpu_val 1 cur)" "$(cpu_val 3 cur)" "$(cpu_val 5 cur)" \
    "$MODE" >> "$OUT"

  [ "$DUR" -gt 0 ] && [ $((NOW - START)) -ge "$DUR" ] && break
  sleep 2
done

echo "done: $(wc -l < "$OUT") lines"
