# Portable pre-vehicle verification: 0ce5dd5

This checkpoint supersedes the 336f996 PC candidate below. It is ready for the
**conditional, supervised vehicle trials** in [the procedure](portable-candidate.md)
and [the Korean visit checklist](portable-vehicle-checklist.ko.md). It is not a
vehicle-success or permanent automatic-operation approval. Vehicle and deployed
rc.1q/USB contents were not changed.

## Safety corrections

- Installation and every manual `arm --trial` start with radio held off. Trial
  consumption is synced before maintenance and prevents repeat activation after
  healthy, cold restart or same-id partial-state loss. A dirty same-id trial is
  restored instead of reapplied. Permanent auto remains a separate post-vehicle choice.
- `boot.sh probe` admits one byte-identical DiPO ODEX row and uses retained native
  supervision, readable payload and stock restart dependencies. Evidence requires
  the pending bind, actual copy dev:ino in DiPO, library mapping and PID start time.
- Current maintenance and same-boot pending state fence new entry. Internal
  maintenance requires the bounded supervisor. Disable waits for existing
  maintenance before inspecting dirty state or reporting restoration; diagnostics
  cannot prevent disable. Android/Binder queries and waits have deadlines.
- Both authored AP request paths fail closed on durable-record/flush failure.
  AP rearm preserves verified evidence and needs an explicit reviewed token;
  panic mtime is labeled unreliable. Persistent AP baseline/restore is checked.
- Preload environment is cleared for children; Bootstrap receives explicit JNI
  inputs. Input overflow declines the engine and still scrubs child inputs.

## Fresh PC evidence

Private local logs are under `.build/portable/` and are not shipped:

| Check | Evidence |
| --- | --- |
| Full regression | `full-hardening-final-v4.log`: ALL TESTS PASSED, exit 0, TEST_JOBS=4, bounded JVM heap |
| Source identity | `hardening-source-freeze-v4.json`: 27 owned source/test/doc files unchanged through final regression and commit |
| Strict real-controller lifecycle | `lifecycle-hardening-strict-final.log`: three cold boots, independent state loss, fallback, session degradation and explicit disable PASS; strict mode rejects the old known-defect branch |
| Probe and independent rescue | `boot-native-fixture-final.log`, final whole-suite portable_boot group: caller-group SIGKILL, caller-only death before apply, interrupted startup, no replay, bad probe refusal PASS |
| Disable regression | `disable-race-red.log` reproduces premature restoration with old ordering; `disable-race-green.log` PASS with new ordering |
| Actual extracted ARM VM | `vm-hardening-final.log`, coupled engine v3: dispatch/original/exception/GC/monitors, loader/Bootstrap, probe marker and 15 DiPO hooks PASS |
| Native structural patches | `patcher-hardening-arm.log`: five differential fixtures, 32 unknown-shape no-output refusals and malformed/metadata checks PASS |
| AP / environment | AP focused/full tests, bounded stock/broker flush tests and six Dalvik host tests including overflow PASS |
| Commands and authored builds | 111 on-unit scripts; fresh native, core/host APK and coupled engine builds PASS |
| Archive | 42 authored members; reopen/audit and five adversarial artifact tests PASS |

The first concurrent whole run had four legacy service-quiescence expectation
failures; the isolated group passed 50/50 and the final whole run passes it.
The production safety gate was preserved. A later full run exposed a host-test
3-second startup observation limit before Android was stopped (`armed`, zygote
running). Controlled slow-hash injection reproduced it in `startup-wait-red.log`;
`startup-wait-green.log` passes with the corrected preparation wait. The fixture
now uses the native digest rather than spawning Python for every tiny file.
Vehicle time limits were not relaxed. The final v4 whole run includes this fix.

The PC VM substitutes ashmem and disables dexopt, with bytecode verification on.
Host loader warnings about guest preload paths are retained in its log; guest
Bootstrap and probe-marker assertions independently establish guest engine loading.
These checks do not establish real Binder/mount propagation, vehicle dexopt,
SMP/GC behavior under load, startup latency/memory, suspend, driver/AP or displays.
Some legacy private-stock installation fixtures skip when their private input is
not supplied; the separate native structural oracle uses the private V039 stock.

## Sealed artifact

- Code: `0ce5dd5a8d0c2f2fd829f206096d58eb6ae57756` (local commit, no push/release).
- ZIP: `.build/portable/gen5w.kr.portable-0ce5dd5-prevehicle.zip`; 326761 bytes, 42 members.
- SHA256: `4b7f9095b1d3786491f7c12f3a8bb1c64e543c0959ec41766cc21d82028c821a`; companion `.zip.sha256` and `final-prevehicle-receipt.json`.
- `CANDIDATE.json`: exact code revision, one-shot radio-off admission,
  `vehicle_verified=false`. Dirty=true honestly reflects preserved unrelated notes
  and existing crash logs, which are excluded from the package.
- No OEM APK/ODEX/native file or private signing material is shipped.
- Claude reviewed the preliminary 42-member ZIP and source. The final repack
  differs only in boot.sh, README.md, CANDIDATE.json and SHA256SUMS; the two code
  follow-ups are covered by `claude-guardian-fence-review.md` and
  `claude-disable-fence-review.md`. Final archive bytes were separately audited.
- Diagnostic: GO. Supervised premise / radio-off one-shot / staged wireless /
  second trial: CONDITIONAL GO. Permanent automatic use requires actual target
  validation and separate evaluation of late-reset recovery risk. No target
  execution or approval is claimed.

---

## Historical 336f996 PC checkpoint (superseded)

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
