"""Derive a timer-only recipe from a privately supplied stock SystemUI ODEX.

No stock instructions are emitted. Only the authored 3000 ms operand, header
checksums and whole-file identities leave this process. Stock spec/visibility
checks, message handling and register maps are preserved byte for byte.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'iap2'))
from control_patch import Dex

METHODS = ('Lcom/android/systemui/consentscreen/F;->dS()V',
           'Lcom/android/systemui/consentscreen/F;->dP()V')


def make_recipe(raw, apk):
    dex = Dex(raw)
    names = [name for name in METHODS if name in dex.code]
    if len(names) != 1:
        raise ValueError('unknown stock timer method identity')
    method = names[0]
    start, _, _ = dex.code[method]
    count = struct.unpack_from('<I', dex.data, start + 12)[0]
    words = struct.unpack_from('<' + 'H' * count, dex.data, start + 16)
    # Exact instruction boundary facts verified privately for these two inputs:
    # const-wide/16 v0,10000 followed by the existing scheduling invocation.
    slots = [i for i in range(count - 4)
             if words[i:i+2] == (0x0016, 10000)
             and words[i+2] == 0x4070
             and dex.methods[words[i+3]] ==
             'Lcom/android/systemui/consentscreen/F;->a(IJ)V']
    if len(slots) != 1:
        raise ValueError('expected one stock consent timer scheduling operand')
    offset = dex.base + start + 16 + (slots[0] + 1) * 2
    changed = bytearray(raw)
    changed[offset:offset+2] = struct.pack('<H', 3000)
    signature = hashlib.sha1(changed[dex.base+32:dex.base+dex.length]).digest()
    changed[dex.base+12:dex.base+32] = signature
    checksum = struct.pack('<I', zlib.adler32(changed[dex.base+12:dex.base+dex.length]) & 0xffffffff)
    changed[dex.base+8:dex.base+12] = checksum
    # The ODEX dependencies/optimization sections were not modified, so their
    # checksum and GC maps remain valid. There is no control-flow/type change.
    recipe = {
        'original_sha256': hashlib.sha256(raw).hexdigest(),
        'patched_sha256': hashlib.sha256(changed).hexdigest(),
        'apk_sha256': hashlib.sha256(apk).hexdigest(),
        'method': method,
        'stock_delay_ms': 10000,
        'delay_ms': 3000,
        'patches': [{'offset': offset, 'bytes': [184, 11]},
                    {'offset': dex.base+8, 'bytes': list(checksum+signature)}],
    }
    return recipe, bytes(changed)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stock', type=Path, required=True)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    recipe, _ = make_recipe(args.stock.read_bytes(), args.apk.read_bytes())
    args.output.write_text(json.dumps(recipe, indent=2)+'\n', encoding='ascii', newline='\n')
