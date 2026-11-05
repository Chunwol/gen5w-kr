"""Structural dispatch and integrity checks for the V039 BT recipe."""
import json
import argparse
import hashlib
from pathlib import Path
import struct
import sys
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/iap2'))
from control_patch import Dex
from bt_patch import make_recipe

PRIVATE_STOCK = None


def release_recipe(version):
    if version != 'v039':
        raise ValueError('BT relay release supports exact V039 only')
    return json.loads((ROOT / 'tools/iap2/bt-v039.json').read_text())


def execute_bt(data, intent):
    """Execute the authored dispatch body with the exact V039 table indexes."""
    registers, ins, outs, tries, debug, count = struct.unpack_from('<HHHHII', data)
    assert (registers, ins, outs, tries, debug, count) == (8, 4, 3, 0, 0, 41)
    words = struct.unpack_from('<' + 'H' * count, data, 16)
    registers = {4: 'service', 5: intent}
    serial = None
    result = None
    calls = []
    pc = 0
    for _ in range(100):
        word = words[pc]
        op = word & 0xff
        if op == 0x38:  # if-eqz
            delta = struct.unpack('<h', struct.pack('<H', words[pc + 1]))[0]
            pc += delta if not registers.get((word >> 8) & 0xf) else 2
        elif op == 0x1a:  # const-string
            index = words[pc + 1]
            registers[(word >> 8) & 0xff] = {0x83c: 'component', 0xe62: 'serial'}[index]
            pc += 2
        elif op == 0x12:  # const/4
            value = (word >> 12) & 0xf
            registers[(word >> 8) & 0xf] = value - 16 if value & 8 else value
            pc += 1
        elif op in (0x6e, 0x70):  # invoke-virtual/direct
            argc = word >> 12
            packed = words[pc + 2]
            args = [registers[(packed >> (4 * i)) & 0xf] for i in range(argc)]
            method = words[pc + 1]
            if method == 47:
                result = args[0].get(args[1], args[2]) if args[0] is not None else args[2]
            elif method == 49:
                result = args[0].get(args[1]) if args[0] is not None else None
            elif method == 1732:
                serial = args[1]
                calls.append(('serial', serial))
            elif method == 1718:
                calls.append(('connect', args[1]))
            elif method == 1719:
                calls.append(('disconnect', args[1]))
            else:
                raise AssertionError('unexpected V039 method index: ' + str(method))
            pc += 3
        elif op in (0x0a, 0x0c):  # move-result / move-result-object
            registers[(word >> 8) & 0xff] = result
            pc += 1
        elif op in (0x34, 0x36):  # if-lt / if-gt
            left = registers[(word >> 8) & 0xf]
            right = registers[(word >> 12) & 0xf]
            delta = struct.unpack('<h', struct.pack('<H', words[pc + 1]))[0]
            take = left < right if op == 0x34 else left > right
            pc += delta if take else 2
        elif op == 0x7b:  # neg-int
            dest = (word >> 8) & 0xf
            source = (word >> 12) & 0xf
            registers[dest] = -registers[source]
            pc += 1
        elif op == 0x28:  # goto/8
            delta = struct.unpack('<b', bytes([(word >> 8) & 0xff]))[0]
            pc += delta
        elif op == 0x0f:  # return
            return registers[(word >> 8) & 0xff], serial, calls
        else:
            raise AssertionError('unexpected V039 opcode: ' + hex(op))
    raise AssertionError('V039 dispatch did not terminate')


def audit_private_v039(path):
    raw = path.read_bytes()
    profile = release_recipe('v039')
    assert hashlib.sha256(raw).hexdigest() == profile['original_sha256'], \
        'private input is not the exact reviewed V039 ODEX'
    recipe, changed = make_recipe(raw)
    assert recipe == profile, 'generated BT recipe differs from reviewed V039 profile'
    assert hashlib.sha256(changed).hexdigest() == profile['patched_sha256']
    assert len(changed) == len(raw)

    rebuilt = bytearray(raw)
    for patch in profile['patches']:
        start = patch['offset']
        replacement = bytes(patch['bytes'])
        rebuilt[start:start + len(replacement)] = replacement
    assert bytes(rebuilt) == changed, 'recipe patches do not reproduce generated ODEX'

    original_dex = Dex(raw)
    assert 'Lcom/tcc/iap2server/Iap2Service$2;->Iap2SvcTransportReadDone([BI)Z' in original_dex.methods, \
        'exact V039 iAP2 server no longer exposes the reviewed component transport write'
    patched_dex = Dex(changed)
    assert patched_dex.methods == original_dex.methods
    assert patched_dex.fields == original_dex.fields
    assert patched_dex.strings == original_dex.strings
    base, length = patched_dex.base, patched_dex.length
    assert changed[base + 12:base + 32] == hashlib.sha1(changed[base + 32:base + length]).digest()
    assert struct.unpack_from('<I', changed, base + 8)[0] == \
        zlib.adler32(changed[base + 12:base + length]) & 0xffffffff
    deps = struct.unpack_from('<I', changed, 16)[0]
    opt, opt_size = struct.unpack_from('<II', changed, 24)
    assert struct.unpack_from('<I', changed, 36)[0] == \
        zlib.adler32(changed[deps:opt + opt_size]) & 0xffffffff


class BtRecipeTest(unittest.TestCase):
    def test_v039_dispatches_only_components_four_and_five(self):
        recipe = json.loads((ROOT / 'tools/iap2/bt-v039.json').read_text())
        handler = bytes(recipe['patches'][0]['bytes'])

        for component in (4, 5):
            sticky, serial, calls = execute_bt(handler, {'component': component, 'serial': 'SERIAL'})
            self.assertEqual(sticky, 1)
            self.assertEqual(serial, 'SERIAL')
            self.assertEqual(calls, [('serial', 'SERIAL'), ('connect', component)])

        for component in (-4, -5):
            sticky, serial, calls = execute_bt(handler, {'component': component, 'serial': 'SERIAL'})
            self.assertEqual(sticky, 1)
            self.assertIsNone(serial)
            self.assertEqual(calls, [('disconnect', -component)])

        for intent in (None, {}, {'component': 3}, {'component': -3},
                       {'component': 6}, {'component': 99}):
            sticky, serial, calls = execute_bt(handler, intent)
            self.assertEqual(sticky, 1)
            self.assertIsNone(serial)
            self.assertEqual(calls, [])

    def test_v039_recipe_is_the_only_release_profile_and_is_alternative_to_route(self):
        bt = json.loads((ROOT / 'tools/iap2/bt-v039.json').read_text())
        route = json.loads((ROOT / 'tools/iap2/route-v039.json').read_text())
        self.assertEqual(release_recipe('v039'), bt)
        with self.assertRaises(ValueError):
            release_recipe('v035')
        self.assertEqual(bt['original_sha256'], route['original_sha256'])
        self.assertNotEqual(bt['patched_sha256'], route['patched_sha256'])

    def test_private_stock_v039_rebuilds_the_exact_recipe_and_integrity(self):
        if PRIVATE_STOCK is None:
            self.skipTest('pass --stock-v039 with private stock input for integrity audit')
        audit_private_v039(PRIVATE_STOCK)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--stock-v039', type=Path)
    args = parser.parse_args()
    PRIVATE_STOCK = args.stock_v039
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(BtRecipeTest)
    result = unittest.TextTestRunner().run(suite)
    sys.exit(not result.wasSuccessful())
