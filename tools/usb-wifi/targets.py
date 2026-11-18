#!/usr/bin/env python3
"""USB WLAN driver families to audit for the Gen5W 3.18.24 target.

This is a candidate/build inventory, not a claim of vehicle compatibility.
In-tree options refer to upstream Linux 3.18.24; external entries need a
separately pinned source tree and are not enabled by the in-tree builder.
"""

TARGETS = {
    # In-tree Linux 3.18.24 USB WLAN drivers.
    "AR5523": dict(module="ar5523", config="CONFIG_AR5523", source="in-tree-3.18",
                   bands={"2.4GHz"}, ap=False,
                   chipsets="AR5523 family; 802.11a variants are not usable with this driver"),
    "ATH9K_HTC": dict(module="ath9k_htc", config="CONFIG_ATH9K_HTC", source="in-tree-3.18",
                      bands={"2.4GHz", "5GHz"}, ap=True,
                      chipsets="AR9271 (2.4 GHz); AR7010 + AR928x (variant-dependent dual band)"),
    "AT76C50X_USB": dict(module="at76c50x-usb", config="CONFIG_AT76C50X_USB",
                         source="in-tree-3.18", bands={"2.4GHz"}, ap=False,
                         chipsets="Atmel AT76C503/AT76C505/AT76C505A; no AP/master mode"),
    "CARL9170": dict(module="carl9170", config="CONFIG_CARL9170", source="in-tree-3.18",
                     bands={"2.4GHz", "5GHz"}, ap=True,
                     chipsets="AR9170; 5 GHz depends on radio variant"),
    "LIBERTAS_THINFIRM": dict(module="libertas_tf_usb", config="CONFIG_LIBERTAS_THINFIRM",
                               source="in-tree-3.18", bands={"2.4GHz"}, ap=None,
                               extra_configs=("CONFIG_LIBERTAS_THINFIRM_USB",),
                               chipsets="Marvell 8388 USB"),
    "LIBERTAS_USB": dict(module="usb8xxx", config="CONFIG_LIBERTAS_USB", source="in-tree-3.18",
                         bands={"2.4GHz"}, ap=None, extra_configs=("CONFIG_LIBERTAS",),
                         chipsets="Marvell Libertas USB family"),
    "ORINOCO_USB": dict(module="orinoco_usb", config="CONFIG_ORINOCO_USB", source="in-tree-3.18",
                        bands={"2.4GHz"}, ap=None, extra_configs=("CONFIG_HERMES",),
                        chipsets="Lucent/Agere USB variants"),
    "P54_USB": dict(module="p54usb", config="CONFIG_P54_USB", source="in-tree-3.18",
                    bands={"2.4GHz", "5GHz"}, ap=None, extra_configs=("CONFIG_P54_COMMON",),
                    chipsets="Prism54 USB; band depends on radio and firmware"),
    "RTL8187": dict(module="rtl8187", config="CONFIG_RTL8187", source="in-tree-3.18",
                     bands={"2.4GHz"}, ap=None, chipsets="RTL8187 family"),
    "RTL8192U": dict(module="r8192u_usb", config="CONFIG_RTL8192U", source="in-tree-3.18",
                     bands={"2.4GHz"}, ap=None, chipsets="RTL8192U staging driver"),
    "R8712U": dict(module="r8712u", config="CONFIG_R8712U", source="in-tree-3.18",
                   bands={"2.4GHz"}, ap=None, chipsets="RTL8712/RTL8192SU"),
    "RT2500USB": dict(module="rt2500usb", config="CONFIG_RT2500USB", source="in-tree-3.18",
                      bands={"2.4GHz"}, ap=None, chipsets="RT2571W/RT2671 USB family"),
    "RT2800USB": dict(module="rt2800usb", config="CONFIG_RT2800USB", source="in-tree-3.18",
                      bands={"2.4GHz", "5GHz"}, ap=True,
                      extra_configs=("CONFIG_RT2800USB_RT35XX", "CONFIG_RT2800USB_RT55XX"),
                      chipsets="RT3572/RT5572 and other variant-dependent radios"),
    "RT73USB": dict(module="rt73usb", config="CONFIG_RT73USB", source="in-tree-3.18",
                    bands={"2.4GHz"}, ap=None, chipsets="RT73 USB family"),
    "USB_NET_RNDIS_WLAN": dict(module="rndis_wlan", config="CONFIG_USB_NET_RNDIS_WLAN",
                               source="in-tree-3.18", bands=set(), ap=None,
                               chipsets="RNDIS WLAN devices; radio capabilities vary"),
    "ZD1201": dict(module="zd1201", config="CONFIG_USB_ZD1201", source="in-tree-3.18",
                   bands={"2.4GHz"}, ap=None, chipsets="ZyDAS ZD1201 USB"),
    "ZD1211RW": dict(module="zd1211rw", config="CONFIG_ZD1211RW", source="in-tree-3.18",
                     bands={"2.4GHz"}, ap=None, chipsets="ZyDAS ZD1211 USB"),

    # Out-of-tree 5 GHz candidates with historical 3.18-era build evidence.
    "MT7610U": dict(module="mt7610u", config="EXT:mt7610u vendor driver", source="external",
                    bands={"2.4GHz", "5GHz"}, ap=None, chipsets="MediaTek MT7610U"),
    "MT7612U": dict(module="mt7612u", config="EXT:mt7612u vendor driver", source="external",
                    bands={"2.4GHz", "5GHz"}, ap=None, chipsets="MediaTek MT7612U"),
    "RTL8192DU": dict(module="r8192du", config="EXT:Realtek RTL8192DU", source="external",
                      bands={"2.4GHz", "5GHz"}, ap=None, chipsets="Realtek RTL8192DU"),
    "RTL8812AU": dict(module="8812au", config="EXT:Realtek RTL8812AU", source="external",
                      bands={"2.4GHz", "5GHz"}, ap=True, chipsets="Realtek RTL8812AU"),
    "RTL8812BU": dict(module="88x2bu", config="EXT:Realtek RTL8812BU", source="external",
                      bands={"2.4GHz", "5GHz"}, ap=None, chipsets="Realtek RTL8812BU"),
}


def in_tree_targets():
    """Return upstream 3.18.24 entries in stable symbol order."""
    return {symbol: TARGETS[symbol] for symbol in sorted(TARGETS)
            if TARGETS[symbol]["source"] == "in-tree-3.18"}


def config_options():
    """Return scripts/config arguments for all in-tree target families."""
    options = ["--module", "MAC80211", "--module", "RT2X00",
               "--enable", "ATH_CARDS", "--enable", "RTL_CARDS"]
    for item in in_tree_targets().values():
        symbols = (item["config"],) + tuple(item.get("extra_configs", ()))
        for symbol in symbols:
            options.extend(("--module", symbol.removeprefix("CONFIG_")))
    return options
