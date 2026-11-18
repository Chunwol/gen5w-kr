#!/usr/bin/env python3
"""Validate the declared Linux 3.18 USB WLAN driver build targets."""
import importlib.util
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "usb_wifi_targets", ROOT / "tools/usb-wifi/targets.py")
targets = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(targets)


class UsbWifiTargetTests(unittest.TestCase):
    def test_package_exposes_the_explicit_dongle_test_action(self):
        package = ROOT / "tools/usb-wifi/package"
        metadata = (package / "NEMESIS.data").read_text(encoding="utf-8")
        self.assertIn("[app.1]\nkind=sh\npath=bin/dongle-test.sh", metadata)
        self.assertTrue((package / "bin/dongle-test.sh").is_file())

    def test_gpl_bundle_includes_new_build_script_dependency(self):
        source = (ROOT / "tools/usb-wifi/gpl_source.py").read_text(encoding="utf-8")
        self.assertIn('files["build/targets.py"]', source)
        self.assertIn('files["build/assemble_payload.py"]', source)

    def test_payload_assembler_packages_every_compiled_target_and_alias(self):
        spec = importlib.util.spec_from_file_location(
            "usb_wifi_assembler", ROOT / "tools/usb-wifi/assemble_payload.py")
        assembler = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(assembler)
        targets = assembler.TARGETS.in_tree_targets()
        with TemporaryDirectory() as temp:
            base = Path(temp)
            release = base / "module-root/lib/modules/test-release"
            kernel = release / "kernel"
            kernel.mkdir(parents=True)
            crypto = kernel / "crypto"
            crypto.mkdir()
            for name in ("ccm", "ctr", "seqiv"):
                (crypto / f"{name}.ko").write_bytes(b"fixture crypto module")
            report_targets = {}
            dep_lines = []
            aliases = []
            for index, (symbol, item) in enumerate(targets.items(), 1):
                rel = f"drivers/{symbol.lower()}/{item['module']}.ko"
                module = kernel / rel
                module.parent.mkdir(parents=True, exist_ok=True)
                module.write_bytes(b"fixture module")
                installed_rel = f"kernel/{rel}"
                report_targets[symbol] = {"status": "compiled", "modules": [{"path": rel}]}
                dep_lines.append(installed_rel + ":")
                aliases.append(f"alias usb:v{index:04X}p0001d*dc*dsc*dp*ic*isc*ip*in* {item['module']}")
            release.joinpath("modules.dep").write_text("\n".join(dep_lines) + "\n")
            release.joinpath("modules.alias").write_text("\n".join(aliases) + "\n")
            report = base / "report.json"
            report.write_text(json.dumps({"status": "experimental-build-only",
                                          "targets": report_targets}))
            package = base / "package"
            with patch.object(assembler, "module_metadata", return_value=[]):
                result = assembler.assemble(base / "module-root", report, package, base / "firmware")
            self.assertEqual(result["compiled_profiles"], len(targets))
            self.assertEqual(len(list((package / "files/modules").glob("*.ko"))), len(targets) + 3)
            self.assertEqual(len((package / "files/modules/modules.profile").read_text().splitlines()), len(targets))
            self.assertEqual(len((package / "files/modules/modules.alias").read_text().splitlines()), len(targets))

    def test_catalog_covers_3_18_in_tree_usb_wlan_families(self):
        expected = {
            "ATH9K_HTC", "AR5523", "AT76C50X_USB", "CARL9170", "P54_USB",
            "RTL8187", "RTL8192U", "R8712U", "RT2500USB", "RT2800USB",
            "RT73USB", "ZD1201", "ZD1211RW", "LIBERTAS_USB",
            "LIBERTAS_THINFIRM", "ORINOCO_USB", "USB_NET_RNDIS_WLAN",
        }
        actual = {name for name, item in targets.TARGETS.items()
                  if item["source"] == "in-tree-3.18"}
        self.assertTrue(expected.issubset(actual))

    def test_5ghz_ap_candidates_are_separate_from_build_targets(self):
        expected = {"ATH9K_HTC", "CARL9170", "RT2800USB", "RTL8812AU"}
        actual = {
            symbol for symbol, item in targets.TARGETS.items()
            if "5GHz" in item["bands"] and item["ap"]
        }
        self.assertTrue(expected.issubset(actual))

    def test_each_target_has_kernel_config_and_evidence_boundary(self):
        for symbol, item in targets.TARGETS.items():
            with self.subTest(symbol=symbol):
                self.assertTrue(item["module"])
                self.assertTrue(item["config"])
                self.assertIn(item["source"], {"in-tree-3.18", "external"})
                self.assertIn(item["bands"], ({"2.4GHz"}, {"5GHz"}, {"2.4GHz", "5GHz"}, set()))
                self.assertIn(item["ap"], {True, False, None})

    def test_build_configuration_enables_every_in_tree_family_and_chip_variant(self):
        options = targets.config_options()
        enabled = {options[index + 1] for index, option in enumerate(options[:-1])
                   if option in {"--module", "--enable"}}
        self.assertIn("RT2X00", enabled)
        for symbol, item in targets.in_tree_targets().items():
            with self.subTest(symbol=symbol):
                self.assertIn(item["config"].removeprefix("CONFIG_"), enabled)
                for extra in item.get("extra_configs", ()):
                    self.assertIn(extra.removeprefix("CONFIG_"), enabled)
        self.assertNotIn("8812AU", enabled)


if __name__ == "__main__":
    unittest.main()
