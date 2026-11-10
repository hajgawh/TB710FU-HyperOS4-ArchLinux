#!/bin/bash
# install-userspace.sh — 把 TB710FU 的 Arch 用户态修复安装到目标系统。
#
# 用法：
#   sudo ./install-userspace.sh                 # 装到当前系统 /
#   sudo ROOT=/mnt/root ./install-userspace.sh  # 装进已挂载的 rootfs
#   sudo USER_NAME=archlinux ./install-userspace.sh
#
# 设计原则：
#   - 只覆盖本目录列出的文件；同名旧文件先备份为 .before-<时间戳>
#   - 不删除 UCM 文件，只改名 .disabled（可回退）
#   - 不自动重启任何服务；最后打印需要手动做的步骤
#   - 实验性单元（tb-phy58 / tb-dp-mode-keep / tb-dp-bootgate / tb-usb-*）不启用
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${ROOT:-/}
USER_NAME=${USER_NAME:-archlinux}
USER_HOME=${USER_HOME:-$ROOT/home/$USER_NAME}
STAMP=$(date +%Y%m%d-%H%M%S)
S=$ROOT/etc/systemd/system
U=$ROOT/etc/systemd/user
SBIN=$ROOT/usr/local/sbin
BIN=$ROOT/usr/local/bin

say() { printf '%s\n' "$*"; }

install_file() { # src dst mode
	local src=$1 dst=$2 mode=${3:-644}
	mkdir -p "$(dirname "$dst")"
	if [ -e "$dst" ] && ! cmp -s "$src" "$dst"; then
		cp -a "$dst" "$dst.before-$STAMP"
	fi
	install -m "$mode" "$src" "$dst"
}

install_user_file() { # src dst mode; keep the home directory's owner
	local src=$1 dst=$2 mode=${3:-644}
	install_file "$src" "$dst" "$mode"
	if [ -e "$USER_HOME" ]; then
		chown --reference="$USER_HOME" "$dst" 2>/dev/null || true
	fi
}

say "== audio"
install_file "$HERE/audio/56-tb710fu-audio.conf"            "$ROOT/etc/wireplumber/wireplumber.conf.d/56-tb710fu-audio.conf"
install_file "$HERE/audio/tb-audio-init"                   "$SBIN/tb-audio-init" 755
install_file "$HERE/audio/tb-audio-init.service"           "$S/tb-audio-init.service"
install_file "$HERE/audio/tb-audio-watch"                  "$BIN/tb-audio-watch" 755
install_file "$HERE/audio/tb-audio-watch.service"          "$S/tb-audio-watch.service"
install_file "$HERE/audio/tb-dp-audio"                     "$SBIN/tb-dp-audio" 755
install_file "$HERE/audio/tb-dp-audio.service"             "$S/tb-dp-audio.service"
install_file "$HERE/audio/71-tb-dp-audio.rules"            "$ROOT/etc/udev/rules.d/71-tb-dp-audio.rules"
install_file "$HERE/audio/tb-dp-sink-ensure"               "$BIN/tb-dp-sink-ensure" 755

for f in 58-tb710fu-dp.conf 59-tb710fu-noautolink.conf 61-tb-alsa-buffer.conf 99-tb-no-ucm.conf; do
	install_file "$HERE/audio/$f" "$USER_HOME/.config/wireplumber/wireplumber.conf.d/$f"
done
install_file "$HERE/audio/tb-dp-sink-ensure.service" \
	"$USER_HOME/.config/systemd/user/tb-dp-sink-ensure.service"
if [ -f "$HERE/audio/tb-speaker-keepalive.service.orig" ] && [ ! -e "$USER_HOME/.config/systemd/user/tb-speaker-keepalive.service.orig" ]; then
	install_file "$HERE/audio/tb-speaker-keepalive.service.orig" \
		"$USER_HOME/.config/systemd/user/tb-speaker-keepalive.service.orig"
fi

