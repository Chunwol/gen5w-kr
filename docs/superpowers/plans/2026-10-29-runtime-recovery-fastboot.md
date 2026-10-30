# Runtime Recovery and Fastboot Recovery Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Keep recovery armed across later ignition cycles and provide a host-side, stock-only fastboot recovery path without modifying the vehicle bootloader in the public installer.

**Architecture:** The wireless bridge keeps a durable bootguard directory after `sys.boot_completed`; a small state helper resets the consecutive-failure counter only after a completed boot, while the existing recovery script restores verified on-unit originals after repeated incomplete boots. A Windows/Python host tool probes fastboot, validates an external stock manifest, and only permits an explicit allowlisted flash; no bootloader, modem, MICOM, erase, or unlock operation is included.

**Tech Stack:** Android 4.4 mksh shell, Python 3 host utility, Bash/Python tests.

**Spec:** User request to make the next version recoverable when a later ignition enters the same boot loop.

## Global Constraints

- Never delete the bootguard merely because `sys.boot_completed=1` was observed once.
- Never put LK, bootloader, modem, MICOM, stock binaries, keys, or per-car identifiers in the repository.
- Fastboot recovery must verify the exact product and external SHA-256 manifest before any write.
- Only `boot`, `system`, `recovery`, and `dtb` may be flash targets; no erase, unlock, bootloader, modem, MICOM, or arbitrary partition.
- No vehicle, USB, boot partition, or fastboot write is performed in this change.

## Review Focus

- A later boot loop after an earlier successful boot leaves the guard armed and reaches recovery after the configured consecutive-failure limit.
- A normal completed boot resets the failure counter without deleting the guard directory.
- Missing, symlinked, mismatched, or path-traversal stock manifest entries are refused.
- Fastboot probe failures and product mismatches produce a report without issuing flash commands.
- Existing package and integration tests remain green.

### Task 1: Persistent bootguard state

**Files:**
- Create: `packages/wireless-bridge/scripts/bootguard-state.sh`
- Modify: `packages/wireless-bridge/scripts/service.sh`
- Create: `tests/bootguard-runtime.sh`
- Modify: `tests/run.sh`

- [x] Write tests for `begin`, failure-limit return, and `mark-ok` retaining the guard while resetting the count.
- [x] Implement the state helper with atomic marker writes and symlink refusal.
- [x] Use it from the bridge supervisor and keep the guard after completed boot.
- [x] Run the focused runtime test and the bridge/bootguard tests.

### Task 2: Host-side fastboot recovery tool

**Files:**
- Create: `tools/recovery/fastboot_recovery.py`
- Create: `tests/fastboot_recovery.py`
- Create: `docs/bootloader-recovery.md`
- Modify: `docs/README.md`

- [x] Write parser, manifest, allowlist, and no-flash-on-probe-failure tests.
- [x] Implement read-only probe and explicitly confirmed stock-only flash mode.
- [x] Document that the vehicle must already enumerate in fastboot and that LK/USB wiring remains unverified.
- [x] Run focused host tests.
- [x] Build a non-destructive PC recovery USB bundle with no images, installer action, or automatic flash command.
- [ ] Run the complete repository suite.

### Task 3: Evidence and release boundary

**Files:**
- Modify: `docs/boot-safety.md`
- Modify: `README.md`

- [x] State that public installers do not modify LK and that the host tool is a recovery aid, not proof of real-vehicle fastboot access.
- [x] Block release claims until real fastboot enumeration and a supervised stock restore are separately verified.
