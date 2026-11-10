#!/bin/sh
# kshim_variants.sh NAME IMAGE DTB
# Pack the two kShimC boot images for boot_a: menu default HyperOS and menu default Linux.
#   -> $OUT/NAME_{android,linux}/boot.img and $OUT/current/boot_{android,linux}.img
# Each one is checked against your own vbmeta_a (AVB chain) before it is copied to current/.
#
# Inputs (environment, all files from YOUR device):
#   STOCK_BOOT   v3 Android-only boot image                     (default work/v3/boot.img)
#   VBMETA       v3 vbmeta image                                (default work/v3/vbmeta.img)
#   SHIM         kShimC binary built from kshim/                 (default work/kshim/kShimC.bin)
#   OUT          output directory                                (default work/boot)
#   LINUX_NAME   menu entry for the Linux kernel                 (default "Arch Linux")
set -e
cd "$(dirname "$0")/.."
N=${1:?usage: kshim_variants.sh NAME IMAGE DTB}; IMG=${2:?}; DTB=${3:?}
STOCK_BOOT=${STOCK_BOOT:-work/v3/boot.img}; VBMETA=${VBMETA:-work/v3/vbmeta.img}
SHIM=${SHIM:-work/kshim/kShimC.bin}; OUT=${OUT:-work/boot}; PY=${PYTHON:-python3}
[ -f "$STOCK_BOOT" ] || { echo "ERROR: no v3 base boot: $STOCK_BOOT (set STOCK_BOOT=work/v3/boot.img)" >&2; exit 1; }
[ -f "$VBMETA" ] || { echo "ERROR: no vbmeta: $VBMETA (set VBMETA=work/v3/vbmeta.img)" >&2; exit 1; }
sha16() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -c1-16; else shasum -a 256 "$1" | cut -c1-16; fi; }
V=$(mktemp -d); trap 'rm -rf "$V"' EXIT; cp "$VBMETA" "$V/vbmeta.img"
mkdir -p "$OUT/current"
for d in android linux; do
  ok=0
  for t in 1 2 3; do   # the DBKP packer fails now and then (exit 234); retry
    if $PY tools/kshim_pack_boot.py --boot "$STOCK_BOOT" --shim "$SHIM" \
        --out "$OUT/${N}_$d" --probe-slots --timeout-ms 8000 --linux "$IMG" --dtb "$DTB" \
        --linux-name "${LINUX_NAME:-Arch Linux}" --default $d > "$V/pack.log" 2>&1; then ok=1; break; fi
    sleep 3
  done
  [ $ok = 1 ] || { cat "$V/pack.log"; exit 1; }
  cp "$OUT/${N}_$d/boot.img" "$V/boot.img"
  $PY tools/avb/avbtool.py info_image --image "$V/vbmeta.img" >/dev/null 2>&1 \
     || { echo "AVB: cannot parse $VBMETA"; exit 1; }
  $PY tools/avb/avbtool.py verify_image --image "$V/boot.img" \
     --key tools/avb/testkey_rsa4096.pem > "$V/avb.log" 2>&1 \
     || { cat "$V/avb.log"; echo "AVB verify failed ($d)"; exit 1; }
  grep -q "^boot: Successfully verified" "$V/avb.log" \
     || { cat "$V/avb.log"; echo "AVB verify failed ($d)"; exit 1; }
  cp "$OUT/${N}_$d/boot.img" "$OUT/current/boot_$d.img"
  echo "$d: $(sha16 "$OUT/current/boot_$d.img") (avb ok)"
done
