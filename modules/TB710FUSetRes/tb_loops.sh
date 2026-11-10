#!/system/bin/sh
# TB710FU 常驻循环（v2.0）— 由 service.sh 以 setsid 启动。
# ksud 会在 service.sh 退出后收割它留下的后台子进程：v1.7 写在 service.sh 里的
# 三个 ( ... ) & 循环全部被杀（存档线程从未写过 lasttime，触摸桥只剩首轮同步
# 执行）。本脚本是独立会话，不进 service.sh 的进程组，收割管不到这里。
LOG=/data/local/tmp/tb710fu_loops.log
TB_TIME=/mnt/vendor/persist/tb710fu/lasttime
echo "$(date +%F_%T) loops-start pid=$$" >> "$LOG"

# ---- panel_direction follows the display rotation (v2.0) --------------------
# OS4's nt36532_ts.ko indexes panel_direction by rotation/90:
#   0=Vertical 0°, 1=Right Up 90°, 2=Vertical reverse 180°, 3=Left Up 270°.
# Xiaomi WMS publishes the current rotation in degrees through sys.tp.grip_enable
# (DisplayRotationStubImpl.writeRotationChangeToProperties).  The system package's
# init rc still writes 3 (the OS3-derived value); on OS4 that is 270° even in the
# normal 90° landscape, which rotates the firmware's edge/palm model 180° and
# makes the Type-C-side back gesture unreliable.  Follow the real rotation instead
# of hard-coding 3; only write on change to avoid extra SPI commands.
TB_PANELDIR_LAST=""
tb_paneldir_follow() {
  g=$(getprop sys.tp.grip_enable 2>/dev/null)
  case "$g" in
    0|90|180|270) pd=$((g / 90)) ;;
    *) pd=1 ;;  # framework has not published the rotation yet; boot in landscape
  esac
  [ "$pd" = "$TB_PANELDIR_LAST" ] && return 0
  if echo "$pd" > /proc/panel_direction 2>/dev/null; then
    TB_PANELDIR_LAST=$pd
    echo "$(date +%F_%T) panel_direction=$pd (grip=$g)" >> "$LOG"
  fi
}

# ---- OS3 lwky switches (OS4 is missing the SystemUI PropObserver) -----------
# init.lwky.rc only reacts to persist.sys.gesture_wakeup=2/0 and
# persist.sys.high_touch_sampling_rate.enable=1/0; "true" is not a valid value.
lwky_bridge_once() {
  g=$(settings get system gesture_wakeup_option 2>/dev/null)
  case "$g" in
    2|1|true) want=2; node=1 ;;
    0|false)  want=0; node=0 ;;
    *) want=""; node="" ;;
  esac
  if [ -n "$want" ]; then
    [ "$(getprop persist.sys.gesture_wakeup)" = "$want" ] || setprop persist.sys.gesture_wakeup "$want"
    [ "$(cat /proc/gesture_control 2>/dev/null | tr -dc '0-9')" = "$node" ] || echo "$node" > /proc/gesture_control
  fi
  case "$(getprop persist.sys.high_touch_sampling_rate.enable)" in
    1) # game_mode 2 = vendor "game mode / remove palm reject" (0x79/0x04).
       # 4 (0x79/0x03) is lwky's high-sampling guess but keeps palm rejection
       # and makes the right-edge back gesture hard to start.
       [ "$(cat /proc/game_mode 2>/dev/null)" = "2" ] || echo 2 > /proc/game_mode
       # game_edge is the vendor HAL's 0..3 corner/edge inhibition level; 4 is
       # out of range and blocks back gestures near the charging port.
       [ "$(cat /proc/game_edge 2>/dev/null)" = "0" ] || echo 0 > /proc/game_edge ;;
    0) [ "$(cat /proc/game_mode 2>/dev/null)" = "5" ] || echo 5 > /proc/game_mode
       [ "$(cat /proc/game_edge 2>/dev/null)" = "0" ] || echo 0 > /proc/game_edge ;;
  esac
  # init.lwky.rc only reacts to property *changes*; at boot the stylus switch is
  # already 1, so its one-shot trigger never fires and the vendor pen scanner
  # stays off.  Keep the node in sync with the persisted switch.
  case "$(getprop persist.sys.stylus.enable)" in
    1) [ "$(cat /proc/support_pen 2>/dev/null | tr -dc '0-9')" = "1" ] || echo 1 > /proc/support_pen ;;
    0) [ "$(cat /proc/support_pen 2>/dev/null | tr -dc '0-9')" = "0" ] || echo 0 > /proc/support_pen ;;
  esac
}
lwky_bridge_once
( while :; do lwky_bridge_once; sleep 5; done ) &
# panel_direction must react quickly to rotation (1 s), while the lwky bridge
# only needs the slower 5 s cadence.
( while :; do tb_paneldir_follow; sleep 1; done ) &
# -----------------------------------------------------------------------------

( while :; do
    v=$(settings get secure security_pc_secure_protect_mode_key 2>/dev/null)
    case "$v" in 0|1|2) setprop persist.sys.pc_mode "$v" ;; *) setprop persist.sys.pc_mode 0 ;; esac
    sleep 15
  done ) &

# ---- tb710fu fake-hwclock 存档（v1.9：两行 = epoch + RTC 原始计数）------------
# 只存档、不恢复；恢复在 service.sh 最前面（必须早于系统读时间）。RTC raw 用来在下次
# 开机按"raw 增量"补上关机/Arch 会话期间的时间。
( while :; do
    tb_n=$(date +%s 2>/dev/null)
    tb_r=$(cat /sys/class/rtc/rtc0/since_epoch 2>/dev/null)
    case "$tb_n" in ''|*[!0-9]*) tb_n='' ;; esac
    if [ -n "$tb_n" ]; then
      { echo "$tb_n"; echo "$tb_r"; } > "$TB_TIME.tmp" 2>/dev/null && mv -f "$TB_TIME.tmp" "$TB_TIME" 2>/dev/null \
        || echo "$(date +%F_%T) save-fail" >> "$LOG"
    fi
    sleep 180
  done ) &
# -----------------------------------------------------------------------------
echo "$(date +%F_%T) loops-ready" >> "$LOG"
wait
