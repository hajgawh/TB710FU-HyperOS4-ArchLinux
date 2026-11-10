#!/bin/bash
# Verify a built TB710FU HyperOS 4 package without mounting it.
#
# Checks the three EROFS images, the super layout/manifest, and the package-level
# fixes that used to live in KSU modules (font 100%, 40px corner, stock refresh/
# island, lwky assets, colour jar, VoiceAssist whitelist, face unlock, props).
#
# usage: verify_package.sh [OUT_DIR] [OS4_DIR]
# env:   TB_WORK, TB_OS4_DIR, TB_SUPER_NAME
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${TB_WORK:-$ROOT/work}
OUT=${1:-$WORK/build_os4/out}
OS4=${2:-${TB_OS4_DIR:-$WORK/hyperos4_411}}
SUPER=${TB_SUPER_NAME:-super_fixed.img}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok()  { printf '  OK   %s\n' "$*"; PASS=$((PASS+1)); }
bad() { printf '  FAIL %s\n' "$*"; FAIL=$((FAIL+1)); }

need_file() { # img path label
  local out
  if out=$(dump.erofs --path="$2" "$1" 2>&1) && grep -q '^Path :' <<<"$out"; then
    ok "$3"
  else
    bad "$3 (missing $2 or cannot inspect $1)"
  fi
}
no_file() { # img path label
  local out
  if ! out=$(dump.erofs --path="$2" "$1" 2>&1); then
    bad "$3 (cannot inspect $1)"
  elif grep -q '^Path :' <<<"$out"; then
    bad "$3 (unexpected $2)"
  else
    ok "$3"
  fi
}
cat_file() { # img path dest
  dump.erofs --path="$2" --cat "$1" > "$3" 2>/dev/null || { : > "$3"; return 1; }
}
sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}
size() {
  case "$(uname -s)" in
    Darwin) stat -f%z "$1" ;;
    *)      stat -c%s "$1" ;;
  esac
}

SYS=$OUT/system.img
SEXT=$OUT/system_ext.img
PROD=$OUT/product.img
SUPERIMG=$OUT/$SUPER

echo "== files"
for f in "$SYS" "$SEXT" "$PROD" "$SUPERIMG"; do
  if [ -f "$f" ]; then ok "$(basename "$f") $(size "$f") bytes"; else bad "missing $f"; fi
done
[ "$FAIL" = 0 ] || { echo; echo "cannot continue without images"; exit 1; }

echo "== EROFS integrity"
for img in "$SYS" "$SEXT" "$PROD"; do
  if fsck.erofs -d0 "$img" >/dev/null 2>&1; then ok "$(basename "$img") fsck"; else bad "$(basename "$img") fsck"; fi
done

echo "== system: bootfix (package-level defaults)"
cat_file "$SYS" /system/etc/tb710fu_bootfix.sh "$TMP/bootfix.sh"
for pat in 'font_scale 1.0' 'device_font_scale 1.0' 'ui_mode_scale 1'; do
  if grep -q "$pat" "$TMP/bootfix.sh"; then ok "bootfix has '$pat'"; else bad "bootfix missing '$pat'"; fi
done
for key in back_gesture_inset_scale_left back_gesture_inset_scale_right; do
  if grep -Eq "settings[[:space:]]+put[[:space:]]+secure[[:space:]]+$key" "$TMP/bootfix.sh"; then
    bad "bootfix writes $key (must stay stock 1.0)"
  else
    ok "bootfix leaves $key at stock default"
  fi
  if grep -q "settings delete secure $key" "$TMP/bootfix.sh"; then
    ok "bootfix clears old $key"
  else
    bad "bootfix missing delete for $key"
  fi
done
for pat in 'peak_refresh_rate' 'miui_refresh_rate' 'user_refresh_rate' 'dynamic_island'; do
  if grep -Eq "settings[[:space:]]+(put|delete)[^#]*$pat|setprop[^#]*$pat" "$TMP/bootfix.sh"; then
    bad "bootfix writes '$pat' (must stay stock)"
  else
    ok "bootfix leaves '$pat' alone"
  fi
