#!/usr/bin/env python3
# 注意：这是 Python 3 脚本（文件名保留 .sh 兼容旧文档）；直接执行，
# 不要用 `bash set-bt-addr.sh`。
"""set-bt-addr.sh — 把蓝牙补丁里的占位符地址换成你自己的工厂地址。

为什么不能只改一个补丁：
  - `0002-tb-base.patch` 在板级 DTS 里**新增** local-bd-address；
  - `0020-...-Bluetooth-address.patch` 把 kshim DTS 的 00 改成同一个地址，
    并且它的 context 行与删除行注释里都带着板级 DTS 的地址。
  两个补丁必须写成同一个值，否则 `git am` 在 0020 会 context mismatch。

处理策略：
  - 0002（新增补丁）：只改 `+` 行（MAC + 数组）；
  - 0020 / incremental（后续补丁）：改所有行的 MAC（`-` 注释必须与 0002 的输出
    一致，否则删除行匹配不上）；数组只改 `+` 与 context 行，`-` 的零数组保持 00。

用法：
  tools/arch-kernel/set-bt-addr.sh 02:11:22:33:44:55 [PATCH...]

不带 PATCH 时默认处理三个补丁：
  patches/kernel/full/0002-tb-base.patch
  patches/kernel/full/0020-tb710fu-restore-factory-Bluetooth-address.patch
  patches/kernel/incremental/0001-tb710fu-restore-factory-Bluetooth-address.patch
"""
import os
import re
import sys

MAC_RE = re.compile(r"\b(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b")
ARR_RE = re.compile(r"(local-bd-address\s*=\s*\[)[^\]]*(\])")
DEFAULT = [
    "patches/kernel/full/0002-tb-base.patch",
    "patches/kernel/full/0020-tb710fu-restore-factory-Bluetooth-address.patch",
    "patches/kernel/incremental/0001-tb710fu-restore-factory-Bluetooth-address.patch",
]


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    addr = sys.argv[1].strip()
    if not re.fullmatch(r"(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}", addr):
        print(f"错误：地址格式应为 AA:BB:CC:DD:EE:FF（收到 {addr}）", file=sys.stderr)
        return 2
    readable = addr.upper()
    little = " ".join(reversed([b.lower() for b in addr.split(":")]))

    patches = sys.argv[2:] or DEFAULT
    for path in patches:
        if not os.path.isfile(path):
            print(f"错误：找不到 {path}", file=sys.stderr)
            return 1
        base = os.path.basename(path)
        is_base_patch = base.startswith("0002-")
        out = []
        with open(path, encoding="utf-8") as f:
            for line in f:
                added = line.startswith("+") and not line.startswith("+++")
                removed = line.startswith("-") and not line.startswith("---")
                context = line.startswith(" ")
                header_or_meta = line.startswith(("diff ", "index ", "From ", "Date: ",
                                                  "Subject: ", "@@", "+++", "---"))

                if header_or_meta:
                    out.append(line)
                    continue

                if is_base_patch:
                    if added:
                        line = MAC_RE.sub(readable, line)
                        line = ARR_RE.sub(lambda m: m.group(1) + little + m.group(2), line)
                else:
                    # 后续补丁：删除行/上下文/新增行的 MAC 都要与 0002 的输出一致。
                    if added or removed or context:
                        line = MAC_RE.sub(readable, line)
                    if added or context:
                        line = ARR_RE.sub(lambda m: m.group(1) + little + m.group(2), line)
                out.append(line)
        with open(path, "w", encoding="utf-8") as f:
            f.writelines(out)
        print(f"已更新 {path} -> {readable}（小端 [ {little} ]）")

    print("\n下一步：")
    print("  1) grep -n 'local-bd-address' patches/kernel/full/0002-tb-base.patch "
          "patches/kernel/full/0020-*.patch")
    print(f"     确认两处新增数组都是 [ {little} ]")
    print("  2) 再按 docs/05-arch-kernel.md 应用补丁序列")
    print("  3) 刷入后核对：btmgmt info | grep address")
    return 0


if __name__ == "__main__":
    sys.exit(main())
