#!/bin/bash
# Build and sign the two NCM RRO overlays used by build_os4.py.
#
# The overlays correct:
#   * Tethering: usb0 tethering resources
#   * Connectivity: EthernetTracker's default regex so it does not grab usb0
#
# They are static RROs on /product/overlay.  system-partition APKs are scanned
# with skipVerify, so a self-signed key is enough for this use.  Do not use this
# key for anything else.
#
# usage: tools/build_overlays.sh
# env:   TB_OVERLAY_OUT, TB_OVERLAY_KEYSTORE, TB_OVERLAY_STOREPASS
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${TB_OVERLAY_OUT:-$ROOT/work/overlay}
KS=${TB_OVERLAY_KEYSTORE:-$OUT/tb710fu-overlay.jks}
PASS=${TB_OVERLAY_STOREPASS:-tb710fu}
ALIAS=tb710fu

command -v apktool >/dev/null || { echo "apktool not found" >&2; exit 1; }
command -v keytool >/dev/null || { echo "keytool not found (install a JDK)" >&2; exit 1; }
command -v jarsigner >/dev/null || { echo "jarsigner not found (install a JDK)" >&2; exit 1; }
mkdir -p "$OUT"

if [ ! -f "$KS" ]; then
  echo "generating local test keystore: $KS"
  keytool -genkeypair -keystore "$KS" -storepass "$PASS" -keypass "$PASS" \
    -alias "$ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=TB710FU Overlay Test, OU=local, O=local, C=CN" >/dev/null
fi

build_one() { # $1=src dir name, $2=output apk name
  src=$ROOT/assets/overlay-src/$1
  un=$OUT/$2.unsigned.apk
  dst=$OUT/$2
  [ -d "$src" ] || { echo "missing $src" >&2; exit 1; }
  echo "== $1 -> $2"
  apktool b "$src" -o "$un" >/dev/null
  jarsigner -keystore "$KS" -storepass "$PASS" -keypass "$PASS" \
    -digestalg SHA-256 -sigalg SHA256withRSA \
    -signedjar "$dst" "$un" "$ALIAS" >/dev/null
  jarsigner -verify -keystore "$KS" -storepass "$PASS" "$dst" >/dev/null
  rm -f "$un"
  ls -l "$dst"
}

build_one src_tether TB710FUTetheringOverlay.apk
build_one src_eth    TB710FUConnectivityOverlay.apk

cat <<EOF

Done. Copy these into your build tree if they are not already there:
  $OUT/TB710FUTetheringOverlay.apk
  $OUT/TB710FUConnectivityOverlay.apk
EOF
