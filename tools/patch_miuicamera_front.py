#!/usr/bin/env python3
"""Patch MiuiCamera.apk so getFrontCameraId() falls back to camera 1.

Xiaomi's camera app resolves camera roles only from the Xiaomi vendor tags
com.xiaomi.cameraid.role.cameraId(s).  The ZUI/QTI camera HAL on TB710FU does
not publish those tags, so the role map stays empty and getFrontCameraId()
returns -1; the switch-camera path then tries to open camera -1 and the app
bails out, leaving the front camera unreachable.

The QTI HAL does expose the front camera as id 1 (verified with an NDK
camera2 client and with this patch running on the device).  s6.e.A()I compiles
SparseIntArray.get(1, -1); flipping that default to 1 makes the role-map miss
fall back to camera 1.

The edit is one byte inside a dex (the const/4 high byte), so the APK is
modified in place: dex checksum/signature and the ZIP entry CRC are updated,
and everything else -- including the APK Signing Block -- is preserved.
System-partition APKs run with skipVerify, so the certificate stays valid.

Usage: patch_miuicamera_front.py MiuiCamera.apk [output.apk]
       (omit output to patch in place)
"""
import hashlib
import os
import struct
import sys
import tempfile
import zlib


def uleb128(buf, off):
    result = shift = 0
    while True:
        b = buf[off]
        off += 1
        result |= (b & 0x7F) << shift
        if not b & 0x80:
            return result, off
        shift += 7


def parse_header(buf):
    return dict(
        string_ids_size=struct.unpack_from('<I', buf, 56)[0],
        string_ids_off=struct.unpack_from('<I', buf, 60)[0],
        type_ids_size=struct.unpack_from('<I', buf, 64)[0],
        type_ids_off=struct.unpack_from('<I', buf, 68)[0],
        proto_ids_size=struct.unpack_from('<I', buf, 72)[0],
        proto_ids_off=struct.unpack_from('<I', buf, 76)[0],
        method_ids_size=struct.unpack_from('<I', buf, 88)[0],
        method_ids_off=struct.unpack_from('<I', buf, 92)[0],
        class_defs_size=struct.unpack_from('<I', buf, 96)[0],
        class_defs_off=struct.unpack_from('<I', buf, 100)[0],
    )


def get_string(buf, h, idx):
    off = struct.unpack_from('<I', buf, h['string_ids_off'] + idx * 4)[0]
    _, off = uleb128(buf, off)
    end = buf.find(b'\0', off)
    return buf[off:end].decode('utf-8', 'replace')


def get_type(buf, h, idx):
    return get_string(buf, h, struct.unpack_from('<I', buf, h['type_ids_off'] + idx * 4)[0])


def get_method(buf, h, idx):
    off = h['method_ids_off'] + idx * 8
    cls_idx, _proto_idx, name_idx = struct.unpack_from('<HHI', buf, off)
    return get_type(buf, h, cls_idx), get_string(buf, h, name_idx)


def parse_class_data(buf, off):
    sf, off = uleb128(buf, off)
    inf, off = uleb128(buf, off)
    dm, off = uleb128(buf, off)
    vm, off = uleb128(buf, off)
    for _ in range(sf + inf):  # static + instance fields
        _, off = uleb128(buf, off)
        _, off = uleb128(buf, off)
    methods = []
    for kind, count in (('direct', dm), ('virtual', vm)):
        idx = 0
        for _ in range(count):
            delta, off = uleb128(buf, off)
            idx += delta
            _acc, off = uleb128(buf, off)
            code_off, off = uleb128(buf, off)
            methods.append((kind, idx, code_off))
    return methods


def find_front_camera_default(buf):
    """Return (status, dex_offset, register) for Ls6/e;.A()I's role fallback."""
    h = parse_header(buf)
    for i in range(h['class_defs_size']):
        off = h['class_defs_off'] + i * 32
        class_idx = struct.unpack_from('<I', buf, off)[0]
        if get_type(buf, h, class_idx) != 'Ls6/e;':
            continue
        class_data_off = struct.unpack_from('<I', buf, off + 24)[0]
        for _kind, method_idx, code_off in parse_class_data(buf, class_data_off):
            cls, name = get_method(buf, h, method_idx)
            if cls != 'Ls6/e;' or name != 'A' or not code_off:
                continue
            _regs, _ins, _outs, _tries, _dbg, size = struct.unpack_from('<HHHHII', buf, code_off)
            ioff = code_off + 16
            for j in range(size - 2):
                off = ioff + j * 2
                cu0, cu1, cu2 = struct.unpack_from('<HHH', buf, off)
                if (cu0 & 0xFF) != 0x6E:  # invoke-kind
                    continue
                mcls, mname = get_method(buf, h, cu1)
                if mcls != 'Landroid/util/SparseIntArray;' or mname != 'get':
                    continue
                nargs = cu0 >> 12  # 35c: A = argument word count
                regs = [(cu2 >> (4 * k)) & 0xF for k in range(nargs)]
                if len(regs) != 3:
                    continue
                default_reg = regs[2]
                for k in range(j - 1, -1, -1):
                    c = struct.unpack_from('<H', buf, ioff + k * 2)[0]
                    if (c & 0xFF) != 0x12:  # const/4
                        continue
                    reg = (c >> 8) & 0xF
                    lit = (c >> 12) & 0xF
                    lit = lit - 16 if lit >= 8 else lit
                    if reg != default_reg:
                        continue
                    if lit == -1:
                        return ('todo', ioff + k * 2 + 1, default_reg)
                    if lit == 1:
                        return ('done', ioff + k * 2 + 1, default_reg)
                    raise SystemExit(f'const/4 v{reg}, #{lit} is neither -1 nor 1')
    return (None, None, None)


