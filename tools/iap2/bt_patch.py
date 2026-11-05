"""Create the Bluetooth session entry for the stock iAP2 server, from stock metadata.

Stock Iap2Service starts an iAP2 session only from its USB attach receiver;
onStartCommand ignores its intent. Like the legacy control shim, this swaps the
code_off of onStartCommand with the dormant debugTrigger() slot and puts our own
handler there. The handler only reacts to the two external transports the
Bluetooth bridge drives:

  extra com.telechips.android.iap2.component = 4 (Bluetooth CarPlay) or 5 (the
  CarPlay session's channel): setDeviceSerial(extra "serial"); receiveConnect(c)
  extra = -4 or -5: receiveDisconnect(c)
  anything else (no intent, no extra, USB values): nothing; START_STICKY as stock

It also enables the same two existing protocol capabilities as the route recipe
(Wi-Fi information, route guidance). Output recipes hold only authored
instructions, offsets and whole-file identities.
"""
import argparse
import json
from pathlib import Path
import struct

from control_patch import Dex, finalize, leb

SERVICE = 'Lcom/tcc/iap2server/Iap2Service;->'
INFO = 'Lcom/tcc/iap2server/Iap2InitInformationMsg;->'
COMPONENTS = (4, 5)


def handler(dex):
    """Words of the onStartCommand handler; registers v0/v1 scratch, v4 this, v5 intent."""
    def method(name): return dex.methods.index(name)

    def string(value):
        index = dex.strings.index(value)
        if index > 0xffff: raise ValueError('string index needs const-string/jumbo')
        return index

    getint = method('Landroid/content/Intent;->getIntExtra(Ljava/lang/String;I)I')
    getstring = method('Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;')
    serial = method(SERVICE + 'setDeviceSerial(Ljava/lang/String;)V')
    connect = method(SERVICE + 'receiveConnect(I)V')
    disconnect = method(SERVICE + 'receiveDisconnect(I)V')
    words, labels, branches = [], {}, []

    def emit(*values): words.extend(values)

    def branch(word, label, width=2):
        branches.append((len(words), label, width)); emit(word, *([0] * (width - 1)))

    def call(op, index, regs):
        emit(op | len(regs) << 12, index, sum(v << (4 * i) for i, v in enumerate(regs)))

    def const4(reg, value): emit(0x12 | reg << 8 | (value & 15) << 12)

    low, high = COMPONENTS
    branch(0x0538, 'end')                        # if-eqz v5, end
    emit(0x001a, string('com.telechips.android.iap2.component'))
    const4(1, 0)
    call(0x6e, getint, [5, 0, 1]); emit(0x000a)  # v0 = getIntExtra(key, 0)
    const4(1, low); branch(0x1034, 'stop')       # if-lt v0, v1 (4)
    const4(1, high); branch(0x1036, 'end')       # if-gt v0, v1 (5)
    emit(0x011a, string('serial'))               # const-string v1, "serial"
    call(0x6e, getstring, [5, 1]); emit(0x010c)  # move-result-object v1
    call(0x70, serial, [4, 1])
    call(0x70, connect, [4, 0])
    branch(0x0028, 'end', 1)                     # goto end
    labels['stop'] = len(words)
    emit(0x007b)                                 # neg-int v0, v0
    const4(1, low); branch(0x1034, 'end')
    const4(1, high); branch(0x1036, 'end')
    call(0x70, disconnect, [4, 0])
    labels['end'] = len(words)
    emit(0x1012, 0x000f)                         # const/4 v0, 1 (START_STICKY); return v0
    for pos, label, width in branches:
        offset = labels[label] - pos
        if width == 1:
            if not -128 <= offset < 128: raise ValueError('goto out of range')
            words[pos] |= (offset & 255) << 8
        else:
            words[pos + 1] = offset & 0xffff
    return words


def make_recipe(raw):
    dex = Dex(raw)
    old_start, start_operand, start_width = dex.code[SERVICE + 'onStartCommand(Landroid/content/Intent;II)I']
    old_debug, debug_operand, debug_width = dex.code[SERVICE + 'debugTrigger()V']
    words = handler(dex)

    def body(offset, registers, ins, instructions):
        _, _, _, tries, _, size = struct.unpack_from('<HHHHII', dex.data, offset)
        # Any original try items stay as unused bytes after insns (tries=0).
        if len(instructions) > size: raise ValueError('insufficient original method slot')
        return struct.pack('<HHHHII', registers, ins, 3, 0, 0, size) + \
            struct.pack('<' + 'H' * size, *(instructions + [0] * (size - len(instructions))))

    patches = [(dex.base + old_debug, body(old_debug, 8, 4, words)),
               (dex.base + old_start, body(old_start, 1, 1, [0x000e])),
               (dex.base + start_operand, leb(old_debug, start_width)),
               (dex.base + debug_operand, leb(old_start, debug_width))]
    cap, _, _ = dex.code[INFO + 'checkSupportsFeatures()V']
    cap_size = struct.unpack_from('<I', dex.data, cap + 12)[0]
    cap_words = struct.unpack_from('<' + 'H' * cap_size, dex.data, cap + 16)
    if cap_words[:2] != (0x0212, 0x1312): raise ValueError('capability constant registers changed')
    counts = {}
    for field in ('iAP2UsedWifiInformation', 'iAP2UsedRouteGuidance'):
        index = dex.fields.index(INFO + field + ':I'); counts[field] = 0
        for i in range(cap_size - 1):
            if cap_words[i] & 255 == 0x67 and cap_words[i + 1] == index:
                patches.append((dex.base + cap + 16 + i * 2, struct.pack('<H', 0x0367)))
                counts[field] += 1
    if counts != {'iAP2UsedWifiInformation': 1, 'iAP2UsedRouteGuidance': 3}:
        raise ValueError('unexpected capability assignments: ' + str(counts))
    recipe, result = finalize(raw, dex, patches, [SERVICE[:-2], INFO[:-2]])
    recipe['id'] = 'iap2-bt-session-1'
    return recipe, result


def main():
    p = argparse.ArgumentParser(); p.add_argument('original'); p.add_argument('recipe'); p.add_argument('--private-output')
    a = p.parse_args()
    recipe, result = make_recipe(Path(a.original).read_bytes())
    Path(a.recipe).write_text(json.dumps(recipe, indent=2) + '\n', encoding='utf-8', newline='\n')
    if a.private_output: Path(a.private_output).write_bytes(result)
    print('Generated Bluetooth session recipe, original=' + recipe['original_sha256'])


if __name__ == '__main__': main()