say "== power"
install_file "$HERE/power/10-tb710fu-powerkey.conf" "$ROOT/etc/systemd/logind.conf.d/10-tb710fu-powerkey.conf"
install_file "$HERE/power/tb710fu-s2idle.conf"      "$ROOT/etc/systemd/sleep.conf.d/tb710fu-s2idle.conf"
install_file "$HERE/power/50-tb-s2idle.conf"        "$ROOT/etc/tmpfiles.d/50-tb-s2idle.conf"
install_file "$HERE/power/tb-charge-limit"          "$SBIN/tb-charge-limit" 755
install_file "$HERE/power/tb-charge-limit.service"  "$S/tb-charge-limit.service"
install_file "$HERE/power/charge-limit.conf"        "$ROOT/etc/tb710fu/charge-limit.conf"
install_file "$HERE/power/tb-charge-limit"          "$ROOT/usr/lib/systemd/system-sleep/tb-charge-limit" 755
[ -f "$HERE/power/tb-hwclock-sync.service" ] && install_file "$HERE/power/tb-hwclock-sync.service" "$S/tb-hwclock-sync.service"
[ -f "$HERE/power/tb-hwclock-sync.timer" ]   && install_file "$HERE/power/tb-hwclock-sync.timer"   "$S/tb-hwclock-sync.timer"
[ -f "$HERE/power/tb-dp-wake-fix" ]          && install_file "$HERE/power/tb-dp-wake-fix"          "$BIN/tb-dp-wake-fix" 755

say "== thermal"
install_file "$HERE/thermal/tb-thermal-guard"         "$SBIN/tb-thermal-guard" 755
install_file "$HERE/thermal/tb-thermal-guard.service" "$S/tb-thermal-guard.service"
install_file "$HERE/thermal/thermal-guard.conf"       "$ROOT/etc/tb710fu/thermal-guard.conf"
[ -f "$HERE/thermal/tb-cpu-boost" ] && {
	install_file "$HERE/thermal/tb-cpu-boost" "$SBIN/tb-cpu-boost" 755
	install_file "$HERE/thermal/tb-cpu-boost.service" "$S/tb-cpu-boost.service"
	install_file "$HERE/thermal/cpu-boost.conf" "$ROOT/etc/tb710fu/cpu-boost.conf"
}
[ -f "$HERE/thermal/tb-cpufreq-governor" ] && {
	install_file "$HERE/thermal/tb-cpufreq-governor" "$SBIN/tb-cpufreq-governor" 755
	install_file "$HERE/thermal/tb-cpufreq-governor.service" "$S/tb-cpufreq-governor.service"
	install_file "$HERE/thermal/cpu-governor.conf" "$ROOT/etc/tb710fu/cpu-governor.conf"
}

say "== plasma temperature bar"
install_user_file "$HERE/thermal/widget/tb-batt-read" "$USER_HOME/.local/bin/tb-batt-read" 755
PLASMOID="$USER_HOME/.local/share/plasma/plasmoids/org.tb710fu.batterytempbar"
if [ -d "$HERE/thermal/widget/org.tb710fu.batterytempbar" ]; then
	mkdir -p "$PLASMOID"
	cp -a "$HERE/thermal/widget/org.tb710fu.batterytempbar/." "$PLASMOID/"
	chown -R --reference="$USER_HOME" "$PLASMOID" 2>/dev/null || true
fi

say "== storage / memory"
install_file "$HERE/storage/zram-generator.conf" "$ROOT/etc/systemd/zram-generator.conf"
install_file "$HERE/storage/99-zram.conf"        "$ROOT/etc/sysctl.d/99-zram.conf"
install_file "$HERE/storage/earlyoom"            "$ROOT/etc/default/earlyoom"
install_file "$HERE/storage/lru-gen.conf"        "$ROOT/etc/tmpfiles.d/lru-gen.conf"
install_user_file "$HERE/storage/app.slice.d/50-memory.conf" \
	"$USER_HOME/.config/systemd/user/app.slice.d/50-memory.conf"
install_user_file "$HERE/storage/session.slice.d/50-memory.conf" \
	"$USER_HOME/.config/systemd/user/session.slice.d/50-memory.conf"

