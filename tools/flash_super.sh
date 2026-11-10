#!/bin/bash
# flash_super.sh SUPER_IMG [--wipe]
# Write a HyperOS super image over EDL (tablet in 9008 mode: `adb reboot edl`).
#   --wipe   also zero the head of metadata and userdata (first boot = factory reset;
#            needed when the system/vendor combination changes)
# Optional: VENDOR_BOOT=... VBMETA_IMG=... also write vendor_boot_a / vbmeta_a.
# Env: EDL (bkerler/edl, default "edl"), LOADER (firehose programmer for TB710FU,
#      default work/firehose/prog_firehose_ddr-TB710FU.melf)
# Never touches persist/modemst*/fsg/fsc/devinfo/frp/keystore/ssd/secdata/... .
set -euo pipefail

IMG=${1:?usage: flash_super.sh SUPER_IMG [--wipe]}; WIPE=${2:-}
EDL=${EDL:-edl}; LOADER=${LOADER:-work/firehose/prog_firehose_ddr-TB710FU.melf}
L=(--loader="$LOADER" --memory=ufs)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
step() { echo "$(date +%H:%M:%S) == $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ---- image checks: never let a wrong file reach the super partition -------------
[ -f "$IMG" ] || die "no such image: $IMG"
case "$(uname -s)" in
  Darwin) SIZE=$(stat -f%z "$IMG") ;;
  *)      SIZE=$(stat -c%s "$IMG") ;;
esac
[ $((SIZE % 1048576)) -eq 0 ] || die "image size $SIZE is not a whole number of MiB"
[ "$SIZE" -le 20401094656 ] || die "image ($SIZE B) is larger than the 20,401,094,656 B super partition"
[ "$SIZE" -lt $((10 * 1024 * 1024 * 1024)) ] || die "image ($SIZE B) would reach the 10 GiB Linux root"
python3 - "$IMG" <<'PY' || die "not a liblp super image: $IMG"
import struct, sys
p = sys.argv[1]
with open(p, 'rb') as f:
    f.seek(4096)
    b = f.read(8)
if len(b) < 8 or struct.unpack_from('<I', b, 0)[0] != 0x616C4467:
    sys.exit(1)
PY

# ---- EDL wrapper: treat ERROR/FAIL as failure, require a Wrote line -------------
edl_w() { # partition file
  local part=$1 file=$2 out
  out=$("$EDL" w "$part" "$file" "${L[@]}" 2>&1) || { printf '%s\n' "$out"; return 1; }
  if grep -qiE 'error|fail|cannot|no such|not found' <<<"$out"; then
    printf '%s\n' "$out"; return 1
  fi
  grep -q 'Wrote' <<<"$out" || { printf '%s\n' "$out"; return 1; }
}

step "check connection"
GPT=$("$EDL" printgpt --lun=0 "${L[@]}" 2>&1) || { printf '%s\n' "$GPT"; die "EDL connection failed"; }
grep -qE '^super:' <<<"$GPT" || { printf '%s\n' "$GPT"; die "no super partition in GPT"; }

step "write super $IMG ($(du -h "$IMG" | cut -f1))"
edl_w super "$IMG" || die "writing super failed"

if [ "$WIPE" = --wipe ]; then
  dd if=/dev/zero of="$T/zeros.bin" bs=1048576 count=64 2>/dev/null
  step "wipe metadata"
  edl_w metadata "$T/zeros.bin" || die "wiping metadata failed"
  step "wipe userdata head"
  edl_w userdata "$T/zeros.bin" || die "wiping userdata failed"
fi

if [ -n "${VENDOR_BOOT:-}" ] && [ -n "${VBMETA_IMG:-}" ]; then
  step "write vendor_boot_a + vbmeta_a"
  edl_w vendor_boot_a "$VENDOR_BOOT" || die "writing vendor_boot_a failed"
  edl_w vbmeta_a "$VBMETA_IMG" || die "writing vbmeta_a failed"
fi

step "verify super head (lp metadata)"
# super starts at LUN0 sector 9608 (4 KiB sectors) in the stock TB710FU GPT
"$EDL" rs 9608 256 "$T/head.bin" --lun=0 "${L[@]}" >/dev/null 2>&1 \
  || die "cannot read back super head"
cmp -s "$T/head.bin" <(head -c 1048576 "$IMG") \
  || die "SUPER METADATA MISMATCH - do not reboot; re-check the image/EDL"
echo "SUPER METADATA OK"

step "reset"
# edl's reset subcommand rejects --memory, so pass only the loader here
"$EDL" reset --resetmode=reset --loader="$LOADER" 2>&1 | tail -1 \
  || echo "WARNING: reset failed; reboot manually"
step "DONE"
