"""Execute authored Dalvik dispatch and optionally audit private stock recipes."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/iap2'))
from control_patch import Dex
from dipo_patch import make_recipe, call_fallback, CALL_MARKER, RECEIVER, SERVICE


class RecipeScopeTest(unittest.TestCase):
    def test_v035_and_v039_recipes_leave_obsolete_wireless_dispatch_untouched(self):
        profiles = {
            'v035': ((503488, 132), (828404, 4)),
            'v039': ((505464, 132), (832148, 4)),
        }
        for version, protected_ranges in profiles.items():
            recipe = json.loads((ROOT / 'tools/iap2' / ('dipo-' + version + '.json')).read_text())
            for patch in recipe['patches']:
                start = patch['offset']; end = start + len(patch['bytes'])
                for protected_start, protected_size in protected_ranges:
                    protected_end = protected_start + protected_size
                    self.assertFalse(start < protected_end and protected_start < end,
                        version + ' recipe modifies obsolete wireless receiver range')


class CallFallbackTest(unittest.TestCase):
    def fixture(self):
        # Authored synthetic method, not copied stock code.
        words = [0x001a, 0, 0x002b, 18, 0, 0x0029, 14,
                 0x0062, 0, 0x30f8, 193, 0x408,
                 0x0062, 0, 0x30f8, 193, 0x508, 0x0029, 2, 0x000e,
                 0x0100, 4, 0, 0, 5, 0, 5, 0, 5, 0, 5, 0]
        return words, [CALL_MARKER], ['Lcom/daudio/app/dipo/telechips/CarPlayTelephony;->HookSwitch:Lcom/daudio/app/dipo/telechips/CarPlayTelephony;']

    def test_only_missing_state_falls_through(self):
        words, strings, fields = self.fixture()
        pc, replacement = call_fallback(words, strings, fields)
        self.assertEqual(pc, 5)
        self.assertEqual(replacement, [0x003b, 14]) # if-gez v0, existing return
        for state in (-1, -2, 0, 1, 2, 3, 4, 99):
            # Packed-switch keeps 0..3 on its original case table.
            target = 'stock' if 0 <= state <= 3 else ('hook' if state < 0 else 'return')
            reached = pc + replacement[1] if state >= 0 else pc + 2
            actual = 'stock' if 0 <= state <= 3 else ('return' if words[reached] == 0x000e else 'hook')
            self.assertEqual(actual, target)
        changed = words[:]; changed[pc:pc+2] = replacement
        self.assertEqual(len(changed), len(words))
        self.assertEqual(changed[:pc], words[:pc])
        self.assertEqual(changed[pc+2:], words[pc+2:])

    def test_unknown_layout_rejected(self):
        for index, value in [(6, 3), (8, 1), (20, 0x0200), (21, 3), (22, 1), (24, 4)]:
            words, strings, fields = self.fixture(); words[index] = value
            with self.assertRaises(ValueError): call_fallback(words, strings, fields)
        words, strings, fields = self.fixture()
        with self.assertRaises(ValueError): call_fallback(words, ['different marker'], fields)


def private_check(path):
    raw = path.read_bytes()
    recipe, changed = make_recipe(raw)
    version = next((v for v in ('v035', 'v039') if
        json.loads((ROOT / 'tools/iap2' / ('dipo-' + v + '.json')).read_text())['original_sha256'] ==
        hashlib.sha256(raw).hexdigest()), None)
    assert version is not None, 'stock ODEX does not match a reviewed DiPO profile'
    profile = ROOT / ('tools/iap2/dipo-' + version + '.json')
    assert json.loads(profile.read_text()) == recipe, 'reviewed profile changed'
    assert recipe['original_sha256'] == hashlib.sha256(raw).hexdigest()
    assert recipe['patched_sha256'] == hashlib.sha256(changed).hexdigest()
    assert len(raw) == len(changed)
    permitted = set()
    rebuilt = bytearray(raw)
    for patch in recipe['patches']:
        start = patch['offset']; data = bytes(patch['bytes'])
        rebuilt[start:start + len(data)] = data
        permitted.update(range(start, start + len(data)))
    assert bytes(rebuilt) == changed
    assert all(a == b or i in permitted for i, (a, b) in enumerate(zip(raw, changed)))
    base, length = struct.unpack_from('<II', raw, 8)
    assert changed[base + 12:base + 32] == hashlib.sha1(changed[base + 32:base + length]).digest()
    assert struct.unpack_from('<I', changed, base + 8)[0] == zlib.adler32(changed[base + 12:base + length]) & 0xffffffff
    original_dex = Dex(raw); changed_dex = Dex(changed)
    def instructions(data, dex, method):
        offset = dex.code[method][0]
        count = struct.unpack_from('<I', dex.data, offset + 12)[0]
        start = dex.base + offset + 16
        return data[start:start + count * 2]
    receiver_method = RECEIVER + '->onReceive(Landroid/content/Context;Landroid/content/Intent;)V'
    assert instructions(raw, original_dex, receiver_method) == instructions(changed, changed_dex, receiver_method), \
        'obsolete wireless receiver bytecode changed'
    call_method = SERVICE + '->i(II)V'
    call_offset = original_dex.code[call_method][0]
    count = struct.unpack_from('<I', original_dex.data, call_offset + 12)[0]
    call_words = list(struct.unpack_from('<' + 'H' * count, original_dex.data, call_offset + 16))
    branch, replacement = call_fallback(call_words, original_dex.strings, original_dex.fields)
    expected = call_words[:]; expected[branch:branch + 2] = replacement
    changed_offset = changed_dex.code[call_method][0]
    changed_count = struct.unpack_from('<I', changed_dex.data, changed_offset + 12)[0]
    actual = list(struct.unpack_from('<' + 'H' * changed_count, changed_dex.data, changed_offset + 16))
    assert actual == expected, 'retained call-key fallback differs from reviewed branch'
    print('PASS private DiPO extent/identity/checksum/scope:', version)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--stock', action='append', type=Path, default=[])
    args = parser.parse_args()
    result = unittest.TextTestRunner().run(unittest.TestSuite([unittest.defaultTestLoader.loadTestsFromTestCase(c) for c in (RecipeScopeTest, CallFallbackTest)]))
    if not result.wasSuccessful(): sys.exit(1)
    for path in args.stock: private_check(path)
