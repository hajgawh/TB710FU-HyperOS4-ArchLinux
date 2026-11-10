#!/system/bin/sh
# TB710FU boot services (runs as root)

# ---- tb710fu fake-hwclock: 断网开机时间修复（v1.9）---------------------------
# Android 内核读不到 Arch 侧写进 SDAM 的 RTC 偏移（6.1 GKI 无 offset 接线），离线开机
# 只能靠存档。v1.7 只存"上次时间"，在 Arch 里待一整天再回安卓就会恢复成整天前的时间。
# v1.9 存档改成两行 (epoch, RTC 原始计数)：RTC 计数器跨系统/跨关机一直在走，所以
# 开机时间 = 存档 epoch + (现在 raw - 存档 raw)；raw 回退（PMIC 复位）时退回旧逻辑。
TB_TIME=/mnt/vendor/persist/tb710fu/lasttime
mkdir -p "$(dirname "$TB_TIME")" 2>/dev/null
tb_now=$(date +%s 2>/dev/null)
tb_epoch=$(sed -n 1p "$TB_TIME" 2>/dev/null)
tb_raw=$(sed -n 2p "$TB_TIME" 2>/dev/null)
tb_rtc=$(cat /sys/class/rtc/rtc0/since_epoch 2>/dev/null)
case "$tb_epoch" in ''|*[!0-9]*) tb_epoch='' ;; esac
case "$tb_raw" in ''|*[!0-9]*) tb_raw='' ;; esac
case "$tb_rtc" in ''|*[!0-9]*) tb_rtc='' ;; esac
tb_target=''
# ① RTC 增量法（可跨 Arch 会话、跨断电）
if [ -n "$tb_epoch" ] && [ -n "$tb_raw" ] && [ -n "$tb_rtc" ] && [ "$tb_rtc" -ge "$tb_raw" ] 2>/dev/null; then
  tb_target=$((tb_epoch + tb_rtc - tb_raw))
fi
# ② 旧格式/时钟倒退兜底：存档本身比当前系统时间新就直接用存档
if [ -n "$tb_epoch" ] && [ "$tb_epoch" -gt "$tb_now" ] 2>/dev/null; then
  if [ -z "$tb_target" ] || [ "$tb_target" -lt "$tb_epoch" ]; then tb_target=$tb_epoch; fi
fi
if [ -n "$tb_target" ] && [ "$tb_target" -gt "$tb_now" ] 2>/dev/null; then
  BB=/data/adb/ksu/bin/busybox
  if [ -x "$BB" ]; then
    TZ=UTC "$BB" date -s "@$tb_target" >/dev/null 2>&1 || TZ=UTC date -s "@$tb_target" >/dev/null 2>&1
  else
    tb_v=$(awk -v s="$tb_target" 'BEGIN{
      d=int(s/86400); r=s-d*86400; z=d+719468
      e=int(z/146097); f=z-e*146097
      y=int((f-int(f/1460)*4+int(f/36524)-int(f/146096))/365)
      yy=y+e*400; dd=f-(365*y+int(y/4)-int(y/100))
      mp=int((5*dd+2)/153); d2=dd-int((153*mp+2)/5)+1
      m=mp+3; if (m>12) {m-=12; yy+=1}
      printf "%02d%02d%02d%02d%04d.%02d", m, d2, int(r/3600), int((r%3600)/60), yy, r%60}')
    [ -n "$tb_v" ] && TZ=UTC date "$tb_v" >/dev/null 2>&1
  fi
fi
# -----------------------------------------------------------------------------

# 开机标记：service.sh 是否真的执行过（与 tb_loops.log 一起验收）
echo "$(date +%F_%T) service.sh-start" >> /data/local/tmp/tb710fu_boot.log
sleep 10
cmd window size reset   # undo OS3 set_res 3198 wedge
# purge OS3 wmhp window rules (wrong for 434-density; re-created by wmhp.sh each boot)
for f in autoui2_list autoui_list embedded_rules_list fixed_orientation_list; do
  chattr -i /data/system/cloudFeature_$f.xml 2>/dev/null
  rm -f /data/system/cloudFeature_$f.xml
done

# ---- PC apps (mslg: WPS / CAD) compatibility --------------------------------
# The OS4 launchers (5.0.5) expect /data/vendor/rootfs and a rootfs dated
# >= 26.01.01, but the frozen OS3 ODM stack serves /data/rootfs (25.09.04).
# Bridge the paths, satisfy the version gate, deploy the guest app images that
# ship inside the launcher APKs, and keep Welcome from deleting the rootfs
# (it wipes /data/rootfs when version.txt exists -> top level is mode 0555).
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 60 ]; do sleep 2; i=$((i+1)); done
sleep 5

