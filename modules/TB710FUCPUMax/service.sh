#!/system/bin/sh
# TB710FUCPUMax v1.2
#
# 频率归属：
#   性能模式：模块把四个 CPU 簇解锁到 cpuinfo_max_freq。
#             只撤销 Scene / 系统写下的上限；thermal-engine 已经生效的热档不覆盖。
#   均衡模式：退出性能模式时只把“仍是硬件最大值”的簇恢复成进入性能模式前的值，
#             之后不再写，交给 Scene 的调度。
#   省电模式：同样只撤销模块写的满频，之后不再写，交给澎湃系统。
#
# 为什么不能完全不管均衡/省电：2026-10-25 实测关闭性能模式后 60 秒，
# Scene 和系统都不会主动把 scaling_max_freq 降回去；必须由模块做一次交接。
#
# 为什么重新打开性能模式会恢复不了：旧版还有 cpuss-0 < 50℃ 的附加门槛。
# 关闭再打开时 CPU 结温可能仍有 60℃+，但后盖/温控区还没到阈值，结果模块
# 一直暂停，直到 CPU 冷却。v1.2 直接去掉 cpuss 门槛：CPU 顶到 95℃ 墙是
# 正常工况，结温保护由内核 TSENS/TJ 和 thermal-engine 负责；模块只根据
# 后盖 back_temp / rear-tof 判断 thermal-engine 是否已经在压频。
#
# 节点权限：policy1/3/5 是 0444，policy0 是 0664；写入时临时 chmod 0644，
# 写完恢复原 mode。

