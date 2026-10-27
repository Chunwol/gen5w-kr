"""Author an AP command adapter in an existing exact-hash ODEX code slot.

Only protocol/signature/layout facts are read from stock metadata. The emitted
method is authored here; no OEM instructions or files are included in recipes.
Mode 2 uses Connectivity fields in command-local registers without writing the
WifiConfiguration object or its store. Original null/ordinary/factory/channel
and permission/exception behavior is retained.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'iap2'))
from control_patch import Dex, finalize, uleb

CLASS = 'Lcom/android/server/NetworkManagementService;'
METHOD = CLASS+'->startAccessPoint(Landroid/net/wifi/WifiConfiguration;Ljava/lang/String;)V'


def make_recipe(raw, framework):
    dex = Dex(raw)
    frame = Dex(framework)
    # Independently cross-check both private framework versions using labelled
    # quick reads in toString, not an assumed alphabetical object layout.
    off = frame.code['Landroid/net/wifi/WifiConfiguration;->toString()Ljava/lang/String;'][0]
    count = struct.unpack_from('<I', frame.data, off+12)[0]
    words = struct.unpack_from('<'+'H'*count, frame.data, off+16)
    offsets = {}
    for label in (' ConnectivitySSID: ', ' ConnectivityPSK: '):
        index = frame.strings.index(label)
        matches = [i for i in range(count-1) if words[i]&255 == 0x1a and words[i+1] == index]
        if len(matches) != 1:
            raise ValueError('unknown framework field evidence')
        pos = matches[0]+2
        found = [words[i+1] for i in range(pos, min(pos+12, count-1)) if words[i]&255 == 0xf4]
        if not found:
            raise ValueError('missing framework quick field evidence')
        offsets[label] = found[0]
    if offsets != {' ConnectivitySSID: ': 16, ' ConnectivityPSK: ': 12}:
        raise ValueError('unreviewed framework layout')
    code, _, _ = dex.code[METHOD]
    registers, ins, outs, tries, _, capacity = struct.unpack_from('<HHHHII', dex.data, code)
    if (registers, ins, outs, tries, capacity) != (14, 3, 3, 2, 299):
        raise ValueError('unknown AP method slot')
    # Validate existing standard field facts against the optimized method.
    old = struct.unpack_from('<299H', dex.data, code+16)
    for pair in ((0xc4f2, 0x9c), (0xc5f2, 0x78), (0xc4f2, 0x94),
                 (0xc9f4, 0x14), (0xcaf4, 0x48)):
        if not any(old[i:i+2] == pair for i in range(298)):
            raise ValueError('unknown standard profile layout')
    own, labels, branches = [], {}, []
    refs = {'methods': {}, 'fields': {}, 'strings': {}, 'types': {}}
    def ref(kind, name):
        pool = getattr(dex, kind)
        index = pool.index(name)
        refs[kind][str(index)] = name
        return index
    def emit(*values): own.extend(values)
    def label(name): labels[name] = len(own)
    def branch(op, target): branches.append((len(own), target)); emit(op, 0)
    def jump(target): branch(0x0029, target)
    def call(op, name, regs):
        if len(regs) > 4: raise ValueError('too many arguments')
        emit(op | len(regs)<<12, ref('methods', name),
             sum(reg << (4*i) for i, reg in enumerate(regs)))
    def string(reg, value): emit(0x1a | reg<<8, ref('strings', value))
    def constant(reg, value): emit(0x12 | reg<<8 | (value&15)<<12)
    def move(dst, src): emit(0x07 | dst<<8 | src<<12)
    def result(reg, obj=True): emit((0x0c if obj else 0x0a) | reg<<8)
    def quick(reg, offset, obj=True): emit((0xf4 if obj else 0xf2) | reg<<8 | 12<<12, offset)
    def getprop(dst, key, default=False):
        string(9, key)
        if default:
            string(10, '')
            call(0x71, 'Landroid/os/SystemProperties;->get(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;', [9, 10])
        else: call(0x71, 'Landroid/os/SystemProperties;->get(Ljava/lang/String;)Ljava/lang/String;', [9])
        result(dst)
    def empty(reg):
        call(0x6e, 'Ljava/lang/String;->isEmpty()Z', [reg]); result(10, False)
    def array(size):
        constant(7, size); emit(0x23 | 2<<8 | 7<<12, ref('types', '[Ljava/lang/Object;'))
    def put(index, reg): constant(7, index); emit(0x4d | reg<<8, 2 | 7<<8)
    def sensitive(source):
        emit(0x22 | 8<<8, ref('types', 'Lcom/android/server/NativeDaemonConnector$SensitiveArg;'))
        call(0x70, 'Lcom/android/server/NativeDaemonConnector$SensitiveArg;-><init>(Ljava/lang/Object;)V', [8, source])
    execute = 'Lcom/android/server/NativeDaemonConnector;->execute(Ljava/lang/String;[Ljava/lang/Object;)Lcom/android/server/NativeDaemonEvent;'
    # v11=this, v12=config, v13=interface. v0 connector, v1 command,
    # v2 arguments, v3 SSID, v4 key, v5 auth, v6 channel, v7..10 scratch.
    emit(0x52 | 11<<12, ref('fields', CLASS+'->mContext:Landroid/content/Context;'))
    string(1, 'android.permission.CONNECTIVITY_INTERNAL'); string(2, 'NetworkManagementService')
    call(0x6e, 'Landroid/content/Context;->enforceCallingOrSelfPermission(Ljava/lang/String;Ljava/lang/String;)V', [0, 1, 2])
    label('try')
    string(0, 'AP')
    call(0x6e, CLASS+'->wifiFirmwareReload(Ljava/lang/String;Ljava/lang/String;)V', [11, 13, 0])
    emit(0x52 | 11<<12, ref('fields', CLASS+'->mConnector:Lcom/android/server/NativeDaemonConnector;'))
    string(1, 'softap'); branch(0x38 | 12<<8, 'null')
    quick(3, 0x14); quick(4, 0x48); quick(6, 0x9c, False); quick(9, 0x78, False)
    branch(0x38 | 9<<8, 'channel')
    quick(6, 0x94, False)
    label('channel')
    label('security')
    call(0x71, CLASS+'->getSecurityType(Landroid/net/wifi/WifiConfiguration;)Ljava/lang/String;', [12]); result(5)
    getprop(9, 'wifi.info.channel'); empty(9); branch(0x39 | 10<<8, 'auth')
    call(0x71, 'Ljava/lang/Integer;->parseInt(Ljava/lang/String;)I', [9]); result(6, False)
    label('auth')
    getprop(9, 'wifi.info.auth'); empty(9); branch(0x39 | 10<<8, 'factory')
    string(5, 'open'); jump('args')
    label('factory')
    # All callers, including OEM callers outside our Java controller, retain
    # stock behavior unless security and CP credentials are independently valid.
    string(8, 'wpa2-psk')
    call(0x6e, 'Ljava/lang/String;->equals(Ljava/lang/Object;)Z', [8, 5]); result(8, False)
    branch(0x38 | 8<<8, 'factoryprops')
    quick(9, 0x78, False)
    constant(10, 2); branch(0x33 | 9<<8 | 10<<12, 'factoryprops')
    quick(9, 16); quick(10, 12)
    branch(0x38 | 9<<8, 'factoryprops'); branch(0x38 | 10<<8, 'factoryprops')
    call(0x6e, 'Ljava/lang/String;->isEmpty()Z', [9]); result(8, False)
    branch(0x39 | 8<<8, 'factoryprops')
    call(0x6e, 'Ljava/lang/String;->length()I', [10]); result(8, False)
    emit(0x13 | 7<<8, 8); branch(0x34 | 8<<8 | 7<<12, 'factoryprops')
    emit(0x13 | 7<<8, 63); branch(0x36 | 8<<8 | 7<<12, 'factoryprops')
    move(3, 9); move(4, 10); jump('args')
    label('factoryprops')
    getprop(7, 'wifi.info.factory_ssid', True)
    getprop(9, 'wifi.info.factory_pw', True)
    empty(7); branch(0x39 | 10<<8, 'args')
    empty(9); branch(0x39 | 10<<8, 'args')
    move(3, 7); move(4, 9)
    label('args')
    array(7); string(8, 'set'); put(0, 8); put(1, 13)
    # SensitiveArg suppresses both SSID and key in connector diagnostic logs.
    sensitive(3); put(2, 8); string(8, 'broadcast'); put(3, 8)
    call(0x71, 'Ljava/lang/Integer;->toString(I)Ljava/lang/String;', [6]); result(8); put(4, 8)
    put(5, 5); sensitive(4); put(6, 8)
    call(0x6e, execute, [0, 1, 2]); jump('start')
    label('null')
    array(2); string(8, 'set'); put(0, 8); put(1, 13); call(0x6e, execute, [0, 1, 2])
    label('start')
    array(1); string(8, 'startap'); put(0, 8); call(0x6e, execute, [0, 1, 2])
    label('endtry'); emit(0x000e)
    label('catch'); emit(0x000d)
    call(0x6e, 'Lcom/android/server/NativeDaemonConnectorException;->rethrowAsParcelableException()Ljava/lang/IllegalArgumentException;', [0])
    result(0); emit(0x0027)
    for pos, target in branches:
        own[pos+1] = (labels[target]-pos)&65535
    if len(own) > capacity: raise ValueError('authored adapter exceeds original slot')
    # Keep all code_item/data offsets fixed, including the original two try
    # entries so subsequent aligned code items retain their exact position.
    # Both regions share one freshly authored typed exception handler.
    def enc(value):
        data=[]
        while value > 127: data.append((value&127)|128); value >>= 7
        return bytes(data+[value])
    handler = b'\x01\x01'+enc(ref('types', 'Lcom/android/server/NativeDaemonConnectorException;'))+enc(labels['catch'])
    body = struct.pack('<HHHHII',14,3,3,2,0,capacity)
    body += struct.pack('<299H', *(own+[0]*(capacity-len(own))))+b'\0\0'
    body += struct.pack('<IHH',labels['try'], labels['args']-labels['try'], 1)
    body += struct.pack('<IHH',labels['args'], labels['endtry']-labels['args'], 1)+handler
    # The next original code item bounds this existing code slot.
    bound = min(value[0] for value in dex.code.values() if value[0] > code)
    if len(body) > bound-code: raise ValueError('typed catch exceeds original slot')
    body += bytes(bound-code-len(body))
    recipe, changed = finalize(raw, dex, [(dex.base+code, body)], [CLASS])
    recipe.update(framework_sha256=hashlib.sha256(framework).hexdigest(),
                  method=METHOD, authored_code_units=len(own), labels=labels,
                  field_offsets={'ConnectivitySSID':16, 'ConnectivityPSK':12}, refs=refs)
    return recipe, changed


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stock', type=Path, required=True)
    parser.add_argument('--framework', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    recipe, _ = make_recipe(args.stock.read_bytes(), args.framework.read_bytes())
    args.output.write_text(json.dumps(recipe, indent=2)+'\n', encoding='ascii', newline='\n')
