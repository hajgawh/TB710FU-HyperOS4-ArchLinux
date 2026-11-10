#!/system/bin/sh
# TB710FU 共享分区：/dev/block/sda16（GPT 名 share，ext4）→ /mnt/share
# 与 Arch 侧 /mnt/share 是同一个文件系统，用于双系统之间互传文件。
#
# v1.1 两个真机坑：
#   1) `mount -o context=...` 需要 SELinux `associate` 权限，只有 vold/init 域有，
#      su 域被拒（avc denied associate ... tclass=filesystem，且报错是误导性的
#      "'/dev/block/sda16' is read-only"）。→ 改成无 context 挂载。
#   2) 无 context 挂载时挂载点默认是 unlabeled，新文件也继承 unlabeled；用 chcon
#      把挂载点打成 media_rw_data_file，root 文件管理器复制进来的文件自动继承该标签。
#   另：fs_mgr 可能把非 fstab 分区置只读，mount 前兜底 setrw。
#
# 注意：一次性挂载，不留常驻子进程（ksud 会收割 service.sh 的子进程）。

DEV=/dev/block/by-name/share
[ -b "$DEV" ] || DEV=/dev/block/sda16
[ -b "$DEV" ] || exit 0

mkdir -p /mnt/share
grep -qs " /mnt/share " /proc/mounts && exit 0

[ "$(blockdev --getro "$DEV" 2>/dev/null)" = "1" ] && blockdev --setrw "$DEV" 2>/dev/null

mount -t ext4 -o rw,noatime "$DEV" /mnt/share || exit 0
chcon u:object_r:media_rw_data_file:s0 /mnt/share 2>/dev/null
chmod 0777 /mnt/share 2>/dev/null