say "== display"
install_file "$HERE/display/tb-native-display"         "$SBIN/tb-native-display" 755
install_file "$HERE/display/tb-native-display.service" "$S/tb-native-display.service"
install_file "$HERE/display/tb-panel-cycle-py"         "$SBIN/tb-panel-cycle-py" 755
[ -f "$HERE/display/tb710fu-display.conf" ] && \
	install_file "$HERE/display/tb710fu-display.conf" "$ROOT/etc/modprobe.d/tb710fu-display.conf"

say "== sensors"
[ -f "$HERE/sensors/tb-hexagon-prep" ] && install_file "$HERE/sensors/tb-hexagon-prep" "$SBIN/tb-hexagon-prep" 755

say "== tools"
for f in "$HERE"/tools/tb-*; do
	[ -f "$f" ] || continue
	case "$f" in *.desktop) continue;; esac
	install_file "$f" "$BIN/$(basename "$f")" 755
done
# tb-vk-restart 的登录自启（v3：脚本自己只做 +6s 一次切换）
install_user_file "$HERE/tools/tb-vk-restart.desktop" \
	"$USER_HOME/.config/autostart/tb-vk-restart.desktop"

say "== enable units (system)"
if [ "$ROOT" = / ]; then
	systemctl enable tb-audio-init.service tb-audio-watch.service tb-thermal-guard.service \
		tb-charge-limit.service tb-dp-audio.service tb-native-display.service 2>/dev/null || true
	systemctl enable tb-hwclock-sync.timer 2>/dev/null || true
	[ -f "$S/tb-cpu-boost.service" ] && systemctl enable tb-cpu-boost.service 2>/dev/null || true
	udevadm control --reload 2>/dev/null || true
	systemctl daemon-reload
	sysctl --system >/dev/null 2>&1 || true
	systemd-tmpfiles --create /etc/tmpfiles.d/lru-gen.conf 2>/dev/null || true
	systemctl try-restart earlyoom 2>/dev/null || true
else
	mkdir -p "$S/multi-user.target.wants" "$S/display-manager.service.wants"
	for u in tb-audio-init tb-audio-watch tb-thermal-guard tb-charge-limit tb-dp-audio tb-cpu-boost; do
		[ -f "$S/$u.service" ] && ln -sfn "/etc/systemd/system/$u.service" "$S/multi-user.target.wants/$u.service"
	done
	ln -sfn /etc/systemd/system/tb-native-display.service "$S/display-manager.service.wants/tb-native-display.service"
	[ -f "$S/tb-hwclock-sync.timer" ] && ln -sfn /etc/systemd/system/tb-hwclock-sync.timer "$S/timers.target.wants/tb-hwclock-sync.timer"
fi

say "== disable UCM profiles (rename, reversible)"
for f in "$ROOT/usr/share/alsa/ucm2/conf.d/sm8650/Lenovo-TB710FU.conf" \
         "$ROOT/usr/share/alsa/ucm2/conf.d/LenovoTB710FU/LenovoTB710FU.conf" \
         "$ROOT/usr/share/alsa/ucm2/LenovoTB710FU/LenovoTB710FU.conf"; do
	[ -f "$f" ] && mv "$f" "$f.disabled" && say "   disabled $f"
done

say ""
say "== 还需手动完成 =="
say "1. 把用户加入 realtime 组（PipeWire 实时调度）："
say "     sudo usermod -aG realtime $USER_NAME     # 重新登录生效"
say "2. 确认已安装 rtkit / realtime-privileges："
say "     pacman -S --needed rtkit realtime-privileges"
say "3. 用户级单元（首次安装后以该用户执行）："
say "     systemctl --user daemon-reload"
say "     # 会同时加载 app.slice MemoryHigh=4G / session.slice MemoryLow=1G"
say "     systemctl --user enable --now tb-dp-sink-ensure.service"
say "     systemctl --user mask --now tb-speaker-keepalive.service   # 如存在"
say "4. 重新登录或重启后生效。logind 配置修改不要 restart systemd-logind（会踢掉图形会话）。"
