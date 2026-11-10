TB710FU 双系统引导配对（kShimC）
================================

boot_a 里装的是 kShimC 双内核引导镜像：开机先起菜单（音量键选、电源键确认、
8 秒倒计时进默认项），"默认进哪个系统"是打包时固化的，所以切换系统 =
把对应变体整块写入 boot_a（Image-00 = 原厂 HyperOS GKI 内核永远不变）。

  boot_android.img  菜单默认 HyperOS —— Arch 侧 `sudo switch2os4` 写入的就是它
  boot_linux.img    菜单默认 Arch    —— OS4 侧 /data/adb/tbboot/switch2arch.sh 写入它

两个变体只差菜单默认项，Image-01（Linux）和 DTB 完全相同。产出方式见
docs/05-arch-kernel.md §7（kshim_variants.sh，--default android / linux 各打一个，
AVB 验证后保留成对）。打包是确定性的：同输入复跑应逐字节复现，可用来核对。

本仓库不包含任何 boot 镜像，也不硬编码作者的配对哈希。
所有配对信息由 pair.env 提供：

  tools/make-pair.sh boot_android.img boot_linux.img > pair.env

日常用法
--------
  Arch 侧：  应用菜单"重启到 HyperOS"图标，或 sudo switch2os4（--status 看状态）
  HyperOS 侧：KernelSU 管理器 → 模块 → TB710FU 系统切换 → 执行动作；
            或 adb shell su -c /data/adb/tbboot/switch2arch.sh
  兜底：    开机 8 秒菜单里手动选另一侧

部署（Arch 侧）
---------------
  sudo install -m755 tools/arch-side/switch2os4 /usr/local/bin/switch2os4
  sudo install -m644 pair.env /usr/local/share/tbboot/pair.env
  sudo install -m600 boot_android.img boot_linux.img /usr/local/share/tbboot/
  sudo install -m440 tools/arch-side/tb-switch.sudoers /etc/sudoers.d/tb-switch
  # 应用菜单图标
  install -m644 tools/arch-side/tb-switch2os4.desktop \
    ~/.local/share/applications/tb-switch2os4.desktop

  注意：switch2os4 不再内置 HASH_ANDROID/HASH_LINUX；它 source
  /usr/local/share/tbboot/pair.env。哈希不一致时会拒绝写入。

部署（HyperOS 侧）
------------------
  平板进 HyperOS 后：
    TB_SERIAL=<serial> tools/os4-switch/install_switch2arch.sh boot_linux.img pair.env
  （装 /data/adb/tbboot/ + KSU 模块 tb710fu_switch）

升级 Arch 内核后
----------------
刷了新 boot_linux.img 之后，两份"配对镜像"就过时了，必须同步更新：
  1) 用新内核 Image/DTB 重打两个变体（kshim_variants.sh）；
  2) 重新 make-pair.sh 生成 pair.env；
  3) 新 boot_android.img / boot_linux.img / pair.env install 到
     /usr/local/share/tbboot/；
  4) 平板在 HyperOS 时重跑 install_switch2arch.sh 更新 OS4 侧副本。
switch 脚本发现镜像哈希不在 pair.env 内会警告（Arch 侧）/拒绝（HyperOS 侧），
就是为这个场景兜底。

安全边界
--------
  - 只写 /dev/disk/by-partlabel/boot_a（OS4 侧 /dev/block/by-name/boot_a）；
  - 不写 boot_b、misc、bcb；不切 A/B 槽；不调用 OTA/update_engine；
  - 写入前备份 boot_a，写入后回读 sha256；
  - 失败自动回滚；不要用 --force 绕过配对校验。
