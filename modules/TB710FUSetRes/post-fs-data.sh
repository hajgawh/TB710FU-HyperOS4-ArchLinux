#!/system/bin/sh
# TB710FU v2.0: make the OS4 pad landscape allowlist cover Settings/browser.
#
# HyperOS 4 pads run packages that are not in
# /product/etc/landscape_fullscreen_list.xml in a centered portrait letterbox
# (mBounds=781..2420 on the 3200x2000 landscape display).  The launcher's edge
# gesture stub then sits over the black bar rather than the app, and the back
# gesture loses its MOVE stream when the finger enters the app (offset_x=0,
# should_invoke_back=false).  Bind the module's list (original + Settings +
# browser) before system_server reads it.
#
# /product is mounted before post-fs-data; system_server starts later, so this
# bind mount is visible when MiuiLandscapeFullscreenController loads the file.
MODDIR=${0%/*}
SRC="$MODDIR/landscape_fullscreen_list.xml"
TMP=/data/local/tmp/tb710fu_landscape_list.xml
DST=/product/etc/landscape_fullscreen_list.xml
LOG=/data/local/tmp/tb710fu_landscape.log

[ -f "$SRC" ] || { echo "$(date +%F_%T) no source list" >> "$LOG"; exit 0; }
[ -f "$DST" ] || { echo "$(date +%F_%T) no product list" >> "$LOG"; exit 0; }

mkdir -p /data/local/tmp 2>/dev/null
cp -f "$SRC" "$TMP" 2>/dev/null || { echo "$(date +%F_%T) copy failed" >> "$LOG"; exit 0; }
chmod 0644 "$TMP" 2>/dev/null
# /data/local/tmp is the path verified by hand with system_server: the bind mount
# exposes the source inode/label, and system_server can read it.
mount --bind "$TMP" "$DST" 2>>"$LOG"
if grep -q 'com.android.settings' "$DST" 2>/dev/null; then
  echo "$(date +%F_%T) landscape list bind ok" >> "$LOG"
else
  echo "$(date +%F_%T) landscape list bind FAILED" >> "$LOG"
fi
exit 0
