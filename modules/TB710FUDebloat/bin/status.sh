#!/system/bin/sh
# status.sh - 打印模块状态与清单内每个包的启用/冻结情况（只读）

SELF_DIR=$(cd "${0%/*}" && pwd)
MODDIR_OVERRIDE=$(cd "$SELF_DIR/.." && pwd)
. "$SELF_DIR/common.sh"
exec 0</dev/null

echo "module : $MODDIR"
echo "state  : $(get_state)"
echo "log    : $LOG_FILE"
echo

wait_pm || { echo "警告：PackageManager 未就绪"; exit 1; }

ALL=$(list_all)
DIS=$(list_disabled)
# 用实际系统状态判断 suspend，不依赖 suspended.txt 记录
SUS=$(list_suspended)
# 按用户卸载的包（-u 过滤含未安装包），辅以 uninstalled.txt 记录
UNALL=$(pm list packages -u --user 0 2>/dev/null | sed 's/^package://')
UNREC=""
[ -f "$STATE_DIR/uninstalled.txt" ] && UNREC=$(cat "$STATE_DIR/uninstalled.txt")

printf '%-42s %s\n' "PACKAGE" "STATUS"
printf '%-42s %s\n' "------------------------------------------" "--------"
while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  if ! printf '%s\n' "$ALL" | grep -qx "$pkg"; then
    if printf '%s\n' "$UNALL" | grep -qx "$pkg" || printf '%s\n' "$UNREC" | grep -qx "$pkg"; then
      st="UNINSTALLED"
    else
      st="not-installed"
    fi
  elif printf '%s\n' "$DIS" | grep -qx "$pkg"; then
    st="FROZEN"
  elif printf '%s\n' "$SUS" | grep -qx "$pkg"; then
    st="SUSPENDED"
  else
    st="enabled"
  fi
  printf '%-42s %s\n' "$pkg" "$st"
done <<EOF
$(read_packages)
EOF

echo
echo "== components (lists/components.txt) =="
printf '%-95s %s\n' "COMPONENT" "STATUS"
printf '%-95s %s\n' "-----------------------------------------------------------------------------------------------" "--------"
if [ -f "$COMP_LIST" ]; then
  while IFS= read -r comp; do
    [ -n "$comp" ] || continue
    pkg=${comp%%/*}
    cls=${comp#*/}
    if ! printf '%s\n' "$ALL" | grep -qx "$pkg"; then
      st="pkg-not-installed"
    elif comp_disabled "$pkg" "$cls"; then
      st="FROZEN"
    else
      st="enabled"
    fi
    printf '%-95s %s\n' "$comp" "$st"
  done <<EOF
$(read_components)
EOF
fi

echo
echo "== net blackhole (lists/netblock.txt) =="
sh "$SELF_DIR/netblackhole.sh" status
