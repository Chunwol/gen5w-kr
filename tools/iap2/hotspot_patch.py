"""Exact V039 local-hotspot entry gates; no subscription/database changes."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
from control_patch import Dex, finalize
from dipo_patch import instructions, signed

ORIGINAL_SHA = '0cff4c10359f49a808340dcdc535c6de36f1d3f7f7d42fa8ce9eb4c498d58347'
CHECK = 'Lcom/hkmc/wifisettings/common/e;->s(Landroid/content/Context;)Z'
TARGETS = (
    'Lcom/hkmc/wifisettings/WifiHotspot;->onPreferenceTreeClick(Landroid/preference/PreferenceScreen;Landroid/preference/Preference;)Z',
    'Lcom/hkmc/wifisettings/service/a;->handleMessage(Landroid/os/Message;)V',
    'Lcom/hkmc/wifisettings/service/b;->handleMessage(Landroid/os/Message;)V',
)


def local_entry(words, check_index):
    decoded = instructions(words)
    calls = [pc for pc, op, _ in decoded if op == 0x71 and words[pc + 1] == check_index]
    if len(calls) != 1:
        raise ValueError('expected one CCS check at hotspot entry')
    call = calls[0]
    branch = call + 4
    if words[call + 3] & 255 != 0x0a:
        raise ValueError('expected boolean result')
    register = words[call + 3] >> 8
    if words[branch] != (register << 8 | 0x39):
        raise ValueError('expected CCS-allowed branch')
    target = branch + signed(words[branch + 1], 16)
    if target not in {pc for pc, _, _ in decoded} or target <= branch:
        raise ValueError('invalid allowed target')
    # Same-width goto/16 follows the existing local AP path. All later radio,
    # CarPlay/AA ownership and configuration checks remain untouched.
    return branch, [0x0029, words[branch + 1]]


def make_recipe(raw):
    if hashlib.sha256(raw).hexdigest() != ORIGINAL_SHA:
        raise ValueError('not the verified V039 WifiSettings ODEX')
    dex = Dex(raw)
    check = dex.methods.index(CHECK)
    patches = []
    classes = []
    for name in TARGETS:
        offset = dex.code[name][0]
        size = struct.unpack_from('<I', dex.data, offset + 12)[0]
        words = struct.unpack_from('<' + 'H' * size, dex.data, offset + 16)
        pc, replacement = local_entry(words, check)
        patches.append((dex.base + offset + 16 + 2 * pc, struct.pack('<HH', *replacement)))
        classes.append(name.split('->')[0])
    return finalize(raw, dex, patches, classes)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('stock', type=Path)
    parser.add_argument('--recipe', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    recipe, patched = make_recipe(args.stock.read_bytes())
    args.recipe.write_text(json.dumps(recipe, indent=2) + '\n', encoding='utf-8')
    args.output.write_bytes(patched)


if __name__ == '__main__':
    main()
