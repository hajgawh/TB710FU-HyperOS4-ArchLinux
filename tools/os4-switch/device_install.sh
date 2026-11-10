#!/system/bin/sh
# 设备端安装器（root）：把主机 push 到 /data/local/tmp 的文件落到正式位置。
# 由主机的 install_switch2arch.sh 调用，不手动运行。
set -e
S=/data/local/tmp/tb_install_stage
D=/data/adb/tbboot
M=/data/adb/modules/tb710fu_switch
PART=/dev/block/by-name/boot_a

[ -f "$S/pair.env" ] || { echo "缺 $S/pair.env" >&2; exit 1; }
[ -f "$S/boot_linux.img" ] || { echo "缺 $S/boot_linux.img" >&2; exit 1; }
FREE=$(df -k /data | awk 'NR==2 {print $4}')
[ "${FREE:-0}" -ge 204800 ] || { echo "ERROR: /data 剩余 ${FREE:-0} KiB，至少需要 200 MiB" >&2; exit 1; }

mkdir -p "$D/backup" "$M"
chmod 700 "$D/backup" 2>/dev/null || true

cp "$S/boot_linux.img"        "$D/boot_linux.img"
cp "$S/boot_linux.img.sha256" "$D/boot_linux.img.sha256"
cp "$S/switch2arch.sh"        "$D/switch2arch.sh"
cp "$S/pair.env"              "$D/pair.env"
cp "$S/module.prop"           "$M/module.prop"
cp "$S/action.sh"             "$M/action.sh"
chmod 755 "$D/switch2arch.sh" "$M/action.sh"
chmod 600 "$D/boot_linux.img" "$D/pair.env"
chmod 644 "$D/boot_linux.img.sha256" "$M/module.prop"
chown root:root "$D"/* "$M"/* 2>/dev/null || true
WANT=$(awk -F= '/^HASH_LINUX=/{print $2}' "$D/pair.env")
GOT=$(sha256sum "$D/boot_linux.img" | awk '{print $1}')
[ -n "$WANT" ] && [ "$WANT" = "$GOT" ] \
  || { echo "ERROR: boot_linux.img sha256 $GOT != pair.env $WANT" >&2; exit 1; }
SIDE=$(cat "$D/boot_linux.img.sha256" 2>/dev/null | awk '{print $1}')
[ "$SIDE" = "$GOT" ] || { echo "ERROR: sidecar sha256 $SIDE != $GOT" >&2; exit 1; }
rm -rf "$S" /data/local/tmp/tb_install.sh

echo "== 安装完成"
ls -l "$D" "$M"
echo "== boot_linux.img sha256"
sha256sum "$D/boot_linux.img"
echo "sidecar: $(cat "$D/boot_linux.img.sha256")"
echo "== 当前 boot_a"
sha256sum "$PART"
