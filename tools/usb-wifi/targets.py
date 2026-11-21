#!/usr/bin/env python3
"""USB WLAN driver families to audit for the Gen5W 3.18.24 target.

This is a candidate/build inventory, not a claim of vehicle compatibility.
In-tree options refer to upstream Linux 3.18.24; external entries need a
separately pinned source tree and are not enabled by the in-tree builder.
"""

BOTH = {"2.4GHz", "5GHz"}
ONLY_2G = {"2.4GHz"}
# These change struct net_device and iw_handler_def. The V039 kernel has none of
# them, so a module built with any of them writes to the wrong kernel fields.
LAYOUT_OPTIONS = ("CONFIG_WIRELESS_EXT", "CONFIG_WEXT_PRIV", "CONFIG_WEXT_SPY")
_NEEDS_WEXT = "selects CONFIG_WIRELESS_EXT, which the V039 kernel does not have"
# APIs these vendor trees call that Linux 3.18 has under an older name.
COMPAT_FLAGS = "-Dstrscpy=strlcpy -Dget_random_u32=prandom_u32"
# The stock hotspot runs on 5 GHz channel 149. The car has no CRDA, so cfg80211
# stays on the world domain, where that channel may not start an AP. These
# drivers therefore use their own Korean channel plan (149 active, not DFS).
KR_PLAN = "-DCONFIG_RTW_CHPLAN=0x28 -DCONFIG_FORCE_SW_CHANNEL_PLAN"
KR_PLAN_8851 = "-DCONFIG_RTW_CHPLAN=0x4B"
_B851 = ("\t{USB_DEVICE_AND_INTERFACE_INFO(USB_VENDER_ID_REALTEK, 0xB851, 0xff, 0xff, 0xff), "
         ".driver_info = RTL8851B},\n")


