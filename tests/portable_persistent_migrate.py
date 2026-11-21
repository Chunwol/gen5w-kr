#!/usr/bin/env python3
"""Host fixtures for the persistent overlay migration helper contract."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATE = ROOT / "tools/portable/persistent-migrate.sh"
STATIC = "/system/app/HKMC_DiPO.odex"
PERMISSIONS = "/system/etc/permissions"


def adapter_main(args):
    import sys

    cmd, *args = args
    root = Path(os.environ["PORTABLE_TEST_ROOT"])
    events = root / ".migration-events"
    mount_state = root / ".mount-state"

    def event(name):
        with events.open("a", encoding="utf-8") as stream:
            stream.write(name + "\n")

    def mapped(path):
        value = Path(path)
        if value.is_absolute() and str(value).startswith("/system/"):
            return root / str(value).lstrip("/")
        if value.is_absolute() and str(value).startswith("/data/"):
            return root / str(value).lstrip("/")
        return value

    if cmd == "boot":
        print("host-fixture-boot")
    elif cmd == "sha":
        print(hashlib.sha256(mapped(args[0]).read_bytes()).hexdigest())
    elif cmd == "meta":
        # Host fixture models Android root-owned system files.
        st = mapped(args[0]).stat()
        print(f"0|0|{st.st_mode & 0o777:o}")
    elif cmd == "size":
        print(mapped(args[0]).stat().st_size)
    elif cmd == "label":
        labels = json.loads((root / ".labels.json").read_text())
        print(labels.get(str(mapped(args[0])), "system_file"))
    elif cmd == "ident":
        labels = json.loads((root / ".labels.json").read_text())
        for path in args:
            target = mapped(path)
            if target.is_symlink() or not target.is_file():
                return 1
            st = target.stat()
            print(f"{hashlib.sha256(target.read_bytes()).hexdigest()}|0|0|{st.st_mode & 0o777:o}|"
                  + labels.get(str(target), "system_file"))
    elif cmd == "size-sum":
        print(sum(mapped(path).stat().st_size for path in args))
    elif cmd == "settle":
        for k in range(0, len(args), 5):
            path, uid, gid, mode, wanted = args[k:k + 5]
            rc = adapter_main(["setmeta", path, uid, gid, mode])
            if rc:
                return rc
            rc = adapter_main(["setlabel", path, wanted])
            if rc:
                return rc
    elif cmd == "setmeta":
        path, uid, gid, mode = args
        target = mapped(path)
        if (os.environ.get("GEN5W_FAIL_ROLLBACK_RESTORE")
                and ".gen5w-preupdate-restore." in str(target)):
            event("injected-rollback-restore-failure")
            return 1
        system_root = root / "system"
        if (mount_state.read_text().strip() == "rw"
                and (target == system_root or system_root in target.parents)):
            counter = root / ".system-setmeta-count"
            count = int(counter.read_text()) if counter.exists() else 0
            count += 1
            counter.write_text(str(count))
            fail_at = int(os.environ.get("GEN5W_FAIL_AFTER_WRITE_COUNT", "0"))
            if ((os.environ.get("GEN5W_FAIL_AFTER_FIRST_WRITE") and count == 2)
                    or (fail_at and count == fail_at)):
                live_first = system_root / "etc/permissions/stock.xml"
                original_inode = int((root / ".stock-xml-original-inode").read_text())
                if mapped("/system/app/HKMC_DiPO.odex").read_bytes() != b"stock-dipo-odex":
                    (root / ".first-target-published-before-failure").write_text("yes\n")
                if (mapped("/system/app/HKMC_DiPO.odex").read_bytes() != b"stock-dipo-odex"
                        and live_first.stat().st_ino != original_inode):
                    (root / ".multiple-targets-published-before-failure").write_text("yes\n")
                event("injected-partial-write-failure")
                return 1
        # Ownership is represented by the metadata adapter in this fixture.
        os.chmod(target, int(mode, 8))
        event("setmeta")
    elif cmd == "setlabel":
        path, label = args
        labels_path = root / ".labels.json"
        labels = json.loads(labels_path.read_text())
        labels[str(mapped(path))] = label
        labels_path.write_text(json.dumps(labels))
        event("setlabel")
    elif cmd == "visible":
        event("visible " + args[0])
        return 0 if (root / ".foreign-mount").exists() else 1
    elif cmd == "bound":
        event("bound " + " ".join(args))
        return 1 if (root / ".foreign-mount").exists() else 0
    elif cmd == "unmount":
        event("unmount " + " ".join(args))
        if (root / ".fail-unmount").exists():
            return 1
    elif cmd == "free-bytes":
        print((root / ".free-bytes").read_text().strip())
    elif cmd == "overlay-status":
        state = root / "data/local/gen5w-portable/overlay/state"
        print("state|" + (state.read_text().strip() if state.exists() else "disabled"))
    elif cmd == "remount-rw":
        event("remount-rw")
        if os.environ.get("GEN5W_FAIL_REMOUNT_RW"):
            return 1
        (root / ".system-setmeta-count").write_text("0")
        recovery = root / "data/local/gen5w-portable/persistent/recovery"
        manifest = recovery / "manifest"
        backups = recovery / "originals/system"
        if (manifest.is_file()
                and (backups / "app/HKMC_DiPO.odex").is_file()
                and (backups / "etc/permissions/stock.xml").is_file()
                and not (backups / "etc/permissions/wireless.xml").exists()):
            (root / ".recovery-before-system-write").write_text("yes\n")
        if os.environ.get("GEN5W_PRECREATE_LIVE_TEMP"):
            live_temp = Path(os.environ["PORTABLE_TEST_LIVE_TEMP"])
            sentinel = root / "live-temp-sentinel"
            sentinel.write_bytes(b"sentinel-must-not-change\n")
            live_temp.symlink_to(sentinel)
        mount_state.write_text("rw")
    elif cmd == "remount-ro":
        event("remount-ro")
        if (root / ".fail-remount-ro").exists():
            return 1
        mount_state.write_text("ro")
    elif cmd == "is-ro":
        return 0 if mount_state.read_text().strip() == "ro" else 1
    elif cmd == "sync":
        event("sync")
    elif cmd in ("reboot", "package", "install"):
        event(cmd + (" " + " ".join(args) if args else ""))
    else:
        print("unknown adapter operation: " + cmd, file=sys.stderr)
        return 64
    return 0


class PersistentMigrationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="persistent-migrate-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.system = self.root / "system"
        self.data = self.root / "data"
        self.usb = self.root / "usb"
        self.stock = self.data / "stock-origins"
        for path in (self.system / "app", self.system / "etc/permissions",
                     self.data / "overlay/files", self.usb, self.stock):
            path.mkdir(parents=True, exist_ok=True)
        (self.root / ".mount-state").write_text("ro")
        (self.root / ".free-bytes").write_text("10000000")
        (self.root / ".labels.json").write_text("{}")
        self.adapter = self.data / "migrate-adapter"
        self.adapter.write_text(
            "#!/bin/sh\nexec python3 " + str(Path(__file__).resolve()) + " --adapter \"$@\"\n",
            encoding="utf-8",
        )
        self.adapter.chmod(0o755)
        self.adapter_exec = self.root / "migrate-adapter-exec"
        self.adapter_exec.write_text(self.adapter.read_text(encoding="utf-8"), encoding="utf-8")
        self.adapter_exec.chmod(0o755)
        mapped_adapter_check = self.root / str(self.adapter_exec).lstrip("/")
        mapped_adapter_check.parent.mkdir(parents=True, exist_ok=True)
        mapped_adapter_check.write_text(self.adapter_exec.read_text(encoding="utf-8"), encoding="utf-8")
        mapped_adapter_check.chmod(0o755)
        self.manifest = self.data / "verified-overlay-manifest"
        self.recovery = self.data / "local/gen5w-portable/persistent/recovery"
        self.owner = self.data / "local/gen5w-portable/persistent/manifest"
        self.static_original = b"stock-dipo-odex"
        self.static_applied = b"portable-dipo-odex-v1"
        self.stock_xml = b"<permissions>stock</permissions>\n"
        self.new_xml = b"<permissions>wireless</permissions>\n"
        self._write(self.system / "app/HKMC_DiPO.odex", self.static_original)
        self._write(self.system / "etc/permissions/stock.xml", self.stock_xml)
        (self.root / ".stock-xml-original-inode").write_text(
            str((self.system / "etc/permissions/stock.xml").stat().st_ino)
        )
        self._write(self.data / "overlay/files/HKMC_DiPO.odex", self.static_applied)
        self._write(self.data / "overlay/files/permissions/stock.xml", self.stock_xml)
        self._write(self.data / "overlay/files/permissions/wireless.xml", self.new_xml)
        self._write(self.stock / "system/app/HKMC_DiPO.odex", self.static_original)
        self._write(self.stock / "system/etc/permissions/stock.xml", self.stock_xml)
        self.stock_index = self.stock / "index.tsv"
        self.write_stock_index()
        labels = {
            str(self.system / "app/HKMC_DiPO.odex"): "stock_app_file",
            str(self.system / "etc/permissions/stock.xml"): "system_file",
            str(self.stock / "system/app/HKMC_DiPO.odex"): "copied_origin_file",
            str(self.stock / "system/etc/permissions/stock.xml"): "copied_origin_file",
        }
        (self.root / ".labels.json").write_text(json.dumps(labels))
        self._write(self.root / "mounts", f"{STATIC}\n{PERMISSIONS}\n".encode())
        self.write_manifest()
        self.env = os.environ.copy()
        self.env.update({
            "PORTABLE_TEST_ROOT": str(self.root),
            "PORTABLE_TEST_MIGRATE_ADAPTER": str(self.adapter_exec),
        })

    def seed_held_overlay(self):
        """Install a held overlay journal and a test overlay command shim.

        The migrator test seam is expected to pass `retire-live hold`, then use
        `retire-restore` after a fully successful rollback or
        `retire-finalize` after migration succeeds. A failed rollback must keep
        the retirement plan pending and must not call restore.
        """
        self.overlay = self.data / "local/gen5w-portable/overlay"
        self.overlay.mkdir(parents=True, exist_ok=True)
        (self.overlay / "state").write_text("committed\n")
        (self.overlay / "boot").write_text("host-fixture-boot\n")
        (self.overlay / "journal").write_text(
            STATIC + "|stock-identity\n", encoding="ascii"
        )
        (self.root / "mounts").write_text(STATIC + "\n")
        (self.root / "mapping").write_text(
            "/data/overlay/files/HKMC_DiPO.odex|" + STATIC + "\n"
        )
        self.overlay_shim = self.data / "overlay-command-shim"
        self.overlay_shim.write_text(
            "#!/bin/sh\n"
            "exec python3 " + str(Path(__file__).resolve())
            + " --overlay-adapter \"$@\"\n",
            encoding="utf-8",
        )
        self.overlay_shim.chmod(0o755)
        self.env.update({
            "PORTABLE_TEST_OVERLAY_STATE": "/data/local/gen5w-portable/overlay",
            "PORTABLE_TEST_OVERLAY_SHELL": str(self.overlay_shim),
            "PORTABLE_TEST_ZYGOTE_STATE": "running",
        })

    def overlay_events(self):
        path = self.root / ".overlay-events"
        return path.read_text().splitlines() if path.exists() else []

    def assert_overlay_restored(self):
        self.assertEqual((self.overlay / "state").read_text(), "committed\n")
        self.assertFalse((self.overlay / "retire.plan").exists())
        self.assertEqual((self.root / "mounts").read_text(), STATIC + "\n")

    def assert_overlay_pending_without_rebind(self):
        self.assertTrue((self.overlay / "retire.plan").is_file())
        self.assertEqual((self.overlay / "state").read_text(), "retired-pending\n")
        self.assertEqual((self.root / "mounts").read_text(), "")
        self.assertNotIn("retire-restore", self.overlay_events())

    @staticmethod
    def digest(data):
        return hashlib.sha256(data).hexdigest()

    @staticmethod
    def _write(path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        path.chmod(0o644)

    def write_manifest(self, applied=None, bad_source=False):
        applied = applied or self.static_applied
        source_hash = self.digest(applied)
        if bad_source:
            source_hash = "0" * 64
        rows = [
            "dipo|/data/overlay/files/HKMC_DiPO.odex|/system/app/HKMC_DiPO.odex|"
            + source_hash + "|0|0|644|static",
        ]
        stock_row = "stock.xml|" + self.digest(self.stock_xml) + "|0|0|644\n"
        authored_row = "wireless.xml|" + self.digest(self.new_xml) + "|0|0|644\n"
        directory_digest = self.digest((stock_row + authored_row + stock_row).encode())
        rows.append(
            "projection|/data/overlay/files/permissions|/system/etc/permissions|"
            + directory_digest + "|0|0|755|directory"
        )
        self.manifest.write_text("\n".join(rows) + "\n", encoding="ascii")

    def write_stock_index(self, rows=None):
        if rows is None:
            rows = [
                "|".join([STATIC, self.digest(self.static_original), "0", "0", "644", "stock_app_file"]),
                "|".join([PERMISSIONS + "/stock.xml", self.digest(self.stock_xml), "0", "0", "644", "system_file"]),
            ]
        self.stock_index.write_text("\n".join(rows) + "\n", encoding="ascii")

    def set_copied_origin_labels_to_indexed_values(self):
        labels_path = self.root / ".labels.json"
        labels = json.loads(labels_path.read_text())
        labels[str(self.stock / "system/app/HKMC_DiPO.odex")] = "stock_app_file"
        labels[str(self.stock / "system/etc/permissions/stock.xml")] = "system_file"
        labels_path.write_text(json.dumps(labels))

    def run_migration(self, **extra_env):
        env = self.env.copy()
        env.update(dict(extra_env))
        return subprocess.run(
            [os.environ.get("MIGRATE_SHELL","mksh"), *os.environ.get("MIGRATE_SHELL_ARGS","").split(), str(MIGRATE), "apply", "/data/verified-overlay-manifest", "/data/stock-origins"],
            env=env, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, timeout=35, errors="replace",
        )

    def events(self):
        path = self.root / ".migration-events"
        return path.read_text().splitlines() if path.exists() else []

    def backup(self, target):
        return self.recovery / "originals" / target.lstrip("/")

    def seed_existing_manifests(self):
        self.backup(STATIC).parent.mkdir(parents=True, exist_ok=True)
        self.backup(STATIC).write_bytes(self.static_original)
        original_hash = self.digest(self.static_original)
        applied_hash = self.digest(self.static_applied)
        row = "|".join([
            STATIC, "file", original_hash, applied_hash,
            "0", "0", "644", "system_file",
            "0", "0", "644", "system_file",
        ])
        self.recovery.mkdir(parents=True, exist_ok=True)
        (self.recovery / "manifest").write_text(
            "GEN5W-RECOVERY-MANIFEST|1\n" + row + "\n", encoding="ascii"
        )
        self.owner.parent.mkdir(parents=True, exist_ok=True)
        self.owner.write_text("existing-owner-manifest\n", encoding="ascii")

    def assert_malformed_existing_recovery_refused(self, mutate):
        self.seed_existing_manifests()
        mutate()
        old_recovery = (self.recovery / "manifest").read_bytes()
        old_owner = self.owner.read_bytes()

        result = self.run_migration()

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.recovery / "manifest").read_bytes(), old_recovery)
        self.assertEqual(self.owner.read_bytes(), old_owner)
        self.assertNotIn("remount-rw", self.events())
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assert_no_external_actions()

    def read_recovery_rows(self):
        lines = (self.recovery / "manifest").read_text(encoding="ascii").splitlines()
        self.assertEqual(lines[0], "GEN5W-RECOVERY-MANIFEST|1")
        return {parts[0]: parts for parts in (line.split("|") for line in lines[1:])}

    def assert_no_external_actions(self):
        events = self.events()
        self.assertFalse(any("reboot" in event or "package" in event for event in events))

    def assert_only_allowlisted_system_files(self):
        actual = sorted(path.relative_to(self.system).as_posix()
                        for path in self.system.rglob("*") if path.is_file())
        self.assertEqual(actual, [
            "app/HKMC_DiPO.odex",
            "etc/permissions/stock.xml",
            "etc/permissions/wireless.xml",
        ])

    def test_migrates_bootguard_qb_runtime_with_immutable_original(self):
        target = "/system/etc/qb_runtime.sh"
        original = b"#!/system/bin/sh\n# stock\n"
        applied = b"#!/system/bin/sh\n# hook\n# stock\n"
        self._write(self.system / target.removeprefix("/system/"), original)
        self._write(self.stock / target.lstrip("/"), original)
        self._write(self.data / "overlay/files/qb_runtime.sh", applied)
        with self.stock_index.open("a") as stream:
            stream.write(target + "|" + self.digest(original) + "|0|0|644|system_file\n")
        with self.manifest.open("a") as stream:
            stream.write("bootguard|/data/overlay/files/qb_runtime.sh|" + target
                         + "|" + self.digest(applied) + "|0|0|644|static\n")
        labels_path = self.root / ".labels.json"
        labels = json.loads(labels_path.read_text())
        labels[str(self.system / "etc/qb_runtime.sh")] = "system_file"
        labels_path.write_text(json.dumps(labels))
        result = self.run_migration()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.system / "etc/qb_runtime.sh").read_bytes(), applied)
        self.assertEqual(self.backup(target).read_bytes(), original)
        self.assertIn(target, self.read_recovery_rows())
        self.assert_no_external_actions()

    def test_migrates_dongle_stand_in_with_immutable_original(self):
        # USB Wi-Fi dongle backend: the stock Broadcom module is replaced by the
        # stand-in and must be restorable from its immutable original.
        target = "/system/wifi/bcmdhd.ko"
        original = b"stock-bcmdhd"
        applied = b"stand-in-bcmdhd"
        self._write(self.system / target.removeprefix("/system/"), original)
        self._write(self.stock / target.lstrip("/"), original)
        self._write(self.data / "overlay/files/bcmdhd.ko", applied)
        with self.stock_index.open("a") as stream:
            stream.write(target + "|" + self.digest(original) + "|0|0|644|system_file\n")
        with self.manifest.open("a") as stream:
            stream.write("dongle|/data/overlay/files/bcmdhd.ko|" + target
                         + "|" + self.digest(applied) + "|0|0|644|static\n")
        labels_path = self.root / ".labels.json"
        labels = json.loads(labels_path.read_text())
        labels[str(self.system / "wifi/bcmdhd.ko")] = "system_file"
        labels_path.write_text(json.dumps(labels))
        result = self.run_migration()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.system / "wifi/bcmdhd.ko").read_bytes(), applied)
        self.assertEqual(self.backup(target).read_bytes(), original)
        self.assertIn(target, self.read_recovery_rows())
        self.assert_no_external_actions()

    def test_migrates_file_and_expands_permissions_directory_with_recovery_first(self):
        result = self.run_migration()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.system / "app/HKMC_DiPO.odex").read_bytes(), self.static_applied)
        self.assertEqual((self.system / "etc/permissions/stock.xml").read_bytes(), self.stock_xml)
        self.assertEqual((self.system / "etc/permissions/wireless.xml").read_bytes(), self.new_xml)
        self.assertEqual(self.backup(STATIC).read_bytes(), self.static_original)
        self.assertEqual(self.backup(PERMISSIONS + "/stock.xml").read_bytes(), self.stock_xml)
        rows = self.read_recovery_rows()
        self.assertEqual(rows[STATIC][1], "file")
        self.assertEqual(rows[STATIC][7], "stock_app_file")
        self.assertEqual(rows[PERMISSIONS + "/stock.xml"][1], "file")
        self.assertEqual(rows[PERMISSIONS + "/stock.xml"][7], "system_file")
        self.assertEqual(rows[PERMISSIONS + "/wireless.xml"][1], "absent")
        self.assertTrue((self.stock / "system/app/HKMC_DiPO.odex").is_file())
        self.assertTrue((self.stock / "system/etc/permissions/stock.xml").is_file())
        self.assertTrue((self.root / ".recovery-before-system-write").is_file())
        self.assert_only_allowlisted_system_files()
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assertTrue(self.owner.is_file())
        self.assert_no_external_actions()

    def test_update_keeps_first_original_backups_immutable(self):
        first = self.run_migration()
        self.assertEqual(first.returncode, 0, first.stdout)
        original_backup = self.backup(STATIC).read_bytes()
        prior_applied = self.digest(self.static_applied)
        updated = b"portable-dipo-odex-v2"
        self._write(self.data / "overlay/files/HKMC_DiPO.odex", updated)
        self.write_manifest(applied=updated)

        result = self.run_migration()

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.system / "app/HKMC_DiPO.odex").read_bytes(), updated)
        self.assertEqual(self.backup(STATIC).read_bytes(), original_backup)
        recovery_lines = (self.recovery / "manifest").read_text(encoding="ascii").splitlines()
        self.assertEqual(recovery_lines[0], "GEN5W-RECOVERY-MANIFEST|2")
        rows = {parts[0]: parts for parts in (line.split("|") for line in recovery_lines[1:])}
        self.assertEqual(len(rows[STATIC]), 13)
        self.assertEqual(rows[STATIC][12], prior_applied)
        self.assertEqual(self.backup(STATIC).read_bytes(), self.static_original)
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assert_no_external_actions()

    def test_foreign_mount_refuses_without_system_mutation(self):
        (self.root / ".foreign-mount").touch()
        before = (self.system / "app/HKMC_DiPO.odex").read_bytes()
        result = self.run_migration()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.system / "app/HKMC_DiPO.odex").read_bytes(), before)
        self.assertNotIn("remount-rw", self.events())
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assert_no_external_actions()
        self.assert_no_external_actions()

    def test_source_hash_mismatch_refuses_before_system_mutation(self):
        self.write_manifest(bad_source=True)
        before = (self.system / "app/HKMC_DiPO.odex").read_bytes()
        result = self.run_migration()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.system / "app/HKMC_DiPO.odex").read_bytes(), before)
        self.assertNotIn("remount-rw", self.events())
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assert_no_external_actions()

    def test_source_hash_failure_preserves_existing_manifests_before_publication(self):
        self.seed_existing_manifests()
        old_recovery = (self.recovery / "manifest").read_bytes()
        old_owner = self.owner.read_bytes()
        self.write_manifest(bad_source=True)

        result = self.run_migration()

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.recovery / "manifest").read_bytes(), old_recovery)
        self.assertEqual(self.owner.read_bytes(), old_owner)
        self.assertNotIn("remount-rw", self.events())
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assert_no_external_actions()

    def test_duplicate_target_in_existing_recovery_manifest_refuses_preserving_manifests(self):
        def mutate():
            path = self.recovery / "manifest"
            lines = path.read_text(encoding="ascii").splitlines()
            path.write_text("\n".join(lines + [lines[1]]) + "\n", encoding="ascii")

        self.assert_malformed_existing_recovery_refused(mutate)

    def test_wrong_field_count_in_existing_recovery_manifest_refuses_preserving_manifests(self):
        def mutate():
            path = self.recovery / "manifest"
            lines = path.read_text(encoding="ascii").splitlines()
            lines[1] += "|unexpected"
            path.write_text("\n".join(lines) + "\n", encoding="ascii")

        self.assert_malformed_existing_recovery_refused(mutate)

    def test_invalid_hash_in_existing_recovery_manifest_refuses_preserving_manifests(self):
        def mutate():
            path = self.recovery / "manifest"
            lines = path.read_text(encoding="ascii").splitlines()
            fields = lines[1].split("|")
            fields[2] = "not-a-sha256"
            lines[1] = "|".join(fields)
            path.write_text("\n".join(lines) + "\n", encoding="ascii")

        self.assert_malformed_existing_recovery_refused(mutate)

    def test_invalid_kind_in_existing_recovery_manifest_refuses_preserving_manifests(self):
        def mutate():
            path = self.recovery / "manifest"
            lines = path.read_text(encoding="ascii").splitlines()
            fields = lines[1].split("|")
            fields[1] = "directory"
            lines[1] = "|".join(fields)
            path.write_text("\n".join(lines) + "\n", encoding="ascii")

        self.assert_malformed_existing_recovery_refused(mutate)

    def test_unsupported_target_in_existing_recovery_manifest_refuses_preserving_manifests(self):
        def mutate():
            path = self.recovery / "manifest"
            lines = path.read_text(encoding="ascii").splitlines()
            fields = lines[1].split("|")
            fields[0] = "/system/app/../outside"
            lines[1] = "|".join(fields)
            path.write_text("\n".join(lines) + "\n", encoding="ascii")

        self.assert_malformed_existing_recovery_refused(mutate)

    def test_mismatched_existing_backup_refuses_preserving_manifests(self):
        def mutate():
            self.backup(STATIC).write_bytes(b"foreign-backup-bytes\n")

        self.assert_malformed_existing_recovery_refused(mutate)

    def test_missing_existing_backup_refuses_preserving_manifests(self):
        def mutate():
            self.backup(STATIC).unlink()

        self.assert_malformed_existing_recovery_refused(mutate)

    def test_missing_stock_origin_index_row_refuses_before_system_mutation(self):
        self.set_copied_origin_labels_to_indexed_values()
        self.write_stock_index([
            "|".join([PERMISSIONS + "/stock.xml", self.digest(self.stock_xml), "0", "0", "644", "system_file"]),
        ])
        before = (self.system / "app/HKMC_DiPO.odex").read_bytes()

        result = self.run_migration()

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.system / "app/HKMC_DiPO.odex").read_bytes(), before)
        self.assertNotIn("remount-rw", self.events())
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assert_no_external_actions()

    def test_duplicate_stock_origin_index_target_refuses_before_system_mutation(self):
        self.set_copied_origin_labels_to_indexed_values()
        static_row = "|".join([STATIC, self.digest(self.static_original), "0", "0", "644", "stock_app_file"])
        xml_row = "|".join([PERMISSIONS + "/stock.xml", self.digest(self.stock_xml), "0", "0", "644", "system_file"])
        self.write_stock_index([static_row, xml_row, static_row])
        before = (self.system / "app/HKMC_DiPO.odex").read_bytes()

        result = self.run_migration()

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.system / "app/HKMC_DiPO.odex").read_bytes(), before)
        self.assertNotIn("remount-rw", self.events())
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assert_no_external_actions()

    def test_stock_origin_index_metadata_mismatch_refuses_before_system_mutation(self):
        self.set_copied_origin_labels_to_indexed_values()
        self.write_stock_index([
            "|".join([STATIC, self.digest(self.static_original), "0", "0", "600", "stock_app_file"]),
            "|".join([PERMISSIONS + "/stock.xml", self.digest(self.stock_xml), "0", "0", "644", "system_file"]),
        ])
        before = (self.system / "app/HKMC_DiPO.odex").read_bytes()

        result = self.run_migration()

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.system / "app/HKMC_DiPO.odex").read_bytes(), before)
        self.assertNotIn("remount-rw", self.events())
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assert_no_external_actions()

    def test_low_space_failure_preserves_existing_manifests_before_publication(self):
        self.seed_existing_manifests()
        old_recovery = (self.recovery / "manifest").read_bytes()
        old_owner = self.owner.read_bytes()
        (self.root / ".free-bytes").write_text("0")

        result = self.run_migration()

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.recovery / "manifest").read_bytes(), old_recovery)
        self.assertEqual(self.owner.read_bytes(), old_owner)
        self.assertNotIn("remount-rw", self.events())
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assert_no_external_actions()

    def test_low_space_refuses_before_system_mutation(self):
        (self.root / ".free-bytes").write_text("0")
        before = (self.system / "app/HKMC_DiPO.odex").read_bytes()
        result = self.run_migration()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.system / "app/HKMC_DiPO.odex").read_bytes(), before)
        self.assertNotIn("remount-rw", self.events())
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")

    def test_partial_write_failure_rolls_back_and_returns_read_only(self):
        before_static = (self.system / "app/HKMC_DiPO.odex").read_bytes()
        before_xml = (self.system / "etc/permissions/stock.xml").read_bytes()
        result = self.run_migration(GEN5W_FAIL_AFTER_FIRST_WRITE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.root / ".first-target-published-before-failure").is_file())
        self.assertEqual((self.system / "app/HKMC_DiPO.odex").read_bytes(), before_static)
        self.assertEqual((self.system / "etc/permissions/stock.xml").read_bytes(), before_xml)
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assert_no_external_actions()

    def test_held_retirement_restores_after_failure_before_system_write(self):
        self.seed_held_overlay()
        before = (self.system / "app/HKMC_DiPO.odex").read_bytes()

        result = self.run_migration(GEN5W_FAIL_REMOUNT_RW="1")

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.system / "app/HKMC_DiPO.odex").read_bytes(), before)
        self.assertEqual(self.overlay_events(), [
            "retire-live hold", "retire-restore:stock",
        ])
        self.assert_overlay_restored()
        self.assertNotIn("stop-android", self.events())
        self.assertNotIn("start-android", self.events())

    def test_held_retirement_restores_only_after_exact_partial_write_rollback(self):
        self.seed_held_overlay()

        result = self.run_migration(GEN5W_FAIL_AFTER_WRITE_COUNT="3")

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.system / "app/HKMC_DiPO.odex").read_bytes(), self.static_original)
        self.assertEqual((self.system / "etc/permissions/stock.xml").read_bytes(), self.stock_xml)
        self.assertTrue((self.root / ".multiple-targets-published-before-failure").is_file())
        self.assertEqual(self.overlay_events(), [
            "retire-live hold", "retire-restore:stock",
        ])
        self.assert_overlay_restored()
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")

    def test_failed_exact_rollback_keeps_retirement_pending_without_rebind(self):
        self.seed_held_overlay()

        result = self.run_migration(
            GEN5W_FAIL_AFTER_FIRST_WRITE="1",
            GEN5W_FAIL_ROLLBACK_RESTORE="1",
        )

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.system / "app/HKMC_DiPO.odex").read_bytes(), self.static_applied), result.stdout
        self.assertEqual(self.overlay_events(), ["retire-live hold"])
        self.assert_overlay_pending_without_rebind()
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")

    def test_successful_migration_finalizes_held_retirement(self):
        self.seed_held_overlay()

        result = self.run_migration()

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.system / "app/HKMC_DiPO.odex").read_bytes(), self.static_applied)
        self.assertEqual(self.overlay_events(), [
            "retire-live hold", "retire-finalize",
        ])
        self.assertEqual((self.overlay / "state").read_text(), "retired\n")
        self.assertEqual((self.overlay / "journal").read_text(), "")
        self.assertFalse((self.overlay / "retire.plan").exists())
        self.assertEqual((self.root / "mounts").read_text(), "")
        self.assertNotIn("stop-android", self.events())
        self.assertNotIn("start-android", self.events())

    def test_remount_ro_busy_after_verified_apply_defers_ro_to_reboot(self):
        # Linux refuses MS_RDONLY while replaced files are still mapped by
        # running stock processes (seen in the V039 VM: EBUSY). Every target
        # is verified before this point, so the install completes and the
        # required reboot mounts /system read-only again.
        (self.root / ".fail-remount-ro").touch()
        result = self.run_migration()
        self.assertEqual(result.returncode, 0, str(result.stdout))
        self.assertIn("stays writable until the required reboot", result.stdout)
        self.assertIn("read-only after the required reboot", result.stdout)
        self.assertEqual((self.root / ".mount-state").read_text(), "rw")
        self.assertNotIn("reboot", self.events())

    def test_symlinked_live_new_temp_refuses_without_touching_sentinel(self):
        sentinel = self.root / "live-temp-sentinel"

        result = self.run_migration(GEN5W_PRECREATE_LIVE_TEMP="1")

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(sentinel.read_bytes(), b"sentinel-must-not-change\n")
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assertNotIn("reboot", self.events())
        self.assert_no_external_actions()


    def test_stale_overlay_journal_from_earlier_boot_is_not_retired(self):
        # Vehicle 2026-11-19: a journal of an earlier boot reports expired;
        # nothing is bound, so migration must not demand a same-boot retirement.
        self.seed_held_overlay()
        (self.overlay / "state").write_text("expired\n")
        (self.root / "mounts").write_text("")

        result = self.run_migration()

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.system / "app/HKMC_DiPO.odex").read_bytes(), self.static_applied)
        self.assertEqual(self.overlay_events(), [])

def overlay_adapter_main(args):
    import sys

    root = Path(os.environ["PORTABLE_TEST_ROOT"])
    overlay = root / "data/local/gen5w-portable/overlay"
    events = root / ".overlay-events"
    cmd = " ".join(args)

    def event(name):
        with events.open("a", encoding="utf-8") as stream:
            stream.write(name + "\n")

    if args == ["status"]:
        state = overlay / "state"
        print("state|" + (state.read_text().strip() if state.exists() else "disabled"))
    elif args == ["retire-live", "hold"]:
        event(cmd)
        (overlay / "retire.plan").write_text(
            STATIC + "|stock-identity\n", encoding="ascii"
        )
        (overlay / "state").write_text("retired-pending\n")
        (root / "mounts").write_text("")
    elif args == ["retire-restore"]:
        live = root / "system/app/HKMC_DiPO.odex"
        stock_xml = root / "system/etc/permissions/stock.xml"
        if (live.read_bytes() != b"stock-dipo-odex"
                or stock_xml.read_bytes() != b"<permissions>stock</permissions>\n"):
            event("retire-restore:before-stock-rollback")
            print("test overlay adapter observed non-stock target before rebind", file=sys.stderr)
            return 1
        event("retire-restore:stock")
        (overlay / "state").write_text("committed\n")
        (root / "mounts").write_text(STATIC + "\n")
        (overlay / "retire.plan").unlink(missing_ok=True)
    elif args == ["retire-finalize"]:
        event(cmd)
        (overlay / "state").write_text("retired\n")
        (overlay / "journal").write_text("")
        (overlay / "retire.plan").unlink(missing_ok=True)
    else:
        print("unknown overlay adapter operation: " + cmd, file=sys.stderr)
        return 64
    return 0


if __name__ == "__main__":
    if len(os.sys.argv) > 1 and os.sys.argv[1] == "--adapter":
        raise SystemExit(adapter_main(os.sys.argv[2:]))
    if len(os.sys.argv) > 1 and os.sys.argv[1] == "--overlay-adapter":
        raise SystemExit(overlay_adapter_main(os.sys.argv[2:]))
    unittest.main(verbosity=2)
