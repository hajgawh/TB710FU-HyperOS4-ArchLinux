#!/system/bin/sh
# TB710FUSetRes 卸载后的运行时数据清理（**参考实现，未在真机全量验收**）
#
# 为什么需要它：`ksud module uninstall` 只删模块目录、停开机脚本，模块在运行期建立的
# 东西（符号链接、目录权限、property、时间锚点、WPS/CAD 客户机镜像）**不会回滚**。
# 官方 README §5 只写了"需要时手工清理"；这个脚本把那句话变成可执行的清单。
#
# 用法（设备上，root）：
#   sh uninstall.sh                # 预览：只打印将要做什么
#   sh uninstall.sh --yes          # 执行（默认保留 WPS/CAD 镜像与时间锚点）
#   sh uninstall.sh --yes --purge-clock    # 同时删除离线时间锚点
#   sh uninstall.sh --yes --purge-images   # 同时删除 WPS/CAD 客户机镜像（几百 MB，不可恢复）
#
# 顺序建议：先 `ksud module uninstall tb710fu_setres_noop`，重启，再跑本脚本。

set -u

RE=/data/rootfs
APPLY=0
PURGE_CLOCK=0
PURGE_IMAGES=0
for a in "$@"; do
  case "$a" in
    --yes)          APPLY=1 ;;
    --purge-clock)  PURGE_CLOCK=1 ;;
    --purge-images) PURGE_IMAGES=1 ;;
    -h|--help)      sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done

say() { echo "$*"; }
run() {  # run <描述> <命令...>
  desc=$1; shift
  if [ "$APPLY" = 1 ]; then
    if "$@"; then say "  done   : $desc"
    else say "  FAILED : $desc  (命令: $*)"; fi
  else
    say "  would  : $desc"
  fi
}

say "TB710FUSetRes cleanup (apply=$APPLY purge_clock=$PURGE_CLOCK purge_images=$PURGE_IMAGES)"
say ""

# --- 1) rootfs 路径桥 --------------------------------------------------------
if [ -L /data/vendor/rootfs ]; then
  run "删除符号链接 /data/vendor/rootfs" rm -f /data/vendor/rootfs
else
  say "  skip   : /data/vendor/rootfs 不是符号链接（可能已被清理，或本来就是真目录）"
fi

# OS3 时代的真目录被模块改名保留过，这里只提示，不自动动
for d in /data/vendor/rootfs.old-*; do
  [ -d "$d" ] || continue
  say "  NOTE   : 发现 $d（模块改名保留的原目录）"
  say "           确认无用后再手工处理：mv \"$d\" /data/vendor/rootfs  或  rm -rf \"$d\""
done

# --- 2) 目录权限 -------------------------------------------------------------
if [ -d "$RE" ]; then
  run "把 $RE 权限恢复成 0755" chmod 0755 "$RE"
else
  say "  skip   : $RE 不存在"
fi

# --- 3) property（重启后本来也会失效；这里顺手清一次） ----------------------
RESETPROP=/data/adb/ksu/bin/resetprop
[ -x "$RESETPROP" ] || RESETPROP=$(command -v resetprop 2>/dev/null || true)
if [ -n "$RESETPROP" ] && [ -x "$RESETPROP" ]; then
  run "删除 ro.vendor.mslg.rootfs.version" "$RESETPROP" -d ro.vendor.mslg.rootfs.version
else
  say "  skip   : resetprop 不可用（该 property 重启后自然消失）"
fi

# --- 4) 开机日志（纯诊断，可删） --------------------------------------------
for f in /data/local/tmp/tb710fu_boot.log /data/local/tmp/tb710fu_loops.log \
         /data/local/tmp/tb710fu_landscape.log; do
  [ -f "$f" ] && run "删除 $f" rm -f "$f"
done

# --- 5) 离线时间锚点（默认保留） --------------------------------------------
CLOCK=/mnt/vendor/persist/tb710fu/lasttime
if [ "$PURGE_CLOCK" = 1 ]; then
  [ -f "$CLOCK" ] && run "删除离线时间锚点 $CLOCK" rm -f "$CLOCK"
else
  [ -f "$CLOCK" ] && say "  keep   : $CLOCK（--purge-clock 才删；删了下次开机走 NTP 兜底）"
fi

# --- 6) WPS/CAD 客户机镜像（默认保留，几百 MB 用户数据） --------------------
if [ "$PURGE_IMAGES" = 1 ]; then
  for f in "$RE"/mslgkingsoftimg "$RE"/mslgzwcad2025img \
           "$RE"/kingsoft.txt "$RE"/kingsoft_md5.txt \
           "$RE"/zwcad2025.txt "$RE"/zwcad2025_md5.txt; do
    [ -e "$f" ] && run "删除 $f" rm -f "$f"
  done
else
  for f in "$RE"/mslgkingsoftimg "$RE"/mslgzwcad2025img; do
    [ -e "$f" ] && say "  keep   : $f（--purge-images 才删）"
  done
  [ -d "$RE" ] && say "  NOTE   : 想只清 WPS/CAD 的部署状态但保留镜像，可删除 $RE/*.txt"
fi

say ""
if [ "$APPLY" = 1 ]; then
  say "完成。建议重启一次，再用下面的命令确认没有残留："
else
  say "以上为预览。确认无误后加 --yes 执行。"
fi
say "  ls -l /data/vendor/rootfs                 # 期望：No such file（或你自己放回的真目录）"
say "  ls -ld /data/rootfs                        # 期望：drwxr-xr-x"
say "  getprop ro.vendor.mslg.rootfs.version      # 期望：空（重启后必然为空）"
say "  ps -ef | grep '[t]b_loops'                 # 期望：无输出"
