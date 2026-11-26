"""Exercise candidate staging with a fake patch boundary, never mount real files."""
from pathlib import Path
import json
import os
import stat
import importlib.util
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CandidateTests(unittest.TestCase):
    def module(self):
        spec = importlib.util.spec_from_file_location('portable_candidate', ROOT / 'tools/portable/candidate.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def load(self, relative):
        spec = importlib.util.spec_from_file_location('portable_' + Path(relative).stem, ROOT / relative)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_app_digest_covers_compilation_inputs_and_tracks_file_set(self):
        build = self.load('tools/portable/build_apps.py')
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for relative in build.SOURCE_ROOTS:
                path = root / relative
                if path.suffix in ('.java', '.xml', '.py'):
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(b'original')
                else:
                    path.mkdir(parents=True, exist_ok=True)
                    (path / 'Source.java').write_bytes(b'original')
            original = build.source_digest(root)
            for path in sorted(root.rglob('*')):
                if not path.is_file():
                    continue
                path.write_bytes(b'changed')
                self.assertNotEqual(original, build.source_digest(root), str(path))
                path.write_bytes(b'original')
            added = root / 'app/src/NewAaParser.java'
            added.write_bytes(b'new source')
            self.assertNotEqual(original, build.source_digest(root))
            added.unlink()
            self.assertEqual(original, build.source_digest(root))
            (root / 'app/src/Source.java').unlink()
            self.assertNotEqual(original, build.source_digest(root))

    def test_bundle_requires_all_inputs_before_creating_output(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / 'candidate'
            with self.assertRaises((ValueError, FileNotFoundError)):
                module.assemble(output, Path(temp) / 'missing')
            self.assertFalse(output.exists())

    def test_bundle_copies_only_authored_allowlist_and_hashes(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            inputs = base / 'inputs'
            inputs.mkdir()
            (inputs / 'dex-patch').write_bytes(b'authored-test-helper')
            output = base / 'candidate'
            module.assemble(output, inputs)
            self.assertTrue((output / 'bin/dex-patch').is_file())
            self.assertTrue((output / 'prepare.sh').is_file())
            self.assertTrue((output / 'overlay.sh').is_file())
            self.assertTrue((output / 'SHA256SUMS').is_file())
            self.assertFalse(list(output.rglob('*.odex')))
            self.assertFalse(list(output.rglob('*.apk')))
            before = (output / 'SHA256SUMS').read_bytes()
            with self.assertRaises(FileExistsError):
                module.assemble(output, inputs)
            self.assertEqual(before, (output / 'SHA256SUMS').read_bytes())

    def test_rejects_symlink_input_ancestor_and_output_ancestor(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            real = base / 'real'
            real.mkdir()
            (real / 'dex-patch').write_bytes(b'helper')
            alias = base / 'alias'
            try:
                alias.symlink_to(real, target_is_directory=True)
            except OSError:
                self.skipTest('symlink creation unavailable')
            with self.assertRaises(ValueError):
                module.assemble(base / 'candidate', alias)
            with self.assertRaises(ValueError):
                module.assemble(alias / 'candidate', real)
            self.assertFalse((real / 'candidate').exists())

    def test_runtime_preflight_is_complete_before_output_creation(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            (base / 'dex-patch').write_bytes(b'helper')
            with self.assertRaises(FileNotFoundError):
                module.assemble(base / 'candidate', base, runtime=True)
            self.assertFalse((base / 'candidate').exists())

    def test_runtime_bundle_remains_disabled_and_has_all_inputs(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            inputs = base / 'inputs'
            (inputs / 'dalvik').mkdir(parents=True)
            (inputs / 'apps').mkdir()
            (inputs / 'apps/gen5w-core.apk').write_bytes(b'portable-core-no-autostart')
            (inputs / 'apps/bridge.dex').write_bytes(b'portable-bridge-guard')
            (inputs / 'apps/wireless-host.apk').write_bytes(b'portable-host-identity')
            (inputs / 'dex-patch').write_bytes(b'helper')
            for name in ('engine.jar', 'adapter.jar', 'libgen5whook.so', 'abi.sha256', 'hook-vm-test.jar'):
                (inputs / 'dalvik' / name).write_bytes(b'authored-fixture')
            output = base / 'candidate'
            # Dalvik inputs must carry the digest of the current sources (2026-11-19:
            # a stale pre-fix hook library shipped in six releases).
            with self.assertRaises(ValueError):
                module.assemble(output, inputs, runtime=True)
            (inputs / 'dalvik/source.sha256').write_text('0' * 64 + '\n', encoding='ascii')
            with self.assertRaises(ValueError):
                module.assemble(output, inputs, runtime=True)
            build = self.load('tools/portable/dalvik/build.py')
            (inputs / 'dalvik/source.sha256').write_text(build.source_digest() + '\n', encoding='ascii')
            (inputs / 'dalvik/libgen5whook.so').write_bytes(b'fixture -Xbootclasspath/a: fixture')
            with self.assertRaises(ValueError):
                module.assemble(output, inputs, runtime=True)
            self.assertFalse(output.exists())
            (inputs / 'dalvik/libgen5whook.so').write_bytes(b'authored-fixture')
            with self.assertRaisesRegex(ValueError, 'apps inputs carry no source'):
                module.assemble(output, inputs, runtime=True)
            self.assertFalse(output.exists())
            (inputs / 'apps/source.sha256').write_text('0' * 64 + '\n', encoding='ascii')
            with self.assertRaisesRegex(ValueError, 'apps inputs were built from different sources'):
                module.assemble(output, inputs, runtime=True)
            self.assertFalse(output.exists())
            apps_build = self.load('tools/portable/build_apps.py')
            (inputs / 'apps/source.sha256').write_text(apps_build.source_digest() + '\n', encoding='ascii')
            module.assemble(output, inputs, runtime=True)
            self.assertFalse((output / 'enabled').exists())
            self.assertTrue((output / 'app/gen5w-core.apk').read_bytes() == b'portable-core-no-autostart', 'wrong core APK variant')
            self.assertTrue((output / 'NEMESIS.data').is_file())
            self.assertTrue((output / 'boot.sh').is_file())
            self.assertEqual((output / 'bootguard.sh').read_bytes(),
                             (ROOT / 'tools/portable/bootguard.sh').read_bytes())
            self.assertEqual((output / 'bootguard-restore.sh').read_bytes(),
                             (ROOT / 'tools/portable/recovery-usb/restore.sh').read_bytes())
            self.assertTrue((output / 'rescue.sh').is_file())
            self.assertTrue((output / 'dalvik/libgen5whook.so').is_file())
            self.assertTrue((output / 'runtime.sh').is_file())
            self.assertTrue((output / 'session.sh').is_file())
            self.assertTrue((output / 'app/bridge.dex').is_file())
            self.assertTrue((output / 'app/wireless-host.apk').is_file())
            self.assertTrue((output / 'app/gen5w-core.apk').is_file())
            if os.name != 'nt':
                for directory in [output, *(p for p in output.rglob('*') if p.is_dir())]:
                    self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o755)
            self.assertFalse(list(output.rglob('*.odex')))
            self.assertFalse((output / 'enabled').exists())

    def test_output_cannot_be_source_or_release_folder(self):
        module = self.module()
        for output in (ROOT / 'tools/portable', ROOT / 'dist', ROOT / 'packages/test', ROOT / 'tests/candidate-output', ROOT / '.git/candidate-output'):
            with self.subTest(output=output), self.assertRaises(ValueError):
                module.assemble(output, ROOT / '.build/portable')

    def test_regional_audio_helper_is_staged_without_legacy_recipe_gate(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as temp:
            base=Path(temp); inputs=base/'inputs'; (inputs/'audio').mkdir(parents=True)
            (inputs/'dex-patch').write_bytes(b'helper')
            (inputs/'audio/audio-region-patch').write_bytes(b'authored-regional-helper')
            output=base/'candidate'
            module.assemble(output, inputs)
            self.assertEqual((output/'bin/audio-region-patch').read_bytes(),b'authored-regional-helper')
            self.assertEqual(json.loads((output/'CANDIDATE.json').read_text())['audio_compatibility'],'reviewed-elf-regions')
            (inputs/'audio/BUILD-FAILED').write_text('incomplete')
            with self.assertRaises(ValueError):module.assemble(base/'incomplete',inputs)

    def test_artifact_audit_allowlist_includes_persistent_start_service(self):
        source = (ROOT / 'tools/portable/artifact.py').read_text(encoding='utf-8')
        self.assertIn("'persistent-migrate', 'persistent-start'", source)


if __name__ == '__main__':
    unittest.main()
