#!/bin/bash
# Build the six runtime KSU module zips from runtime-modules/<name>/.
#
# usage: modules/build_modules.sh [OUT_DIR]
# env:   TB_MODULES_OUT
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-${TB_MODULES_OUT:-$ROOT/work/ksu-modules}}
mkdir -p "$OUT"

for name in TB710FUSetRes TB710FUThermal TB710FUCPUMax TB710FUDebloat TB710FUDPWidebusOff TB710FUShareMount; do
  src=$ROOT/modules/$name
  [ -d "$src" ] || { echo "missing $src" >&2; exit 1; }
  find "$src" -name '*.sh' -type f -exec chmod 0755 {} +
  rm -f "$OUT/$name.zip"
  ( cd "$src" && zip -rX "$OUT/$name.zip" . \
      -x '*.DS_Store' -x '*/__pycache__/*' -x '*.md' >/dev/null )
  echo "built $OUT/$name.zip"
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$OUT/$name.zip"; else shasum -a 256 "$OUT/$name.zip"; fi
done

cat <<EOF

Install on the tablet:
  adb push "$OUT/TB710FUSetRes.zip" /data/local/tmp/
  adb shell "ksud module install /data/local/tmp/TB710FUSetRes.zip"
  # same for TB710FUThermal.zip / TB710FUCPUMax.zip / TB710FUDebloat.zip
  #          TB710FUDPWidebusOff.zip / TB710FUShareMount.zip
  # reboot once
EOF
