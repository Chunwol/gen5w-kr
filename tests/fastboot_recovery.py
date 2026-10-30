#!/usr/bin/env python3
import hashlib
import importlib.util
import json
import sys
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "recovery" / "fastboot_recovery.py"
SPEC = importlib.util.spec_from_file_location("fastboot_recovery_impl", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)
RecoveryError = MODULE.RecoveryError
ALLOWED_PARTITIONS = MODULE.ALLOWED_PARTITIONS
build_flash_plan = MODULE.build_flash_plan
parse_fastboot_vars = MODULE.parse_fastboot_vars
validate_manifest = MODULE.validate_manifest


class FastbootRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.image = self.root / "boot.img"
        self.image.write_bytes(b"stock boot image\n")
        self.sha = hashlib.sha256(self.image.read_bytes()).hexdigest()

    def tearDown(self):
        self.tmp.cleanup()

    def write_manifest(self, partition="boot", file_name="boot.img", sha=None, product="kona-gen5w"):
        data = {
            "product": product,
            "partitions": [{"name": partition, "file": file_name, "sha256": sha or self.sha}],
        }
        path = self.root / "manifest.json"
        path.write_text(json.dumps(data), encoding="utf-8")
        return path

    def test_parse_fastboot_variables(self):
        parsed = parse_fastboot_vars(
            "(bootloader) product: kona-gen5w\n"
            "(bootloader) version-bootloader: v039\n"
            "Finished. Total time: 0.001s\n"
        )
        self.assertEqual(parsed["product"], "kona-gen5w")
        self.assertEqual(parsed["version-bootloader"], "v039")

    def test_manifest_accepts_external_stock_image(self):
        manifest = self.write_manifest()
        entries = validate_manifest(manifest, self.root, expected_product="kona-gen5w")
        self.assertEqual(entries[0][0], "boot")
        self.assertEqual(entries[0][1], self.image)

    def test_manifest_rejects_unsafe_partition(self):
        manifest = self.write_manifest(partition="bootloader")
        with self.assertRaises(RecoveryError):
            validate_manifest(manifest, self.root, expected_product="kona-gen5w")
        self.assertNotIn("bootloader", ALLOWED_PARTITIONS)

    def test_manifest_rejects_path_traversal_and_symlink(self):
        manifest = self.write_manifest(file_name="../boot.img")
        with self.assertRaises(RecoveryError):
            validate_manifest(manifest, self.root, expected_product="kona-gen5w")
        link = self.root / "link.img"
        link.symlink_to(self.image)
        manifest = self.write_manifest(file_name="link.img")
        with self.assertRaises(RecoveryError):
            validate_manifest(manifest, self.root, expected_product="kona-gen5w")

    def test_product_mismatch_and_hash_mismatch_are_refused(self):
        manifest = self.write_manifest(product="other-unit")
        with self.assertRaises(RecoveryError):
            validate_manifest(manifest, self.root, expected_product="kona-gen5w")
        manifest = self.write_manifest(sha="0" * 64)
        with self.assertRaises(RecoveryError):
            validate_manifest(manifest, self.root, expected_product="kona-gen5w")

    def test_probe_plan_is_read_only_and_only_allowlisted(self):
        manifest = self.write_manifest()
        plan = build_flash_plan(
            {"product": "kona-gen5w"}, manifest, self.root, expected_product="kona-gen5w"
        )
        self.assertEqual(plan, [["flash", "boot", str(self.image)]])
        self.assertFalse(any(command[0] in {"erase", "oem", "unlock"} for command in plan))

    def test_probe_failure_never_reaches_flash(self):
        calls = []

        def runner(command, **_kwargs):
            calls.append(command)
            if command[1] == "devices":
                return subprocess.CompletedProcess(command, 0, "", "")
            raise AssertionError("getvar must not run without a device")

        with self.assertRaises(RecoveryError):
            MODULE.probe_fastboot("fastboot", expected_product="kona-gen5w", runner=runner)
        self.assertEqual(calls, [["fastboot", "devices"]])

    def test_flash_requires_explicit_confirmation_before_probe(self):
        calls = []

        def runner(command, **_kwargs):
            calls.append(command)
            return subprocess.CompletedProcess(command, 0, "", "")

        with self.assertRaises(RecoveryError):
            MODULE.flash_stock(
                "fastboot",
                self.write_manifest(),
                self.root,
                expected_product="kona-gen5w",
                runner=runner,
            )
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
