#!/usr/bin/env python3
import importlib.util
import json
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "recovery" / "build_recovery_usb.py"
SPEC = importlib.util.spec_from_file_location("recovery_usb_impl", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class RecoveryUsbTests(unittest.TestCase):
    def test_bundle_is_non_destructive_and_deterministic(self):
        with tempfile.TemporaryDirectory() as tmp:
            first = Path(tmp) / "recovery"
            archive = MODULE.build(first)
            names = sorted(p.name for p in first.iterdir())
            self.assertIn("fastboot_recovery.py", names)
            self.assertIn("NO-AUTO-FLASH.txt", names)
            self.assertNotIn("NEMESIS.sh", names)
            self.assertNotIn("GEN5W-ACTION", names)
            self.assertNotIn("boot.img", names)
            self.assertNotIn("system.img", names)
            manifest = json.loads(
                (first / "stock-manifest.example.json").read_text(encoding="utf-8")
            )
            self.assertEqual(manifest["product"], "kona-gen5w")
            with zipfile.ZipFile(archive) as zf:
                self.assertEqual(sorted(zf.namelist()), names)


if __name__ == "__main__":
    unittest.main()
