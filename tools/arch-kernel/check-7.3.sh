#!/bin/bash
# check-7.3.sh - verify a TB710FU 7.3 tree and sy7758.ko for the regressions
# found during the 7.3 port.
#
#   ./check-7.3.sh [TREE] [SY7758_KO]
#   TREE        kernel source tree (default: current directory)
#   SY7758_KO   built module (default: TREE/drivers/video/backlight/sy7758.ko)
#
# Exit code 0 = all checks passed.  This script is intentionally self-contained
# and does not modify anything.
set -u

TREE="${1:-.}"
MOD="${2:-$TREE/drivers/video/backlight/sy7758.ko}"
FAIL=0

ok()  { printf 'OK   %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; FAIL=1; }

need() {
    # need FILE PATTERN [DESCRIPTION]
    if [ ! -f "$1" ]; then
        bad "$1: missing file"
        return
    fi
    if grep -qF -- "$2" "$1"; then
        ok "${3:-$1}: $2"
    else
        bad "${3:-$1}: missing '$2'"
    fi
}

DTS="$TREE/arch/arm64/boot/dts/qcom/sm8650-lenovo-tb710fu.dts"
SY="$TREE/drivers/video/backlight/sy7758.c"
CFG="$TREE/.config"

echo "== TB710FU 7.3 tree checks =="
need "$SY" 'devm_gpiod_get_optional' 'sy7758: optional enable GPIO'
need "$SY" 'silergy,follower' 'sy7758: follower property'
need "$SY" 'FIELD_PREP(MSK_CFG5_PS_MODE, 0)' 'sy7758: PS_MODE=0 (do not change)'
need "$DTS" 'silergy,follower' 'DTS: follower node'
need "$DTS" 'enable-gpios = <&tlmm 89 GPIO_ACTIVE_HIGH>' 'DTS: main enable GPIO (v4 DTB)'
need "$DTS" 'pinctrl-0 = <&sy7758_pwr_active>' 'DTS: main pinctrl active'
need "$DTS" 'pinctrl-1 = <&sy7758_pwr_sleep>' 'DTS: main pinctrl sleep'
need "$TREE/drivers/net/wireless/ath/ath12k/core.c" 'tb710fu_board_name' 'ath12k: board_name override'
need "$TREE/drivers/net/wireless/ath/ath12k/mac.c" 'tb710fu_ps_inact' 'ath12k: STA PS pinning'
need "$TREE/net/mac80211/ieee80211_i.h" 'resume_disconnect' 'mac80211: resume_disconnect hook field'
need "$TREE/net/mac80211/util.c" 'local->resume_disconnect(hw)' 'mac80211: invoke resume hook'
need "$TREE/include/net/mac80211.h" 'ieee80211_set_resume_disconnect' 'mac80211: resume hook setter API'
need "$TREE/drivers/net/wireless/ath/ath12k/mac.c" 'ieee80211_resume_disconnect(vif)' 'ath12k: disconnect STA on resume'
need "$TREE/drivers/net/wireless/ath/ath12k/mac.c" 'ieee80211_set_resume_disconnect(hw' 'ath12k: register resume hook'
if awk '/local->resume_disconnect\(hw\)/ { a = NR }
        /ieee80211_reenable_keys\(sdata\)/ { b = NR }
        END { exit !(a && b && a < b) }' "$TREE/net/mac80211/util.c"; then
    ok 'mac80211: resume hook runs before ieee80211_reenable_keys()'
else
    bad 'mac80211: resume hook must run before ieee80211_reenable_keys()'
fi
need "$TREE/drivers/gpu/drm/panel/panel-nt36532-wqhd-dual-dsi-dsc.c" 'nt36532_enable_supplies' 'panel: synchronous supplies enable'
need "$TREE/drivers/gpu/drm/panel/panel-nt36532-wqhd-dual-dsi-dsc.c" 'consumer is NULL (stale panel?)' 'panel: NULL consumer guard'
if grep -q 'regulator_bulk_enable(ARRAY_SIZE(pinfo->supplies)' "$TREE/drivers/gpu/drm/panel/panel-nt36532-wqhd-dual-dsi-dsc.c"; then
    bad 'panel: still uses async regulator_bulk_enable()'
else
    ok 'panel: does not use async regulator_bulk_enable()'
fi
need "$TREE/drivers/regulator/core.c" 'if (!bulk->consumer)' 'regulator: async worker NULL guard'
need "$TREE/drivers/regulator/core.c" 'Failed to enable %s: no consumer' 'regulator: bulk enable NULL check'

if [ -f "$CFG" ]; then
    echo "== kernel config checks =="
    need "$CFG" 'CONFIG_LOCALVERSION="-tb710fu"' 'config: localversion'
    if grep -q '^# CONFIG_MODVERSIONS is not set' "$CFG"; then
        ok 'config: MODVERSIONS off'
    else
        bad 'config: MODVERSIONS must be off for the rebuilt module'
    fi
    if grep -q '^# CONFIG_MODULE_SIG is not set' "$CFG"; then
        ok 'config: MODULE_SIG off'
    else
        bad 'config: MODULE_SIG must be off for the rebuilt module'
    fi
    if grep -q '^CONFIG_BACKLIGHT_SY7758=m' "$CFG"; then
        ok 'config: BACKLIGHT_SY7758=m'
    else
        bad 'config: BACKLIGHT_SY7758 must be m'
    fi
    # 2026-11-08: prevent the v15 config drift from silently dropping these.
    need "$CFG" 'CONFIG_PSI=y' 'config: PSI (oomd/KDE pressure)'
    need "$CFG" 'CONFIG_LRU_GEN=y' 'config: MGLRU'
    need "$CFG" 'CONFIG_LRU_GEN_ENABLED=y' 'config: MGLRU enabled'
    need "$CFG" 'CONFIG_ZRAM_BACKEND_LZ4=y' 'config: zram LZ4 backend'
    need "$CFG" 'CONFIG_ZRAM_BACKEND_ZSTD=y' 'config: zram ZSTD backend'
else
    echo "WARN $CFG not found; skipping config checks"
fi

if [ -f "$MOD" ]; then
    echo "== sy7758.ko checks =="
    VERMAGIC="$(modinfo -F vermagic "$MOD" 2>/dev/null || true)"
    if [ "$VERMAGIC" = "7.3.0-tb710fu SMP preempt mod_unload aarch64" ]; then
        ok "module vermagic: $VERMAGIC"
    else
        bad "module vermagic: '$VERMAGIC' (expected 7.3.0-tb710fu SMP preempt mod_unload aarch64)"
    fi
    DEPS="$(modinfo -F depends "$MOD" 2>/dev/null || true)"
    if [ "$DEPS" = "backlight" ]; then
        ok "module depends: $DEPS"
    else
        bad "module depends: '$DEPS' (expected backlight)"
    fi
    if nm -u "$MOD" 2>/dev/null | grep -q 'devm_gpiod_get_optional'; then
        ok 'module imports devm_gpiod_get_optional'
    else
        bad 'module does not import devm_gpiod_get_optional'
    fi
else
    echo "WARN $MOD not found; skipping module checks"
fi

DTB="$TREE/arch/arm64/boot/dts/qcom/sm8650-lenovo-tb710fu-kshim.dtb"
if command -v dtc >/dev/null 2>&1 && [ -f "$DTB" ]; then
    echo "== compiled DTB checks =="
    if dtc -I dtb -O dts "$DTB" 2>/dev/null | grep -Eq 'enable-gpios = <0x[0-9a-f]+ 0x59 0x00>'; then
        ok 'DTB: main sy7758 enable-gpios'
    else
        bad 'DTB: main sy7758 enable-gpios missing'
    fi
    if dtc -I dtb -O dts "$DTB" 2>/dev/null | grep -q 'silergy,follower'; then
        ok 'DTB: follower node'
    else
        bad 'DTB: follower node missing'
    fi
fi

if [ "$FAIL" -eq 0 ]; then
    echo "== ALL CHECKS PASSED =="
else
    echo "== CHECKS FAILED =="
fi
exit "$FAIL"