done
cat_file "$SYS" /system/etc/init/tb710fu_bootfix.rc "$TMP/bootfix.rc"
grep -q 'sys.boot_completed=1' "$TMP/bootfix.rc" && grep -q 'u:r:shell:s0' "$TMP/bootfix.rc" \
  && ok 'bootfix.rc runs on boot_completed as shell' || bad 'bootfix.rc trigger/seclabel'
cat_file "$SYS" /system/etc/init/tb710fu_paneldir.rc "$TMP/paneldir.rc"
grep -q 'write /proc/panel_direction 3' "$TMP/paneldir.rc" \
  && ok 'paneldir.rc writes 3 (legacy boot default; SetRes v2.0 follows rotation)' || bad 'paneldir.rc missing write'

echo "== system: lwky assets"
need_file "$SYS" /system/lwky/lwky_cover 'lwky_cover present'
need_file "$SYS" /system/lwky/lwky_smart_charge_hyper 'lwky_smart_charge_hyper present'
no_file   "$SYS" /system/lwky/wmhp.sh 'wmhp.sh dropped'
no_file   "$SYS" /system/lwky/set_res.sh 'set_res.sh dropped'
need_file "$SYS" /system/etc/init/init.lwky.rc 'init.lwky.rc present'
cat_file  "$SYS" /system/etc/init/init.lwky.rc "$TMP/init.lwky.rc"
grep -q 'lwky_wmhp' "$TMP/init.lwky.rc" && bad 'init.lwky.rc still has lwky_wmhp' || ok 'init.lwky.rc has no lwky_wmhp'
grep -q 'set_resolution' "$TMP/init.lwky.rc" && bad 'init.lwky.rc still has set_resolution' || ok 'init.lwky.rc has no set_resolution'
grep -q 'write /proc/game_edge 4' "$TMP/init.lwky.rc" \
  && bad 'init.lwky.rc writes out-of-range game_edge 4' || ok 'init.lwky.rc avoids game_edge 4'
grep -q 'write /proc/game_edge 0' "$TMP/init.lwky.rc" \
  && ok 'init.lwky.rc keeps edge anti-mistouch off (0)' || bad 'init.lwky.rc missing game_edge 0'
grep -q 'write /proc/game_mode 4' "$TMP/init.lwky.rc" \
  && bad 'init.lwky.rc still uses palm-reject game_mode 4' || ok 'init.lwky.rc avoids game_mode 4'
grep -q 'write /proc/game_mode 2' "$TMP/init.lwky.rc" \
  && ok 'init.lwky.rc uses game_mode 2 (remove palm reject)' || bad 'init.lwky.rc missing game_mode 2'
need_file "$SYS" /system/usr/keylayout/Vendor_17ef_Product_617f.kl 'Lenovo pen keylayout'
need_file "$SYS" /system/app/Joyose/Joyose.apk 'Joyose moved into system'
need_file "$SYS" /system/etc/init/init.lwky.rc 'init.lwky.rc present'

echo "== product: build.prop"
cat_file "$PROD" /etc/build.prop "$TMP/product-build.prop"
check_prop() { # key=value label
  if grep -qxF "$1" "$TMP/product-build.prop"; then ok "build.prop $1"; else bad "build.prop missing $1"; fi
}
check_prop 'ro.sf.lcd_density=440'
check_prop 'ro.product.marketname=联想小新平板Pro GT'
check_prop 'ro.product.odm.marketname=联想小新平板Pro GT'
check_prop 'ro.vendor.mslg.rootfs.version=rootfs-26.01.01.tgz'
check_prop 'persist.sys.gesture_wakeup=2'
check_prop 'persist.sys.device_case_enabled=1'
check_prop 'persist.sys.high_touch_sampling_rate.enable=1'
check_prop 'persist.sys.stylus.enable=1'
check_prop 'persist.sys.pc_mode=0'
grep -q '^ro.build.version.incremental=.*\.DEV$' "$TMP/product-build.prop" \
  && ok 'build.prop .DEV incremental' || bad 'build.prop .DEV incremental'
