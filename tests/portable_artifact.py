"""Audit real authored build inputs; inject corrupt and foreign distribution members."""
import hashlib
import os
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT/'tools/portable'/f'{name}.py')
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class ArtifactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.audit = module('artifact')
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)/'candidate'
            module('candidate').assemble(path, Path(os.environ.get('PORTABLE_BUILD_INPUTS', str(ROOT/'.build/portable/final-inputs-v5'))), runtime=True)
            cls.files = cls.audit.read_directory(path)

    def sealed(self, files):
        files['SHA256SUMS'] = ''.join(hashlib.sha256(data).hexdigest()+'  '+name+'\n'
                                     for name, data in sorted(files.items())
                                     if name != 'SHA256SUMS').encode('ascii')
        return files

    def test_real_authored_candidate(self):
        self.assertGreater(self.audit.audit(dict(self.files)), 30)

    def test_dongle_payload_shipped_and_bounded(self):
        self.assertIn('dongle/bcmdhd.ko', self.files)
        self.assertIn('dongle/modules/ath9k_htc.ko', self.files)
        self.assertIn('dongle/firmware/htc_9271.fw', self.files)
        self.assertIn('wifi-backend.sh', self.files)
        self.assertIn('dongle.sh', self.files)
        files = dict(self.files)
        files['dongle/modules/../evil.ko'] = b'\x7fELF'
        with self.assertRaises(AssertionError):
            self.audit.audit(self.sealed(files))
        files = dict(self.files)
        files['dongle/modules/ath9k_htc.ko'] = b'not a module'
        with self.assertRaises(AssertionError):
            self.audit.audit(self.sealed(files))

    def test_corruption_and_unhashed_files(self):
        files = dict(self.files)
        files['boot.sh'] += b'corrupted'
        with self.assertRaises(AssertionError): self.audit.audit(files)
        files = dict(self.files)
        files['diagnostics.txt'] = b'not covered'
        with self.assertRaises(AssertionError): self.audit.audit(files)

    def test_hashed_oem_and_secret_still_refused(self):
        for name in ('system/app/HKMC_DiPO.odex', 'private/signing.pass', '../escape'):
            files = dict(self.files)
            files[name] = b'forbidden'
            with self.assertRaises(AssertionError): self.audit.audit(self.sealed(files))

    def test_native_binary_and_required_payload(self):
        files = dict(self.files)
        files['bin/dex-patch'] = b'not an ARM binary'
        with self.assertRaises(AssertionError): self.audit.audit(self.sealed(files))
        files = dict(self.files)
        del files['rescue.sh']
        with self.assertRaises(AssertionError): self.audit.audit(self.sealed(files))

    def test_foreign_dex_implementation(self):
        data = self.files['app/bridge.dex']
        self.audit.dex(data)
        changed = data.replace(b'Lkr/gen5w/', b'Lxx/gen5w/')
        self.assertNotEqual(changed, data)
        with self.assertRaises(AssertionError): self.audit.dex(changed)


if __name__ == '__main__': unittest.main()