def zip_dex_entries(data):
    """Yield (name, local_header_off, method, flags, csize, usize) for stored dex entries."""
    eocd = data.rfind(b'PK\x05\x06')
    if eocd < 0:
        raise SystemExit('not a ZIP: EOCD not found')
    cdir_off = struct.unpack_from('<I', data, eocd + 16)[0]
    cdir_size = struct.unpack_from('<I', data, eocd + 12)[0]
    pos, end = cdir_off, cdir_off + cdir_size
    while pos < end and data[pos:pos + 4] == b'PK\x01\x02':
        flags, method = struct.unpack_from('<HH', data, pos + 8)
        crc, csize, usize = struct.unpack_from('<III', data, pos + 16)
        nlen, elen, clen = struct.unpack_from('<HHH', data, pos + 28)
        name = data[pos + 46:pos + 46 + nlen].decode('utf-8', 'replace')
        lho = struct.unpack_from('<I', data, pos + 42)[0]
        if name.startswith('classes') and name.endswith('.dex'):
            yield name, lho, flags, method, csize, usize, crc, pos
        pos += 46 + nlen + elen + clen


def patch(apk_in, apk_out=None):
    data = bytearray(open(apk_in, 'rb').read())
    patched = None
    already = None
    for name, lho, flags, method, csize, usize, crc, cdir in zip_dex_entries(data):
        sig, _ver, _flag, method_h, _mt, _md, _crc_h, csize_h, usize_h, nlen, elen = \
            struct.unpack_from('<IHHHHHIIIHH', data, lho)
        if sig != 0x04034B50:
            raise SystemExit(f'{name}: bad local header')
        if method != 0 or method_h != 0:
            raise SystemExit(f'{name}: compressed dex, in-place patch impossible')
        if flags & 0x8:
            raise SystemExit(f'{name}: data descriptor, unsupported')
        if csize != usize or csize_h != usize_h:
            raise SystemExit(f'{name}: stored entry with csize != usize')
        start = lho + 30 + nlen + elen
        dex = data[start:start + usize]
        status, target, reg = find_front_camera_default(dex)
        if status == 'done':
            already = name
        elif status == 'todo':
            if patched:
                raise SystemExit('front-camera fallback found in more than one dex')
            # const/4 vA, #+1: high byte = A | (1 << 4)
            dex[target] = (reg & 0xF) | 0x10
            dex[12:32] = b'\0' * 20
            dex[12:32] = hashlib.sha1(bytes(dex[32:])).digest()
            struct.pack_into('<I', dex, 8, zlib.adler32(bytes(dex[12:])) & 0xFFFFFFFF)
            data[start:start + usize] = dex
            new_crc = zlib.crc32(bytes(dex)) & 0xFFFFFFFF
            struct.pack_into('<I', data, lho + 14, new_crc)
            struct.pack_into('<I', data, cdir + 16, new_crc)
            patched = name
            print(f'[camera] {name}: getFrontCameraId default -1 -> 1 '
                  f'(const/4 v{reg}, dex+0x{target:x}, crc 0x{new_crc:08x})')
    if patched:
        if apk_out:
            open(apk_out, 'wb').write(data)
            print(f'[camera] wrote {apk_out}')
        else:
            fd, tmp = tempfile.mkstemp(prefix=os.path.basename(apk_in) + '.',
                                       dir=os.path.dirname(apk_in))
            os.close(fd)
            try:
                open(tmp, 'wb').write(data)
                os.replace(tmp, apk_in)
            except BaseException:
                if os.path.exists(tmp):
                    os.remove(tmp)
                raise
            print(f'[camera] wrote {apk_in} (in place)')
        return True
    if already:
        print(f'[camera] {already}: already patched (default 1), nothing to do')
        return False
    raise SystemExit('Ls6/e;.A()I front-camera fallback not found')


def main():
    if len(sys.argv) not in (2, 3):
        raise SystemExit(__doc__)
    patch(sys.argv[1], sys.argv[2] if len(sys.argv) == 3 else None)


if __name__ == '__main__':
    main()
