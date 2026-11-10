#!/bin/bash
# Install the three runtime modules and retire the package-covered modules.
#
# Run after the new super is flashed and the device has booted with USB/Wi-Fi
# debugging.  It does not reboot; reboot once afterwards so removals and the
# current service.sh take effect.
#
# usage: tools/post_flash_modules.sh [ADB_SERIAL]
# env:   ADB_SERIAL
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SERIAL=${1:-${ADB_SERIAL:-}}
if [ -z "$SERIAL" ]; then
  echo "usage: $0 ADB_SERIAL (or set ADB_SERIAL)" >&2
  adb devices -l >&2
  exit 2
fi
A=(adb -s "$SERIAL")
MOD=$ROOT/work/ksu-modules
TMP=/data/local/tmp

echo "== root check"
ID=$("${A[@]}" shell id 2>/dev/null | tr -d '\r')
case "$ID" in
  uid=0*) echo "  OK   $ID" ;;
  *) echo "  ERROR: adb shell is not root ($ID). Enable KernelSU's ADB Root first." >&2; exit 1 ;;
esac

echo "== push module zips"
for z in TB710FUSetRes.zip TB710FUThermal.zip TB710FUCPUMax.zip; do
  [ -s "$MOD/$z" ] || { echo "  ERROR: missing $MOD/$z (run modules/build_modules.sh)" >&2; exit 1; }
  "${A[@]}" push "$MOD/$z" "$TMP/$z" >/dev/null
  echo "  pushed $z"
done

echo "== retire package-covered modules"
# Directory names and module ids do not always match (the old identity module
# shipped as TB710FUIdentity with id tb710fu_identity).  Try the id, then the
# directory name, then remove the directory directly.
for name in tb710fu_font100 TB710FUFont100 tb710fu_corner40 TB710FUCorner40 tb710fu_identity TB710FUIdentity; do
  present=0
  "${A[@]}" shell "test -d /data/adb/modules/$name -o -d /data/adb/modules_update/$name" >/dev/null 2>&1 && present=1
  if [ "$present" = 1 ]; then
    "${A[@]}" shell "ksud module uninstall $name" >/dev/null 2>&1 || true
    "${A[@]}" shell "rm -rf /data/adb/modules/$name /data/adb/modules_update/$name" >/dev/null 2>&1 || true
    if "${A[@]}" shell "test -d /data/adb/modules/$name -o -d /data/adb/modules_update/$name" >/dev/null 2>&1; then
      echo "  ERROR: $name is still present after uninstall/rm" >&2
      exit 1
    fi
    echo "  removed: $name"
  else
    echo "  already absent: $name"
  fi
done

echo "== install/update runtime modules"
for pair in TB710FUSetRes.zip:tb710fu_setres_noop TB710FUThermal.zip:tb710fu_thermal TB710FUCPUMax.zip:tb710fu_cpumax; do
  z=${pair%%:*}; id=${pair##*:}
  "${A[@]}" shell "ksud module install $TMP/$z" >/dev/null
  "${A[@]}" shell "ksud module list" | tr -d '\r' | grep -q "$id" \
    || { echo "  ERROR: $z installed but $id is not in ksud module list" >&2; exit 1; }
  echo "  installed $z ($id)"
done

echo "== current modules"
"${A[@]}" shell 'ksud module list' | tr -d '\r' | sed 's/^/  /'

cat <<'EOF'

Done. Reboot once so the retired modules disappear and TB710FUSetRes v2.0
service.sh starts.  After reboot:

  tools/verify_device.sh <serial>
EOF
