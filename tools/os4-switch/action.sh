#!/system/bin/sh
# KernelSU 管理器“执行动作”按钮：切换到 Arch Linux
echo "== TB710FU：重启进入 Arch Linux"
/data/adb/tbboot/switch2arch.sh --yes
rc=$?
echo "== 退出码 ${rc}（未看到“回读校验通过”则没有切换）"
exit $rc
