#!/usr/bin/env python3
"""Print the GKI kernel identity carried by an Android boot.img.

Used by kshim_variants.sh as a guard: the Android side of the kShimC pair must
keep the *same* GKI as the release that is known to boot the ported HyperOS,
otherwise Android hangs at the splash screen (v15 regression, 2026-11-03).

Usage: kshim_gki_check.py BOOT.img
Output: "<sha256> <size> <linux version string>"
"""
import hashlib
import re
import struct
import sys

PAGE = 4096


def main():
    d = open(sys.argv[1], "rb").read()
    assert d[:8] == b"ANDROID!", "not an Android boot image: %s" % sys.argv[1]
    kernel_size = struct.unpack_from("<I", d, 8)[0]
    kernel = d[PAGE:PAGE + kernel_size]
    assert kernel[56:60] == b"ARM\x64", "kernel is not a raw arm64 Image"
    m = re.search(rb"Linux version [0-9][^\x00]{0,120}", kernel)
    ver = m.group(0).decode("latin1") if m else "?"
    print("%s %d %s" % (hashlib.sha256(kernel).hexdigest(), kernel_size, ver))


if __name__ == "__main__":
    main()
