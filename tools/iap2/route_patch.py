"""Create the hash-bound Wi-Fi/RouteGuidance capability-only ODEX recipe."""
import json
from pathlib import Path
import struct
import sys

from control_patch import Dex, finalize


def make_capability_recipe(raw):
    """Enable the two existing iAP2 capability bits without replacing service code."""
    dex = Dex(raw)
    info = 'Lcom/tcc/iap2server/Iap2InitInformationMsg;->'
    cap, _, _ = dex.code[info + 'checkSupportsFeatures()V']
    cap_size = struct.unpack_from('<I', dex.data, cap + 12)[0]
    cap_words = struct.unpack_from('<' + 'H' * cap_size, dex.data, cap + 16)
    if cap_words[:2] != (0x0212, 0x1312):
        raise ValueError('capability constant registers changed')

    patches = []
    counts = {}
    for field in ('iAP2UsedWifiInformation', 'iAP2UsedRouteGuidance'):
        index = dex.fields.index(info + field + ':I')
        counts[field] = 0
        for i in range(cap_size - 1):
            if cap_words[i] & 255 == 0x67 and cap_words[i + 1] == index:
                patches.append((dex.base + cap + 16 + i * 2, struct.pack('<H', 0x0367)))
                counts[field] += 1
    if counts != {'iAP2UsedWifiInformation': 1, 'iAP2UsedRouteGuidance': 3}:
        raise ValueError('unexpected capability assignments: ' + str(counts))

    return finalize(raw, dex, patches, [])


def main():
    if len(sys.argv) != 3:
        raise SystemExit('usage: route_patch.py STOCK_ODEX OUTPUT_JSON')
    source, output = map(Path, sys.argv[1:])
    recipe, _ = make_capability_recipe(source.read_bytes())
    output.write_text(json.dumps(recipe, indent=2) + '\n', encoding='utf-8', newline='\n')
    print('Generated capability-only recipe, original=' + recipe['original_sha256'])


if __name__ == '__main__':
    main()
