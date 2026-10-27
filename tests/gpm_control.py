"""Validate HKMC_GPM Android Auto HUD recipe and patching logic."""
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
from gpm_patch import make_recipe

class GpmRecipeTest(unittest.TestCase):
    def test_recipe_matches_committed_profile(self):
        profile = ROOT / 'tools/iap2/gpm-v039.json'
        self.assertTrue(profile.exists(), 'gpm-v039.json must exist')
        data = json.loads(profile.read_text(encoding='utf-8'))
        self.assertEqual(data['id'], 'gpm-hud-enable-1')
        self.assertEqual(data['original_sha256'], '8c510448ee23dff74d6690e8e88ea119947706390dcc2f8e717dad4004dacc58')
        self.assertEqual(data['patched_sha256'], 'bb4407f6c78fb76a39ef51d88c14a7d77dd385f2fe1492ca198a7be02c900bfe')
        # Check that patch 0 zeroes 4 bytes at offset 1017894
        self.assertEqual(data['patches'][0]['offset'], 1017894)
        self.assertEqual(data['patches'][0]['bytes'], [0, 0, 0, 0])

def private_check(path):
    raw = path.read_bytes()
    recipe, changed = make_recipe(raw)
    profile = ROOT / 'tools/iap2/gpm-v039.json'
    if profile.exists():
        assert json.loads(profile.read_text(encoding='utf-8')) == recipe, 'reviewed gpm profile changed'
    assert recipe['original_sha256'] == hashlib.sha256(raw).hexdigest()
    assert recipe['patched_sha256'] == hashlib.sha256(changed).hexdigest()
    assert len(raw) == len(changed)
    permitted = set()
    rebuilt = bytearray(raw)
    for patch in recipe['patches']:
        start = patch['offset']
        data = bytes(patch['bytes'])
        rebuilt[start:start + len(data)] = data
        permitted.update(range(start, start + len(data)))
    assert bytes(rebuilt) == changed
    base, length = struct.unpack_from('<II', raw, 8)
    assert changed[base + 12:base + 32] == hashlib.sha1(changed[base + 32:base + length]).digest()
    assert struct.unpack_from('<I', changed, base + 8)[0] == zlib.adler32(changed[base + 12:base + length]) & 0xffffffff
    print('PASS private HKMC_GPM extent/identity/checksum:', path)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--stock', action='append', type=Path, default=[])
    args = parser.parse_args()
    result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(GpmRecipeTest))
    if not result.wasSuccessful():
        sys.exit(1)
    for path in args.stock:
        private_check(path)