case "$0" in
  */*) MODDIR=${0%/*} ;;
  *)   MODDIR=$(pwd) ;;
esac

STATE=${TB710FU_CPUMAX_STATE:-/data/adb/tb710fu_cpumax}
LOG=$STATE/cpumax.log
TAG=cpumax
POLICIES="0 1 3 5"
ONESHOT=${ONESHOT:-0}
MODE_OVERRIDE=${TB710FU_CPUMAX_MODE:-}
case "$MODE_OVERRIDE" in
  performance|balanced|powersave) ;;
  *) MODE_OVERRIDE="" ;;
esac
# 仅用于 ONESHOT 测试，正常运行时不要设置。
T_BACK=${TB710FU_CPUMAX_TEMP_BACK:-}
T_REAR=${TB710FU_CPUMAX_TEMP_REAR:-}
T_CPUSS=${TB710FU_CPUMAX_TEMP_CPUSS:-}

# thermal-engine_cpu_0.conf（性能/均衡两套的 action_info 相同）里出现过的
# CPU cap。当前值命中这些值时，说明 thermal-engine 正在压频，性能模式不要
# 把它抬回 max。policy3 的 2841600 既是 Scene fast 值又是原厂第一档，单独
# 用 policy_safe 的 back_temp 门槛处理，不放进这个列表。
THERMAL_0="2035200 1920000 1689600 1459200 1017600"
THERMAL_1="2764800 2515200 2246400 1920000 1708800 1286400"
THERMAL_3="2572800 2323200 2035200 1708800 1286400"
THERMAL_5="2880000 2496000 2169600 2112000 1708800 1593600"

mkdir -p "$STATE" 2>/dev/null

tlog() {
  echo "$(date '+%m-%d %H:%M:%S') [$TAG] $*" >> "$LOG" 2>/dev/null
  sz=$(wc -c < "$LOG" 2>/dev/null)
  [ "${sz:-0}" -gt 65536 ] && mv -f "$LOG" "$LOG.1" 2>/dev/null
}

is_on() {
  case "$1" in 1|true|on) return 0 ;; *) return 1 ;; esac
}

zone_of() {
  zt=""
  for z in /sys/class/thermal/thermal_zone*; do
    [ "$(cat "$z/type" 2>/dev/null)" = "$1" ] && { zt=${z##*thermal_zone}; break; }
  done
  echo "$zt"
}

read_zone() {
  [ -n "$1" ] && cat "/sys/class/thermal/thermal_zone$1/temp" 2>/dev/null | tr -d ' \r\n'
}

init_zones() {
  Z_BACK=$(zone_of back_temp)
  Z_REAR=$(zone_of rear-tof-therm)
  Z_CPUSS=$(zone_of cpuss-0)
}

ensure_zones() {
  [ -n "$Z_BACK" ] && [ -n "$Z_REAR" ] && [ -n "$Z_CPUSS" ] || init_zones
}

read_temp() {
  ensure_zones
  case "$1" in
    back)
      if [ -n "$T_BACK" ]; then echo "$T_BACK"; else read_zone "$Z_BACK"; fi
      ;;
    rear)
      if [ -n "$T_REAR" ]; then echo "$T_REAR"; else read_zone "$Z_REAR"; fi
      ;;
    cpuss)
      if [ -n "$T_CPUSS" ]; then echo "$T_CPUSS"; else read_zone "$Z_CPUSS"; fi
      ;;
  esac
}

get_mode() {
  [ -n "$MODE_OVERRIDE" ] && { echo "$MODE_OVERRIDE"; return; }

  perf=$(settings get system POWER_PERFORMANCE_MODE_OPEN 2>/dev/null | tr -d ' \r\n')
  save=$(settings get system POWER_SAVE_MODE_OPEN 2>/dev/null | tr -d ' \r\n')
  extreme=$(settings get system EXTREME_POWER_SAVE_MODE_OPEN 2>/dev/null | tr -d ' \r\n')
  low=$(settings get global low_power 2>/dev/null | tr -d ' \r\n')

  # 省电优先级最高：即使性能开关还留着 1，也交给澎湃。
  if is_on "$save" || is_on "$extreme" || is_on "$low"; then
    echo powersave
    return
  fi
  if is_on "$perf"; then
    echo performance
    return
  fi
  echo balanced
}

cap_node() {
  echo "/sys/devices/system/cpu/cpufreq/policy$1/$2"
}

read_cap() {
  cat "$(cap_node "$1" scaling_max_freq)" 2>/dev/null | tr -d ' \r\n'
}

read_hw() {
  cat "$(cap_node "$1" cpuinfo_max_freq)" 2>/dev/null | tr -d ' \r\n'
}

scene_cap() {
  case "$1" in
    0) echo 1804800 ;;
    1|3) echo 2841600 ;;
    5) echo 2995200 ;;
  esac
}

write_cap() { # $1=policy $2=value_khz
  p=$1
  val=$2
  node=$(cap_node "$p" scaling_max_freq)
  [ -f "$node" ] || return 1
  cur=$(cat "$node" 2>/dev/null | tr -d ' \r\n')
  [ "$cur" = "$val" ] && return 0

  perm=$(stat -c '%a' "$node" 2>/dev/null)
  chmod 0644 "$node" 2>/dev/null || {
    tlog "chmod failed for policy$p"
    return 1
  }
  if echo "$val" > "$node" 2>>"$LOG"; then
    tlog "policy$p $cur -> $val"
    rc=0
  else
    tlog "write failed for policy$p ($cur -> $val)"
    rc=1
  fi
  [ -n "$perm" ] && chmod "$perm" "$node" 2>/dev/null
  return $rc
}

# 进入性能模式前先记录当时的 cap。全部已经是硬件最大值时，说明没有可保留
# 的 Scene/系统基线（例如模块刚升级或刚在性能模式启动），此时用 Scene fast
# 值作为均衡/省电的交接值，避免把满频当成 Scene 的选择。
save_pre_caps() {
  tmp="$STATE/pre_caps.tmp"
  : > "$tmp" 2>/dev/null || return 1
  allmax=1
  for p in $POLICIES; do
    hw=$(read_hw "$p")
    cur=$(read_cap "$p")
    [ -n "$hw" ] && [ -n "$cur" ] || continue
    [ "$cur" != "$hw" ] && allmax=0
  done
  for p in $POLICIES; do
    hw=$(read_hw "$p")
    cur=$(read_cap "$p")
    [ -n "$hw" ] || continue
    if [ "$allmax" = 1 ]; then
      v=$(scene_cap "$p")
    else
      v=$cur
    fi
    [ -n "$v" ] && echo "$p $v" >> "$tmp"
  done
  mv -f "$tmp" "$STATE/pre_caps" 2>/dev/null
  touch "$STATE/active" 2>/dev/null
  tlog "snapshot pre-performance caps (allmax=$allmax)"
}

ensure_snapshot() {
  [ -f "$STATE/pre_caps" ] || save_pre_caps
  touch "$STATE/active" 2>/dev/null
}

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

# 只撤销模块写到硬件最大值的 cap。如果当前值已经被 thermal-engine、Scene
# 或澎湃改成更低的值，说明对方已经接管，保持不动。
handoff() {
  [ -f "$STATE/active" ] || [ -f "$STATE/pre_caps" ] || return 0
  changed=0
  for p in $POLICIES; do
    hw=$(read_hw "$p")
    cur=$(read_cap "$p")
    [ -n "$hw" ] && [ -n "$cur" ] || continue
    [ "$cur" = "$hw" ] || continue
    want=$(snapshot_value "$p")
    [ -n "$want" ] || want=$(scene_cap "$p")
    [ -n "$want" ] || continue
    [ "$cur" = "$want" ] && continue
    write_cap "$p" "$want" && changed=1
  done
  rm -f "$STATE/pre_caps" "$STATE/active"
  if [ "$changed" = 1 ]; then
    tlog "handoff: removed module max caps"
  else
    tlog "handoff: no module max caps left"
  fi
}

# 以下两组温度门槛对应 thermal-engine_cpu_0.conf 的性能曲线：
#   cluster0/1 第一档 37℃、clear 35℃
#   cluster2   第一档 38℃、clear 36℃（Scene 的 2841600 和原厂第一档相同）
#   cluster3   第一档 39℃、clear 34℃
# 后盖 back<33.9℃ 时四簇都已 clear，可以无条件解锁。
# cpuss-0 不作为门槛：CPU 结温顶到 95℃ 墙是正常工况，由内核 TSENS/TJ 保护。
all_clear() {
  b=$(read_temp back)
  r=$(read_temp rear)
  [ -n "$b" ] && [ -n "$r" ] || return 1
  [ "$b" -lt 33900 ] && [ "$r" -lt 52000 ]
}

policy_safe() {
  b=$(read_temp back)
  r=$(read_temp rear)
  [ -n "$b" ] && [ -n "$r" ] || return 1
  [ "$r" -lt 54500 ] || return 1
  case "$1" in
    0|1) [ "$b" -lt 36500 ] ;;
    3)   [ "$b" -lt 35500 ] ;;
    5)   [ "$b" -lt 38500 ] ;;
    *)   return 1 ;;
  esac
}

is_thermal_cap() {
  p=$1
  cur=$2
  case "$p" in
    0) list=$THERMAL_0 ;;
    1) list=$THERMAL_1 ;;
    3) list=$THERMAL_3 ;;
    5) list=$THERMAL_5 ;;
    *) return 1 ;;
  esac
  for v in $list; do
    [ "$v" = "$cur" ] && return 0
  done
  return 1
}

MAX_PENDING=0

set_max() {
  MAX_PENDING=0
  clear_now=0
  all_clear && clear_now=1
  changed=0
  for p in $POLICIES; do
    hw=$(read_hw "$p")
    cur=$(read_cap "$p")
    [ -n "$hw" ] && [ -n "$cur" ] || continue
    [ "$cur" = "$hw" ] && continue

    if [ "$clear_now" != 1 ]; then
      # 命中 thermal-engine 的档位就不要覆盖；等它 clear 后自然恢复。
      if is_thermal_cap "$p" "$cur"; then
        MAX_PENDING=1
        continue
      fi
      if ! policy_safe "$p"; then
        MAX_PENDING=1
        continue
      fi
    fi

    write_cap "$p" "$hw" && changed=1
  done
  if [ "$changed" = 1 ]; then
    tlog "performance: raised to hw max"
  fi
}

run_watcher() {
  init_zones

  if [ "$ONESHOT" = "1" ]; then
    mode=$(get_mode)
    tlog "oneshot mode=$mode zones back=$Z_BACK rear=$Z_REAR cpuss=$Z_CPUSS"
    case "$mode" in
      performance) ensure_snapshot; set_max ;;
      *) handoff ;;
    esac
    return 0
  fi

  i=0
  while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 120 ]; do
    sleep 2
    i=$((i+1))
  done
  sleep 15

  init_zones
  # 开机/手动重启后先丢掉上一轮的交接状态；如果当前是性能模式，会在下面
  # 重新快照。
  rm -f "$STATE/pre_caps" "$STATE/active"
  mode=$(get_mode)
  tlog "start mode=$mode zones back=$Z_BACK rear=$Z_REAR cpuss=$Z_CPUSS"
  last_mode=""
  pending_logged=0

  while :; do
    if [ ! -f "$MODDIR/module.prop" ] || [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]; then
      handoff
      exit 0
    fi

    mode=$(get_mode)
    if [ "$mode" != "$last_mode" ]; then
      tlog "mode ${last_mode:-init} -> $mode"
      # 退出性能模式：只撤销模块自己的满频，然后不再写。
      [ "$mode" != performance ] && handoff
      last_mode=$mode
    fi

    case "$mode" in
      performance)
        ensure_snapshot
        set_max
        if [ "$MAX_PENDING" = "1" ]; then
          if [ "$pending_logged" != "1" ]; then
            tlog "perf waiting: back=$(read_temp back) rear=$(read_temp rear) cpuss=$(read_temp cpuss)"
            pending_logged=1
          fi
        else
          pending_logged=0
        fi
        ;;
      balanced|powersave)
        # 交接已经在模式切换时完成；这里刻意什么都不写。
        pending_logged=0
        ;;
    esac
    sleep 2
  done
}

if [ "$ONESHOT" = "1" ]; then
  run_watcher
  exit 0
fi

if [ "${TB710FU_WATCHER_DAEMON:-}" = 1 ]; then
  run_watcher
  exit 0
fi

# ksud reaps the service.sh process group after it exits; detach into a new
# session so the watcher survives (same trick as TB710FUSetRes).
if [ -x /data/adb/ksu/bin/busybox ]; then
  TB710FU_WATCHER_DAEMON=1 /data/adb/ksu/bin/busybox setsid sh "$MODDIR/service.sh"     >/dev/null 2>&1 </dev/null &
else
  TB710FU_WATCHER_DAEMON=1 setsid sh "$MODDIR/service.sh" >/dev/null 2>&1 </dev/null &
fi
exit 0
