#!/system/bin/sh
# TB710FU: write widebus=N as early as possible. No HPD/altmode manipulation.
for m in $(mount | sed -n 's/.* on \(.*\) type debugfs.*/\1/p'); do
    if [ -e "$m/drm_dp/widebus_mode" ]; then
        echo N > "$m/drm_dp/widebus_mode" 2>/dev/null
        exit 0
    fi
done
mount -t debugfs none /sys/kernel/debug 2>/dev/null
[ -e /sys/kernel/debug/drm_dp/widebus_mode ] && echo N > /sys/kernel/debug/drm_dp/widebus_mode 2>/dev/null
