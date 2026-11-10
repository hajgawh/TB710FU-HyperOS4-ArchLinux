#!/usr/bin/env python3
"""In-place APK resource patcher for TB710FU OS4 builds.

The system partition skips APK content-digest verification for preinstalled
apps, but the certificate (and therefore sharedUserId / signature permissions)
still has to survive.  Rewriting the zip with zipfile/zip strips the APK
Signing Block, so this tool edits the stored resources.arsc bytes directly
inside the original APK and fixes the two CRC32 fields.  Everything else,
including META-INF and the v3 signing block, is left untouched.

Usage:
    patch_apk_res.py <in.apk> <out.apk> --entry-id 0x5c --dimen rounded_corner_content_padding=10
    patch_apk_res.py <in.apk> <out.apk> --entry-id 0x5c --bool support_round_corner=true
"""
import argparse
import struct
import shutil
import zlib

RES_TABLE_TYPE = 0x0002
RES_STRING_POOL_TYPE = 0x0001
RES_TABLE_PACKAGE_TYPE = 0x0200
RES_TABLE_TYPE_TYPE = 0x0201

TYPE_DIMENSION = 0x05
TYPE_INT_BOOLEAN = 0x12

ANDROID_DIMENSION = 0


def chunks(buf, start=0, end=None):
    end = len(buf) if end is None else end
    p = start
    while p + 8 <= end:
        typ, hsz, size = struct.unpack_from('<HHI', buf, p)
        if size < 8 or p + size > end:
            break
        yield typ, hsz, size, p
        p += size


def find_package(buf):
    if len(buf) < 12:
        raise SystemExit('resources.arsc: too short')
    typ, hsz, size = struct.unpack_from('<HHI', buf, 0)
    if typ != RES_TABLE_TYPE:
        raise SystemExit('resources.arsc: not a resource table')
    for t, h, s, p in chunks(buf, hsz, min(size, len(buf))):
        if t == RES_TABLE_PACKAGE_TYPE:
            return p, h, s
    raise SystemExit('resources.arsc: package chunk not found')


def iter_types(buf, pkg_start, pkg_hsz, pkg_end):
    for typ, hsz, size, p in chunks(buf, pkg_start + pkg_hsz, pkg_end):
        if typ == RES_TABLE_TYPE_TYPE:
            yield p, hsz, size


def entry_value_offset(buf, type_start, type_hsz, type_size, entry_index):
    """Return absolute offset of the Res_value.data field, or None."""
    (ttype, thsz, tsize, tid, tflags, treserved,
     entry_count, entries_start) = struct.unpack_from('<HHIBBHII', buf, type_start)
    if entry_index >= entry_count:
        return None
    off_pos = type_start + type_hsz + entry_index * 4
    if off_pos + 4 > type_start + type_size:
        return None
    ent_off = struct.unpack_from('<I', buf, off_pos)[0]
    if ent_off == 0xFFFFFFFF:
        return None
    ent = type_start + entries_start + ent_off
    esize, eflags = struct.unpack_from('<HH', buf, ent)
    if eflags & 1:          # FLAG_COMPLEX: not a simple value
        return None
    val = ent + esize
    vsize, vres0, vtype, vdata = struct.unpack_from('<HBBI', buf, val)
    return val + 4, vtype, vdata


def patch_scalar(buf, entry_index, new_type, new_data):
    pkg_start, pkg_hsz, pkg_size = find_package(buf)
    pkg_end = pkg_start + pkg_size
    hits = 0
    for tstart, thsz, tsize in iter_types(buf, pkg_start, pkg_hsz, pkg_end):
        r = entry_value_offset(buf, tstart, thsz, tsize, entry_index)
        if r is None:
            continue
        data_off, vtype, vdata = r
        struct.pack_into('<I', buf, data_off, new_data)
        struct.pack_into('<B', buf, data_off - 1, new_type)
        hits += 1
    return hits