def _vendor(module, bands, chipsets, repo, commit, flags=COMPAT_FLAGS, mp="n", debug="n",
            rename=False, fixes=(), drop_aliases=(), patch=None, make=()):
    """Describe a cfg80211 vendor driver built from one pinned public commit."""
    return dict(module=module, config="EXT:" + repo, source="external", bands=set(bands), ap=True,
                stock_ap="5GHz" in bands, chipsets=chipsets, repo="https://github.com/" + repo + ".git", commit=commit,
                build=dict(flags=flags, mp=mp, debug=debug, rename=rename, fixes=fixes,
                           patch=patch, make=tuple(make)),
                drop_aliases=drop_aliases)


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
                         blocked=_NEEDS_WEXT, chipsets="Marvell Libertas USB family"),
    "ORINOCO_USB": dict(module="orinoco_usb", config="CONFIG_ORINOCO_USB", source="in-tree-3.18",
                        bands={"2.4GHz"}, ap=None, extra_configs=("CONFIG_HERMES",),
                        blocked=_NEEDS_WEXT, chipsets="Lucent/Agere USB variants"),
    "P54_USB": dict(module="p54usb", config="CONFIG_P54_USB", source="in-tree-3.18",
                    bands={"2.4GHz", "5GHz"}, ap=None, extra_configs=("CONFIG_P54_COMMON",),
                    chipsets="Prism54 USB; band depends on radio and firmware"),
    "RTL8187": dict(module="rtl8187", config="CONFIG_RTL8187", source="in-tree-3.18",
                     bands={"2.4GHz"}, ap=None, chipsets="RTL8187 family"),
    "RTL8192U": dict(module="r8192u_usb", config="CONFIG_RTL8192U", source="in-tree-3.18",
                     bands={"2.4GHz"}, ap=None, blocked=_NEEDS_WEXT,
                     chipsets="RTL8192U staging driver"),
    "R8712U": dict(module="r8712u", config="CONFIG_R8712U", source="in-tree-3.18",
                   bands={"2.4GHz"}, ap=None, blocked=_NEEDS_WEXT, chipsets="RTL8712/RTL8192SU"),
    "RT2500USB": dict(module="rt2500usb", config="CONFIG_RT2500USB", source="in-tree-3.18",
                      bands={"2.4GHz"}, ap=None, chipsets="RT2571W/RT2671 USB family"),
    "RT2800USB": dict(module="rt2800usb", config="CONFIG_RT2800USB", source="in-tree-3.18",
                      bands={"2.4GHz", "5GHz"}, ap=True,
                      bool_configs=("CONFIG_RT2800USB_RT33XX", "CONFIG_RT2800USB_RT35XX",
                                    "CONFIG_RT2800USB_RT3573", "CONFIG_RT2800USB_RT53XX",
                                    "CONFIG_RT2800USB_RT55XX"),
                      chipsets="RT2870/RT3070/RT3572/RT3573/RT5370/RT5372/RT5572 family"),
    "RT73USB": dict(module="rt73usb", config="CONFIG_RT73USB", source="in-tree-3.18",
                    bands={"2.4GHz"}, ap=None, chipsets="RT73 USB family"),
    "USB_NET_RNDIS_WLAN": dict(module="rndis_wlan", config="CONFIG_USB_NET_RNDIS_WLAN",
                               source="in-tree-3.18", bands=set(), ap=None,
                               chipsets="RNDIS WLAN devices; radio capabilities vary"),
    "ZD1201": dict(module="zd1201", config="CONFIG_USB_ZD1201", source="in-tree-3.18",
                   bands={"2.4GHz"}, ap=None, blocked=_NEEDS_WEXT, chipsets="ZyDAS ZD1201 USB"),
    "ZD1211RW": dict(module="zd1211rw", config="CONFIG_ZD1211RW", source="in-tree-3.18",
                     bands={"2.4GHz"}, ap=None, chipsets="ZyDAS ZD1211 USB"),

    # Out-of-tree 5 GHz candidates with historical 3.18-era build evidence.
    "MT7610U": dict(module="mt7610u", config="EXT:mt7610u vendor driver", source="external",
                    bands={"2.4GHz", "5GHz"}, ap=None, chipsets="MediaTek MT7610U"),
    "MT7612U": dict(module="mt7612u", config="EXT:mt7612u vendor driver", source="external",
                    bands={"2.4GHz", "5GHz"}, ap=None, chipsets="MediaTek MT7612U"),
    "RTL8192DU": dict(module="r8192du", config="EXT:Realtek RTL8192DU", source="external",
                      bands={"2.4GHz", "5GHz"}, ap=None, chipsets="Realtek RTL8192DU"),
    "RTL8812AU": _vendor("8812au", BOTH, "RTL8812AU",
                         "aircrack-ng/rtl8812au", "734485506a30d6237c2deaad666a19f8ca5379f2",
                         flags=KR_PLAN, rename=True, patch="8812au-linux-3.18.patch",
                         make=("CONFIG_RTL8821A=n", "CONFIG_RTL8814A=n",
                               "CONFIG_EFUSE_CONFIG_FILE=n")),
    "RTL8812BU": _vendor("88x2bu", BOTH, "RTL8812BU/RTL8822BU",
                         "OpenHD/rtl88x2bu", "111d1f2417e9f1c5eeeaee481e1e50f7a16cac74",
                         flags=COMPAT_FLAGS + " " + KR_PLAN, rename=True),
    "RTL8821CU": _vendor("8821cu", BOTH, "RTL8811CU/RTL8821CU",
                         "morrownr/8821cu-20210916", "bda65aac150d2cde0df9603206eec23a6f3b77c4",
                         flags=KR_PLAN, rename=True),
    "RTL8821AU": _vendor("8821au", BOTH, "RTL8811AU/RTL8821AU",
                         "morrownr/8821au-20210708", "1a819991f5b75e64dfcf922b96a6681f367cbba0",
                         # Its Makefile follows the OS domain by default; 0 selects the driver plan.
                         flags=COMPAT_FLAGS + " " + KR_PLAN + " -DCONFIG_RTW_REGD_SRC=0"),
    "RTL8851BU": _vendor("8851bu", BOTH, "RTL8851BU/RTL8831BU",
                         "fofajardo/rtl8851bu", "9e37e7a1101316a05d5daede91549ea779b64539",
                         flags=COMPAT_FLAGS + " " + KR_PLAN_8851, mp="y", fixes=(
                             # A 16-bit counter cast to atomic_t is invalid for ARM ldrex/strex.
                             ("os_dep/osdep_service_linux.c",
                              "ATOMIC_INC((ATOMIC_T *)&rtw_warn_on_cnt);", "rtw_warn_on_cnt++;"),
                             # IDs listed for this chip by the upstream Linux rtw89 driver.
                             ("os_dep/linux/usb_intf.c", _B851, _B851
                              + _B851.replace("USB_VENDER_ID_REALTEK, 0xB851", "USB_VENDER_ID_REALTEK, 0xB831")
                              + _B851.replace("USB_VENDER_ID_REALTEK, 0xB851", "0x2001, 0x332A")),
                         )),
    "RTL8188EU": _vendor("8188eu", ONLY_2G, "RTL8188EU/RTL8188EUS/RTL8188ETV",
                         "lwfinger/rtl8188eu", "f42fc9c45d2086c415dce70d3018031b54a7beef",
                         mp="y", debug="y",
                         # 0BDA:F179 is an RTL8188FTV; the rtl8188fu profile owns it.
                         drop_aliases=("usb:v0BDApF179",)),
    "RTL8188FU": _vendor("rtl8188fu", ONLY_2G, "RTL8188FU/RTL8188FTV",
                         "kelebek333/rtl8188fu", "cefa9185df3e56d7208a8c147d0cf57b2440908f", mp="y"),
    "RTL8188GU": _vendor("8188gu", ONLY_2G, "RTL8188GU/RTL8188GTV",
                         "McMCCRU/rtl8188gu", "c2b79fc1c085d9fc4a70ac0f5bc730ec929c562b", mp="y"),
    "RTL8192EU": _vendor("8192eu", ONLY_2G, "RTL8192EU",
                         "Mange/rtl8192eu-linux-driver", "c629cc972a0d878c930d19c4a9309c27c1e61f92",
                         flags=COMPAT_FLAGS + " -DWLAN_CATEGORY_WNM_UNPROTECTED=11",
                         # make 4.4 rejects this self-reference with the 3.18 kbuild.
                         fixes=(("Makefile", "EXTRA_CFLAGS += $(ccflags-y)\n", ""),)),
}


