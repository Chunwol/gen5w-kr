# Portable emergency recovery USB Implementation Plan

> **For agentic workers:** Use the executing-plans workflow task-by-task. The user requested inline progress through the work and a report; keep every task independently testable and do not deploy to the vehicle without the explicit vehicle gate below.

**Goal:** Prepare and verify a NEMESIS emergency USB path that can restore the future portable persistent patch when Android UI/zygote does not start.

**Architecture:** Keep three artifacts distinct: the existing ordinary installer (currently staged as 0.3.71), the harmless emergency-dispatch probe (already built; it restores nothing), and a future restore-only USB (not implemented). Complete and host-test the restore protocol before vehicle work because those host fixtures do not mutate the car. Keep the restore USB and all persistent `/system` writes gated on target-vehicle proof. The ordinary installer never contains the emergency marker.

**Tech Stack:** POSIX/mksh-compatible shell on Android 4.4, Python artifact generator, existing bash/Python host test harnesses, official NEMESIS USB descriptor.

**Spec:** `docs/superpowers/specs/2026-11-17-portable-persistent-live-update-design.md`

## Global Constraints

- Do not touch bootloader, boot partition/image, ramdisk, init, or other boot-chain files.
- Do not include `NEMESIS.emergency` in normal installer USBs or product packages.
- The emergency USB is restore-only; it must never install packages, patch, or re-arm portable operation.
- Refuse unknown targets, incomplete/corrupt original manifests, symlinks, and foreign live hashes before any write.
- Keep all verified originals; never overwrite the first original backup on update.
- Restore `/system` to read-only and independently verify mount flags before reporting success or rebooting.
- Persistent patch implementation and vehicle-installable patch candidate remain blocked until Android-down emergency execution and exact restore are demonstrated on the target vehicle.
- Host fixtures prove only script logic; they do not count as target-vehicle recovery verification.

## Review Focus

