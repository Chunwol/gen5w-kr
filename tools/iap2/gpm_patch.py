"""Generate native Android Auto HUD patch for HKMC_GPM.odex.

Bypasses the step-of-spec check in GalConnectionSession.<init> so that
GpmNaviTBTManager is unconditionally instantiated and started. This causes
GalConnectionSession to advertise NavigationStatusService to connected Android
phones, activating native turn-by-turn HUD guidance. OEM executable bytes are
never committed or distributed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
from control_patch import Dex, finalize

SESSION = 'Lcom/google/android/projection/service/GalConnectionSession;'
INIT = SESSION + '-><init>(Landroid/content/Context;Ljava/lang/String;Lcom/google/android/projection/service/GalConnectionManager;Lcom/google/android/projection/sink/audio/AudioFocusManager;Lcom/google/android/projection/sink/audio/MediaPlaybackInfo;)V'

def make_recipe(raw):
    dex = Dex(raw)
    if INIT not in dex.code:
        raise ValueError('GalConnectionSession.<init> not found in ODEX')
    offset = dex.code[INIT][0]
    registers, ins, outs, tries, _, count = struct.unpack_from('<HHHHII', dex.data, offset)
    words = list(struct.unpack_from('<' + 'H' * count, dex.data, offset + 16))

    # Find the step-of-spec check:
    # invoke Lcom/google/android/projection/sink/d/d;->bJ()I
    # move-result v0
    # const/16 v3, 0x03e7 (999)
    # if-ne / if-lt v0, v3, target
    patch_pos = None
    for i in range(count - 9):
        if words[i] & 0xff == 0x71:
            mid = words[i+1]
            if mid < len(dex.methods) and dex.methods[mid] in {
                    'Lcom/google/android/projection/sink/d/d;->bJ()I',
                    'Lcom/google/android/projection/sink/d/d;->bG()I'}:
                # verify pattern: move-result, const/16 999, if
                if (words[i+3] & 0xff == 0x0a and
                    words[i+4] & 0xff == 0x13 and words[i+5] == 0x03e7 and
                    words[i+6] == 0x3034 and words[i+7] == 11 and
                    words[i+8] & 0xff == 0x22 and words[i+9] < len(dex.types) and
                    dex.types[words[i+9]] == 'Lcom/google/android/projection/sink/navigation/GpmNaviTBTManager;'):
                    # Both reviewed versions branch around this exact allocation.
                    # Do not accept a similarly named getter elsewhere.
                    patch_pos = i + 6
                    break

    if patch_pos is None:
        raise ValueError('stepofspec branch not found in GalConnectionSession.<init>')

    # Replace the conditional branch with 2 NOPs (4 bytes)
    absolute = dex.base + offset + 16 + patch_pos * 2
    patches = [(absolute, b'\x00\x00\x00\x00')]

    recipe, result = finalize(raw, dex, patches, [SESSION])
    recipe['id'] = 'gpm-hud-enable-1'
    return recipe, result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('original', type=Path)
    parser.add_argument('recipe', type=Path)
    parser.add_argument('--private-output', type=Path)
    args = parser.parse_args()
    recipe, result = make_recipe(args.original.read_bytes())
    args.recipe.write_text(json.dumps(recipe, indent=2) + '\n', encoding='utf-8', newline='\n')
    if args.private_output:
        args.private_output.write_bytes(result)
    print('Generated HKMC_GPM native AA HUD recipe, original=' + recipe['original_sha256'])

if __name__ == '__main__':
    main()
