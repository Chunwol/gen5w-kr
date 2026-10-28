"""Generate an authored dispatch inside one stock DiPO receiver branch.

The existing wireless action body and one missing-call-state branch change. Receiver
registration, comparison, other actions, stock creation/start methods and native
transport logic remain byte-identical. OEM bytes are never emitted in a recipe.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zlib
from control_patch import Dex, finalize

ACTION = 'com.daudio.app.dipo.carplaymagiccode.wireless'
NEXT_ACTION = 'com.daudio.app.dipo.carplaymagiccode.routeguidance'
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


def locate_body(words, strings):
    decoded = instructions(words)
    matches = [pc for pc, op, _ in decoded if op == 0x1a and strings[words[pc + 1]] == ACTION]
    if len(matches) != 1: raise ValueError('wireless action must be unique')
    action = matches[0]
    # Stock metadata must identify String.equals via execute-inline #3, then
    # move-result and an if-eqz that skips this whole inner body.
    if words[action + 2] & 255 != 0xee or words[action + 3] != 3 or words[action + 5] & 255 != 0x0a or words[action + 6] & 255 != 0x38:
        raise ValueError('unsupported wireless action comparison')
    if words[action + 5] >> 8 != words[action + 6] >> 8:
        raise ValueError('comparison register mismatch')
    branch = action + 6
    begin, end = branch + 2, branch + signed(words[branch + 1], 16)
    boundaries = {pc for pc, _, _ in decoded}
    if begin not in boundaries or end not in boundaries or end <= begin:
        raise ValueError('invalid matched body extent')
    if words[end] & 255 != 0x1a or strings[words[end + 1]] != NEXT_ACTION:
        raise ValueError('next receiver action differs')
    for pc, op, _ in decoded:
        if begin <= pc < end: continue
        targets = []
        if op == 0x28: targets.append(pc + signed(words[pc] >> 8, 8))
        elif op == 0x29 or 0x32 <= op <= 0x3d: targets.append(pc + signed(words[pc + 1], 16))
        elif op == 0x2a: targets.append(pc + signed(words[pc + 1] | words[pc + 2] << 16, 32))
        elif op in (0x2b, 0x2c):
            payload = pc + signed(words[pc + 1] | words[pc + 2] << 16, 32)
            count = words[payload + 1]
            start = payload + (4 if op == 0x2b else 2 + 2 * count)
            targets.extend(pc + signed(words[start + 2 * i] | words[start + 2 * i + 1] << 16, 32) for i in range(count))
        if any(begin <= target < end for target in targets):
            raise ValueError('another receiver branch enters replaced body')
    return begin, end


def dispatch_words(receiver, field, start_method, capacity):
    if not 0 <= receiver <= 15: raise ValueError('receiver outside iget register encoding')
    words = [0x54 | receiver << 12, field, 0x0112,
             0x206e, start_method, 0x0010, 0x000e]
    if capacity < len(words): raise ValueError('insufficient matched body extent')
    return words + [0] * (capacity - len(words))


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
    name = RECEIVER + '->onReceive(Landroid/content/Context;Landroid/content/Intent;)V'
    offset = dex.code[name][0]
    registers, ins, outs, tries, _, count = struct.unpack_from('<HHHHII', dex.data, offset)
    if ins != 3 or registers < ins or outs < 2 or tries:
        raise ValueError('unsupported receiver frame/exception table')
    words = list(struct.unpack_from('<' + 'H' * count, dex.data, offset + 16))
    begin, end = locate_body(words, dex.strings)
    field_count, field_offset = struct.unpack_from('<II', dex.data, 80)
    fields = []
    for i in range(field_count):
        owner, kind, label = struct.unpack_from('<HHI', dex.data, field_offset + i * 8)
        fields.append((dex.types[owner], dex.strings[label], dex.types[kind]))
    field = fields.index((RECEIVER, 'R', SERVICE))
    start_method = dex.methods.index(SERVICE + '->I(Z)V')
    own = dispatch_words(registers - ins, field, start_method, end - begin)
    body = struct.pack('<' + 'H' * len(own), *own)
    absolute = dex.base + offset + 16 + begin * 2
    call_offset = dex.code[SERVICE + '->i(II)V'][0]
    call_registers, call_ins, _, call_tries, _, call_count = struct.unpack_from('<HHHHII', dex.data, call_offset)
    if (call_registers, call_ins, call_tries) != (11, 3, 0):
        raise ValueError('unsupported call key frame')
    call_words = struct.unpack_from('<'+'H'*call_count, dex.data, call_offset+16)
    call_pc, own_branch = call_fallback(call_words, dex.strings, dex.fields)
    call_absolute = dex.base+call_offset+16+call_pc*2
    recipe,result=finalize(raw,dex,[(absolute,body),
        (call_absolute,struct.pack('<HH',*own_branch))],[RECEIVER,SERVICE])
    recipe['id']='dipo-wireless-start-call-2'
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
    print('Generated own DiPO inner-branch dispatch:', recipe['original_sha256'])


if __name__ == '__main__': main()