# ---- Settings rows -----------------------------------------------------------
# The system package's /system/etc/tb710fu_bootfix.sh already writes
# font_scale=1.0 / device_font_scale=1.0 / ui_mode_scale=1 and deletes the
# legacy 1.5x back-gesture keys (framework default 1.0).  Do not duplicate
# them here.
# Refresh rate and dynamic island are intentionally untouched everywhere.

RE=/data/rootfs
KSUD=/data/adb/ksu/bin/ksud
RESETPROP=/data/adb/ksu/bin/resetprop
chmod 0777 "$RE" 2>/dev/null
mkdir -p "$RE/usr" "$RE/proc" "$RE/sys" "$RE/boot" "$RE/srv"
if [ ! -L /data/vendor/rootfs ]; then
  # Keep an OS3-era real directory instead of deleting it; rename once, then link.
  if [ -e /data/vendor/rootfs ]; then
    if ! mv /data/vendor/rootfs "/data/vendor/rootfs.old-$(date +%s)" 2>/dev/null; then
      echo "$(date +%F_%T) cannot move /data/vendor/rootfs; leaving it untouched" >> /data/local/tmp/tb710fu_boot.log
      exit 1
    fi
  fi
  ln -sfn "$RE" /data/vendor/rootfs
fi
"$RESETPROP" ro.vendor.mslg.rootfs.version rootfs-26.01.01.tgz
"$KSUD" sepolicy patch "allow mslg_app vendor_data_file dir search" >/dev/null 2>&1
"$KSUD" sepolicy patch "allow mslg_app vendor_data_file lnk_file read" >/dev/null 2>&1

deploy_img() { # $1=apk $2=asset $3=dest $4=marker $5=marker_text $6=md5file $7=md5
  if [ ! -f "$3" ]; then
    if ! /system/bin/unzip -p "$1" "$2" > "$3.tmp"; then
      rm -f "$3.tmp"
      echo "$(date +%F_%T) deploy_img: unzip failed: $1/$2" >> /data/local/tmp/tb710fu_boot.log
      return 1
    fi
    if ! mv -f "$3.tmp" "$3"; then
      rm -f "$3.tmp"
      echo "$(date +%F_%T) deploy_img: mv failed: $3" >> /data/local/tmp/tb710fu_boot.log
      return 1
    fi
  fi
  [ -f "$4" ] || printf "%s" "$5" > "$4" || return 1
  [ -f "$6" ] || printf "%s" "$7" > "$6" || return 1
}
deploy_img /product/data-app/WpsLauncher/WpsLauncher.apk assets/wps/mslgkingsoftimg \
  "$RE/mslgkingsoftimg" "$RE/kingsoft.txt" \
  "wps-office_12.1.2.22554.professional.preload.sw_arm64.deb" \
  "$RE/kingsoft_md5.txt" "10880bcf67dd2688273f7e8728a3624e"
deploy_img /product/data-app/CadLauncher/CadLauncher.apk assets/cad/mslgzwcad2025img \
  "$RE/mslgzwcad2025img" "$RE/zwcad2025.txt" \
  "zwcad2025_2026-09-02-2.deb" \
  "$RE/zwcad2025_md5.txt" "ae7a894e6e99d78dc00f3a23b5ec4517"
chmod 0666 "$RE"/kingsoft.txt "$RE"/kingsoft_md5.txt "$RE"/zwcad2025.txt "$RE"/zwcad2025_md5.txt 2>/dev/null
chmod 0555 "$RE"

# ---- 常驻循环交给脱离进程组的 tb_loops.sh（v1.8）------------------------------
# v1.7 的三个循环写在 service.sh 里用 ( ... ) & 启动，ksud 在 service.sh 退出后
# 把整个进程组收割掉（存档线程从未写过 lasttime，触摸桥只剩首轮同步执行生效）。
# setsid 另起会话启动独立脚本，收割管不到那里。
MODDIR=${0%/*}
echo "$(date +%F_%T) service.sh-loops-launch" >> /data/local/tmp/tb710fu_boot.log
if [ -x /data/adb/ksu/bin/busybox ]; then
  /data/adb/ksu/bin/busybox setsid sh "$MODDIR/tb_loops.sh" >/dev/null 2>&1 </dev/null &
else
  setsid sh "$MODDIR/tb_loops.sh" >/dev/null 2>&1 </dev/null &
fi
sleep 2
echo "$(date +%F_%T) service.sh-exit" >> /data/local/tmp/tb710fu_boot.log
exit 0
