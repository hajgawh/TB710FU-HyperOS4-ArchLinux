#!/bin/bash
# build-single-module.sh — 只重编一个子系统并导出 .ko（日常迭代用）。
#
# 用法（在 Mac 上，docker 已启动）：
#   ./build-single-module.sh drivers/gpu/drm/msm msm.ko /tmp/out
#   ./build-single-module.sh drivers/gpu/drm/panel panel-nt36532-wqhd-dual-dsi-dsc.ko /tmp/out
#   ./build-single-module.sh drivers/input/touchscreen/NT36XXX_SPI nvt_36xxx.ko /tmp/out
#   ./build-single-module.sh drivers/video/backlight sy7758.ko /tmp/out
#
# 关键点：
#   1) 必须显式 KERNELRELEASE=7.3.0-tb710fu，否则内核树会重跑 syncconfig，
#      可能生成 7.3.0-tb710fu-tb710fu。
#   2) 触摸模块禁止 rmmod（已知卸载 Oops），只能替换文件后重启。
set -euo pipefail

SUBDIR=${1:?usage: build-single-module.sh <M=subdir> <ko-name> [outdir]}
KO=${2:?}
OUTDIR=${3:-/tmp/tb710fu-module}
VOL=${KERNEL_VOLUME:-tb-kwork}
TREE=${KERNEL_TREE_IN_VOL:-/w/rebase/linux-7.3}
BUILDER=${KERNEL_BUILDER:-kernel-build:latest}
KV=${KERNELRELEASE:-7.3.0-tb710fu}

mkdir -p "$OUTDIR"
docker run --rm -v "$VOL":/w -v "$OUTDIR":/out "$BUILDER" sh -c "
  set -e
  cd $TREE
  make -j\$(nproc) KERNELRELEASE=$KV M=$SUBDIR modules
  find $SUBDIR -name '$KO' -exec cp {} /out/ \;
  sha256sum /out/$KO
"
echo
echo "安装到平板（先备份）："
echo "  M=/lib/modules/$KV/kernel/$SUBDIR/$KO"
echo "  sudo cp -a \$M \$M.before-\$(date +%Y%m%d-%H%M)"
echo "  sudo install -m 644 $OUTDIR/$KO \$M"
echo "  sudo depmod -a $KV"
echo "  sudo systemctl reboot"
