"""Entry-gate decoding, refusal, and optional private exact-stock audit."""
import os
import json
from pathlib import Path
import struct
import sys
import unittest
import importlib.util
import tempfile
from unittest.mock import patch as mock_patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/iap2'))
import hotspot_patch as patch
from control_patch import Dex


class HotspotControlTest(unittest.TestCase):
    def test_build_staging_cannot_ship_deleted_files(self):
        spec = importlib.util.spec_from_file_location('local_hotspot_build', ROOT / 'tools/local-hotspot/build.py')
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            package = root / 'tools/local-hotspot/package'
            (package / 'scripts').mkdir(parents=True)
            (package / 'scripts/control.sh').write_text('exit 0\n')
            recipe = root / 'tools/iap2/hotspot-v039.json'
            recipe.parent.mkdir(parents=True)
            recipe.write_text(json.dumps({'original_sha256': '0' * 64, 'patched_sha256': '1' * 64, 'patches': []}))

            def build_command(command, **kwargs):
                if '-o' in command:
                    Path(command[-1]).write_bytes(b'fake compiler output')
                else:
                    source, output = map(Path, command[-2:])
                    with zipfile.ZipFile(output, 'w') as archive:
                        for file in source.rglob('*'):
                            if file.is_file():
                                archive.write(file, file.relative_to(source))

            with mock_patch.object(builder, 'ROOT', root), mock_patch.object(sys, 'argv', ['build.py', '--ndk', folder]), mock_patch.object(builder.subprocess, 'run', side_effect=build_command):
                builder.main()
                (root / '.build/local-hotspot/package/obsolete.txt').write_text('must not ship')
                builder.main()
            with zipfile.ZipFile(root / '.build/local-hotspot/gen5w.kr.localhotspot-trial.zip') as archive:
                self.assertNotIn('obsolete.txt', archive.namelist())

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
        self.assertEqual(recipe, json.loads((ROOT / 'tools/iap2/hotspot-v039.json').read_text()))
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
