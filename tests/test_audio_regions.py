"""Consumer tests for portable regional audio, using only authored synthetic ELF."""
import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

def fixture():
    data = bytearray(1024)
    struct.pack_into('<16sHHIIIIIHHHHHH', data, 0, b'\x7fELF\x01\x01\x01' + b'\0'*9,
                     3, 40, 1, 0, 52, 0x300, 0x5000200, 52, 32, 1, 40, 5, 4)
    struct.pack_into('<8I', data, 52, 1, 0, 0, 0, 0x1a0, 0x1a0, 5, 0x1000)
    data[0x100:0x140] = bytes(range(64))
    data[0x180:0x1a0] = b'R'*32
    data[0x280:0x290] = b'comment-metadata'
    names=b'\0.text\0.rodata\0.comment\0.shstrtab\0'
    data[0x2a0:0x2a0+len(names)] = names
    for i, args in enumerate([(0,0,0,0,0,0,0,0,0,0),
        (1,1,6,0x100,0x100,64,0,0,4,0), (7,1,2,0x180,0x180,32,0,0,4,0),
        (15,1,0,0,0x280,16,0,0,1,0), (24,3,0,0,0x2a0,len(names),0,0,1,0)]):
        struct.pack_into('<10I', data, 0x300+i*40, *args)
    return bytes(data)

class AudioRegions(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec=importlib.util.spec_from_file_location('audio_regions', ROOT/'tools/audio/build_regions.py')
        cls.module=importlib.util.module_from_spec(spec);spec.loader.exec_module(cls.module)
        cls.temp=tempfile.TemporaryDirectory();cls.work=Path(cls.temp.name)
        cls.original=fixture();cls.replacement=b'new-code'
        patch={'offset':0x110,'length':8,'original_span_sha256':hashlib.sha256(cls.original[0x110:0x118]).hexdigest(),
               'replacement':cls.replacement}
        profiles={'audio':cls.module.profile(cls.original,[patch])}
        profiles.update({n:cls.module.profile(cls.original) for n in ('core','utils','opus')})
        (cls.work/'region_recipe.h').write_text(cls.module.header_for_profiles(profiles),encoding='ascii')
        cls.exe=cls.work/('regions.exe' if os.name=='nt' else 'regions')
        subprocess.run([shutil.which('gcc') or 'cc','-std=c99','-Wall','-Wextra','-Werror','-I',str(cls.work),
                        str(ROOT/'tools/audio/region_patch.c'),'-o',str(cls.exe)],check=True)
    @classmethod
    def tearDownClass(cls): cls.temp.cleanup()
    def run_helper(self,command,data,arg=None):
        src=self.work/'input.so';src.write_bytes(data)
        args=[str(self.exe),command,str(src)]+([] if arg is None else [str(arg)])
        r=subprocess.run(args,capture_output=True)
        self.assertEqual(src.read_bytes(),data,'input modified')
        return r.returncode
    def test_accepts_unrelated_text_and_nonallocated_metadata(self):
        variant=bytearray(self.original);variant[0x135]^=1;variant[0x288]^=1
        self.assertEqual(self.run_helper('original',variant),0)
        out=self.work/'variant-patched.so'
        self.assertEqual(self.run_helper('apply',variant,out),0)
        expected=bytearray(variant);expected[0x110:0x118]=self.replacement
        self.assertEqual(out.read_bytes(),expected)
        self.assertEqual(self.run_helper('patched',expected),0)
    def test_refuses_changed_patch_guard_and_partial_patch_without_output(self):
        for off in (0x110,0x180):
            variant=bytearray(self.original);variant[off]^=1
            out=self.work/('refused-'+str(off)+'.so')
            self.assertNotEqual(self.run_helper('apply',variant,out),0);self.assertFalse(out.exists())
        partial=bytearray(self.original);partial[0x110:0x114]=self.replacement[:4]
        self.assertNotEqual(self.run_helper('original',partial),0)
        self.assertNotEqual(self.run_helper('patched',partial),0)
    def test_dependency_code_is_checked_but_metadata_is_not(self):
        variant=bytearray(self.original);variant[0x288]^=1
        self.assertEqual(self.run_helper('verify',variant,'utils'),0)
        variant[0x135]^=1
        self.assertNotEqual(self.run_helper('verify',variant,'utils'),0)
        self.assertEqual(self.run_helper('verify',self.original,'not-a-role'),2)
    def test_rejects_mapping_changes_wrong_abi_and_truncation(self):
        for off in (4,5,16,18,28,36,42,44,60,68,72,80):
            variant=bytearray(self.original);variant[off]^=1
            self.assertNotEqual(self.run_helper('original',variant),0)
        self.assertNotEqual(self.run_helper('original',self.original[:0x185]),0)
    def test_output_must_be_fresh(self):
        out=self.work/'existing';out.write_bytes(b'keep')
        self.assertNotEqual(self.run_helper('apply',self.original,out),0)
        self.assertEqual(out.read_bytes(),b'keep')
    def test_builder_refuses_unreviewed_or_ambiguous_patch(self):
        patch={'offset':0x110,'length':8,'original_span_sha256':'0'*64,'replacement':self.replacement}
        with self.assertRaises(ValueError):self.module.profile(self.original,[patch])
        patch['original_span_sha256']=hashlib.sha256(self.original[0x110:0x118]).hexdigest()
        with self.assertRaises(ValueError):self.module.profile(self.original,[patch,patch])

if __name__=='__main__':unittest.main()
