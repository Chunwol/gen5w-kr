# Gen5W Boot Safety Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Prevent an integrated Gen5W update from rebooting without an armed recovery path and make boot-loop recovery restore every file owned by the integrated packages.

**Architecture:** Keep the existing NEMESIS transaction and package backups. Add a pre-reboot bootguard contract with an atomic armed marker, restore all owned ODEX/library targets from verified durable backups, and make Dalvik-cache cleanup fail closed. Keep ODEX-only patching explicit; do not regenerate ODEX with dexopt because that would discard byte patches.

**Tech Stack:** Android 4.4 toolbox/mksh shell scripts, NEMESIS package hooks, Bash mock tests.

**Spec:** User request to compare Gen5W safety mechanisms and prevent another brick.

## Global Constraints

- Never reboot after a successful install unless a bootguard was armed and verified.
- Never silently continue when a matching Dalvik-cache entry cannot be removed.
- Restore only non-symlink files from package-owned durable backups.
- Preserve existing uncommitted changes and do not claim vehicle recovery without live evidence.
- ODEX-only byte patches must not be replaced by a stock dexopt result.

## Review Focus

- Bootguard must cover services.odex, SystemUI.odex, Iap2ServerApp.odex, HKMC_DiPO.odex, HKMC_GPM.odex, and libCarPlayAudio.so.
- An incomplete bootguard directory or failed marker write must refuse reboot.
- A failed Dalvik-cache deletion must abort the package hook and retain backups.
- Recovery failure must stop without issuing another reboot.
- Existing transaction rollback and package byte-identity tests must remain green.

---

### Task 1: Add failing bootguard recovery tests

**Files:**
- Create: tests/bootguard.sh
- Modify: tests/run.sh

- [ ] Write a fixture with patched targets and stock backups for every integrated target, run the current recovery script, and assert all targets return byte-identically to stock.
- [ ] Run bash tests/bootguard.sh and observe failure because the current script restores only two targets.
- [ ] Add assertions for stale Dalvik entries being removed and a recovery marker being written.

### Task 2: Make bootguard restore complete and fail closed

**Files:**
- Modify: packages/wireless-bridge/scripts/bootguard-recover.sh
- Test: tests/bootguard.sh

- [ ] Add restore calls for bridge ODEX files and the audio library.
- [ ] Verify each atomic replacement with a byte comparison and refuse symlink paths.
- [ ] Wipe all matching Dalvik entries and return failure if any remain.
- [ ] On restore failure, record recovery-required state and exit without another reboot.

### Task 3: Make installation refuse an unprotected reboot

**Files:**
- Modify: tools/integrated/common.sh
- Modify: packages/wireless-bridge/scripts/service.sh
- Test: tests/integrated.sh, tests/bootguard.sh

- [ ] Write an atomic armed marker and validate it before the bridge service counts boot attempts.
- [ ] Move bootguard arming before the committed state and make arm failure roll back the transaction instead of rebooting.
- [ ] Keep the guard until sys.boot_completed=1, then remove it.
- [ ] Add a test-injected arm failure and assert no reboot is requested.

### Task 4: Make package cache cleanup fail closed

**Files:**
- Modify: packages/hotspot-match/scripts/profile-common.sh
- Modify: packages/notice-timer/scripts/common.sh
- Modify: packages/wireless-bridge/scripts/common.sh
- Modify: corresponding post.sh hooks
- Test: existing hotspot_profile.sh, notice.sh, bridge.sh

- [ ] Replace ignored glob deletion with checked removal and post-removal verification.
- [ ] Abort and restore the target if cache cleanup fails.
- [ ] Add mock assertions that stale entries are removed before a package hook returns success.

### Task 5: Document the safety comparison and limits

**Files:**
- Create: docs/boot-safety.md
- Modify: README.md or relevant safety documentation

- [ ] Record the verified safety mechanisms of NEMESIS, Leafia, LaunchPad, Rear Dashcam, Phone Assistant, and the auto-dismiss package.
- [ ] State that research/decryption utilities are not runtime head-unit programs.
- [ ] State that bootguard improves recovery but cannot guarantee hardware/eMMC or power-failure recovery.

---
