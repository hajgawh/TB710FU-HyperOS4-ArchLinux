# TB710FUShareMount v1.1 — 共享分区挂载（ext4 → /mnt/share）

- 模块 ID：`tb710fu_share_mount`
- 版本：v1.1 / versionCode 2
- 作用：开机把 sda16（GPT 名 `share`，ext4，8 GiB）挂到 `/mnt/share`
- 日志：无独立日志；用 `mount` / `dmesg` 检查

Arch 侧 `/etc/fstab` 里是同一个分区（`LABEL=share → /mnt/share`），两边看到的是一份数据，用于双系统
互传文件（同一台设备双系统不能同时在线，网络直传不成立）。

## 1. 作用与边界

- 只挂载一个分区：`/dev/block/by-name/share`（不存在时回退 `/dev/block/sda16`）→ `/mnt/share`。
- 只在 Android 开机时挂载；`/mnt/share` 已经是挂载点就直接退出，不重复挂。
- 不做格式化、不建文件系统、不改分区表；分区数据由两边共享。
- 不提供常驻同步或权限修复；Arch 侧权限由 `tb-share-fixperm.service` / fstab 默认 ACL 消化。

## 2. 实现方式（`service.sh`）

1. `DEV=/dev/block/by-name/share`，不是块设备时回退 `/dev/block/sda16`；两个都不存在就退出。
2. `mkdir -p /mnt/share`；`/proc/mounts` 里已有 `/mnt/share` 就退出。
3. Android 的 fs_mgr 可能把非 fstab 分区置只读：`blockdev --getro` 返回 1 时先
   `blockdev --setrw`。
4. **无 `context=` 挂载**：`mount -t ext4 -o rw,noatime "$DEV" /mnt/share`。
5. 挂载成功后 `chcon u:object_r:media_rw_data_file:s0 /mnt/share`，再 `chmod 0777 /mnt/share`。

一次性挂载，不留常驻子进程。

## 3. 安装 / 启用（OS4 侧）

模块 zip 本身就放在共享分区里，所以要先手工挂一次做引导：

```sh
su -c 'mkdir -p /mnt/share'
su -c 'mount -t ext4 -o rw /dev/block/by-name/share /mnt/share'
su -c 'ksud module install /mnt/share/TB710FUShareMount.zip'
```

`/dev/block/by-name/share` 不存在时用 `/dev/block/sda16`。装完重启生效；之后每次开机由
`service.sh` 自动挂载。

## 4. 验收

```sh
# 挂载点存在且是 ext4
adb shell 'mount | grep /mnt/share'

# SELinux 标签应为 media_rw_data_file
adb shell 'ls -Zd /mnt/share'

# 可写（先建探针，确认后再删）
adb shell 'su -c "touch /mnt/share/.probe"'

# Arch 侧看到同一个文件
ls -l /mnt/share/.probe

# 清理探针
adb shell 'su -c "rm /mnt/share/.probe"'
```

## 5. 使用

- Android 侧：带 root 的文件管理器（MT管理器、MiXplorer、Solid Explorer+root 插件）浏览
  `/mnt/share`。小米文件管理器没有 root 模式，看不到。
- Arch 侧：`/mnt/share`（fstab 自动挂载），或 `~/Share` 快捷软链。
- 属主/权限：两边新建文件的 uid/位不统一（Android 侧多为 root 或 media_rw、位可能是 0600/0660），
  Arch 侧靠 fstab 挂载点的默认 ACL + `tb-share-fixperm.service` 定时 `chmod -R a+rwX` 消化；
  需要立刻可读时 `sudo chmod -R a+rwX /mnt/share`。

## 6. 卸载 / 回退

```sh
adb shell "ksud module uninstall tb710fu_share_mount"
adb reboot
```

卸载后重启不再挂载；分区数据不受影响。需要立即卸载当前挂载：

```sh
adb shell 'su -c "umount /mnt/share"'
```

## 7. 设计要点与不要做

1. **不要用 `mount -o context=u:object_r:media_rw_data_file:s0`。** SELinux 要求 `associate` 权限，
   只有 vold/init 域有；su 域会被拒，而且报错是误导性的 `'/dev/block/sda16' is read-only` +
   `Permission denied`（`dmesg` 里是 `avc: denied { associate } ... tclass=filesystem`）。
2. **挂载后 `chcon` 挂载点。** 无 `context=` 时挂载点默认是 `u:object_r:unlabeled:s0`，新文件也继承
   unlabeled；给 `/mnt/share` 打上 `media_rw_data_file` 后，root 文件管理器复制进来的文件会自动继承
   该标签。root 读写 unlabeled 文件也没问题，但标签正确更省事。
3. **保留 `blockdev --setrw` 兜底。** fs_mgr 可能把非 fstab 分区置只读，挂载前按 `--getro` 结果
   决定是否 `--setrw`。
4. **一次性挂载，不要留常驻子进程。** ksud 会收割 `service.sh` 的子进程；这里没有需要后台保活的
   循环，挂完就退出。
5. **不要改成 exFAT。** Arch 侧内核没编这个模块；ext4 有日志，非正常切换也能自愈。
6. **切系统前等拷贝完成。** 文件管理器提示完成/进度归零再重启，别在写入中途切。
