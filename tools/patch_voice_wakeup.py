#!/usr/bin/env python3
"""Whitelist TB710FU/piano/yupei in VoiceAssist's offline wakeup asset.

The asset is a deflated JSON file inside a Xiaomi-signed priv-app.  Rebuilding
the APK would lose the platform certificate, so this rewrites the deflate
stream *in place* at the same compressed and uncompressed sizes.  The new JSON
is padded with spaces to the original length and the deflate stream is padded
with zero bytes to the original compressed length; zlib stops at the final
block and ignores the trailing bytes.  The two CRC32 fields are updated.

The list is lowered in entropy by replacing some old device entries with
duplicates of "piano"; this is what makes a 4-entry-larger JSON fit into the
same 226-byte deflate stream.
"""
import json
import struct
import sys
import zlib

sys.path.insert(0, __file__.rsplit('/', 1)[0])
from patch_apk_res import zip_entry_info


ENTRY = 'assets/voiceassist.ai.voice.trigger.config'
WANT = [('piano', 9), ('yupei', 9), ('TB710FU', 9)]


def build_json(raw, dups):
    arr = json.loads(raw)['cloudControl']
    out = []
    n = 0
    for i, e in enumerate(arr):
        if i < len(WANT):
            out.append({'device': WANT[i][0], 'os': WANT[i][1]})
        elif n < dups and i % 2 == 0:
            out.append({'device': 'piano', 'os': 9})
            n += 1
        else:
            out.append(e)
    return json.dumps({'cloudControl': out}, separators=(',', ':'))


def main():
    if len(sys.argv) != 3:
        raise SystemExit('usage: patch_voice_wakeup.py <in.apk> <out.apk>')
    src, dst = sys.argv[1:]
    data = bytearray(open(src, 'rb').read())
    info = zip_entry_info(bytes(data), ENTRY)
    if info['method'] != 8:
        raise SystemExit('voice asset is not deflated')
    off, csize, usize = info['data_off'], info['csize'], info['usize']

    # Extract the original asset through zipfile so we use the same bytes the
    # framework will see.
    import zipfile
    raw = zipfile.ZipFile(src).read(ENTRY)

    chosen = None
    for dups in range(4, 21):
        s = build_json(raw, dups)
        if len(s) > usize:
            continue
        s = s + ' ' * (usize - len(s))
        c = zlib.compressobj(9, zlib.DEFLATED, -15)
        comp = c.compress(s.encode()) + c.flush()
        if len(comp) <= csize:
            chosen = (s, comp, dups)
            break
    if chosen is None:
        raise SystemExit('could not fit the modified JSON into the original deflate stream')
    s, comp, dups = chosen
    comp = comp + b'\x00' * (csize - len(comp))
    data[off:off + csize] = comp
    crc = zlib.crc32(s.encode()) & 0xFFFFFFFF
    struct.pack_into('<I', data, info['crc_off'], crc)
    struct.pack_into('<I', data, info['lcrc_off'], crc)
    open(dst, 'wb').write(data)

    # Verify with Python's zip reader.  It uses zlib and should ignore the
    # zero padding after the final deflate block.
    got = zipfile.ZipFile(dst).read(ENTRY)
    if len(got) != usize or json.loads(got) != json.loads(s):
        raise SystemExit('verification failed after in-place asset patch')
    devices = {e['device'] for e in json.loads(got)['cloudControl']}
    print(f'patched {dst}: {ENTRY} ({usize}B/{csize}B, dups={dups}), '
          f'devices now include {sorted(d for d, _ in WANT if d in devices)}')


if __name__ == '__main__':
    main()
