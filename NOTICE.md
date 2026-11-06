# Notices and Open Source Software

## Gen5W KR
Copyright (C) 2026 Chunwol and contributors.
This project is licensed under the GNU General Public License v3.0 only (GPL-3.0-only).
See [LICENSE](LICENSE) for the full license text.

## Underlying Platform: NEMESIS
Gen5W KR runs on top of the **NEMESIS** framework:
- Project: https://github.com/xwtk/hmg_nemesis
- Author: xwtk and contributors
- License: GNU Affero General Public License v3.0 (AGPL-3.0)
- NEMESIS is a prerequisite for running packages on the head unit and is distributed separately under its own license.

## Dongle edition: GPL-2.0 kernel modules and ath9k_htc firmware
The dongle edition (`gen5w-kr-dongle.zip`) also contains binaries under other licenses:
- `files/modules/*.ko`: Linux kernel modules (mac80211, ath, ath9k_hw, ath9k_common, ath9k_htc, ccm, ctr, seqiv, average) built from Linux 3.18.24 and the Hyundai Mobis Gen5W open-source kernel release (STD_G5_WIDE R7) with the V039 kernel configuration. License: GPL-2.0 (some ath files Dual BSD/GPL).
- `files/bcmdhd.ko`: this project's stand-in module (`tools/usb-wifi/bcmdhd_shim`). License: GPL-2.0-only.
- `files/firmware/htc_9271.fw`, `htc_7010.fw`: the unmodified `htc_9271-1.4.0.fw` and `htc_7010-1.4.0.fw` from Debian's `open-ath9k-htc-firmware` 1.4.0-108-gd856466+dfsg1-1.3+deb12u1 (source: https://github.com/qca/open-ath9k-htc-firmware). License: mostly BSD-3-Clause-Clear; full notices in `licenses/ath9k-htc-firmware.txt` inside the dongle package.

For their corresponding source, `gen5w-kr-dongle-gpl-source.tar.xz` in the same release holds the V039 kernel configuration, build scripts and stand-in source, with official download addresses and SHA-256 for the Linux, Mobis and Debian source archives (not re-hosted by us); the dongle package carries the GPL-2.0 text and a written offer (`licenses/GPL-SOURCE.md`). Our dongle build scripts (`tools/usb-wifi/experiment.py`, `gpl_source.py`) are GPL-2.0-only OR GPL-3.0-only.

## lpatch and the V039 relay delta
- `tools/lpatch/lpatch.c` and `tools/v039-relay/mkdelta.py` come from HMG Leafia Plus (https://github.com/VysseCodes/HMG-Leafia-Plus, GPL-3.0-or-later). They are used under GPL-3.0 as part of this GPL-3.0-only work.
- `tools/v039-relay/HKMC_DiPO.relay.lpd` is a binary delta. The head unit applies it to its own exact stock `HKMC_DiPO.odex`; `lpatch` writes nothing unless the source and the result match the hashes stored in the delta. No manufacturer file is shipped, but the delta holds the bytes that differ from the stock file, so it cannot be used without that exact file. Whether such a delta is acceptable under the manufacturer's terms is not something this project can decide for you.

## OEM Software Notice
This project does not contain, distribute, or relicense proprietary Hyundai, Kia, Genesis, or Mobis firmware, apps, libraries, or decryption keys. The dongle modules above are built from the GPL kernel source Mobis published; that source is not redistributed here, only referenced. All other modifications are performed on-device against the vehicle's own legitimate files.

## Trademarks
Hyundai, Kia, Genesis, Bluelink and Hyundai Mobis are trademarks of their respective owners. Apple CarPlay and CarPlay are trademarks of Apple Inc. Android Auto is a trademark of Google LLC. NEMESIS belongs to its authors. These names are used only to describe compatibility. This is an unofficial project, not affiliated with, endorsed by, or supported by any of these companies.
