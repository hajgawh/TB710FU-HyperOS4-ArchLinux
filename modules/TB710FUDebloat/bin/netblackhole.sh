#!/system/bin/sh
# netblackhole.sh - 反诈上报域名 DNS 层黑洞（iptables 自定义链）
# 用法：netblackhole.sh on|off|status
# 机制：OUTPUT 链跳转到自定义链，按 lists/netblock.txt 的 hex-string 匹配 udp/tcp 53 查询包并 REJECT。
# 注意：iptables 规则重启即失，service.sh 会按 $STATE_DIR/net_state 在每次开机重建（默认 on）。

SELF_DIR=$(cd "${0%/*}" && pwd)
MODDIR_OVERRIDE=$(cd "$SELF_DIR/.." && pwd)
. "$SELF_DIR/common.sh"

[ "$(id -u)" = "0" ] || { echo "错误：需要 root"; exit 1; }
exec 0</dev/null

net_domains() {
  [ -f "$NET_LIST" ] || return 1
  sed -e 's/#.*//' -e 's/[[:space:]]//g' "$NET_LIST" | grep -v '^$'
}

ensure_jump() {
  # $1 = iptables | ip6tables
  if ! "$1" -C OUTPUT -j "$NET_CHAIN" 2>/dev/null; then
    "$1" -I OUTPUT 1 -j "$NET_CHAIN" 2>/dev/null
  fi
}

case "${1:-status}" in
  on)
    log_init "netblackhole on"
    iptables -N "$NET_CHAIN" 2>/dev/null
    iptables -F "$NET_CHAIN" 2>/dev/null
    ip6tables -N "$NET_CHAIN" 2>/dev/null
    ip6tables -F "$NET_CHAIN" 2>/dev/null
    n=0
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      d=${entry%%\|*}
      hex=${entry#*\|}
      [ -n "$hex" ] || { log "SKIP(bad-hex) $entry"; continue; }
      if iptables -A "$NET_CHAIN" -p udp --dport 53 -m string --hex-string "|$hex|" --algo bm -j REJECT 2>/dev/null; then
        iptables -A "$NET_CHAIN" -p tcp --dport 53 -m string --hex-string "|$hex|" --algo bm -j REJECT 2>/dev/null
        ip6tables -A "$NET_CHAIN" -p udp --dport 53 -m string --hex-string "|$hex|" --algo bm -j REJECT 2>/dev/null
        ip6tables -A "$NET_CHAIN" -p tcp --dport 53 -m string --hex-string "|$hex|" --algo bm -j REJECT 2>/dev/null
        log "block(dns) $d"
        n=$((n + 1))
      else
        log "FAIL(dns-rule) $d"
      fi
    done <<EOF
$(net_domains)
EOF
    ensure_jump iptables
    ensure_jump ip6tables
    mkdir -p "$STATE_DIR" 2>/dev/null
    echo on > "$NET_STATE_FILE"
    log "netblackhole on: $n domains"
    ;;
  off)
    log_init "netblackhole off"
    iptables -D OUTPUT -j "$NET_CHAIN" 2>/dev/null
    iptables -F "$NET_CHAIN" 2>/dev/null
    iptables -X "$NET_CHAIN" 2>/dev/null
    ip6tables -D OUTPUT -j "$NET_CHAIN" 2>/dev/null
    ip6tables -F "$NET_CHAIN" 2>/dev/null
    ip6tables -X "$NET_CHAIN" 2>/dev/null
    mkdir -p "$STATE_DIR" 2>/dev/null
    echo off > "$NET_STATE_FILE"
    log "netblackhole off"
    ;;
  status)
    echo "state: $(cat "$NET_STATE_FILE" 2>/dev/null || echo on)"
    echo "rules:"
    iptables -S "$NET_CHAIN" 2>/dev/null | sed 's/^/  v4 /' | head -12
    ip6tables -S "$NET_CHAIN" 2>/dev/null | sed 's/^/  v6 /' | head -12
    iptables -S OUTPUT 2>/dev/null | grep -q -- "-j $NET_CHAIN" && echo "  v4 OUTPUT jump: yes" || echo "  v4 OUTPUT jump: no"
    ;;
  *)
    echo "usage: netblackhole.sh on|off|status"
    exit 1
    ;;
esac