grep -q '^ro.product.mod_device=piano$' "$TMP/product-build.prop" \
  && ok 'build.prop mod_device=piano' || bad 'build.prop mod_device=piano'

echo "== product: device features"
cat_file "$PROD" /etc/device_features/piano.xml "$TMP/piano.xml"
python3 - "$TMP/piano.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
path = sys.argv[1]
try:
    root = ET.parse(path).getroot()
except Exception as e:
    print('  FAIL piano.xml parse: %s' % e); raise SystemExit(1)
bad = 0
def boolval(name):
    e = root.find(".//bool[@name='%s']" % name)
    return None if e is None else (e.text or '').strip()
def intval(name):
    e = root.find(".//integer[@name='%s']" % name)
    return None if e is None else (e.text or '').strip()
def strval(name):
    e = root.find(".//string[@name='%s']" % name)
    return None if e is None else (e.text or '').strip()
if boolval('support_tee_face_unlock') == 'false': print('  OK   piano.xml tee_face=false')
else: print('  FAIL piano.xml tee_face'); bad += 1
if strval('support_mi_keyboard') == 'piano': print('  OK   piano.xml support_mi_keyboard=piano')
else: print('  FAIL piano.xml support_mi_keyboard'); bad += 1
if intval('support_max_fps') == '144': print('  OK   piano.xml support_max_fps=144 (stock)')
else: print('  FAIL piano.xml support_max_fps'); bad += 1
arr = root.find(".//integer-array[@name='fpsList']")
vals = [(e.text or '').strip() for e in arr.findall('item')] if arr is not None else []
if vals == ['120', '90', '60']: print('  OK   piano.xml fpsList=120/90/60 (stock)')
else: print('  FAIL piano.xml fpsList=%s (must be stock)' % vals); bad += 1
dom = root.find(".//string-array[@name='support_face_unlock_region_dom']")
items = [e.text.strip() for e in dom.findall('item')] if dom is not None else []
if 'ALL' in items: print('  OK   piano.xml face region includes ALL')
else: print('  FAIL piano.xml face region %s' % items); bad += 1
raise SystemExit(1 if bad else 0)
PY
[ $? = 0 ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

echo "== product: APK payloads"
cat_file "$PROD" /overlay/DevicesOverlay.apk "$TMP/DevicesOverlay.apk"
OVL_WANT=${TB_DEVICES_OVERLAY_SHA256:-128f7e970c21fe8a469adf149cb387b08f61e94621abdf66d33bdb164dfe5342}
OVL_GOT=$(sha "$TMP/DevicesOverlay.apk")
if [ "$OVL_GOT" = "$OVL_WANT" ]; then
  ok "DevicesOverlay matches the expected 40px stock APK (${OVL_WANT:0:8}...)"
else
  bad "DevicesOverlay hash ${OVL_GOT:0:8}... != ${OVL_WANT:0:8}... (set TB_DEVICES_OVERLAY_SHA256 if you changed it)"
fi
need_file "$PROD" /app/PearlBiometric/PearlBiometric.apk 'PearlBiometric present'
need_file "$PROD" /priv-app/VoiceAssistAndroidT/VoiceAssistAndroidT.apk 'VoiceAssist present'
need_file "$PROD" /overlay/TB710FUTetheringOverlay.apk 'tethering overlay present'
need_file "$PROD" /overlay/TB710FUConnectivityOverlay.apk 'connectivity overlay present'
no_file   "$PROD" /pangu 'pangu tree moved out of product'
cat_file "$PROD" /etc/displayconfig/display_id_4630946395913993603.xml "$TMP/display.xml"
grep -q '<transitionPoint>0.4509</transitionPoint>' "$TMP/display.xml" \
  && grep -q '<minimumLux>10000</minimumLux>' "$TMP/display.xml" \
  && ok 'displayconfig: normal max 0.4509 + HBM at 10000 lux' \
  || bad 'displayconfig brightness/HBM values'
cat_file "$PROD" /app/Aperture/Aperture.apk "$TMP/Aperture.apk"
cat_file "$PROD" /app/CameraParallelServiceStub/CameraParallelServiceStub.apk "$TMP/stub.apk"
if [ -s "$TMP/Aperture.apk" ] && [ -s "$TMP/stub.apk" ]; then
  want=$(sha "$ROOT/hyperos/camera/Aperture.apk")
  got=$(sha "$TMP/Aperture.apk")
  [ "$want" = "$got" ] && ok 'Aperture + SpecialTypesProvider stub present' \
    || bad "Aperture APK hash mismatch ($got != $want)"
else
  bad 'Aperture.apk or CameraParallelServiceStub.apk missing'
fi
no_file   "$PROD" /priv-app/MiuiCamera 'MiuiCamera removed (needs Xiaomi campostproc)'
cat_file "$PROD" /etc/default-permissions/aperture.xml "$TMP/aperture.xml"
grep -q 'org.lineageos.aperture.dev' "$TMP/aperture.xml" 2>/dev/null \
  && ok 'Aperture default-permissions pre-grant present' \
  || bad 'Aperture default-permissions missing'
cat_file "$PROD" /priv-app/VoiceAssistAndroidT/VoiceAssistAndroidT.apk "$TMP/VoiceAssist.apk"
if unzip -p "$TMP/VoiceAssist.apk" assets/voiceassist.ai.voice.trigger.config 2>/dev/null | grep -q '"piano"'; then
  ok 'VoiceAssist whitelist includes piano'
else
  bad 'VoiceAssist whitelist missing piano'
fi

echo "== system_ext: colour jar"
cat_file "$SEXT" /framework/miui-services.jar "$TMP/miui-services.jar"
JAR_WANT=${TB_MIUI_SERVICES_SHA256:-0b41ff1824167a1164270daa13886057e1d67f4650d9f1b51c5ffc7c03c1646a}
JAR_GOT=$(sha "$TMP/miui-services.jar")
if [ "$JAR_GOT" = "$JAR_WANT" ]; then
  ok "miui-services.jar matches the expected colour patch (${JAR_WANT:0:8}...)"
else
  bad "miui-services.jar hash ${JAR_GOT:0:8}... != ${JAR_WANT:0:8}... (set TB_MIUI_SERVICES_SHA256 if you rebuilt it)"
fi
if dump.erofs --path=/framework/oat --ls "$SEXT" 2>/dev/null | grep -q 'miui-services'; then
  bad 'stale miui-services oat/vdex/art still present'
else
  ok 'no stale miui-services oat/vdex/art'
fi

echo "== super"
if [ -f "$SUPERIMG.manifest.json" ]; then
  if python3 "$ROOT/tools/check_super.py" "$SUPERIMG" "$SUPERIMG.manifest.json"; then
    ok 'super partitions match manifest and stay under 10 GiB'
  else
    bad 'super manifest verification'
  fi
  # The manifest is derived from the image, so it cannot notice a partition that
  # make_super.py was never told to pack (narrowed TB_PARTS -> system_ext dropped
  # -> Android cannot boot). Assert the full expected set explicitly.
  missing=$(python3 - "$SUPERIMG.manifest.json" <<'PY'
import json, sys
parts = set(json.load(open(sys.argv[1]))["parts"])
need = {"system_a", "system_ext_a", "product_a", "vendor_a", "odm_a",
        "vendor_dlkm_a", "system_dlkm_a"}
print(",".join(sorted(need - parts)))
PY
)
  [ -z "$missing" ] && ok 'super packs all 7 logical partitions' \
    || bad "super is missing logical partition(s): $missing"
else
  bad "missing $SUPERIMG.manifest.json"
fi

echo
echo "== summary: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
