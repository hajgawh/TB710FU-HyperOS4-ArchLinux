#!/system/bin/sh
# common.sh - 常量与公共函数（由 bin/*.sh、service.sh、uninstall.sh source）

# 模块目录：调用方通过 MODDIR_OVERRIDE 传入；默认按模块 id 兜底
MODDIR=${MODDIR_OVERRIDE:-/data/adb/modules/tb710fu_os4_debloat}
STATE_DIR=/data/adb/tb710fu_os4_debloat
STATE_FILE="$STATE_DIR/state"
LOG_FILE="$STATE_DIR/debloat.log"
PKG_LIST="$MODDIR/lists/packages.txt"
COMP_LIST="$MODDIR/lists/components.txt"
NET_LIST="$MODDIR/lists/netblock.txt"
NET_STATE_FILE="$STATE_DIR/net_state"
NET_CHAIN="TB710FU_DEBLOAT_DNS"

# 永久不碰的核心包（即使清单被误改也拒绝处理）
PROTECTED=" android com.android.systemui com.android.settings com.android.phone com.android.providers.settings com.android.shell com.android.bluetooth com.android.networkstack com.android.providers.media.module com.miui.home com.miui.securitycenter com.miui.securitycore com.miui.packageinstaller com.miui.miwallpaper com.sohu.inputmethod.sogou.xiaomi "

log() {
  mkdir -p "$STATE_DIR" 2>/dev/null
  echo "[$(date '+%m-%d %H:%M:%S' 2>/dev/null || echo '--')] $*" | tee -a "$LOG_FILE"
}

# 启动一次日志段，超过 400 行时截断到 200 行
log_init() {
  mkdir -p "$STATE_DIR" 2>/dev/null
  if [ -f "$LOG_FILE" ]; then
    lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$lines" -gt 400 ] 2>/dev/null; then
      tail -n 200 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
  fi
  log "===== $* ====="
}

is_protected() {
  case "$PROTECTED" in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# 读取组件清单：包名/类名，去注释去空白
read_components() {
  [ -f "$COMP_LIST" ] || return 1
  sed -e 's/#.*//' -e 's/[[:space:]]//g' "$COMP_LIST" | grep -v '^$'
}

# 组件是否已被禁用（从 dumpsys 的 disabledComponents 段匹配类名）
comp_disabled() {
  dumpsys package "$1" 2>/dev/null | awk -v c="$2" '
    /^[^ \t]/ { inblk = 0 }
    /^[ \t]*enabledComponents:/ { inblk = 0; next }
    /^[ \t]*disabledComponents:/ { inblk = 1; next }
    inblk && $0 ~ ("^[ \t]+" c "[ \t]*$") { found = 1 }
    END { if (found) exit 0; exit 1 }
  '
}

# 读取清单：去掉注释、空白，每行一个包名
read_packages() {
  [ -f "$PKG_LIST" ] || return 1
  sed -e 's/#.*//' -e 's/[[:space:]]//g' "$PKG_LIST" | grep -v '^$'
}

list_all() {
  pm list packages --user 0 2>/dev/null | sed 's/^package://'
}

list_disabled() {
  pm list packages -d --user 0 2>/dev/null | sed 's/^package://'
}

# 一次性列出所有 suspended 包（约 3-5s），比逐包 dumpsys 快
list_suspended() {
  dumpsys package 2>/dev/null | awk '
    /^ *Package \[/ { s=$0; sub(/^ *Package \[/, "", s); sub(/\].*/, "", s); pkg=s }
    /suspended=true/ { if (pkg != "") print pkg }
  ' | sort -u
}

# 等 PackageManager 就绪（最长约 180s）
wait_pm() {
  i=0
  while [ "$i" -lt 90 ]; do
    if pm list packages --user 0 2>/dev/null | grep -q '^package:android$'; then
      return 0
    fi
    sleep 2
    i=$((i + 1))
  done
  return 1
}

get_state() {
  cat "$STATE_FILE" 2>/dev/null || echo frozen
}

set_state() {
  mkdir -p "$STATE_DIR" 2>/dev/null
  echo "$1" > "$STATE_FILE"
}
