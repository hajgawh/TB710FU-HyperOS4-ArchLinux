#!/usr/bin/env python3
"""Verify a super image against the manifest written by make_super.py.

usage: check_super.py SUPER.img [SUPER.img.manifest.json]

The manifest records each logical partition's offset/size and the SHA-256 of the
source image.  This script seeks into the super and re-hashes the exact byte
range, so a wrong layout, truncated write or stale partition image is caught
without needing lpunpack.  Exit code 0 = all partitions match.
"""
import hashlib
import json
import os
import struct
import sys

LP_GEOM_MAGIC = 0x616C4467
LP_HEADER_MAGIC = 0x414C5030


def sha256_range(path, offset, size):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        f.seek(offset)
        left = size
        while left:
            b = f.read(min(left, 64 << 20))
            if not b:
                raise SystemExit('short read at offset %d' % (offset + size - left))
            h.update(b)
            left -= len(b)
    return h.hexdigest()


def check_lp_metadata(path):
    """Check the liblp geometry/header magic and header table checksum."""
    with open(path, 'rb') as f:
        f.seek(4096); g1 = f.read(4096)
        f.seek(8192); g2 = f.read(4096)
        f.seek(12288); hdr = f.read(256)
    if len(g1) < 52 or len(g2) < 52 or len(hdr) < 84:
        return 'short LP metadata'
    for name, g in (('geometry copy 1', g1), ('geometry copy 2', g2)):
        if struct.unpack_from('<I', g, 0)[0] != LP_GEOM_MAGIC:
            return f'{name}: bad magic'
        raw = bytearray(g[:52])
        stored = bytes(raw[8:40])
        raw[8:40] = b'\0' * 32
        if hashlib.sha256(bytes(raw)).digest() != stored:
            return f'{name}: checksum mismatch'
    if struct.unpack_from('<I', hdr, 0)[0] != LP_HEADER_MAGIC:
        return 'LP header: bad magic'
    hdr_size = struct.unpack_from('<I', hdr, 8)[0]
    table_size = struct.unpack_from('<I', hdr, 44)[0]
    table_sha = hdr[48:80]
    if hdr_size < 128 or hdr_size > 4096 or table_size == 0 or table_size > (1 << 20):
        return 'LP header: implausible sizes'
    with open(path, 'rb') as f:
        f.seek(12288 + hdr_size)
        tables = f.read(table_size)
    if len(tables) != table_size:
        return 'LP header: short table read'
    if hashlib.sha256(tables).digest() != table_sha:
        return 'LP header: table checksum mismatch'
    return None


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    img = sys.argv[1]
    man = sys.argv[2] if len(sys.argv) > 2 else img + '.manifest.json'
    if not os.path.exists(man):
        raise SystemExit('missing manifest: ' + man)
    m = json.load(open(man))
    size = os.path.getsize(img)
    bad = 0
    print('super  : ' + img)
    lp_err = check_lp_metadata(img)
    if lp_err:
        print('FAIL   : ' + lp_err)
        bad += 1
    else:
        print('OK     : LP geometry/header/table checksum')
    print('size   : %d bytes (%.3f GiB)' % (size, size / 2**30))
    print('used   : %d bytes (%.3f GiB)' % (m['used_end'], m['used_end'] / 2**30))
    if size != m['used_end']:
        print('FAIL   : file size != manifest used_end (%d != %d)' % (size, m['used_end']))
        bad += 1
    if m['used_end'] > m['linux_root_offset']:
        print('FAIL   : used_end past Linux root at %.0f GiB' % (m['linux_root_offset'] / 2**30))
        bad += 1
    else:
        print('guard  : %.0f GiB Linux root untouched' % (m['linux_root_offset'] / 2**30))
    for name, p in m['parts'].items():
        try:
            got = sha256_range(img, p['offset'], p['size'])
        except SystemExit as e:
            print('FAIL   : %s: %s' % (name, e))
            bad += 1
            continue
        ok = got == p['sha256']
        status = 'OK' if ok else 'FAIL'
        print('%-7s: %-18s off=%12d size=%12d sha256=%s...' %
              (status, name, p['offset'], p['size'], got[:16]))
        if not ok:
            bad += 1
    if bad:
        print('\n%d check(s) FAILED' % bad)
        return 1
    print('\nall partitions match the manifest')
    return 0


if __name__ == '__main__':
    sys.exit(main())
