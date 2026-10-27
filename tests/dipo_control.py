"""Execute authored Dalvik dispatch and optionally audit private stock recipes."""
import argparse
import hashlib
from pathlib import Path
import struct
import sys
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/iap2'))
from dipo_patch import dispatch_words, locate_body, make_recipe, ACTION, NEXT_ACTION


class DispatchTest(unittest.TestCase):
    def test_dispatch_uses_receiver_service_and_false_argument(self):
        code = dispatch_words(8, 123, 456, 20)
        registers = {8: {'service': object()}}
        calls = []
        pc = 0
        while True:
            op = code[pc] & 255
            if op == 0x54:
                dest, source = (code[pc] >> 8) & 15, code[pc] >> 12
                self.assertEqual(code[pc + 1], 123)
                registers[dest] = registers[source]['service']; pc += 2
            elif op == 0x12:
                registers[(code[pc] >> 8) & 15] = code[pc] >> 12; pc += 1
            elif op == 0x6e:
                self.assertEqual(code[pc] >> 12, 2)
                self.assertEqual(code[pc + 1], 456)
                args = code[pc + 2]
                calls.append((registers[args & 15], registers[(args >> 4) & 15])); pc += 3
            elif op == 0x0e:
                break
            else:
                self.fail('unexpected authored opcode')
        self.assertEqual(calls, [(registers[8]['service'], 0)])
        self.assertTrue(all(x == 0 for x in code[pc + 1:]))

    def test_unsupported_register_or_slot_rejected(self):
        for receiver, capacity in ((16, 20), (8, 6)):
            with self.assertRaises(ValueError): dispatch_words(receiver, 1, 2, capacity)

    def test_body_locator_preserves_action_check(self):
        words = [0x011a, 0, 0x20ee, 3, 1, 0x010a, 0x0138, 12] + [0] * 10 + [0x011a, 1, 0x000e]
        self.assertEqual(locate_body(words, [ACTION, NEXT_ACTION]), (8, 18))
        words[7] = 11
        with self.assertRaises(ValueError): locate_body(words, [ACTION, NEXT_ACTION])

    def test_external_branch_cannot_enter_replaced_body(self):
        words = [0x011a, 0, 0x20ee, 3, 1, 0x010a, 0x0138, 12] + [0] * 10 + [0x011a, 1, 0xf428]
        with self.assertRaises(ValueError): locate_body(words, [ACTION, NEXT_ACTION])


def private_check(path):
    raw = path.read_bytes()
    recipe, changed = make_recipe(raw)
    profile = ROOT / ('tools/iap2/dipo-' + path.parent.parent.name.split('_')[0] + '.json')
    if profile.exists():
        import json
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
    print('PASS private DiPO extent/identity/checksum:', path.parent.parent.name)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--stock', action='append', type=Path, default=[])
    args = parser.parse_args()
    result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(DispatchTest))
    if not result.wasSuccessful(): sys.exit(1)
    for path in args.stock: private_check(path)
