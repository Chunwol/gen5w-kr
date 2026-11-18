#!/usr/bin/env python3
"""Host safety checks for portable NEMESIS emergency probe and restore USBs."""
from pathlib import Path
import configparser
import os
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tools" / "portable" / "recovery-usb" / "probe"
ORDINARY = ROOT / "tools" / "portable" / "usb"
RESTORE_WRAPPER = ROOT / "tools" / "portable" / "recovery-usb" / "restore-usb" / "NEMESIS.sh"


class EmergencyProbeUsbTest(unittest.TestCase):
    def test_probe_uses_emergency_execute_descriptor(self):
        descriptor = configparser.ConfigParser()
        descriptor.read(PROBE / "NEMESIS.data")
        self.assertEqual(descriptor.get("nemesis", "type"), "execute")
        self.assertEqual(descriptor.get("nemesis", "path"), "NEMESIS.sh")
        self.assertTrue((PROBE / "NEMESIS.emergency").is_file())
        self.assertEqual((PROBE / "NEMESIS.emergency").read_bytes(), b"")

    def test_probe_records_boot_evidence_to_its_usb_volume(self):
        script = (PROBE / "NEMESIS.sh").read_text(encoding="utf-8")
        for required in (
            "/storage/usb0", "/storage/usb1", "/storage/usb2",
            "/mnt/media_rw/usb0", "sys.boot_completed", "init.svc.zygote",
            "NEMESIS-PORTABLE-RECOVERY-PROBE.txt", "/system/xbin/nemesis",
        ):
            self.assertIn(required, script)
        self.assertNotIn("NEMESIS.emergency", [p.name for p in ORDINARY.iterdir()])

    def test_probe_has_no_mutating_android_commands(self):
        script = (PROBE / "NEMESIS.sh").read_text(encoding="utf-8")
        forbidden_commands = re.compile(
            r"^\s*(?:setprop|mount|reboot|cp|mv|rm|chmod|chown|restorecon)\s|"
            r"^\s*/system/xbin/nemesis\s+(?:install|update|uninstall|remount)\b",
            re.MULTILINE,
        )
        self.assertIsNone(forbidden_commands.search(script))
        self.assertNotIn("/system/build.prop", script)
        self.assertNotIn("/data/", script)


class RecoveryWrapperDispatchTest(unittest.TestCase):
    MOUNTS = (
        "/storage/usb0", "/storage/usb1", "/storage/usb2",
        "/mnt/media_rw/usb0", "/mnt/media_rw/usb1", "/mnt/media_rw/usb2",
    )

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="recovery-wrapper-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.dispatch_log = self.root / "dispatch.log"
        self.fake_shell = self.root / "system-sh"
        self.fake_shell.write_text(
            "#!/bin/sh\nprintf '%s\\n%s\\n' \"$GEN5W_RECOVERY_USB_ROOT\" \"$1\" > \"$GEN5W_TEST_DISPATCH_LOG\"\n",
            encoding="utf-8",
        )
        self.fake_shell.chmod(0o755)
        self.mount_map = {mount: (self.root / mount.lstrip("/")).as_posix()
                          for mount in self.MOUNTS}

    def install_layout(self, usb_root, marker=True, restore=True, helper=True):
        usb_root.mkdir(parents=True, exist_ok=True)
        if marker:
            (usb_root / "NEMESIS.emergency").write_bytes(b"")
        if restore:
            (usb_root / "restore.sh").write_text("# fixture\n", encoding="ascii")
        if helper:
            bin_dir = usb_root / "bin"
            bin_dir.mkdir(exist_ok=True)
            patcher = bin_dir / "dex-patch"
            patcher.write_text("#!/bin/sh\nexit 0\n", encoding="ascii")
            patcher.chmod(0o755)
        wrapper_text = RESTORE_WRAPPER.read_text(encoding="utf-8")
        for source, target in self.mount_map.items():
            wrapper_text = wrapper_text.replace(source, target)
        wrapper_text = wrapper_text.replace("/system/bin/sh", self.fake_shell.as_posix())
        wrapper = usb_root / "NEMESIS.sh"
        wrapper.write_text(wrapper_text, encoding="utf-8")
        return wrapper

    def run_wrapper(self, wrapper):
        env = os.environ.copy()
        env["GEN5W_TEST_DISPATCH_LOG"] = self.dispatch_log.as_posix()
        return subprocess.run(["sh", str(wrapper)], env=env, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              timeout=3)

    def test_dispatches_restore_from_every_supported_usb_mount(self):
        for mount in self.MOUNTS:
            with self.subTest(mount=mount):
                self.dispatch_log.unlink(missing_ok=True)
                usb_root = Path(self.mount_map[mount])
                wrapper = self.install_layout(usb_root)
                result = self.run_wrapper(wrapper)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual(self.dispatch_log.read_text(encoding="utf-8").splitlines(),
                                 [usb_root.as_posix(), (usb_root / "restore.sh").as_posix()])

    def test_refuses_missing_or_linked_emergency_marker(self):
        usb_root = Path(self.mount_map["/storage/usb0"])
        wrapper = self.install_layout(usb_root, marker=False)
        result = self.run_wrapper(wrapper)
        self.assertEqual(result.returncode, 4)
        self.assertFalse(self.dispatch_log.exists())

        outside = self.root / "outside-marker"
        outside.write_bytes(b"")
        marker = usb_root / "NEMESIS.emergency"
        marker.symlink_to(outside)
        result = self.run_wrapper(wrapper)
        self.assertEqual(result.returncode, 4)
        self.assertFalse(self.dispatch_log.exists())

    def test_refuses_incomplete_restore_payload(self):
        usb_root = Path(self.mount_map["/mnt/media_rw/usb1"])
        wrapper = self.install_layout(usb_root, restore=False)
        result = self.run_wrapper(wrapper)
        self.assertEqual(result.returncode, 5)
        self.assertFalse(self.dispatch_log.exists())

    def test_refuses_symlinked_restore_script_before_dispatch(self):
        usb_root = Path(self.mount_map["/storage/usb1"])
        wrapper = self.install_layout(usb_root)
        outside = self.root / "outside-restore.sh"
        outside.write_text("#!/bin/sh\nexit 0\n", encoding="ascii")
        outside.chmod(0o755)
        (usb_root / "restore.sh").unlink()
        (usb_root / "restore.sh").symlink_to(outside)

        result = self.run_wrapper(wrapper)

        self.assertEqual(result.returncode, 5)
        self.assertFalse(self.dispatch_log.exists())

    def test_refuses_symlinked_helper_before_dispatch(self):
        usb_root = Path(self.mount_map["/mnt/media_rw/usb2"])
        wrapper = self.install_layout(usb_root)
        outside = self.root / "outside-dex-patch"
        outside.write_text("#!/bin/sh\nexit 0\n", encoding="ascii")
        outside.chmod(0o755)
        helper = usb_root / "bin/dex-patch"
        helper.unlink()
        helper.symlink_to(outside)

        result = self.run_wrapper(wrapper)

        self.assertEqual(result.returncode, 5)
        self.assertFalse(self.dispatch_log.exists())

    def test_refuses_script_invoked_outside_a_supported_usb_root(self):
        usb_root = self.root / "unmounted"
        wrapper = self.install_layout(usb_root)
        result = self.run_wrapper(wrapper)
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.dispatch_log.exists())


if __name__ == "__main__":
    unittest.main()
