# Portable candidate verification record

This record distinguishes PC evidence from vehicle evidence. The candidate is
not a confirmed vehicle release. Existing rc.1q/USB contents remain untouched.

| Check | Current evidence |
| --- | --- |
| Unit command compatibility | 111 on-unit scripts passed |
| Native patchers | Host/ARM builds; five stock differential fixtures and 32 unknown-shape refusals passed |
| Actual extracted ARM VM | Fresh authored engine: original/dispatch/exception/GC/monitors, loader/bootstrap, no-hook preload marker and 15 DiPO hooks passed |
| Real-controller multi-boot | Three cold boots, QuickBoot losing mounts/properties separately, capability fallback, degraded session and disable/inert-next-boot passed |
| Session | Wireless toggles preserve HUD; stale session recovery; killed boot parent triggers owned cleanup passed |
| AP guard | Ownership, foreign inode, linked paths and unfinished starts in same boot refused; evidence retained |
| Authored APK build | Fresh core/host source build, core boot receiver disabled, portable restoration text and token-loss handling; signatures verified |
| UI | Independent Claude review and nine groups reproduced by parent, including strong process identity and AP guard lock; fresh UI/Java tests passed |
| Package archive | PASS: five adversarial tests; final ZIP audited after writing and reopening, 42 authored members, 309996 bytes |
| Full regression | PASS: full-isolated-final.log ended ALL TESTS PASSED, exit 0, TEST_JOBS=2; includes the final UI/Java source |
| Vehicle | Not applied or verified |

PC test logs are private local build outputs under `.build/portable/`:
`full-isolated-final.log`, `vm-final-v2.log`, `patcher-final-v2-arm.log`,
`lifecycle-ap-session.log`, `java-ui-final-v4.log`, `ui-final-parent.log`.
The private VM needs PC ashmem emulation and disables dexopt, while bytecode
verification remains enabled. It cannot prove Binder, mount propagation to the
real zygote, radio, boot latency or physical HUD output.

The final vehicle checklist and explicit disable procedure are in
[portable-candidate.md](portable-candidate.md). A successful software marker does
not substitute for the cold/normal-ignition, wireless, HUD and restoration checks.

The first final whole-suite run exposed a test isolation defect: the screen
fixture gives a sleep process the real wireless-host cmdline, while the legacy
installer correctly refuses any such live app in /proc. Independent Claude UI
runs overlapped those installer tests. A controlled probe reproduced detection
and disappearance after exit. The UI fixture is now serialized after the other
shell tests and reaps its owned jobs before returning; production refusal logic
was preserved. The fresh whole-suite rerun passed and is recorded in `full-isolated-final.log`.

## Final PC candidate

- Code checkpoint: `336f996` (local, no release/push).
- Archive: `.build/portable/gen5w.kr.portable-336f996-pc.zip`.
- SHA256: `970319963da710cbaad7e68972fc9d841d0117b10539db6b0e73df1ce730fc81`.
- A companion `.zip.sha256` is next to it. Audit log: `audit-final-336f996.log`.
- The archive records the full code revision and `vehicle_verified=false`.
  Its conservative whole-worktree dirty flag remains true because unrelated
  existing notes/crash logs are preserved; these are outside the shipped list.
- Vehicle/OEM files and private signing material are excluded. Core and host
  are freshly compiled authored code; compile-only declarations are not shipped.
- No vehicle or USB installation was changed. One final visit must confirm cold
  boot/normal ignition, connection timing, wireless/audio/HUD and explicit disable
  against the stock baseline before a vehicle-success claim.
