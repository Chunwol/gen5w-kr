# Project development rules

Korean Hyundai/Kia/Genesis Gen5W head units (Telechips, Android 4.4.2, Dalvik), installed through NEMESIS (xwtk/hmg_nemesis). Reference car: 2020 Hyundai Kona HEV, `OSHEV.KOR.0000.V039.001.260902`. Design: `docs/design.md`.

## Hard rules

- Write everything here from scratch. Do not copy code, scripts, recipes or patch bytes from other Gen5W projects (several are GPL); facts (feature names, property names, method signatures needed to interoperate) are fine.
- No manufacturer files in the repo: no apps, odex, libraries, firmware pieces or decompiled code. `probe/stubs` holds only declarations we wrote so our code compiles; they are never packaged.
- Never collect or store per-car secrets: VIN, serials, IMEI/SIM/phone numbers, certificates/keys, account tokens, `/data` contents. Mask MAC addresses in logs.
- No CAN frames of our own. Vehicle commands only through stock services, each with its own review.
- Never flash MICOM, bootloader or modem firmware.
- Every `/system` change ships as a NEMESIS package: check the stock state first, back up what is replaced, and uninstall must leave `/system` byte-identical. Prefer adding files over replacing them.
- Detect features on the unit instead of keeping a car list. Unknown or mismatched -> skip that feature and say so in the report.
- Test on the mock (`tests/`) before a car, and say which cars a change was tested on.
- Commits: plain words. No AI attribution lines and no chat/session links.

## Unit quirks

- Shell is mksh with toolbox: no `printf`, no `tail`. Remount only via `nemesis remount rw|ro`.
- Root commands: `nemesis root -c '...'`; `nemesis root 1000 -c` runs as system.
- `pm install` from NEMESIS works only through `[app.N] kind=apk` (it handles the OEM signer check).
- Toast: `am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "..." --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true`.
