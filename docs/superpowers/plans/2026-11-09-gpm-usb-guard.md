# V039 GPM USB Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent storage/hub-only USB devices from starting wired AA through GPM, and install/remove the exact-V039 guard with verified original-pair recovery.

**Architecture:** Wrap validated GPM Context.startService call sites with an authored API18 helper. Build a stock-ODEX-to-DEX delta retaining the existing HUD recipe; extend the existing bridge installer, migration and bootguard to handle the GPM APK/ODEX pair without introducing a generic installer framework.

**Tech Stack:** Java8/API18, Python3 private builder, baksmali/smali2.5.2, Android D8, existing lpatch, mksh shell regression harness.

**Spec:** `docs/superpowers/specs/2026-11-09-gpm-usb-guard-design.md` (user approved).

## Global Constraints

- "Compile for API18"; "Exact V035 behavior remains unchanged."
- "Private stock inputs and decompiled code stay outside Git and release assets."
- "Existing uncommitted DiPO fixes must be preserved."
- "This work does not authorize a public release, version bump, or physical USB update."
- Only explicit GalReceiverService, integer startMode=1, non-null device, at least one interface, all non-null interfaces of class8/9 are suppressed.
- Unknown metadata delegates unchanged; a delegated exception propagates without retry.
- Retain the primary failure and verified backups if any pair restore is incomplete.
- Stage only named task files; never use git add -A. Existing DiPO files are not included in GPM commits unless explicitly reviewed as a shared change.

## Review Focus

1. Interrupted APK-only replacement must remain recognizable and restore both originals (Task3).
2. Metadata exception after examining some interfaces must delegate once, not suppress or duplicate a start (Task1).
3. Legacy owned HUD install must rebuild from original backup, not patched live ODEX (Task3).
4. A missing GPM app on an otherwise supported unit must not make recovery invent an app or delete evidence (Task3).
5. Payload marker/checksum omission must block mutation even when a previous relay marker exists (Task4).

## Task 1: Actual USB guard consumer

**Files:** Create `tools/v039-relay/gpm-src/kr/gen5w/gpm/GpmUsbGuard.java`, `tests/gpm_usb_guard_runtime.py`; modify `tests/run.sh`.

**Interfaces:** Produce `public static ComponentName startService(Context context, Intent intent)` and package-private `boolean storageOnly(UsbDevice device)` in GpmUsbGuard. Consume Android API18 only and shared SafeDiagnostic for fixed non-identifying codes.

- [ ] Write a JVM harness compiling the production helper and only substituting Android boundary classes. Assert `(startCount,result)` is `(0,null)` for interface classes `[8]`, `[9]`, `[8,9]`, and `(1,delegateResult)` for `[255]`, `[8,255]`, empty/null interfaces, null/missing device, non-target component, mode!=1, missing intent metadata and metadata exceptions. Assert a delegate exception is the original exception and `startCount==1`.
- [ ] Run `python tests/gpm_usb_guard_runtime.py`; confirm failure for missing guard behavior rather than a broken fixture.
- [ ] Implement the exact signature and predicate. Keep metadata inspection catch separate from delegated start so thrown starts cannot retry. Suppress only the exact target component (package and class); expose no device details in diagnostics.
- [ ] Run the harness; expect all named cases PASS. Add it to the JDK-enabled list in `tests/run.sh`.
- [ ] Commit only the helper, new test and runner change after checking that runner diff preserves the previous DiPO test registration.

## Task 2: Exact private GPM builder and shipped delta

**Files:** Create `tools/v039-relay/build_gpm_guard.py`, `tests/gpm_guard_builder.py`, `tools/v039-relay/HKMC_GPM.guard.lpd`. Reuse existing `build_dipo_relay.py` utility functions without refactoring its behavior; consume `tools/iap2/gpm_patch.py`, `tools/iap2/gpm-v039.json`, `mkdelta.py`.

**Interfaces:** Produce Python `patch_service_starts(tree: Path) -> dict[str,int]` and CLI with `--stock-apk --stock-odex --framework --baksmali --smali --work --delta-out`. The CLI validates the exact spec hashes and emits only the requested delta plus private working outputs.

- [ ] Write builder fixture tests: wrong APK/ODEX rejected before tool execution; only reviewed Context.startService-compatible invocations rewritten; unrelated methods preserved; empty/ambiguous/unreviewed inventories rejected. Assert helper invocation preserves receiver/Intent registers and ComponentName result; test invoke-range forms explicitly if present in reviewed input.
- [ ] Run `python tests/gpm_guard_builder.py`; observe the missing transformation fail.
- [ ] Inventory all exact private stock startService invocations, record reviewed caller identities/counts in the authored builder, and reject inventory drift. Apply deterministic existing HUD recipe to original bytes and verify the result before deodexing. Add Task1 helper and shared diagnostic classes, assemble API18 DEX, generate delta from original ODEX.
- [ ] Run builder tests, then private CLI using `D:/kona_gen5w_decrypted/port_inputs_private/v039_stock/{app,framework}` and ignored `.build/connection-tools/{baksmali,smali}.jar`. Require exit0 and delta self-check. Keep generated OEM material only in ignored private work folders.
- [ ] Commit the authored builder/test and verified delta, not OEM inputs/outputs.

## Task 3: Recoverable GPM pair lifecycle

**Files:** Create `packages/wireless-bridge/scripts/gpm-relay.sh`, `tests/gpm-relay.sh`; modify bridge `scripts/common.sh`, `pre.sh`, `post.sh`, `preun.sh`, `bootguard-recover.sh`; modify `tests/bridge.sh`, `tests/bootguard.sh`, `tests/bootguard-dongle.sh`, `tests/run-shell.sh`. Existing bridge common/recovery scripts own the per-file backup inventory; keep it there.

