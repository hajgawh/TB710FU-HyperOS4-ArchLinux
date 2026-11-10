#!/bin/bash
# Build a data-preserving TB710FU HyperOS 4 package (system/system_ext/product
# + super) from the extracted yupei OTA and the frozen OS3 port partitions.
#
# This is the "port script": it does not flash.  It builds, assembles the super,
# re-hashes everything, and runs verify_package.sh.  Flash with tools/flash_super.sh
# (no --wipe) once the device is in EDL.
#
# usage:
#   tools/port_build.sh
#   TB_OS4_DIR=$PWD/work/hyperos4_411 TB_SUPER_NAME=super_fixed.img tools/port_build.sh
#
# env:
#   TB_WORK         work directory                 (default <repo>/work)
#   TB_OS4_DIR      extracted OS4 base            (default $TB_WORK/hyperos4_411)
#   TB_PARTS        partitions to rebuild         (default "system system_ext product")
#   TB_SUPER_NAME   output super name             (default super_fixed.img)
#   TB_SUPER_SIZE   physical super size           (default 0x4c0000000)
#   TB_CORNER_PADDING  40 (default) or 10 for the old piano value
#   TB_SKIP_STAGE / TB_KEEP_STAGE / TB_KEEP_BASE  passed through to build_os4.py
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${TB_WORK:-$ROOT/work}
OS4=${TB_OS4_DIR:-$WORK/hyperos4_411}
PARTS=${TB_PARTS:-"system system_ext product"}
SUPER_NAME=${TB_SUPER_NAME:-super_fixed.img}
SUPER_SIZE=${TB_SUPER_SIZE:-0x4c0000000}
OUT=$WORK/build_os4/out
B=$WORK/build_os4

say() { printf '\n== %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

say "inputs"
[ -d "$OS4/x_system" ] && [ -d "$OS4/x_system_ext" ] && [ -d "$OS4/x_product" ] && [ -d "$OS4/x_mi_ext" ] \
  || die "missing extracted trees under $OS4 (x_system/x_system_ext/x_product/x_mi_ext)"
[ -f "$WORK/patches/miui-services-tb710fu-411.jar" ] \
  || die "missing $WORK/patches/miui-services-tb710fu-411.jar"
# 411d camera assets: Aperture (bring your own) + the SpecialTypesProvider stub
# (buildable from hyperos/camera/src).
for f in hyperos/camera/Aperture.apk hyperos/camera/CameraParallelServiceStub.apk; do
  [ -s "$ROOT/$f" ] || die "missing $f (Aperture: bring your own; stub: hyperos/camera/src/build.sh; see hyperos/camera/README.md)"
done
for p in system vendor odm vendor_dlkm system_dlkm; do
  [ -f "$WORK/port/${p}_a.img" ] || die "missing $WORK/port/${p}_a.img"
done
for p in $PARTS; do
  case "$p" in system|system_ext|product) ;;
    *) die "TB_PARTS may only contain system/system_ext/product (got $p)";;
  esac
done
command -v mkfs.erofs >/dev/null || die "mkfs.erofs not found (brew install erofs-utils)"
command -v dump.erofs >/dev/null || die "dump.erofs not found"
command -v fsck.erofs >/dev/null || die "fsck.erofs not found"
mkdir -p "$OUT" "$B"

say "rollback snapshot"
ROLLBACK=$B/rollback_prev
mkdir -p "$ROLLBACK"
n=0
for p in system system_ext product; do
  if [ -f "$OUT/$p.img" ]; then cp -p "$OUT/$p.img" "$ROLLBACK/"; n=$((n+1)); fi
done
[ "$n" = 0 ] && echo "   no previous images (first build)" || echo "   previous parts -> $ROLLBACK"

say "build ${PARTS}"
TB_WORK="$WORK" TB_OS4_DIR="$OS4" python3 "$ROOT/tools/build_os4.py" $PARTS

say "assemble super"
# TB_PARTS selects which images to REBUILD. The super must always carry all three
# of system/system_ext/product: a logical partition left out of the LP metadata
# makes first-stage init fail and Android never boots.
ARGS=()
for p in system system_ext product; do
  [ -f "$OUT/$p.img" ] || die "missing $OUT/$p.img (part '$p' was not rebuilt and has no previous image)"
  case " $PARTS " in *" $p "*) ;; *) echo "   reusing previous $p.img";; esac
  ARGS+=("$p=$OUT/$p.img")
done
ARGS+=("vendor=$WORK/port/vendor_a.img")
ARGS+=("odm=$WORK/port/odm_a.img")
ARGS+=("vendor_dlkm=$WORK/port/vendor_dlkm_a.img")
ARGS+=("system_dlkm=$WORK/port/system_dlkm_a.img")
python3 "$ROOT/tools/make_super.py" "$OUT/$SUPER_NAME" "$SUPER_SIZE" "${ARGS[@]}"

say "hashes"
( cd "$OUT" && { command -v sha256sum >/dev/null 2>&1 && sha256sum "$SUPER_NAME" || shasum -a 256 "$SUPER_NAME"; } > "$SUPER_NAME.sha256" )
( cd "$OUT" && { command -v sha256sum >/dev/null 2>&1 && sha256sum system.img system_ext.img product.img || shasum -a 256 system.img system_ext.img product.img; } > partitions.sha256 )
cat "$OUT/$SUPER_NAME.sha256"
cat "$OUT/partitions.sha256"

say "verify"
TB_WORK="$WORK" TB_OS4_DIR="$OS4" TB_SUPER_NAME="$SUPER_NAME" \
  bash "$ROOT/tools/verify_package.sh" "$OUT" "$OS4"

cat <<EOF

Package is built and verified.  Nothing was flashed.

  super : $OUT/$SUPER_NAME
  parts : $OUT/{system,system_ext,product}.img
  flash : EDL=tools/venv/bin/edl \\
          LOADER=work/firehose/prog_firehose_ddr-TB710FU.melf \\
          bash tools/flash_super.sh $OUT/$SUPER_NAME        # NO --wipe

Rollback: the previous parts were copied to $B/rollback_prev/ before this build;
recreate that super with tools/make_super.py using the same command.
EOF
