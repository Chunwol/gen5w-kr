#!/usr/bin/env python3
"""Every driver profile must load its packaged modules in dependency order."""
from pathlib import Path
import re
import struct
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULES = ROOT / "tools/usb-wifi/package/files/modules"


def symbols(path):
    """Return (exported, undefined) symbol names of a 32-bit little-endian module."""
    data = path.read_bytes()
    if data[:6] != b"\x7fELF\x01\x01":
        raise ValueError(f"not a 32-bit little-endian ELF: {path.name}")
    shoff = struct.unpack_from("<I", data, 32)[0]
    entsize, count, names_index = struct.unpack_from("<HHH", data, 46)
    sections = [struct.unpack_from("<10I", data, shoff + i * entsize) for i in range(count)]
    names = sections[names_index]

    def text(base, offset):
        return data[base + offset:data.index(b"\0", base + offset)].decode()

    by_name = {text(names[4], section[0]): section for section in sections}
    exported = set()
    if "__ksymtab_strings" in by_name:
        section = by_name["__ksymtab_strings"]
        exported = {item.decode() for item in data[section[4]:section[4] + section[5]].split(b"\0") if item}
    table = by_name[".symtab"]
    strings = sections[table[6]]
    undefined = set()
    for offset in range(table[4], table[4] + table[5], 16):
        name, _, _, _, _, shndx = struct.unpack_from("<IIIBBH", data, offset)
        if name and shndx == 0:
            undefined.add(text(strings[4], name))
    return exported, undefined


def profile_errors(profile_lines, module_symbols):
    """List symbols a packaged module provides but the profile does not load first."""
    providers = {}
    for module, (exported, _) in module_symbols.items():
        for symbol in exported:
            providers.setdefault(symbol, set()).add(module)
    errors = []
    for line in profile_lines:
        driver, modules, *_ = line.split("|")
        loaded = set()
        for module in modules.split():
            for symbol in sorted(module_symbols[module][1]):
                owners = providers.get(symbol, set()) - {module}
                if owners and not owners & loaded:
                    errors.append(f"{driver}: {module} needs {symbol} from {sorted(owners)}")
            loaded.add(module)
    return errors


class UsbWifiProfileTests(unittest.TestCase):
    def test_checker_reports_a_missing_provider(self):
        table = {"helper": ({"ewma_add"}, set()), "mac80211": (set(), {"ewma_add"})}
        self.assertEqual(profile_errors(["x|mac80211||2.4GHz|yes|ready"], table),
                         ["x: mac80211 needs ewma_add from ['helper']"])
        self.assertEqual(profile_errors(["x|helper mac80211||2.4GHz|yes|ready"], table), [])

    def test_every_packaged_profile_loads_providers_first(self):
        table = {path.stem: symbols(path) for path in MODULES.glob("*.ko")}
        lines = (MODULES / "modules.profile").read_text(encoding="utf-8").splitlines()
        self.assertEqual(profile_errors(lines, table), [])

    def test_packaged_modules_name_no_builder_home(self):
        leaked = [path.name for path in MODULES.glob("*.ko")
                  if re.search(rb"/home/[a-z]|/Users/", path.read_bytes())]
        self.assertEqual(leaked, [])


if __name__ == "__main__":
    unittest.main()