def parse_bool(s):
    return 0xFFFFFFFF if s.lower() in ('1', 'true', 'yes', 'on') else 0


def parse_dimen_px(s):
    s = s.strip().lower()
    if s.endswith('px'):
        s = s[:-2]
    if s.endswith('dp'):
        raise SystemExit('dp values are density dependent; pass px for an in-place patch')
    return float(s)


def zip_entry_info(apk, name):
    data = memoryview(apk)
    # local header: find via central directory (authoritative)
    eocd = apk.rfind(b'PK\x05\x06')
    if eocd < 0:
        raise SystemExit('not a zip')
    cd_size, cd_off = struct.unpack_from('<II', apk, eocd + 12)
    p = cd_off
    while p < cd_off + cd_size:
        if apk[p:p + 4] != b'PK\x01\x02':
            raise SystemExit('bad central directory')
        (sig, ver_made, ver_need, flags, method, mtime, mdate, crc,
         csize, usize, nlen, elen, clen, disk, iattr, eattr,
         local_off) = struct.unpack_from('<IHHHHHHIIIHHHHHII', apk, p)
        fname = apk[p + 46:p + 46 + nlen].decode('utf-8', 'replace')
        if fname == name:
            local = local_off
            if apk[local:local + 4] != b'PK\x03\x04':
                raise SystemExit('bad local header')
            lcrc_off = local + 14
            lcsize_off = local + 18
            lusize_off = local + 22
            lnlen, lelen = struct.unpack_from('<HH', apk, local + 26)
            data_off = local + 30 + lnlen + lelen
            return {
                'crc_off': p + 16, 'lcrc_off': lcrc_off,
                'csize_off': p + 20, 'lcsize_off': lcsize_off,
                'usize_off': p + 24, 'lusize_off': lusize_off,
                'csize': csize, 'usize': usize, 'method': method,
                'data_off': data_off,
            }
        p += 46 + nlen + elen + clen
    raise SystemExit(f'{name}: entry not found')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src')
    ap.add_argument('dst')
    ap.add_argument('--dimen', action='append', default=[])
    ap.add_argument('--bool', action='append', default=[])
    ap.add_argument('--entry-id', type=lambda x: int(x, 0), required=True,
                    help='resource entry index, e.g. 0x5c for 0x7f03005c')
    args = ap.parse_args()

    shutil.copyfile(args.src, args.dst)
    apk = bytearray(open(args.dst, 'rb').read())
    ent = zip_entry_info(bytes(apk), 'resources.arsc')
    if ent['method'] != 0:
        raise SystemExit('resources.arsc is compressed; in-place patch unsupported')
    arsc_off = ent['data_off']
    arsc_size = ent['usize']
    arsc = bytearray(apk[arsc_off:arsc_off + arsc_size])

    changed = False
    for spec in args.dimen:
        name, val = spec.split('=', 1)
        px = parse_dimen_px(val)
        # Res_value stores dimensions as 24.8 fixed point (px * 256).
        data = int(round(px * 256))
        n = patch_scalar(arsc, args.entry_id, TYPE_DIMENSION, data)
        print(f'dimen {name} -> {px:g}px ({n} config(s))')
        changed |= n > 0
    for spec in args.bool:
        name, val = spec.split('=', 1)
        n = patch_scalar(arsc, args.entry_id, TYPE_INT_BOOLEAN, parse_bool(val))
        print(f'bool {name} -> {val} ({n} config(s))')
        changed |= n > 0
    if not changed:
        raise SystemExit('nothing patched (wrong entry id?)')

    apk[arsc_off:arsc_off + arsc_size] = arsc
    crc = zlib.crc32(arsc) & 0xFFFFFFFF
    struct.pack_into('<I', apk, ent['crc_off'], crc)
    struct.pack_into('<I', apk, ent['lcrc_off'], crc)
    open(args.dst, 'wb').write(apk)
    print(f'patched {args.dst} (crc={crc:08x})')


if __name__ == '__main__':
    main()
