#!/system/bin/sh
# freeze.sh - 冻结 lists/packages.txt 中的包
# 用法：freeze.sh [--dry-run]
#   --dry-run 只打印将要执行的操作，不做任何修改

SELF_DIR=$(cd "${0%/*}" && pwd)
MODDIR_OVERRIDE=$(cd "$SELF_DIR/.." && pwd)
. "$SELF_DIR/common.sh"

DRY=0
case "${1:-}" in
  --dry-run|-n) DRY=1 ;;
esac

[ "$(id -u)" = "0" ] || { echo "错误：需要 root"; exit 1; }

# pm(app_process) 在 stdin 指向文件/管道时会 "Failed transaction"，必须断开。
# 下面的循环用 heredoc/文件重定向自己的 stdin，不受影响。
exec 0</dev/null

log_init "freeze start (dry-run=$DRY)"
wait_pm || { log "错误：PackageManager 未就绪，放弃"; exit 1; }

ALL=$(list_all)
DIS=$(list_disabled)

total=0
newly=0
skipped=0
failed=0

while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  total=$((total + 1))

  if is_protected "$pkg"; then
    log "SKIP protected $pkg"
    skipped=$((skipped + 1))
    continue
  fi

  if ! printf '%s\n' "$ALL" | grep -qx "$pkg"; then
    log "SKIP not-installed $pkg"
    skipped=$((skipped + 1))
    continue
  fi

  if printf '%s\n' "$DIS" | grep -qx "$pkg"; then
    log "OK already-disabled $pkg"
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$DRY" = "1" ]; then
    log "WOULD-DISABLE $pkg"
    continue
  fi

  if out=$(pm disable-user --user 0 "$pkg" < /dev/null 2>&1); then
    log "DISABLED $pkg"
    newly=$((newly + 1))
    continue
  fi

  # MIUI 核心包会被 PackageManagerServiceImpl 拒绝禁用（SecurityException），
  # 降级为 suspend：效果等价于冻结，且可用 unsuspend 恢复。
  case "$out" in
    *"Cannot disable"*|*"SecurityException"*|*"protected package"*)
      # MIUI core 包：停用被硬拦。降级为按用户卸载（APK 仍在 /product、数据保留，
      # 恢复 = cmd package install-existing；persistent 常驻进程不会再被拉起）。
      cmd package unsuspend --user 0 "$pkg" < /dev/null >/dev/null 2>&1
      n=0
      ok=0
      while [ "$n" -lt 3 ]; do
        if out2=$(pm uninstall -k --user 0 "$pkg" < /dev/null 2>&1); then
          ok=1
          break
        fi
        n=$((n + 1))
        sleep 1
      done
      if [ "$ok" = "1" ]; then
        mkdir -p "$STATE_DIR" 2>/dev/null
        grep -qx "$pkg" "$STATE_DIR/uninstalled.txt" 2>/dev/null || echo "$pkg" >> "$STATE_DIR/uninstalled.txt"
        if [ -f "$STATE_DIR/suspended.txt" ]; then
          grep -vx "$pkg" "$STATE_DIR/suspended.txt" > "$STATE_DIR/suspended.txt.tmp" 2>/dev/null && mv "$STATE_DIR/suspended.txt.tmp" "$STATE_DIR/suspended.txt"
        fi
        log "UNINSTALLED $pkg (disable blocked, uninstall fallback)"
        newly=$((newly + 1))
      else
        log "FAIL $pkg :: disable: $out :: uninstall: $out2"
        failed=$((failed + 1))
      fi
      ;;
    *)
      log "FAIL $pkg :: $out"
      failed=$((failed + 1))
      ;;
  esac
done <<EOF
$(read_packages)
EOF

# --- 组件级冻结（lists/components.txt，反诈组件等；包级拦不住的用组件级）---
if [ -f "$COMP_LIST" ]; then
  log "-- components --"
  while IFS= read -r comp; do
    [ -n "$comp" ] || continue
    pkg=${comp%%/*}
    cls=${comp#*/}

    if ! printf '%s\n' "$ALL" | grep -qx "$pkg"; then
      log "SKIP not-installed(pkg) $comp"
      continue
    fi

    if comp_disabled "$pkg" "$cls"; then
      log "OK already-disabled(comp) $comp"
      continue
    fi

    if [ "$DRY" = "1" ]; then
      log "WOULD-DISABLE(comp) $comp"
      continue
    fi

    n=0
    ok=0
    while [ "$n" -lt 3 ]; do
      if out=$(pm disable "$pkg/$cls" < /dev/null 2>&1); then
        ok=1
        break
      fi
      n=$((n + 1))
      sleep 1
    done

    if [ "$ok" = "1" ]; then
      log "DISABLED(comp) $comp"
    else
      log "FAIL(comp) $comp :: $out"
      failed=$((failed + 1))
    fi
  done <<EOF
$(read_components)
EOF
fi

# --- 网络层兜底（DNS 层黑洞反诈上报域名；iptables 规则不持久，靠每次开机重建）---
if [ "$DRY" != "1" ]; then
  sh "$SELF_DIR/netblackhole.sh" on >/dev/null 2>&1
fi

if [ "$DRY" != "1" ]; then
  set_state frozen
fi

log "freeze done: total=$total newly=$newly skipped/already=$skipped failed=$failed state=$(get_state)"
