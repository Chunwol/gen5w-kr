"""Execute the authored AP adapter with a minimal independent instruction VM.
Optional private files rebuild exact recipes and validate unchanged other code.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools/hotspot'))
from profile_patch import Dex, make_recipe, METHOD


def execute(recipe, config, props, deny=False, native_failure=False):
    body = bytes(recipe['patches'][0]['bytes'])
    regs, ins, outs, tries, debug, size = struct.unpack_from('<HHHHII', body)
    assert (regs, ins, outs, tries, debug, size) == (14, 3, 3, 2, 0, 299)
    code = struct.unpack_from('<299H', body, 16)
    refs = recipe['refs']; r = {11: 'service', 12: copy.deepcopy(config), 13: 'wlan0'}
    original = copy.deepcopy(r[12]); calls = []; commands = []; pc = 0; result = None
    def signed(value): return value-65536 if value >= 32768 else value
    for _ in range(1000):
        word = code[pc]; op = word&255; a = word>>8
        if op == 0x12:
            value = word>>12; r[a&15] = value-16 if value >= 8 else value; pc += 1
        elif op == 0x13: r[a] = signed(code[pc+1]); pc += 2
        elif op == 0x1a: r[a] = refs['strings'][str(code[pc+1])]; pc += 2
        elif op == 0x07: r[a&15] = r[word>>12]; pc += 1
        elif op in (0x0c, 0x0a): r[a] = result; pc += 1
        elif op == 0x52:
            field = refs['fields'][str(code[pc+1])]
            assert r[word>>12] == 'service'
            r[a&15] = 'context' if 'mContext:' in field else 'connector'; pc += 2
        elif op in (0xf4, 0xf2):
            assert word>>12 == 12 and r[12] is not None
            r[a&15] = r[12][code[pc+1]]; pc += 2
        elif op in (0x32, 0x33):
            equal = r[a&15] == r[word>>12]
            pc += signed(code[pc+1]) if equal == (op == 0x32) else 2
        elif op in (0x34, 0x36):
            first, second = r[a&15], r[word>>12]
            take = first < second if op == 0x34 else first > second
            pc += signed(code[pc+1]) if take else 2
        elif op in (0x38, 0x39):
            zero = r[a] is None or r[a] == 0
            pc += signed(code[pc+1]) if zero == (op == 0x38) else 2
        elif op == 0x29: pc += signed(code[pc+1])
        elif op == 0x22:
            assert 'SensitiveArg;' in refs['types'][str(code[pc+1])]
            r[a] = {'sensitive': None}; pc += 2
        elif op == 0x23:
            assert refs['types'][str(code[pc+1])] == '[Ljava/lang/Object;'
            r[a&15] = [None]*r[word>>12]; pc += 2
        elif op == 0x4d:
            target = code[pc+1]&255; index = code[pc+1]>>8
            r[target][r[index]] = r[a]; pc += 2
        elif op in (0x6e, 0x70, 0x71):
            method = refs['methods'][str(code[pc+1])]
            packed = code[pc+2]; args = [r[(packed>>(4*i))&15] for i in range(word>>12)]
            calls.append(method)
            if 'enforceCallingOrSelfPermission' in method:
                assert args == ['context', 'android.permission.CONNECTIVITY_INTERNAL', 'NetworkManagementService']
                if deny: return 'denied', commands, calls
            elif 'wifiFirmwareReload' in method: assert args == ['service', 'wlan0', 'AP']
            elif 'getSecurityType' in method: result = args[0]['auth']
            elif 'SystemProperties;->get(' in method: result = props.get(args[0], args[1] if len(args)>1 else '')
            elif 'String;->isEmpty' in method: result = not bool(args[0])
            elif 'String;->equals' in method: result = args[0] == args[1]
            elif 'String;->length' in method: result = len(args[0])
            elif 'Integer;->parseInt' in method: result = int(args[0])
            elif 'Integer;->toString' in method: result = str(args[0])
            elif 'SensitiveArg;-><init>' in method: args[0]['sensitive'] = args[1]
            elif 'NativeDaemonConnector;->execute(' in method:
                if native_failure:
                    result = 'native-exception'; pc = recipe['labels']['catch']; continue
                assert args[:2] == ['connector', 'softap']; commands.append(copy.deepcopy(args[2]))
            elif 'rethrowAsParcelableException' in method: result = 'parcelable-exception'
            else: raise AssertionError(method)
            pc += 3
        elif op == 0x0d: r[a] = result; pc += 1
        elif op == 0x27: return r[a], commands, calls
        elif op == 0x0e:
            assert r[12] == original, 'caller configuration mutated'
            return 'ok', commands, calls
        else: raise AssertionError((pc, hex(op)))
    raise AssertionError('adapter did not terminate')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--private-root', type=Path)
    args = parser.parse_args(); checks = 0
    for version in ('v035', 'v039'):
        recipe = json.loads((ROOT/'tools/hotspot'/f'{version}.json').read_text())
        for mode in (0, 1, 2, 3):
            cfg = {0x14:'ordinary', 0x48:'ordinary-key', 0x78:mode,
                   0x9c:6, 0x94:11, 16:'carplay', 12:'carplay-key', 'auth':'wpa2-psk'}
            for factory in (False, True):
                for override in (False, True):
                    props = {'wifi.info.factory_ssid':'factory', 'wifi.info.factory_pw':'factory-key'} if factory else {}
                    if override: props.update({'wifi.info.channel':'3', 'wifi.info.auth':'force-open'})
                    result, commands, _ = execute(recipe, cfg, props)
                    assert result == 'ok' and len(commands) == 2
                    expected = 'carplay' if mode == 2 and not override else ('factory' if factory and not override else 'ordinary')
                    expected_key = 'carplay-key' if mode == 2 and not override else ('factory-key' if factory and not override else 'ordinary-key')
                    assert commands[0] == ['set', 'wlan0', {'sensitive':expected}, 'broadcast',
                        '3' if override else ('6' if mode == 0 else '11'),
                        'open' if override else 'wpa2-psk', {'sensitive':expected_key}]
                    assert commands[1] == ['startap']; checks += 1
        result, commands, _ = execute(recipe, None, {})
        assert result == 'ok' and commands == [['set', 'wlan0'], ['startap']]; checks += 1
        result, commands, calls = execute(recipe, None, {}, deny=True)
        assert result == 'denied' and not commands and len(calls) == 1; checks += 1
        result, commands, _ = execute(recipe, None, {}, native_failure=True)
        assert result == 'parcelable-exception' and not commands; checks += 1
        for ssid, key in ((None,None), ('','carplay-key'), ('cp',None), ('cp','short'), ('cp','x'*64)):
            cfg = {0x14:'ordinary', 0x48:'ordinary-key', 0x78:2, 0x9c:6, 0x94:11,
                   16:ssid, 12:key, 'auth':'wpa2-psk'}
            for factory in (False, True):
                props = {'wifi.info.factory_ssid':'factory', 'wifi.info.factory_pw':'factory-key'} if factory else {}
                result, commands, _ = execute(recipe, cfg, props)
                assert result == 'ok' and commands[0][2] == {'sensitive':'factory' if factory else 'ordinary'}
                assert commands[0][6] == {'sensitive':'factory-key' if factory else 'ordinary-key'}
                checks += 1
        for auth in ('open', 'wpa-psk'):
            cfg = {0x14:'ordinary', 0x48:'ordinary-key', 0x78:2, 0x9c:6, 0x94:11,
                   16:'cp', 12:'carplay-key', 'auth':auth}
            for factory in (False, True):
                props = {'wifi.info.factory_ssid':'factory', 'wifi.info.factory_pw':'factory-key'} if factory else {}
                result, commands, _ = execute(recipe, cfg, props)
                assert result == 'ok' and commands[0][2] == {'sensitive':'factory' if factory else 'ordinary'}
                assert commands[0][5] == auth
                checks += 1
        if args.private_root:
            private = args.private_root/(version+'_stock/framework')
            raw = (private/'services.odex').read_bytes(); framework = (private/'framework.odex').read_bytes()
            derived, changed = make_recipe(raw, framework); assert derived == recipe
            dex = Dex(changed); old = Dex(raw)
            assert dex.methods == old.methods and dex.code == old.code
            assert changed[dex.base+12:dex.base+32] == hashlib.sha1(changed[dex.base+32:dex.base+dex.length]).digest()
            assert struct.unpack_from('<I',changed,dex.base+8)[0] == zlib.adler32(changed[dex.base+12:dex.base+dex.length])&0xffffffff
            deps = struct.unpack_from('<I', changed, 16)[0]
            opt, opt_size = struct.unpack_from('<II', changed, 24)
            assert struct.unpack_from('<I', changed, 36)[0] == zlib.adler32(changed[deps:opt+opt_size])&0xffffffff
            body = bytes(recipe['patches'][0]['bytes'])
            # Header + 299 code units + alignment + two try entries + one
            # typed handler ends at the next original aligned code item.
            assert len(body) == 640 and len(body)%4 == 0
            allowed = set()
            for patch in recipe['patches']: allowed.update(range(patch['offset'], patch['offset']+len(patch['bytes'])))
            assert all(a == b or i in allowed for i,(a,b) in enumerate(zip(raw,changed)))
            helper = ROOT/'packages/hotspot-match/bin'/f'hotspot-patch-{version}'
            with tempfile.TemporaryDirectory(prefix='gen5w-ap-private-') as tmp:
                source = Path(tmp)/'source'; output = Path(tmp)/'output'; source.write_bytes(raw)
                subprocess.run(['qemu-arm', str(helper), 'apply', str(source), str(output)], check=True)
                assert output.read_bytes() == changed
                subprocess.run(['qemu-arm', str(helper), 'patched', str(output)], check=True)
                assert subprocess.run(['qemu-arm', str(helper), 'apply', str(source), str(output)], capture_output=True).returncode != 0
                output.unlink(); source.write_bytes(b'unknown')
                assert subprocess.run(['qemu-arm', str(helper), 'apply', str(source), str(output)], capture_output=True).returncode != 0
                assert not output.exists()
            checks += 11
    print('PASS AP adapter:', checks, 'dispatch/privacy/exception/private-byte cases')


if __name__ == '__main__': main()
