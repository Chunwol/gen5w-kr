#!/usr/bin/env python3
"""Audit the separate emergency restore-only archive, never ordinary USBs."""
from __future__ import annotations

import configparser
import hashlib
from pathlib import Path
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "tools/portable/recovery-usb/build.py"
PATCHER = ROOT / ".build/portable/dex-patch"
EXPECTED = {
    "NEMESIS.data", "NEMESIS.emergency", "NEMESIS.sh", "restore.sh",
    "RESTORE-STATUS.txt", "manifest-format.md", "bin/dex-patch", "SHA256SUMS",
}


class RecoveryBundleTest(unittest.TestCase):
    def setUp(self):
        build_root = ROOT / ".build"
        build_root.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="recovery-bundle-test-", dir=build_root)
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name) / "restore.zip"

    def build(self):
        return subprocess.run(
            [sys.executable, str(BUILDER), "--output", str(self.output)],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20,
        )

    def test_builds_emergency_only_execute_archive_with_integrity(self):
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue(self.output.is_file())
        self.assertTrue(self.output.with_suffix(".zip.sha256").is_file())
        with zipfile.ZipFile(self.output) as archive:
            self.assertEqual(set(archive.namelist()), EXPECTED)
            descriptor = configparser.ConfigParser()
            descriptor.read_string(archive.read("NEMESIS.data").decode("ascii"))
            self.assertEqual(descriptor.get("nemesis", "type"), "execute")
            self.assertEqual(descriptor.get("nemesis", "path"), "NEMESIS.sh")
            self.assertEqual(archive.read("NEMESIS.emergency"), b"")
            for name in ("NEMESIS.sh", "restore.sh", "bin/dex-patch"):
                mode = archive.getinfo(name).external_attr >> 16
                self.assertEqual(stat.S_IMODE(mode), 0o755, name)
            wrapper = archive.read("NEMESIS.sh").decode("utf-8")
            restore = archive.read("restore.sh").decode("utf-8")
            status = archive.read("RESTORE-STATUS.txt").decode("utf-8")
            self.assertIn("GEN5W_RECOVERY_USB_ROOT", wrapper)
            self.assertIn("Do not use this archive in the vehicle", status)
            self.assertIn('exec /system/bin/sh "$USB/restore.sh"', wrapper)
            self.assertNotIn("GEN5W_RECOVERY_TEST_ROOT", wrapper)
            self.assertIn('"$HELPER" remount-rw', restore)
            self.assertNotIn("mount -o remount,rw /system", restore)

            # Validate the packaged helper is a static 32-bit ARM executable.
            elf = archive.read("bin/dex-patch")
            self.assertEqual(elf[:4], b"\x7fELF")
            self.assertEqual(elf[4:6], b"\x01\x01")
            self.assertEqual(struct.unpack_from("<H", elf, 16)[0], 2)
            self.assertEqual(struct.unpack_from("<H", elf, 18)[0], 40)
            phoff = struct.unpack_from("<I", elf, 28)[0]
            phentsize, phnum = struct.unpack_from("<HH", elf, 42)
            types = [struct.unpack_from("<I", elf, phoff + i * phentsize)[0]
                     for i in range(phnum)]
            self.assertNotIn(3, types, "static helper must not have PT_INTERP")

        expected = hashlib.sha256(self.output.read_bytes()).hexdigest()
        self.assertEqual(self.output.with_suffix(".zip.sha256").read_text().split()[0], expected)

    def test_ordinary_installer_does_not_get_emergency_marker(self):
        self.assertFalse((ROOT / "tools/portable/usb/NEMESIS.emergency").exists())
        self.assertFalse((ROOT / ".build/portable/vehicle-0.3.71-final/NEMESIS.emergency").exists())
        ordinary = ROOT / ".build/portable/gen5w.kr.portable-0.3.71-final.zip"
        with zipfile.ZipFile(ordinary) as archive:
            self.assertFalse(any(Path(name).name == "NEMESIS.emergency"
                                 for name in archive.namelist()))

    def test_rejects_existing_output_without_replacing_it(self):
        self.output.write_bytes(b"preserve")
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.output.read_bytes(), b"preserve")


if __name__ == "__main__":
    unittest.main(verbosity=2)
