#!/system/bin/sh
# TB710FU: keep vendor DP widebus off for the Redmi A27U.
# No HPD cycles here: hpd debugfs writes can leave the WCD939x USBSS switch
# in USB mode while the DP driver still believes it is in DP mode.

LOG=/data/local/tmp/tb-dp-widebus.log
STATUS=/sys/class/drm/card0-DP-1/status

log() { echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"; }

find_dp_dbg() {
    for m in $(mount | sed -n 's/.* on \(.*\) type debugfs.*/\1/p'); do
        if [ -e "$m/drm_dp/widebus_mode" ]; then
            echo "$m/drm_dp"
            return 0
        fi
    done
    f=$(find /dev /sys/kernel/debug -maxdepth 4 -name widebus_mode 2>/dev/null | head -1)
    [ -n "$f" ] && dirname "$f"
}

D=""
i=0
while [ $i -lt 90 ]; do
    D=$(find_dp_dbg)
    [ -n "$D" ] && break
    sleep 2
    i=$((i + 1))
done
if [ -z "$D" ]; then
    log "drm_dp debugfs not found, giving up"
    exit 0
fi

echo N > "$D/widebus_mode" 2>/dev/null
log "boot: widebus=$(cat "$D/widebus_mode" 2>/dev/null) at $D"
prev=$(cat "$STATUS" 2>/dev/null)

while true; do
    [ -e "$D/widebus_mode" ] || D=$(find_dp_dbg)
    if [ -n "$D" ]; then
        cur=$(cat "$STATUS" 2>/dev/null)
        if [ "$cur" = "connected" ] && [ "$cur" != "$prev" ]; then
            echo N > "$D/widebus_mode" 2>/dev/null
            log "connected: widebus=$(cat "$D/widebus_mode" 2>/dev/null)"
        fi
        prev="$cur"
    fi
    sleep 3
done
