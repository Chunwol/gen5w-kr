"""Entry-gate decoding, refusal, and optional private exact-stock audit."""
import importlib.util
import os
from pathlib import Path
import struct
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/iap2'))
import hotspot_patch as patch
from control_patch import Dex


class HotspotControlTest(unittest.TestCase):
    def test_only_entry_branch_changes(self):
        words = [0x1071, 42, 0, 0x060a, 0x0639, 4, 0x0012, 0x000f, 0x000e]
        pc, replacement = patch.local_entry(words, 42)
        self.assertEqual(pc, 4)
        self.assertEqual(replacement, [0x29, 4])
        self.assertEqual(words[pc + 1], replacement[1])

    def test_ambiguous_or_changed_control_flow_refused(self):
        for words in ([0x000e], [0x1071, 42, 0, 0x060a, 0x0638, 2, 0x000e],
                      [0x1071, 42, 0, 0x060a, 0x0639, 0xffff, 0x000e]):
            with self.assertRaises(ValueError):
                patch.local_entry(words, 42)

    def test_unknown_firmware_refused(self):
        with self.assertRaises(ValueError):
            patch.make_recipe(b'unknown firmware')

    @unittest.skipUnless(os.environ.get('GEN5W_HOTSPOT_STOCK'), 'private V039 stock not supplied')
    def test_exact_stock_changes_only_three_gates_and_headers(self):
        raw = Path(os.environ['GEN5W_HOTSPOT_STOCK']).read_bytes()
        recipe, output = patch.make_recipe(raw)
        dex = Dex(raw)
        self.assertEqual(len(output), len(raw))
        ranges = set()
        for item in recipe['patches']:
            ranges.update(range(item['offset'], item['offset'] + len(item['bytes'])))
        self.assertTrue(all(i in ranges for i, (a, b) in enumerate(zip(raw, output)) if a != b))
        for name in patch.TARGETS:
            off = dex.code[name][0]
            size = struct.unpack_from('<I', dex.data, off + 12)[0]
            old = list(struct.unpack_from('<' + 'H' * size, dex.data, off + 16))
            new = list(struct.unpack_from('<' + 'H' * size, output, dex.base + off + 16))
            pc, replacement = patch.local_entry(old, dex.methods.index(patch.CHECK))
            old[pc:pc + 2] = replacement
            self.assertEqual(old, new, name)


if __name__ == '__main__':
    unittest.main()
