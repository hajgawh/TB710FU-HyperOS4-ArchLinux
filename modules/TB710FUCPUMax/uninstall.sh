#!/system/bin/sh
# 卸载时只撤销模块写到硬件最大值的 cap；已经被 thermal-engine、Scene 或
# 澎湃改低的值保持不动。找不到进入性能模式前的快照时，用 Scene fast 值兜底。
STATE=${TB710FU_CPUMAX_STATE:-/data/adb/tb710fu_cpumax}
LOG=$STATE/cpumax.log

snapshot_value() {
  p=$1
  [ -f "$STATE/pre_caps" ] || return 1
  while read -r sp sv; do
    if [ "$sp" = "$p" ]; then
      echo "$sv"
      return 0
    fi
  done < "$STATE/pre_caps"
  return 1
}

scene_cap() {
  case "$1" in
    0) echo 1804800 ;;
    1|3) echo 2841600 ;;
    5) echo 2995200 ;;
  esac
}

for p in 0 1 3 5; do
  node=/sys/devices/system/cpu/cpufreq/policy$p
  [ -f "$node/scaling_max_freq" ] || continue
  hw=$(cat "$node/cpuinfo_max_freq" 2>/dev/null | tr -d ' \r\n')
  cur=$(cat "$node/scaling_max_freq" 2>/dev/null | tr -d ' \r\n')
  [ -n "$hw" ] && [ -n "$cur" ] || continue
  [ "$cur" = "$hw" ] || continue

  want=$(snapshot_value "$p")
  [ -n "$want" ] || want=$(scene_cap "$p")
  [ -n "$want" ] || continue

  mode=$(stat -c '%a' "$node/scaling_max_freq" 2>/dev/null)
  chmod 0644 "$node/scaling_max_freq" 2>/dev/null || continue
  echo "$want" > "$node/scaling_max_freq" 2>/dev/null
  [ -n "$mode" ] && chmod "$mode" "$node/scaling_max_freq" 2>/dev/null
done

echo "$(date '+%m-%d %H:%M:%S') [cpumax] uninstalled; removed module max caps" >> "$LOG" 2>/dev/null
rm -rf "$STATE"
exit 0
