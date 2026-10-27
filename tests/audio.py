"""Behavior tests for our native, hash-guarded audio recipe engine."""
import hashlib
import pathlib
import shutil
import subprocess
import tempfile
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]

class AudioRecipeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.dir = pathlib.Path(cls.tmp.name)
        cls.original = bytes(range(256)) * 4
        cls.changed = cls.original[:48] + b'OWN-CODE' + cls.original[56:]
        cls.header = cls.dir / 'recipe.h'
        cls.header.write_text('#define ORIGINAL_SHA "' + hashlib.sha256(cls.original).hexdigest() + '"\n#define PATCHED_SHA "' + hashlib.sha256(cls.changed).hexdigest() + '"\nstatic const unsigned char replacement[] = {79,87,78,45,67,79,68,69};\nstatic const struct patch patches[] = {{48,8,replacement}};\n')
        cls.exe = cls.dir / ('audio-patch.exe' if __import__('os').name == 'nt' else 'audio-patch')
        subprocess.run([shutil.which('gcc') or 'cc','-std=c99','-Wall','-Wextra','-Werror','-I',str(cls.dir),str(ROOT/'tools/audio/patch.c'),'-o',str(cls.exe)],check=True)
    @classmethod
    def tearDownClass(cls): cls.tmp.cleanup()
    def setUp(self):
        self.src = self.dir/'source'; self.out = self.dir/'result'
        self.src.write_bytes(self.original)
        self.out.unlink(missing_ok=True)
    def run_tool(self,*args):
        return subprocess.run([str(self.exe),*map(str,args)],capture_output=True,text=True)
    def test_apply_and_verify_byte_identity(self):
        self.assertEqual(self.run_tool('apply',self.src,self.out).returncode,0)
        self.assertEqual(self.out.read_bytes(),self.changed)
        self.assertEqual(self.src.read_bytes(),self.original)
        self.assertEqual(self.run_tool('patched',self.out).returncode,0)
        self.assertEqual(self.run_tool('original',self.src).returncode,0)
    def test_mismatch_refuses_before_creating_output(self):
        self.src.write_bytes(self.original[:-1]+b'x')
        self.assertNotEqual(self.run_tool('apply',self.src,self.out).returncode,0)
        self.assertFalse(self.out.exists())
    def test_existing_output_is_never_overwritten(self):
        self.out.write_bytes(b'keep')
        self.assertNotEqual(self.run_tool('apply',self.src,self.out).returncode,0)
        self.assertEqual(self.out.read_bytes(),b'keep')
    def test_patched_file_is_not_a_valid_original(self):
        self.src.write_bytes(self.changed)
        self.assertNotEqual(self.run_tool('original',self.src).returncode,0)
        self.assertNotEqual(self.run_tool('apply',self.src,self.out).returncode,0)
    def test_empty_and_truncated_inputs_are_rejected(self):
        for b in [b'',self.original[:49]]:
            self.src.write_bytes(b)
            self.assertNotEqual(self.run_tool('original',self.src).returncode,0)
    def test_missing_input_is_rejected(self):
        self.src.unlink()
        self.assertNotEqual(self.run_tool('original',self.src).returncode,0)
if __name__ == '__main__': unittest.main()
