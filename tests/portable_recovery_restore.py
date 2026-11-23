#!/usr/bin/env python3
"""Host fixtures for the fixed-function emergency restore script."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RESTORE = ROOT / "tools" / "portable" / "recovery-usb" / "restore.sh"
TARGET = "/system/app/HKMC_DiPO.odex"
ABSENT = "/system/etc/permissions/com.hkmc.software.connectivity.carplay_wireless.xml"
WIFI_ABSENT = "/system/etc/permissions/android.hardware.wifi.xml"


def helper_main(args):
    import sys
    cmd, *args = args
    root = Path(os.environ["GEN5W_RECOVERY_TEST_ROOT"])
    events = root / ".events"
    mount = root / ".mount-state"

    def event(name):
        with events.open("a", encoding="utf-8") as stream:
            stream.write(name + "\n")

    if cmd == "sha256":
        if os.environ.get("GEN5W_SYMLINK_RESTORE_TEMP"):
            guard = root / ".restore-temp-symlink-created"
            if not guard.exists():
                guard.write_text("created\n")
                sentinel = root / "restore-temp-sentinel"
                sentinel.write_text("must remain unchanged\n")
                temp_path = Path(os.environ["GEN5W_RECOVERY_TEST_TMP"])
                temp_path.symlink_to(sentinel)
        print(hashlib.sha256(Path(args[0]).read_bytes()).hexdigest())
    elif cmd == "boot":
        print((root / ".boot-id").read_text().strip())
    elif cmd == "metadata":
        st = Path(args[0]).stat()
        print(f"{st.st_uid}|{st.st_gid}|{stat.S_IMODE(st.st_mode):o}")
    elif cmd == "label":
        labels = json.loads((root / ".labels.json").read_text())
        print(labels.get(str(Path(args[0])), "system_file"))
    elif cmd == "setmeta":
        if os.environ.get("GEN5W_FAIL_SETMETA"):
            return 1
        path, uid, gid, mode = args
        os.chown(path, int(uid), int(gid))
        os.chmod(path, int(mode, 8))
    elif cmd == "setlabel":
        path, label = args
        file = root / ".labels.json"
        labels = json.loads(file.read_text()) if file.exists() else {}
        labels[str(Path(path))] = label
        file.write_text(json.dumps(labels))
    elif cmd == "remount-rw":
        event(cmd)
        if os.environ.get("GEN5W_FAIL_RW"):
            return 1
        mount.write_text("rw")
        if os.environ.get("GEN5W_TERM_AFTER_RW"):
            os.kill(os.getppid(), signal.SIGTERM)
            return 0
        if os.environ.get("GEN5W_SWAP_PARENT_TO_SYMLINK"):
            app = root / "system/app"
            moved = root / "system/app-before-symlink"
            outside = root / "outside-app"
            outside.mkdir()
            outside_target = outside / "HKMC_DiPO.odex"
            outside_target.write_bytes(b"patched-dipo")
            outside_target.chmod(0o644)
            app.rename(moved)
            app.symlink_to(outside, target_is_directory=True)
        if os.environ.get("GEN5W_MUTATE_ON_RW"):
            (root / "system/app/HKMC_DiPO.odex").write_bytes(b"foreign during remount")
    elif cmd == "remount-ro":
        event(cmd)
        if os.environ.get("GEN5W_FAIL_RO"):
            return 1
        if os.environ.get("GEN5W_LIE_RO"):
            return 0
        mount.write_text("ro")
    elif cmd == "is-ro":
        return 0 if mount.read_text() == "ro" else 1
    elif cmd == "sync":
        event(cmd)
    elif cmd == "reboot":
        event(cmd)
        if os.environ.get("GEN5W_FAIL_REBOOT"):
            return 1
        (root / ".boot-id").write_text("22222222-3333-4444-8555-666666666666")
        if os.environ.get("GEN5W_CUT_AFTER_REBOOT"):
            os.kill(os.getppid(), signal.SIGKILL)
    else:
        print("unknown test helper operation", file=sys.stderr)
        return 64
    return 0


class RecoveryRestoreTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gen5w-recovery-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.system = self.root / "system"
        self.usb = self.root / "usb"
        self.recovery = self.root / "data/local/gen5w-portable/persistent/recovery"
        self.originals = self.recovery / "originals"
        for path in (self.system / "app", self.system / "etc/permissions",
                     self.usb / "bin", self.recovery):
            path.mkdir(parents=True, exist_ok=True)
        self.driver = Path(__file__).resolve()
        self.helper = self.usb / "bin/dex-patch"
        self.helper.write_text(
            "#!/bin/sh\nexec python3 " + str(self.driver) + " --helper \"$@\"\n",
            encoding="utf-8",
        )
        self.helper.chmod(0o755)
        (self.root / ".mount-state").write_text("ro")
        (self.root / ".boot-id").write_text("11111111-2222-4333-8444-555555555555")
        (self.root / ".labels.json").write_text("{}")
        self.rows = []
        self.add_file(TARGET, b"patched-dipo", b"stock-dipo")
        self.add_absent(ABSENT, b"wireless-permission")
        self.write_manifest()

    def live(self, target):
        return self.root / target.lstrip("/")

    def backup(self, target):
        return self.originals / target.lstrip("/")

    @staticmethod
    def digest(data):
        return hashlib.sha256(data).hexdigest()

    @staticmethod
    def meta(path):
        st = path.stat()
        return str(st.st_uid), str(st.st_gid), format(stat.S_IMODE(st.st_mode), "o")

    def add_file(self, target, patched, original):
        live = self.live(target)
        live.parent.mkdir(parents=True, exist_ok=True)
        live.write_bytes(patched)
        live.chmod(0o644)
        backup = self.backup(target)
        backup.parent.mkdir(parents=True, exist_ok=True)
        backup.write_bytes(original)
        backup.chmod(0o644)
        meta = self.meta(backup)
        self.rows.append([target, "file", self.digest(original), self.digest(patched),
                          *meta, "system_file", *meta, "system_file"])
        labels = json.loads((self.root / ".labels.json").read_text())
        labels[str(live)] = labels[str(backup)] = "system_file"
        (self.root / ".labels.json").write_text(json.dumps(labels))

    def add_absent(self, target, patched):
        live = self.live(target)
        live.parent.mkdir(parents=True, exist_ok=True)
        live.write_bytes(patched)
        live.chmod(0o644)
        meta = self.meta(live)
        self.rows.append([target, "absent", "-", self.digest(patched),
                          "-", "-", "-", "-", *meta, "system_file"])
        labels = json.loads((self.root / ".labels.json").read_text())
        labels[str(live)] = "system_file"
        (self.root / ".labels.json").write_text(json.dumps(labels))

    def write_manifest(self, rows=None):
        entries = self.rows if rows is None else rows
        body = "GEN5W-RECOVERY-MANIFEST|1\n"
        body += "".join("|".join(row) + "\n" for row in entries)
        self.recovery.joinpath("manifest").write_text(body, encoding="ascii")

    def write_manifest_v2(self, prior_applied_sha, rows=None):
        entries = self.rows if rows is None else rows
        body = "GEN5W-RECOVERY-MANIFEST|2\n"
        for index, row in enumerate(entries):
            prior = prior_applied_sha if index == 0 else "-"
            body += "|".join(row + [prior]) + "\n"
        self.recovery.joinpath("manifest").write_text(body, encoding="ascii")

    def run_restore(self, **extra_env):
        env = os.environ.copy()
        env.update({
            "GEN5W_RECOVERY_TEST_ROOT": str(self.root),
            "GEN5W_RECOVERY_TEST_USB": str(self.usb),
            "GEN5W_RECOVERY_TEST_HELPER": str(self.helper),
        })
        env.update(extra_env)
        return subprocess.run(["mksh", str(RESTORE)], env=env, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10)

    def events(self):
        path = self.root / ".events"
        return path.read_text().splitlines() if path.exists() else []

    def test_restores_original_and_absent_targets_then_reboots_once(self):
        result = self.run_restore()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.live(TARGET).read_bytes(), b"stock-dipo")
        self.assertFalse(self.live(ABSENT).exists())
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assertEqual(self.events().count("reboot"), 1)
        self.assertTrue((self.usb / "GEN5W-RECOVERY-RESULT.txt").is_file())

    def test_restores_dongle_stand_in_to_stock_wifi_module(self):
        target = "/system/wifi/bcmdhd.ko"
        self.add_file(target, b"stand-in-bcmdhd", b"stock-bcmdhd")
        self.write_manifest()
        result = self.run_restore()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.live(target).read_bytes(), b"stock-bcmdhd")
        self.assertEqual(self.live(TARGET).read_bytes(), b"stock-dipo")
        self.assertEqual(self.events().count("reboot"), 1)

    def test_bootguard_invokes_real_restore_and_restores_qb_runtime(self):
        target = "/system/etc/qb_runtime.sh"
        self.add_file(target, b"#!/system/bin/sh\n# hook\n", b"#!/system/bin/sh\n# stock\n")
        self.write_manifest()
        guard = self.root / "data/local/gen5w-portable/persistent/bootguard"
        (guard / "bin").mkdir(parents=True)
        (guard / "restore.sh").write_bytes(RESTORE.read_bytes())
        (guard / "bin/dex-patch").write_bytes(self.helper.read_bytes())
        (guard / "bin/dex-patch").chmod(0o755)
        (guard / "count").write_text("4\n")
        state = self.root / "data/local/gen5w-portable/boot"
        state.mkdir()
        env = os.environ.copy()
        env.update({
            "PORTABLE_TEST_ROOT": str(self.root),
            "PORTABLE_TEST_SH": "/usr/bin/mksh",
            "GEN5W_RECOVERY_TEST_ROOT": str(self.root),
            "GEN5W_RECOVERY_TEST_USB": str(guard),
            "GEN5W_RECOVERY_TEST_HELPER": str(guard / "bin/dex-patch"),
        })
        result = subprocess.run(["mksh", str(ROOT / "tools/portable/bootguard.sh")],
                                env=env, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + (guard / "guard.log").read_text())
        self.assertEqual(self.live(target).read_bytes(), b"#!/system/bin/sh\n# stock\n")
        self.assertEqual(self.live(TARGET).read_bytes(), b"stock-dipo")
        self.assertEqual((state / "enabled").read_text(), "0\n")
        self.assertEqual((state / "reason").read_text(), "bootguard-restored\n")
        self.assertTrue((guard / "tripped").is_file())
        self.assertEqual(self.events().count("reboot"), 1)
        self.assertIn("result=restored", (guard / "GEN5W-RECOVERY-RESULT.txt").read_text())
        # Next boot: the restored report latches the guard; no second restore or reboot.
        again = subprocess.run(["mksh", str(ROOT / "tools/portable/bootguard.sh")],
                               env=env, text=True, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, timeout=15)
        self.assertEqual(again.returncode, 0, again.stdout)
        self.assertEqual(self.events().count("reboot"), 1)
        self.assertIn("latched: stock was already restored", (guard / "guard.log").read_text())

    def test_v1_twelve_column_manifest_remains_compatible(self):
        manifest = (self.recovery / "manifest").read_text(encoding="ascii")
        self.assertEqual(manifest.splitlines()[0], "GEN5W-RECOVERY-MANIFEST|1")
        self.assertEqual(len(manifest.splitlines()[1].split("|")), 12)

        result = self.run_restore()

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.live(TARGET).read_bytes(), b"stock-dipo")

    def test_v2_prior_applied_hash_accepts_and_restores_original(self):
        prior = b"previous-portable-dipo"
        self.live(TARGET).write_bytes(prior)
        self.live(TARGET).chmod(0o644)
        self.write_manifest_v2(self.digest(prior))

        result = self.run_restore()

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.live(TARGET).read_bytes(), b"stock-dipo")
        self.assertFalse(self.live(ABSENT).exists())
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assertEqual(self.events().count("reboot"), 1)

    def test_v2_unknown_prior_applied_hash_refuses_before_write(self):
        unknown_prior = b"unknown-previous-portable-dipo"
        self.live(TARGET).write_bytes(unknown_prior)
        self.live(TARGET).chmod(0o644)
        self.write_manifest_v2(self.digest(b"different-previous-version"))

        result = self.run_restore()

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.live(TARGET).read_bytes(), unknown_prior)
        self.assertNotIn("remount-rw", self.events())
        self.assertNotIn("reboot", self.events())

    def test_wifi_permission_absent_target_is_allowlisted_and_removed(self):
        self.add_absent(WIFI_ABSENT, b"patched-wifi-permission")
        self.write_manifest()

        result = self.run_restore()

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(self.live(WIFI_ABSENT).exists())
        self.assertEqual(self.live(TARGET).read_bytes(), b"stock-dipo")
        self.assertFalse(self.live(ABSENT).exists())
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assertEqual(self.events().count("reboot"), 1)

    def test_foreign_live_hash_refuses_before_any_write(self):
        self.live(TARGET).write_bytes(b"foreign change")
        result = self.run_restore()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.live(TARGET).read_bytes(), b"foreign change")
        self.assertNotIn("remount-rw", self.events())
        self.assertNotIn("reboot", self.events())

    def test_corrupt_backup_refuses_before_any_write(self):
        self.backup(TARGET).write_bytes(b"corrupt backup")
        result = self.run_restore()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.live(TARGET).read_bytes(), b"patched-dipo")
        self.assertNotIn("remount-rw", self.events())

    def test_backup_storage_metadata_does_not_have_to_match_system_original(self):
        backup = self.backup(TARGET)
        backup.chmod(0o600)
        labels = json.loads((self.root / ".labels.json").read_text())
        labels[str(backup)] = "recovery_data_file"
        (self.root / ".labels.json").write_text(json.dumps(labels))

        result = self.run_restore()

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.live(TARGET).read_bytes(), b"stock-dipo")
        self.assertEqual(self.meta(self.live(TARGET)), tuple(self.rows[0][4:7]))
        labels = json.loads((self.root / ".labels.json").read_text())
        self.assertEqual(labels[str(self.live(TARGET))], "system_file")

    def test_missing_manifest_refuses_before_any_write(self):
        (self.recovery / "manifest").unlink()
        result = self.run_restore()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("remount-rw", self.events())

    def test_symlinked_restore_completion_temp_refuses_before_remount(self):
        sentinel = self.root / "restore-temp-sentinel"
        result = self.run_restore(GEN5W_SYMLINK_RESTORE_TEMP="1")

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(sentinel.read_text(), "must remain unchanged\n")
        self.assertNotIn("remount-rw", self.events())
        self.assertNotIn("reboot", self.events())

    def test_corrupt_manifest_refuses_before_any_write(self):
        (self.recovery / "manifest").write_text("GEN5W-RECOVERY-MANIFEST|9\n", encoding="ascii")
        result = self.run_restore()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("remount-rw", self.events())

    def test_symlinked_target_refuses_before_any_write(self):
        target = self.live(TARGET)
        target.unlink()
        outside = self.root / "outside-target"
        outside.write_bytes(b"do not touch")
        target.symlink_to(outside)
        result = self.run_restore()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(outside.read_bytes(), b"do not touch")
        self.assertNotIn("remount-rw", self.events())

    def test_rw_remount_failure_does_not_mutate_or_reboot(self):
        result = self.run_restore(GEN5W_FAIL_RW="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.live(TARGET).read_bytes(), b"patched-dipo")
        self.assertIn("remount-ro", self.events())
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assertNotIn("reboot", self.events())

    def test_term_after_rw_remount_is_cleaned_up_to_read_only(self):
        result = self.run_restore(GEN5W_TERM_AFTER_RW="1")

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assertIn("remount-ro", self.events())
        self.assertNotIn("reboot", self.events())

    def test_foreign_change_after_preflight_is_not_overwritten(self):
        result = self.run_restore(GEN5W_MUTATE_ON_RW="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.live(TARGET).read_bytes(), b"foreign during remount")
        self.assertIn("remount-ro", self.events())
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assertNotIn("reboot", self.events())

    def test_target_parent_becoming_symlink_during_rw_is_rejected(self):
        outside_target = self.root / "outside-app/HKMC_DiPO.odex"

        result = self.run_restore(GEN5W_SWAP_PARENT_TO_SYMLINK="1")

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(outside_target.read_bytes(), b"patched-dipo")
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assertIn("remount-ro", self.events())
        self.assertNotIn("reboot", self.events())

    def test_partial_prior_restore_is_retryable(self):
        self.live(TARGET).write_bytes(b"stock-dipo")
        result = self.run_restore()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.live(TARGET).read_bytes(), b"stock-dipo")
        self.assertFalse(self.live(ABSENT).exists())

    def test_valid_final_manifest_row_without_newline_is_still_restored(self):
        manifest = self.recovery / "manifest"
        manifest.write_bytes(manifest.read_bytes().rstrip(b"\n"))

        result = self.run_restore()

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.live(TARGET).read_bytes(), b"stock-dipo")
        self.assertFalse(self.live(ABSENT).exists())
        self.assertEqual(self.events().count("reboot"), 1)

    def test_duplicate_target_refuses_before_any_write(self):
        self.write_manifest(self.rows + [self.rows[0]])
        result = self.run_restore()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.live(TARGET).read_bytes(), b"patched-dipo")
        self.assertNotIn("remount-rw", self.events())

    def test_symlinked_backup_refuses_before_any_write(self):
        backup = self.backup(TARGET)
        backup.unlink()
        outside = self.root / "outside"
        outside.write_bytes(b"stock-dipo")
        backup.symlink_to(outside)
        result = self.run_restore()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.live(TARGET).read_bytes(), b"patched-dipo")
        self.assertNotIn("remount-rw", self.events())

    def test_ro_busy_after_verified_restore_reboots_to_remount_ro(self):
        # Running stock processes keep the replaced inodes mapped, so Linux
        # refuses MS_RDONLY. All targets are verified first; the reboot then
        # mounts /system read-only, and the report says so.
        result = self.run_restore(GEN5W_FAIL_RO="1")
        self.assertEqual(result.returncode, 0, str(result.stdout))
        self.assertIn("reboot", self.events())
        report = (self.usb / "GEN5W-RECOVERY-RESULT.txt").read_text()
        self.assertIn("result=restored", report)
        self.assertIn("system=rw-until-reboot", report)

    def test_mid_restore_failure_attempts_to_remount_system_read_only(self):
        result = self.run_restore(GEN5W_FAIL_SETMETA="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("remount-ro", self.events())
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assertNotIn("reboot", self.events())

    def test_false_success_remount_ro_is_reported_as_failure(self):
        result = self.run_restore(GEN5W_FAIL_SETMETA="1", GEN5W_LIE_RO="1")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("system-remount-ro-failed", result.stdout)
        self.assertEqual((self.root / ".mount-state").read_text(), "rw")
        self.assertNotIn("reboot", self.events())

    def test_reboot_failure_is_reported_after_restore(self):
        result = self.run_restore(GEN5W_FAIL_REBOOT="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.live(TARGET).read_bytes(), b"stock-dipo")
        self.assertEqual(self.events().count("reboot"), 1)
        report = (self.usb / "GEN5W-RECOVERY-RESULT.txt").read_text()
        self.assertIn("reboot", report)
        retry = self.run_restore()
        self.assertNotEqual(retry.returncode, 0)
        self.assertIn("reboot-not-confirmed", retry.stdout)
        self.assertEqual(self.events().count("reboot"), 1)

    def test_interrupted_after_accepted_reboot_does_not_dispatch_a_second_reboot(self):
        first = self.run_restore(GEN5W_CUT_AFTER_REBOOT="1")
        self.assertNotEqual(first.returncode, 0)
        self.assertEqual(self.events().count("reboot"), 1)

        second = self.run_restore()

        self.assertEqual(second.returncode, 0, second.stdout)
        self.assertEqual(self.events().count("reboot"), 1)
        report = (self.usb / "GEN5W-RECOVERY-RESULT.txt").read_text()
        self.assertIn("reboot=confirmed", report)

    def test_success_marker_makes_dispatch_idempotent(self):
        self.assertEqual(self.run_restore().returncode, 0)
        count = self.events().count("reboot")
        result = self.run_restore()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.events().count("reboot"), count)

    def test_valid_marker_for_old_manifest_does_not_block_restore(self):
        done = self.recovery / "restore.done"
        done.write_text(
            "GEN5W-RESTORE-DONE|1|" + "0" * 64
            + "|11111111-2222-4333-8444-555555555555\n",
            encoding="ascii",
        )

        result = self.run_restore()

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.live(TARGET).read_bytes(), b"stock-dipo")
        self.assertEqual(self.events().count("reboot"), 1)
        self.assertIn(self.digest((self.recovery / "manifest").read_bytes()), done.read_text())

    def test_success_marker_reentry_with_rw_system_remounts_ro_without_success(self):
        first = self.run_restore()
        self.assertEqual(first.returncode, 0, first.stdout)
        self.assertTrue((self.recovery / "restore.done").is_file())
        reboot_count = self.events().count("reboot")
        (self.root / ".mount-state").write_text("rw")

        second = self.run_restore()

        self.assertNotEqual(second.returncode, 0)
        self.assertIn("remount-ro", self.events())
        self.assertEqual((self.root / ".mount-state").read_text(), "ro")
        self.assertEqual(self.events().count("reboot"), reboot_count)
        report = (self.usb / "GEN5W-RECOVERY-RESULT.txt").read_text()
        self.assertNotIn("result=success", report)

    def test_success_marker_does_not_hide_later_target_change(self):
        self.assertEqual(self.run_restore().returncode, 0)
        self.live(TARGET).write_bytes(b"later foreign change")
        count = self.events().count("reboot")
        result = self.run_restore()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.events().count("reboot"), count)
        self.assertEqual(self.live(TARGET).read_bytes(), b"later foreign change")

    def test_path_traversal_refuses_before_any_write(self):
        bad = list(self.rows[0])
        bad[0] = "/system/app/../../data/local/tmp/foreign"
        self.write_manifest([bad])
        result = self.run_restore()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.live(TARGET).read_bytes(), b"patched-dipo")
        self.assertNotIn("remount-rw", self.events())


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "--helper":
        raise SystemExit(helper_main(sys.argv[2:]))
    unittest.main(verbosity=2)
