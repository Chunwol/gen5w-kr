"""Generate the independent call-key fallback without changing projection startup.

Only the missing-call-state branch in DipoService.i(II)V changes. The OEM wireless
receiver, its actions, stock session start path, and native transport remain intact.
OEM bytes are never emitted in a recipe.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zlib
from control_patch import Dex, finalize

RECEIVER = 'Lcom/daudio/app/dipo/service/y;'
SERVICE = 'Lcom/daudio/app/dipo/service/DipoService;'
CALL_MARKER = "onKeyForService() performPhoneKey Call Key - hasn't PTTKey during CarPlay Calling"


def instructions(words):
    """Decode instruction widths and branch metadata, including odex opcodes."""
    widths = [1] * 256
    for op in (2, 5, 8, 0x13, 0x15, 0x16, 0x19, 0x1a, 0x1c, 0x1f, 0x20, 0x22, 0x23, 0x29): widths[op] = 2
    for op in (3, 6, 9, 0x14, 0x17, 0x1b, 0x24, 0x25, 0x26, 0x2a, 0x2b, 0x2c): widths[op] = 3
    widths[0x18] = 5
    for start, end, size in ((0x2d, 0x3e, 2), (0x44, 0x6e, 2), (0x6e, 0x73, 3), (0x74, 0x79, 3), (0x90, 0xb0, 2), (0xd0, 0xec, 2), (0xf2, 0xf8, 2), (0xf8, 0xfc, 3), (0xfc, 0xff, 2)):
        for op in range(start, end): widths[op] = size
    widths[0xed] = 2
    for op in (0xee, 0xef, 0xf0): widths[op] = 3
    result = []
    pc = 0
    while pc < len(words):
        word = words[pc]; op = word & 255
        size = widths[op]
        if op == 0 and word:
            if word == 0x100: size = 4 + 2 * words[pc + 1]
            elif word == 0x200: size = 2 + 4 * words[pc + 1]
            elif word == 0x300:
                count = words[pc + 2] | words[pc + 3] << 16
                size = 4 + (words[pc + 1] * count + 1) // 2
            else: raise ValueError('unknown payload')
        if pc + size > len(words): raise ValueError('truncated instruction')
        result.append((pc, op, size)); pc += size
    return result


def signed(value, bits):
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def call_fallback(words, strings, fields):
    """Replace only the no-PTT call-state default with an authored if-gez.

    Normal 0..3 switch cases keep their original targets. Negative (missing)
    state falls through to the existing HookSwitch press/release block; unknown
    nonnegative states still return. No relocation or register changes.
    """
    decoded = instructions(words)
    markers = [pc for pc, op, _ in decoded if op == 0x1a and strings[words[pc+1]] == CALL_MARKER]
    if len(markers) != 1: raise ValueError('missing unique no-PTT call marker')
    switches = [pc for pc, op, _ in decoded if op == 0x2b and pc > markers[0]]
    if len(switches) != 1: raise ValueError('unsupported no-PTT call switches')
    pc = switches[0]
    payload = pc + signed(words[pc+1] | words[pc+2] << 16, 32)
    if payload < 0 or payload+12 > len(words) or list(words[payload:payload+4]) != [0x100, 4, 0, 0]:
        raise ValueError('unsupported call-state table')
    branch = pc+3
    if words[branch] != 0x29: raise ValueError('expected two-word call default goto')
    end = branch + signed(words[branch+1], 16)
    if not 0 <= end < len(words) or words[end] != 0x000e: raise ValueError('call default must return')
    target = pc + signed(words[payload+4] | words[payload+5] << 16, 32)
    if target != branch+2: raise ValueError('HookSwitch case is not adjacent')
    hook = 'Lcom/daudio/app/dipo/telechips/CarPlayTelephony;->HookSwitch:Lcom/daudio/app/dipo/telechips/CarPlayTelephony;'
    for start in (target, target+5):
        if words[start] != 0x62 or words[start+1] >= len(fields) or fields[words[start+1]] != hook:
            raise ValueError('call fallback does not load HookSwitch')
        if words[start+2] != 0x30f8: raise ValueError('unsupported telephony invocation')
    if words[target+3] != words[target+8] or words[target+4] != 0x408 or words[target+9] != 0x508:
        raise ValueError('HookSwitch press/release registers differ')
    if words[pc] >> 8 != 0: raise ValueError('unsupported call-state register')
    return branch, [0x003b, words[branch+1]] # if-gez v0, original return


def make_recipe(raw):
    dex = Dex(raw)
    call_offset = dex.code[SERVICE + '->i(II)V'][0]
    call_registers, call_ins, _, call_tries, _, call_count = struct.unpack_from('<HHHHII', dex.data, call_offset)
    if (call_registers, call_ins, call_tries) != (11, 3, 0):
        raise ValueError('unsupported call key frame')
    call_words = struct.unpack_from('<'+'H'*call_count, dex.data, call_offset+16)
    call_pc, own_branch = call_fallback(call_words, dex.strings, dex.fields)
    call_absolute = dex.base+call_offset+16+call_pc*2
    recipe,result=finalize(raw,dex,[(call_absolute,struct.pack('<HH',*own_branch))],[SERVICE])
    recipe['id']='dipo-call-key-fallback-1'
    return recipe,result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('original', type=Path)
    parser.add_argument('recipe', type=Path)
    parser.add_argument('--private-output', type=Path)
    args = parser.parse_args()
    recipe, result = make_recipe(args.original.read_bytes())
    args.recipe.write_text(json.dumps(recipe, indent=2) + '\n', encoding='utf-8', newline='\n')
    if args.private_output: args.private_output.write_bytes(result)
    print('Generated call-key fallback recipe:', recipe['original_sha256'])


if __name__ == '__main__': main()