**Interfaces:** Source gpm-relay.sh after common variables/functions exist. Produce shell `gpm_relay_live`, `gpm_relay_apk_live`, `gpm_relay_odex_live`, `gpm_relay_assemble <output>`, `gpm_relay_install`, `gpm_relay_restore`, `gpm_relay_stage_clear`. Return0 on verified success, nonzero on failure; never exit the caller. Use state names `gpmapkoriginal`, `gpmrelay.apk.md5`, `gpmrelay.odex.md5`, `gpmrelaystaging`, `gpmrelay.assembled` and existing `gpmoriginal`; mirror them in durable backup/bootguard inventory.

- [ ] Build real-shell fixtures with distinct original APK/ODEX, HUD-patched ODEX and generated pair bytes. Invoke actual pre/post/preun/recovery scripts, not a reimplemented model. Assert exact original bytes after fresh install/remove, legacy update/remove, repeat install and bootguard. Assert V035 retains ODEX-only behavior and absent-GPM targets remain absent.
- [ ] Add failure cases asserting no unauthorized live mutation for bad delta, incomplete payload, unknown owner/pair, corrupt/missing backups and symlinks. Inject dexopt failure and interruption before/after each pair rename; require both originals restored or verified backups/intent retained if rollback itself fails. Test the five Review Focus conditions in their owning cases.
- [ ] Run `wsl -e bash -c "cd '/mnt/d/수업/kona_gen5w_audit/gen5w-kr-stock-first' && bash tests/gpm-relay.sh"`; observe missing GPM-pair lifecycle assertions fail.
- [ ] Implement narrowly scoped helper and call sites. Save and hash-verify both originals before any mutation. Persist generated hashes and intent before first rename. Recognize stock, owned legacy, owned full/mixed generated pair; reject unknown files. Preoptimize with existing bootclasspath, preserve metadata, verify both live outputs; restore both originals on any failed step. Keep backups/ownership until both original files are verified.
- [ ] Extend existing cleanup, snapshot migration and bootguard validation/restoration, including missing-target interruption handling under verified ownership. Preserve existing exclusion, symlink and remount policies; record primary failure separately from rollback failure.
- [ ] Run new lifecycle tests and existing `tests/bridge.sh`, `tests/bootguard.sh`, `tests/system-reinstall.sh`, `tests/recovery.sh` through WSL. Expect PASS with explicit primary/rollback evidence assertions.
- [ ] Commit only named GPM lifecycle and test changes after `git diff --check`.

## Task 4: Packaging, artifact audit and final review

**Files:** Modify `tools/stage-v039-relay.sh`, `tools/build-all.sh`, `packages/wireless-bridge/scripts/relay-gate.sh`, `tests/relay-gate.sh`, `tests/gpm_guard_builder.py`, `tests/run.sh`, `tools/audit-artifacts.py`.

**Interfaces:** New complete marker `gen5w.kr.bridge:v039-relay-4` requires both `HKMC_DiPO.relay.lpd` and `HKMC_GPM.guard.lpd` and their checksum entries. Old owned installs are migration inputs, not proof the new payload is complete. Public package content remains authored tooling plus deltas.

- [ ] Add gate tests asserting missing GPM delta, missing checksum entry, wrong checksum, old marker and symlink each return failure before mutation; a complete new package returns0. Keep marker absent=77 behavior for non-relay configurations. Run tests and confirm RED before product changes.
- [ ] Stage the GPM delta, update required membership and marker validation, and add GPM payload audit alongside existing DiPO audit. Ensure a manifest omitting a required file cannot pass merely because every listed row hashes correctly.
- [ ] Run `python tests/gpm_guard_builder.py` private mode to reconstruct exact shipped delta; assert source/target MD5, DEX SHA1/adler, expected guard call-site inventory, original native method signatures, retained HUD allocation behavior and absence of new non-authored classes. A stale delta must fail the new guard-edge assertion.
- [ ] Run `bash tests/run.sh` via Git Bash (WSL shell tests), API18 helper/delta build, bridge.dex/wireless-host/app/native builds and local package assembly. Check final process exit codes and report every SKIP. Verify packaged delta bytes and no OEM APK/ODEX/full DEX leaks. Clean-source build-all may run after reviewed explicit commits; it must not bypass dirty-source safeguards or publish anything.
- [ ] Use requesting-code-review for one fresh read-only review of the combined change and migration/recovery tests. Fix blocking findings with RED/GREEN evidence; rerun affected tests and full suite after the last product fix.
- [ ] Commit named packaging/test changes only; record verified results, hashes, limits and next action in KnowledgeHub session and project brief. Keep `last_verified` unchanged without vehicle verification. Final report distinguishes code/fixture verification from actual CarPlay/Wi-Fi success.

## Plan self-review and handoff

- All spec sections map to Tasks1–4; private artifact verification is separate from Java behavior and shell lifecycle.
- Task interfaces use the same helper/state/marker names throughout. No generic installer rewrite, extra UI or external publication is included.
- Existing DiPO work is independently preserved. Shared-file commits require line-level review; an unrelated modified file is not staged automatically.
- Recommended execution: **Native** in this existing isolated worktree, because the builder, payload gate and paired recovery share state and benefit from one implementer maintaining the migration contract. One independent final read-only review remains required.
- Implementation begins after the user reviews this plan and chooses Native or Subagent-driven execution.