def profile_ap(item):
    """Catalog AP value: yes = can host the stock 5 GHz AP, 2g = AP on 2.4 GHz only, no = none."""
    if not item["ap"]:
        return "no"
    return "yes" if item.get("stock_ap") else "2g"


def in_tree_targets():
    """Return the upstream 3.18.24 entries that can be built for the V039 kernel."""
    return {symbol: TARGETS[symbol] for symbol in sorted(TARGETS)
            if TARGETS[symbol]["source"] == "in-tree-3.18" and "blocked" not in TARGETS[symbol]}


def vendor_targets():
    """Return the pinned out-of-tree drivers that are built and packaged."""
    return {symbol: TARGETS[symbol] for symbol in sorted(TARGETS) if "commit" in TARGETS[symbol]}


def config_options():
    """Return scripts/config arguments for all in-tree target families."""
    options = ["--module", "MAC80211", "--module", "RT2X00",
               "--enable", "ATH_CARDS", "--enable", "RTL_CARDS"]
    for item in in_tree_targets().values():
        symbols = (item["config"],) + tuple(item.get("extra_configs", ()))
        for symbol in symbols:
            options.extend(("--module", symbol.removeprefix("CONFIG_")))
        # Chip-table switches are bool options; "--module" would be dropped by olddefconfig.
        for symbol in item.get("bool_configs", ()):
            options.extend(("--enable", symbol.removeprefix("CONFIG_")))
    return options
