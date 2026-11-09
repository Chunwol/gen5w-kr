"""Public transformation tests; optional exact-private delta audit."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT/'tools/v039-relay/build_gpm_guard.py'
CALL = '    invoke-virtual {p1, v0}, Landroid/content/Context;->startService(Landroid/content/Intent;)Landroid/content/ComponentName;\n'

class BuilderTest(unittest.TestCase):
    def setUp(self):
        self.assertTrue(BUILDER.is_file(), 'missing exact GPM builder')
        spec=importlib.util.spec_from_file_location('gpm_builder',BUILDER)
        self.b=importlib.util.module_from_spec(spec); spec.loader.exec_module(self.b)
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup); self.tree=Path(self.tmp.name)
        for file, method, count in (
            ('service/StartReceiver','public onReceive(Landroid/content/Context;Landroid/content/Intent;)V',2),
            ('protocol/WirelessExplorer','private sendStartServiceWireless()V',1)):
            p=self.tree/('com/google/android/projection/'+file+'.smali'); p.parent.mkdir(parents=True,exist_ok=True)
            p.write_text('.method '+method+'\n    .registers 8\n'+CALL*count+'    return-void\n.end method\n')
    def test_transform_preserves_arguments_and_other_methods(self):
        p=self.tree/'other.smali'; p.write_text('.method public untouched()V\n    return-void\n.end method\n')
        self.assertEqual(sum(self.b.patch_service_starts(self.tree).values()),3)
        result=(self.tree/'com/google/android/projection/service/StartReceiver.smali').read_text()
        self.assertEqual(result.count('invoke-static {p1, v0}, Lkr/gen5w/gpm/GpmUsbGuard;->startService'),2)
        self.assertEqual(p.read_text(),'.method public untouched()V\n    return-void\n.end method\n')
        with self.assertRaises(ValueError): self.b.patch_service_starts(self.tree)
    def test_inventory_drift_rejected_before_any_edit(self):
        p=self.tree/'unknown.smali'; p.write_text('.method public extra()V\n'+CALL+'.end method\n')
        original={f:f.read_bytes() for f in self.tree.rglob('*.smali')}
        with self.assertRaises(ValueError): self.b.patch_service_starts(self.tree)
        self.assertEqual({f:f.read_bytes() for f in original},original)
    def test_unreviewed_invoke_range_rejected(self):
        p=self.tree/'com/google/android/projection/service/StartReceiver.smali'
        p.write_text(p.read_text().replace('invoke-virtual {p1, v0}','invoke-virtual/range {v0 .. v1}'))
        with self.assertRaises(ValueError): self.b.patch_service_starts(self.tree)
    def test_bad_inputs_rejected(self):
        a=self.tree/'stock.apk';o=self.tree/'stock.odex';a.write_bytes(b'not stock');o.write_bytes(b'not stock')
        with self.assertRaises(ValueError): self.b.validate_inputs(a,o)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--stock',type=Path);parser.add_argument('--delta',type=Path)
    args=parser.parse_args()
    result=unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(BuilderTest))
    if not result.wasSuccessful():sys.exit(1)
    if args.stock or args.delta:
        assert args.stock and args.delta
        spec=importlib.util.spec_from_file_location('gpm_builder',BUILDER); b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
        b.audit_delta(args.stock,args.delta)
