#!/bin/bash
# flash_super_arch.sh SUPER_IMG [HOST]
#
# Write a HyperOS super image straight to /dev/disk/by-partlabel/super of a running
# TB710FU Arch install over ssh - no EDL, no cable.  The Linux root lives at offset
# 10 GiB inside the physical super partition, so the image must end before that;
# the 4.0.11 package writes 9.68 GiB and is safe.
#
# The transfer is split into 512 MiB chunks (skip= on the sender, seek= on the
# receiver) so a dropped WiFi link only retries one chunk.  Afterwards the written
# range is read back on the device and hashed against the local file.
#
# usage: flash_super_arch.sh work/build_os4/out/super_fixed_411c.img [root@tb710fu]
# env:   SSH (default "ssh -o BatchMode=yes"), CHUNK_MB (512), SKIP_VERIFY=1
set -euo pipefail

IMG=${1:?usage: flash_super_arch.sh SUPER_IMG [HOST]}
HOST=${2:-root@tb710fu}
SSHC=${SSH:-ssh -o BatchMode=yes -o ConnectTimeout=5}
CHUNK_MB=${CHUNK_MB:-512}
LINUX_ROOT=$((10 * 1024 * 1024 * 1024))          # 10 GiB: kShimC Linux root starts here
DEV=/dev/disk/by-partlabel/super

[ -f "$IMG" ] || { echo "ERROR: no such image: $IMG" >&2; exit 1; }
case "$(uname -s)" in
  Darwin) SIZE=$(stat -f%z "$IMG") ;;
  *)      SIZE=$(stat -c%s "$IMG") ;;
esac
[ $((SIZE % 1048576)) = 0 ] || { echo "ERROR: image size $SIZE is not a whole number of MiB" >&2; exit 1; }
[ "$SIZE" -lt "$LINUX_ROOT" ] || { echo "ERROR: image ($SIZE) would reach the 10 GiB Linux root" >&2; exit 1; }
BLOCKS=$((SIZE / 1048576))                       # 1 MiB units
if command -v sha256sum >/dev/null 2>&1; then
  WANT=$(sha256sum "$IMG" | awk '{print $1}')
else
  WANT=$(shasum -a 256 "$IMG" | awk '{print $1}')
fi

say() { printf '\n== %s\n' "$*"; }

say "check $HOST"
$SSHC "$HOST" "set -e
  test -b $DEV || { echo 'no $DEV'; exit 1; }
  bytes=\$(blockdev --getsize64 $DEV)
  echo \"host      : \$(uname -n)\"
  echo \"model     : \$(tr -d '\\0' < /proc/device-tree/model 2>/dev/null)\"
  echo \"super bytes: \$bytes\"
  [ \$bytes -ge $SIZE ] || { echo 'device super smaller than image'; exit 1; }
  df -h / | tail -1
  findmnt -n -o SOURCE / | head -1"
# identity guard: only this tablet has a 20,401,094,656 B super
SUPERBYTES=$($SSHC "$HOST" "blockdev --getsize64 $DEV")
if [ "$SUPERBYTES" != 20401094656 ]; then
  echo "ERROR: $HOST super is $SUPERBYTES B, expected 20401094656 (TB710FU) - refusing" >&2
  exit 1
fi
NAME=$($SSHC "$HOST" "uname -n")
MODEL=$($SSHC "$HOST" "tr -d '\\0' < /proc/device-tree/model 2>/dev/null")
LOWER=$(printf '%s %s' "$NAME" "$MODEL" | tr '[:upper:]' '[:lower:]')
case "$LOWER" in
  *tb710fu*|*piano*) echo "   identity ok: $NAME / $MODEL" ;;
  *) echo "ERROR: $HOST ($NAME / $MODEL) does not look like the TB710FU tablet - refusing" >&2; exit 1 ;;
esac
# the written range must not overlap whatever backs /
ROOTSRC=$($SSHC "$HOST" "findmnt -n -o SOURCE / | head -1")
case "$ROOTSRC" in
  /dev/loop*|*super*) echo "   root source: $ROOTSRC (inside super, starts at 10 GiB)" ;;
  /dev/sd*|/dev/nvme*|/dev/mmcblk*) echo "   root source: $ROOTSRC (own partition, super untouched)" ;;
  *) echo "ERROR: refusing to write super while / is $ROOTSRC (stop Android first)" >&2; exit 1 ;;
esac

PER=$((CHUNK_MB * 1024 / 1024))                  # blocks per chunk in 1 MiB units
CHUNKS=$(( (BLOCKS + PER - 1) / PER ))
say "write $IMG ($(echo "$BLOCKS" | awk '{printf "%.2f GiB", $1/1024}')) in $CHUNKS chunks of ${CHUNK_MB} MiB"
for ((i = 0; i < CHUNKS; i++)); do
  OFF=$((i * PER))
  CNT=$((BLOCKS - OFF < PER ? BLOCKS - OFF : PER))
  WANTB=$((CNT * 1048576))
  okchunk=0
  for try in 1 2 3; do
    # iflag=fullblock is mandatory: the receiver reads from an ssh pipe, where a
    # short read (32 KiB) otherwise becomes a zero-padded block and dd stops early.
    # dd's exit status cannot be trusted for that case, so the byte count decides.
    OUT=$(dd if="$IMG" bs=1048576 skip="$OFF" count="$CNT" 2>/dev/null \
      | $SSHC "$HOST" "dd of=$DEV bs=1048576 seek=$OFF count=$CNT conv=notrunc,fsync iflag=fullblock 2>&1 | tail -2" 2>&1) || true
    GOTB=$(printf '%s\n' "$OUT" | sed -n 's/^\([0-9][0-9]*\) bytes.*/\1/p' | tail -1)
    if [ "$GOTB" = "$WANTB" ]; then
      echo "   chunk $((i + 1))/$CHUNKS ok ($OFF+$CNT MiB)"
      okchunk=1; break
    fi
    echo "   chunk $((i + 1)) retry $try: wrote ${GOTB:-0} of $WANTB bytes"
    printf '%s\n' "$OUT" | grep -vE '^[0-9]+ bytes' | sed 's/^/      /' | tail -3
  done
  [ "$okchunk" = 1 ] || { echo "ERROR: chunk $((i + 1)) failed three times" >&2; exit 1; }
done

if [ "${SKIP_VERIFY:-}" != 1 ]; then
  say "read back $BLOCKS MiB and compare sha256 (local: ${WANT:0:16}...)"
  GOT=$($SSHC "$HOST" "dd if=$DEV bs=1M count=$BLOCKS 2>/dev/null | sha256sum | cut -d' ' -f1")
  echo "   device: $GOT"
  if [ "$GOT" = "$WANT" ]; then
    echo "SUPER VERIFY OK"
  else
    echo "SUPER VERIFY MISMATCH" >&2
    exit 1
  fi
fi

cat <<EOF

super written and verified.  Reboot and pick HyperOS at the kShimC menu:
  systemctl reboot          (or the tablet power menu)
EOF