- The official NEMESIS 1.16 run-script documentation at commit `a7dc770` says Android-down USB `type=execute` runs without a prompt when the root has `NEMESIS.emergency` ([versioned run-script contract](https://github.com/xwtk/hmg_nemesis/blob/a7dc770/05-Run-Scripts.md)). This makes the old assumption that 1.16.3 lacks the marker unsupported; it still does not prove the installed vehicle handler dispatches the probe, so retain the vehicle gate.
- Android is down but USB is mounted at `usb1`/`usb2` or `/mnt/media_rw/usbN`: probe and restore must use only the documented mounted volume and report the actual path.
- A target is original, patched, absent, foreign-modified, symlinked, or partially restored: restore only recognized original/patched states and remain retryable after partial progress.
- Restore succeeds but `/system` remount-ro or reboot fails: report incomplete/needs-reboot and preserve rescue material; never claim successful completion.
- Emergency marker remains after success or USB is left inserted: completion must be idempotent and must not reapply or reinstall anything.

## Execution Order and Current State

1. **Freeze artifact roles and baselines — complete.** Ordinary USB is staged at `.build/portable/vehicle-0.3.71-final`; the emergency artifact at `.build/portable-recovery-probe.zip` is a no-op probe. Do not describe the probe as a restore USB or mutate either staged artifact during host implementation.
2. **Implement restore protocol in host fixtures only — host logic complete, vehicle proof pending.** The fixture adapter directs filesystem operations into temporary test roots; no host test targets a real `/system`. Fixtures cover recognized original/patched/absent/partial states, corrupt/foreign/symlink inputs, recovery-backup storage metadata distinct from original `/system` metadata, target metadata restoration, a valid unterminated final manifest row, reboot failure and interruption after accepted reboot, boot-ID completion confirmation, read-only remount, TOCTOU mutation, and idempotent completion. Current restore fixtures pass 20/20; production helper/SELinux command availability and restore bundle dispatch are unaudited; do not ship.
3. **Assemble separate recovery bundle and freeze both candidates — host-only archive assembled.** Verify the emergency marker exists only in recovery artifacts (probe and restore-only), ordinary installer remains marker-free, and independently audit archive contents/checksums. Write outputs under `.build`; do not copy to physical media automatically. The current host-only archive includes an in-bundle warning and is not vehicle-approved because dispatch and exact restore remain unproven.
4. **Establish VM test capability before spending a VM run — file-backed USB ZIP injection unavailable in the checked Windows runner.** The installed Android Emulator 35.4.9 exposes `-usb-passthrough VID PID BUS PORTS`, which forwards a physical host USB device; that does not attach the generated ZIP as a virtual FAT USB or exercise NEMESIS emergency dispatch. `gen5w-v039-emulator/scripts/run-service-vm.ps1` has no USB-device argument; `emu/gen5w-emulator` has QMP/FAT32 USB hotplug for macOS, but its Windows `run_windows_baseline.py` has no corresponding USB option. The standalone Windows `qemu-system-armel.exe -device help` fails before launch with status `-1073741515` (dependency DLL unavailable); invoking QEMU help through `emulator.exe` failed on the emulator's qemud serial charpipe. No VM boot or USB dispatch was verified. Existing `emu/data/runs` was not touched. A task-created temporary AVD and its temp junction remain outside the emulator run root; no emulator process remains. Do not count physical passthrough, ADB package tests, or host fixtures as virtual-USB dispatch evidence.
5. **Run the emergency probe on the target vehicle, Android up then safely down.** Require a USB report from the down state. If NEMESIS does not dispatch it, stop and investigate that mechanism; do not modify `/system`.
6. **Prove exact restore on one reversible, non-boot-critical vehicle test file.** Require byte-identical restoration (including prior absence), correct metadata, `/system` read-only, completion report, and normal boot. Keep the emergency recovery USB separate from the ordinary installer.
7. **Only after step 6, integrate backup/journal staging into ordinary install/update and build a vehicle candidate.** Preserve first originals across updates; request one normal reboot only after full verification. Never touch boot chain files or stop/restart zygote as an install shortcut.
8. **Final verification once per USB.** After artifacts are frozen, run one complete ordinary-USB VM flow and one complete recovery-USB VM flow if true USB injection exists; otherwise the unmet VM gate stays explicit. Then perform target-vehicle recovery proof before any persistent patch rollout.

**Current evidence (2026-11-17):** Three host fixtures exposed restore correctness defects. First, preflight incorrectly required a backup stored under `/data/.../originals` to share the original `/system` file's mode/SELinux label; backup bytes remain SHA-verified and original target ownership/mode/label are applied to the staged file. Second, `while read` skipped a valid final manifest row without a newline, permitting success/reboot while leaving that target unrestored; all three manifest-reading loops now process a complete EOF row. Third, Android 4.4 AOSP `reboot` sets `sys.powerctl` and returns before shutdown completes; writing the completion marker after that call could lose the marker and replay reboot. The recovery marker now binds manifest SHA to the pre-reboot boot ID and is durably written before reboot; a later dispatch confirms completion after boot ID changes, while same-boot replay refuses another reboot. `tests/portable_recovery_restore.py` passes 20/20. The focused `tests/portable_recovery_usb.py` now passes 7/7, including executing the restore wrapper against all six documented `/storage/usbN` and `/mnt/media_rw/usbN` path forms, and refusing missing/linked markers, incomplete payloads, and non-USB invocation. This is host path-contract coverage, not NEMESIS/vehicle dispatch proof. `tests/portable_recovery_bundle.py` passes 3/3, recovery shell syntax passes, and the prior full `bash tests/run-shell.sh` completed directly with exit code 0 before these test-only wrapper fixtures were added. New host-only `.build/portable-recovery-restore-host-only-reboot-marker-fix.zip` has all eight entries listed in `SHA256SUMS`, empty marker, executable wrapper/helper modes, exact current restore script/manifest spec, correct sidecar hash, and ordinary 0.3.71 ZIP remains marker-free; archive SHA-256 is `97f0e884a9a0b8ce4145be313037df16cae4be76e1b80ef22cfc24595551436a`. No Android VM USB dispatch test was run. The archive itself states it is not approved for vehicle use; persistent installer integration remains incomplete. These checks do not clear the vehicle gate.

**NEMESIS dispatch source clarification (2026-11-17):** The versioned official NEMESIS 1.16 run-script documentation (`a7dc770`) explicitly describes a root `type=execute` script running without a dialog while Android is down if `NEMESIS.emergency` is present. Therefore the earlier concern that 1.16.3 might not support this marker is not supported by the documented 1.16 contract. This remains source-level evidence only: the target vehicle's installed handler and actual Android-down USB dispatch still require the harmless probe.

**Latest source delta (2026-11-17):** Restore now routes successful remount attempts through an independent read-only-state check in the normal completion path, failure cleanup, and completion-marker re-entry. Re-entry with a valid completion marker but a live `rw` mount now enters failure cleanup, reasserts `ro`, reports failure, and does not reboot. `SYSTEM_RW` is set before attempting the read-write remount so partial remounts and TERM in the helper-return window still trigger best-effort read-only cleanup. The restore loop rechecks target and parent symlinks after remount and before remove/replace; a new fixture swaps `/system/app` for an outside symlink during remount. Fixtures also cover false-success read-only remount, failed read-write cleanup, TERM immediately after read-write state changes, and read-write state on completion-marker re-entry. The completion-marker temp path is checked again after manifest hashing, and creation uses shell noclobber; the symlink fixture creates the exact temp symlink during the hash helper and asserts rejection before remount while preserving sentinel contents. The restore USB wrapper now refuses symlinked `restore.sh`, `bin/`, and `bin/dex-patch` payload paths before dispatch; two test-only regressions cover symlinked script/helper payloads. The test agent reviewed fixture paths, but none of the new tests or source changes has been executed. All changes are absent from the older host-only archive/hash above. Run the recovery fixture and rebuild/audit any archive only during final verification; neither artifact is cleared for vehicle use.

---

### Task 1: Build a harmless NEMESIS emergency USB probe

**Files:**
- Create: `tools/portable/recovery-usb/probe/NEMESIS.data`
- Create: `tools/portable/recovery-usb/probe/NEMESIS.emergency` (empty marker)
- Create: `tools/portable/recovery-usb/probe/NEMESIS.sh`
- Create: `tests/portable_recovery_usb.py`
- Modify: `tests/run-shell.sh`

**Interfaces:**
- Produces a root USB layout whose descriptor is exactly `type=execute`, `path=NEMESIS.sh`; probe only records NEMESIS version, USB mount path, `sys.boot_completed`, and zygote state into a report on the same USB.
- The script must not write `/system`, `/data`, properties, reboot, or call NEMESIS package APIs.

- [x] Write tests that assert the marker exists only in this probe tree, descriptor selects `NEMESIS.sh`, script records evidence to mounted USB, and script contains no mutating system/data/reboot commands.
- [x] Run `python tests/portable_recovery_usb.py`; confirmed the expected missing-file failures before implementation.
- [x] Add the fixed descriptor and minimal toolbox-compatible probe script; keep the emergency marker empty.
- [x] Run the focused test and adjacent portable recovery/USB tests; all passed. Run Android shell syntax check; `mksh -n` passed.
- [x] Build `.build/portable-recovery-probe.zip` after auditing its three entries and executable shell mode; it is not copied to a USB automatically.
- [x] Host-execute the restore-only NEMESIS wrapper for all six supported USB mount paths and verify marker/payload refusals; this does not prove NEMESIS or target-vehicle dispatch.
- [x] Preserve the full-suite result: `bash tests/run-shell.sh` completed with exit code 0; all component suites passed. This is host-only evidence, not vehicle or VM USB-dispatch proof.

**Vehicle gate before use of Task 2 output:** On the target Kona's currently installed NEMESIS 1.16.3, run the probe first with Android fully up, then with Android UI/zygote unavailable using an agreed safe test condition. Require a report written by the script with `sys.boot_completed`/zygote evidence from the down condition. If the USB is not dispatched, inspect NEMESIS USB logs and stop; do not attempt any `/system` modification. Task 2 may be implemented and host-tested before this gate, but its bundle must not be used on the vehicle until dispatch succeeds.

### Task 2: Define and test the persistent-original recovery protocol

**Files:**
- Create: `tools/portable/recovery-usb/restore.sh`
- Create: `tools/portable/recovery-usb/manifest-format.md`
- Create: `tests/portable_recovery_restore.py`

**Interfaces:**
- Consumes: vehicle-local `/data/local/gen5w-portable/persistent/recovery/manifest` and a matching immutable `originals/` tree created before any persistent patch write.
- The manifest binds fixed allowlisted `/system` target paths to either an original file digest plus metadata or an explicitly absent original, and the portable-applied digest.
- Produces: exact restored bytes/absence, verified metadata/SELinux context, verified `/system` read-only state, a USB completion report, and at most one normal reboot after every check succeeds.

- [x] Add host fixtures for valid original/patched states, absent original, unknown hash, missing/corrupt manifest, duplicate target, path traversal, symlinked backup/target, partial prior restore, remount-rw/remount-ro failures, mid-restore remount-ro retry, reboot failure, and changed-target-after-completion.
- [x] Run the focused tests and observe expected missing-implementation failures before adding restore.sh.
- [x] Implement fixed allowlist parsing and preflight manifest/backups/live hashes before first mutation (host fixture adapter).
- [x] Implement atomic per-target restore with retryable recognized intermediate states; reject foreign bytes without overwriting them (host fixture adapter).
- [x] Verify content/fixture metadata, read-only remount behavior and reboot result in host fixtures. Production SELinux command behavior is not established.
- [x] Add a regression proving backup storage mode/label may differ while restored target mode/label are exact; observed failure before fix (`backup-metadata-mismatch`) and pass after fix.
- [x] Add a regression for a valid final manifest row without a trailing newline; observed success leaving the last absent target in place before fix, then verified the row is restored after fix.
- [x] Add a regression that kills the restore process just after reboot acceptance; before the boot-ID marker fix, a second dispatch requested a second reboot. After the fix, the new boot confirms completion without repeating reboot; same-boot reboot failure remains visible and is not retried automatically.
- [x] Run full regression after final host changes and audit a separate recovery bundle; full `bash tests/run-shell.sh` exit 0 and host-only recovery archive audit passed. Production SELinux/toolbox behavior and vehicle recovery remain unverified.
- [ ] Do not integrate persistent writes into installer until the next vehicle gate is passed.

**Vehicle gate before Task 3:** With a deliberately prepared reversible test target on the actual vehicle, prove the emergency restore restores byte-identical content while zygote/UI are unavailable, returns `/system` to `ro`, writes its report, and boots normally. Do not induce a failure in a production target to test recovery.

### Task 3: Connect recovery material to persistent install/update

**Files:**
- Modify: `tools/portable/usb/NEMESIS.sh`
- Modify: `tools/portable/package-pre.sh`
- Modify: `tools/portable/package-post.sh`
- Modify: `tools/portable/candidate.py`
- Modify: `tests/portable_usb.sh`
- Modify: `tests/portable_candidate.py`

**Interfaces:**
- Consumes: Task 2 manifest and restore-script contract.
- Produces: installer stages/verifies a complete original recovery set before changing `/system`; installation aborts before mutation if the set cannot be retained and revalidated; update preserves the first stock originals.

- [ ] Add failing installer/update tests for original backup persistence, backup disk full, partial backup, corrupted backup, update preserving first originals, and refusing when emergency restore protocol is not armed.
- [ ] Run focused tests and confirm failure precedes any mocked `/system` write/reboot.
- [ ] Implement backup staging, hash and metadata validation, durable journal commit, and rollback before NEMESIS package replacement.
- [ ] Verify standard installer output contains no emergency marker, while the separate restore bundle does.
- [ ] Run portable USB/candidate tests, full repository suite, full artifact audit, and package/hash checks.

**Final vehicle gate:** Only after Tasks 1–3 host checks pass and the restore path is verified on the target vehicle may a persistent patch candidate be built. Any vehicle inability to run the emergency handler or restore exact originals blocks the persistent `/system` design.

### Historical source snapshot (2026-11-17; later status is updated below)

- `restore.sh` now parses both v1 (12 fields) and v2 (13 fields). V2 accepts one prior applied SHA-256 so restore can recognize a previous payload during an interrupted update; both applied hashes use the recorded applied metadata/label. Existing v1 remains readable.
- `persistent-migrate.sh` is an unintegrated source prototype for preparing recovery state and materializing a verified plan. Failure cleanup now tracks whether owner/recovery manifests were published, retains the new recovery state if rollback is uncertain, and uses checked exclusive temporary files for `/system` replacements and backup publication. A test-only fixture was added for preflight preservation and temp symlink rejection; no tests have been run. Do not package or run it on a vehicle.
- Live overlay migration now has a held retirement transaction: after backups and the next recovery manifest are published, the migrator calls `overlay.sh retire-live hold` without stopping zygote. It keeps the journal/plan until persistent writes are read-only and synced; then it finalizes. On a failed write it restores exact originals and read-only state before asking overlay to rebind. If rollback is uncertain it leaves `retired-pending` and does not rebind. The test seam/fixtures were added but have not been run. This remains standalone source and is not package-integrated or vehicle-cleared.
- Existing recovery manifests are now intended to be fully checked before update work: v1/v2 field counts, supported targets, duplicate rows, hashes, metadata, labels, absent records, and exact original backup bytes. A malformed pre-existing recovery set must refuse before `/system` remount or manifest replacement. Seven test-only corruption cases were added by the test agent; tests remain unrun. Static review remains required for the parser and early-failure cleanup.
- `prepare.sh --stock-origins` now provides an optional exact-byte snapshot and an index of original uid/gid/mode/SELinux context, but normal package-post does not request it and the armed 0.3.71 updater still refuses enabled installs. `boot.sh origins` alone remains hash/metadata only. Resolving update-time origin reuse, Android-running owned-overlay retirement, stable wrapper/config persistence, and updater integration remains required before package integration.
- Test-only fixtures for v2 restore and persistent migration were authored by the low-cost test agent. Per user instruction, no tests have been executed in this work segment; final verification remains pending.
- `prepare.sh --stock-origins` now refuses to create a fresh stock snapshot when the prior recovery manifest is missing but the persistent state directory, recovery directory, or owner manifest remains. This prevents silently treating potentially patched live `/system` files as first-install stock. Two refusal fixtures cover leftover recovery originals and leftover owner manifest; they were reviewed but not run. This protects planning only; it does not integrate or apply persistent writes.

### Emulator and regression update (2026-11-18)

- The ARM helper was rebuilt with the available NDK as a static ELF32 ARM EABI5 executable with no unresolved symbols. The Android VM ran its `size`, `sha256`, mount-state and label-read commands. A red/green test exposed and fixed an embedded terminal NUL in SELinux label output; `label /system/app/HKMC_DiPO.odex` now emits plain `unlabeled\n`.
- The production `restore.sh` completed against its isolated synthetic root inside the V039 VM: it restored the fixture bytes, root:root ownership and mode 0644, verified `/system` read-only, wrote the report/completion marker and requested reboot. This VM has SELinux disabled and no boot ID file, so the VM-only helper wrapper supplied `unlabeled` label behavior, a fixed boot ID and an intercepted reboot. The run verifies the restore transaction flow, not real SELinux xattr behavior, reboot, NEMESIS USB dispatch or vehicle recovery.
- The official V039 `system.ext4` attempts stayed at empty `sys.boot_completed`, with zygote/surfaceflinger/media/netd restarting; its kernel log reported `GIC CPU mask not found - kernel will fail to boot`. Historical successful profiles showed two CPUs. Reproducing the historical profile with the pre-existing `candidate6-lcd-dipo-bt-odex` test system, v11 ramdisk, 1 GiB, 1920x720 and two default CPUs reached `sys.boot_completed=1` at 155.9 seconds. The VM then exposed surfaceflinger, netd, zygote, system_server, mediaserver and vehicle package services. The successful run record is `emu/data/runs/ranchu-v039-services-20261117T181616129624Z/result.json`; disposable `system.img`/`userdata.img` copies and the temporary profile runner were removed after shutdown, while logs and screenshots remain.
- Current-source Core and Wireless Bridge APKs built successfully into `.build/current-vm-apps-20261118/`. VM installation was blocked by `INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES`: the test system has package signing state incompatible with the private probe key, and uninstall attempts failed. We did not alter the system image to bypass signing. Thus the VM validates Android framework/service boot for this candidate image, but does not validate launch of the newly built APKs. Bluetooth/Wi-Fi hardware, HUD ECU behavior, and audio/INFO integration also remain outside this VM's capabilities.
- `tests/run.sh` failed before the fix only because `tools/portable/candidate.py::git_output()` decoded UTF-8 `git status --porcelain` output using Windows cp949. The function now explicitly decodes UTF-8 with replacement for malformed bytes. Afterward `tests/portable_candidate.py` passed 7/7 on Windows and WSL; the complete Python matrix exited 0 and `tests/java.sh` exited 0. The WSL shell run reported every sequential and parallel suite as passing. The whole runner was not repeated after this narrow encoding fix.
- Direction remains gated: source integration has advanced, but do not stage/publish a persistent vehicle candidate until the target vehicle proves harmless Android-down NEMESIS dispatch and exact restore. No vehicle USB was written. The boot-complete candidate VM profile does not clear the old VM USB-injection limitation, real SELinux/reboot limits, or the target-vehicle gate. The next useful VM step is to add a clearly isolated test package ID/signing path or use a source-matched system image; do not replace protected system packages to force an install.

### Install/startup review and regression update (2026-11-18)

- Correct the earlier Task 3 status above: the current `package-post.sh` now calls `prepare.sh --stock-origins`, applies `persistent-migrate.sh`, verifies `persistent-start.sh`, then records `persistent-commit`; only after that does it clear the UI wireless hold. `service.sh` selects `persistent-start.sh run` whenever the recovery manifest exists and only falls back to legacy `boot.sh run` when the persistent manifest is genuinely absent. `persistent-commit` enables the service without scheduling a per-boot zygote restart. The USB entrypoint reports success and requests one normal reboot after NEMESIS returns success.
- Added `tests/portable_package_post.sh` and registered it in `tests/run-shell.sh`. The fixture checks the exact prepare → migrate → recovery-verify → persistent-commit order and verifies a failed migration leaves startup disabled and the UI hold intact. The focused test passed; final `bash tests/run.sh` exited 0 with shell and Python suites passing. The runner skipped its JVM stage because Windows had no JDK; a prior standalone `tests/java.sh` run exited 0. This is host fixture evidence, not proof that NEMESIS invokes package-post as expected on the target or that the installed code boots safely.
- Added `tests/portable_service.sh` for the service selection contract: only an absent recovery manifest can enter legacy `boot.sh run`; present state routes to persistent startup, its failure does not fall back, and a symlink manifest refuses both paths. The new test and the complete `bash tests/run-shell.sh` suite exited 0; the full suite includes shell syntax checks. This does not prove the target NEMESIS service process itself or vehicle boot behavior.
- Current direction is coherent for the requested one-time reboot and no per-boot zygote restart, but no vehicle build is cleared: the actual target NEMESIS Android-down dispatch and exact restore gate still has not passed. No USB was written. A disposable candidate6 V039 VM reaches boot-complete, but current APK installation is blocked by package certificate mismatch, and the VM lacks real radio/HUD hardware. The first car-side action remains the harmless emergency-dispatch probe, not installation.

### Existing-install update preparation fix (2026-11-18)

- Re-ran the existing-install path after the user emphasized that the next version must update the already-installed package. The update USB fixture confirms an active current package is retired before package replacement, a failed update restores the previous view, and success commits persistent startup and asks for one reboot without a zygote restart. `persistent-migrate.py` passes 24/24 including update preserving immutable first originals.
- The now-executed `portable_prepare.sh` exposed real blockers that the mocked package-post fixture did not cover: ordinary (non-origin) structural/audio preparation passed an empty origin metadata value; first `stock-origins` capture treated an empty index as an existing row; an alternate `/system/onebin/.../featurexml.cfg` path lost its `onebin` prefix; and wrapper staging checked unmapped `/data/...` paths when using the fixture root. Fixed these paths and metadata branches in `tools/portable/prepare.sh`.
- Corrected stale fixture expectations to match the selected `bt` target, actual alternate featurexml location, full manifest field layout, and non-root host metadata helper behavior. `tests/portable_prepare.sh` now exits 0, including legacy preparation, original-origin capture, V1/V2 update reuse, wrapper merge, and regional-audio paths.
- `tests/portable_usb.sh` and `tests/portable_package_post.sh` pass. The full `tests/run-shell.sh` reached all scheduled shell and parallel package phases; all displayed package jobs reported PASS and the final `tests/portable_ui.sh` independently exited 0. `git diff --check` reports no whitespace errors (only existing CRLF normalization notices in unrelated worktree files).
- This is source/host evidence only. No vehicle USB was written; actual NEMESIS Android-down dispatch, exact restore on the target, real reboot, and BT audio/HUD/INFO/dongle remain unverified. Next action is the harmless vehicle dispatch probe plus exact restore, then one controlled update over the existing installation.
