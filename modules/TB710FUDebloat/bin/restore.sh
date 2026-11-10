#!/system/bin/sh
# restore.sh - 恢复 lists/packages.txt 中的包
# 顺序：install-existing（按用户卸载的） -> 清理残留 suspend -> pm enable
# 用法：restore.sh

SELF_DIR=$(cd "${0%/*}" && pwd)
MODDIR_OVERRIDE=$(cd "$SELF_DIR/.." && pwd)
. "$SELF_DIR/common.sh"

[ "$(id -u)" = "0" ] || { echo "错误：需要 root"; exit 1; }

# pm(app_process) 在 stdin 指向文件/管道时会 "Failed transaction"，必须断开。
# 下面的循环用 heredoc/文件重定向自己的 stdin，不受影响。
exec 0</dev/null

log_init "restore start"
wait_pm || { log "错误：PackageManager 未就绪，放弃"; exit 1; }

ALL=$(list_all)
DIS=$(list_disabled)
SUS=$(list_suspended)

total=0
newly=0
restored_n=0
unsuspended=0
skipped=0
failed=0
missing=0
un_failed=0
sus_failed=0

# 1) 恢复按用户卸载的包（MIUI core 兜底）：install-existing + unsuspend + enable
UNREC="$STATE_DIR/uninstalled.txt"
if [ -f "$UNREC" ]; then
  while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue

    # 已在安装列表（上次恢复中断的残留记录）：直接视为已恢复
    if printf '%s\n' "$ALL" | grep -qx "$pkg"; then
      log "OK already-installed $pkg"
      restored_n=$((restored_n + 1))
      continue
    fi

    # install-existing 带退避重试（system_server 忙时 binder 会瞬时失败）
    n=0
    ok=0
    while [ "$n" -lt 4 ]; do
      if pm install-existing --user 0 "$pkg" < /dev/null >/dev/null 2>&1; then
        # 不信任返回码，用包列表实证
        if pm list packages --user 0 < /dev/null 2>/dev/null | grep -qx "package:$pkg"; then
          ok=1
          break
        fi
      fi
      case "$n" in
        0) sleep 1 ;;
        1) sleep 3 ;;
        2) sleep 8 ;;
      esac
      n=$((n + 1))
    done
    if [ "$ok" != "1" ]; then
      log "FAIL(install-existing) $pkg"
      un_failed=$((un_failed + 1))
      failed=$((failed + 1))
      continue
    fi
    # 清掉可能残留的 suspended 标记，避免恢复后仍处于休眠态
    if printf '%s\n' "$SUS" | grep -qx "$pkg"; then
      cmd package unsuspend --user 0 "$pkg" >/dev/null 2>&1
    fi
    m=0
    ok2=0
    while [ "$m" -lt 3 ]; do
      if out2=$(pm enable --user 0 "$pkg" < /dev/null 2>&1); then
        ok2=1
        break
      fi
      m=$((m + 1))
      sleep 2
    done
    if [ "$ok2" = "1" ]; then
      log "RESTORED $pkg (install-existing)"
      restored_n=$((restored_n + 1))
    else
      log "FAIL(enable-after-restore) $pkg :: $out2"
      un_failed=$((un_failed + 1))
      failed=$((failed + 1))
    fi
  done < "$UNREC"
fi

# 2) 清理历史版本残留的 suspended 状态（v1.2 遗留）
while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  printf '%s\n' "$SUS" | grep -qx "$pkg" || continue

  n=0
  ok=0
  while [ "$n" -lt 3 ]; do
    if out=$(cmd package unsuspend --user 0 "$pkg" < /dev/null 2>&1); then
      ok=1
      break
    fi
    n=$((n + 1))
    sleep 1
  done

  if [ "$ok" = "1" ]; then
    log "UNSUSPENDED $pkg"
    unsuspended=$((unsuspended + 1))
  else
    log "FAIL(unsuspend) $pkg :: $out"
    sus_failed=$((sus_failed + 1))
    failed=$((failed + 1))
  fi
done <<EOF
$(read_packages)
EOF

# 3) 启用被禁用的包
while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  total=$((total + 1))

  if ! printf '%s\n' "$ALL" | grep -qx "$pkg"; then
    log "SKIP not-installed $pkg"
    missing=$((missing + 1))
    continue
  fi

  if ! printf '%s\n' "$DIS" | grep -qx "$pkg"; then
    log "OK already-enabled $pkg"
    skipped=$((skipped + 1))
    continue
  fi

  n=0
  ok=0
  while [ "$n" -lt 3 ]; do
    if out=$(pm enable --user 0 "$pkg" < /dev/null 2>&1); then
      ok=1
      break
    fi
    n=$((n + 1))
    sleep 1
  done

  if [ "$ok" = "1" ]; then
    log "ENABLED $pkg"
    newly=$((newly + 1))
  else
    log "FAIL $pkg :: $out"
    failed=$((failed + 1))
  fi
done <<EOF
$(read_packages)
EOF

# 4) 恢复组件（反诈组件等）
if [ -f "$COMP_LIST" ]; then
  comp_restored=0
  comp_skipped=0
  while IFS= read -r comp; do
    [ -n "$comp" ] || continue
    pkg=${comp%%/*}
    cls=${comp#*/}

    if ! printf '%s\n' "$ALL" | grep -qx "$pkg"; then
      log "SKIP not-installed(pkg) $comp"
      continue
    fi

    if ! comp_disabled "$pkg" "$cls"; then
      log "OK already-enabled(comp) $comp"
      comp_skipped=$((comp_skipped + 1))
      continue
    fi

    n=0
    ok=0
    while [ "$n" -lt 3 ]; do
      if out=$(pm enable "$pkg/$cls" < /dev/null 2>&1); then
        ok=1
        break
      fi
      n=$((n + 1))
      sleep 1
    done

    if [ "$ok" != "1" ]; then
      log "FAIL(comp) $comp :: $out"
      failed=$((failed + 1))
      continue
    fi
    # 不信任返回码，实证组件确实离开 disabledComponents（pm enable 偶发不落盘）
    if comp_disabled "$pkg" "$cls"; then
      log "FAIL(comp-verify) $comp（enable 后仍为 disabled，可手动 pm enable 重试）"
      failed=$((failed + 1))
    else
      log "ENABLED(comp) $comp"
      comp_restored=$((comp_restored + 1))
    fi
  done <<EOF
$(read_components)
EOF
fi

# 5) 网络层兜底一并关闭
sh "$SELF_DIR/netblackhole.sh" off >/dev/null 2>&1

# 记录文件仅作参考；对应恢复全部成功才清空，便于下次重试失败项
if [ "$un_failed" = "0" ] && [ -f "$UNREC" ]; then
  : > "$UNREC"
fi
if [ "$sus_failed" = "0" ] && [ -f "$STATE_DIR/suspended.txt" ]; then
  : > "$STATE_DIR/suspended.txt"
fi

set_state restored
log "restore done: total=$total newly=$newly restored=$restored_n unsuspended=$unsuspended already=$skipped missing=$missing failed=$failed state=$(get_state)"
