"""Create the hash-bound Wi-Fi/RouteGuidance capability-only ODEX recipe."""
import json
from pathlib import Path
import struct
import sys

from control_patch import Dex, finalize

RG_ITEM = 'Lcom/tcc/iap2server/Iap2InitInformationMsg$RouteGuidanceComponent$RouteGuidanceItem;'


def lane_ident_patches(dex):
    """Replace the Log.d debug block in getComponentInfo with lane params 7=64, 8=10."""
    target = RG_ITEM + '->getComponentInfo(Lcom/tcc/iap2/Iap2NotiMsg;)V'
    c, _, _ = dex.code[target]
    regs, ins, outs, tries, _, n = struct.unpack_from('<HHHHII', dex.data, c)
    words = struct.unpack_from('<' + 'H' * n, dex.data, c + 16)
    if regs < 10 or ins != 2 or outs < 4 or tries != 0 or n < 48:
        raise ValueError('unexpected getComponentInfo header')
    create_group = dex.methods.index(
        'Lcom/tcc/iap2/Iap2NotiMsg;->createIap2NotiObjGroup()Lcom/tcc/iap2/Iap2NotiMsg$Iap2ObjGroup;')
    log_d = dex.methods.index('Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I')
    if (words[0], words[1], words[2], words[11], words[12], words[14]) != (
            0x5712, 0x0612, 0x1512, 0x106e, create_group, 0x000c):
        raise ValueError('unexpected getComponentInfo register setup')
    if (words[15], words[18], words[19], words[40], words[41], words[42]) != (
            0x0071, 0x020c, 0x0322, 0x2071, log_d, 0x0032):
        raise ValueError('unexpected getComponentInfo Log.d block')
    if ((words[43] & 0xff) != 0x13 or (words[43] >> 8) != 2 or
            (words[45] & 0xff) != 0x23 or ((words[45] >> 8) & 15) != 3 or
            (words[47] & 0xff) != 0x54 or ((words[47] >> 8) & 15) != 4):
        raise ValueError('unexpected getComponentInfo post-Log.d clobber')
    int_arr = dex.types.index('[I')
    add_int = dex.methods.index('Lcom/tcc/iap2/Iap2NotiMsg$Iap2ObjGroup;->addObject(II[I)V')
    patch_words = [
        0x7212, 0x5323, int_arr, 0x0413, 0x0040, 0x044b, 0x0603, 0x406e, add_int, 0x3720,
        0x0213, 0x0008, 0x5323, int_arr, 0x0413, 0x000a, 0x044b, 0x0603, 0x406e, add_int, 0x3720,
        0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    ]
    return [(dex.base + c + 16 + 15 * 2, struct.pack('<' + 'H' * len(patch_words), *patch_words))]


def make_capability_recipe(raw):
    """Enable the two existing iAP2 capability bits and lane-guidance identification."""
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

    patches.extend(lane_ident_patches(dex))
    return finalize(raw, dex, patches, [RG_ITEM])


def main():
    if len(sys.argv) != 3:
        raise SystemExit('usage: route_patch.py STOCK_ODEX OUTPUT_JSON')
    source, output = map(Path, sys.argv[1:])
    recipe, _ = make_capability_recipe(source.read_bytes())
    output.write_text(json.dumps(recipe, indent=2) + '\n', encoding='utf-8', newline='\n')
    print('Generated capability-only recipe, original=' + recipe['original_sha256'])


if __name__ == '__main__':
    main()
