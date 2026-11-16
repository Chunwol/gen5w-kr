# V039 regional audio and recovery implementation plan

> **For agentic workers:** Use focused independent task workers and a final code review. Steps track the user-approved in-chat design.

**Goal:** Preserve existing structural portability, admit audio libraries by reviewed patch/ABI regions rather than whole-file identity, and close the three reproduced recovery gaps.
**Architecture:** Keep existing shell/Java/native interfaces; make compatibility checks local to code/ABI that is consumed. Keep bundle and per-vehicle original integrity checks. Each independent recovery task owns its tests and code.
**Tech stack:** API19 ARM C/Thumb, mksh, Java8/Dalvik, Python/WSL fixtures.
**Spec:** User-approved in-chat design on 2026-11-14 and emu/audits/20261114-111357-portability/PORTABILITY-AUDIT.ko.md.

## Global constraints
- Preserve existing dirty work, rc.1q and deployed candidates. No USB/vehicle/original image writes.
- No firmware bytes in source, reports or published packages; hashes and authored code only.
- No new whole-file whitelist for runtime compatibility. Keep ABI, service, patch-region and integrity checks.
- A mismatch must produce no patch output. Unsupported optional features remain explicit skips.
- No commit or push to the package repository without user request.

## Review focus
- Unrelated library-byte changes must be accepted, consumed region changes rejected.
- Fixed addresses require validating ELF mappings, CF string/PLT relationships and decoder ABI; whole-file checks cannot simply be deleted.
- Stale locks may be reclaimed only with proven dead ownership; concurrent acquisition must stay exclusive.
- Failed USB preflight/update must retain original hook and ownership.
- Readiness publication failure must undo this attempt's hooks, preserve preexisting groups and report rollback failure honestly.

## Task 1 — audio compatibility boundary
Files: tools/audio/{patch.c,build.py,recipe*.json}, portable preparation and focused audio tests.
- [x] Add failing tests for whole-file changes outside reviewed regions, changed consumed bytes, partial/foreign patches, truncated ELF, shifted mappings, and no output on refusal.
- [x] Generate region-only fingerprints and validate ELF/symbol/relocation contracts for authored fixed-address selectors and used dependencies; keep historical exact profiles for the legacy installer when needed.
- [x] Update portable preparation to use the new capability check rather than dependency whole-file SHA.
- [x] Build fresh helpers in isolated output, run host+ARM checks against private read-only images and altered copies, audit package.

## Task 2 — session publication/recovery
Files: tools/portable/session.sh, tests/portable_session.sh.
- [x] Add failing empty-lock/publication interruption and concurrent-start tests.
- [x] Atomically publish ownership and safely reclaim only provably orphaned claims; trap cleanup covers intermediate failure.
- [x] Run session/lifecycle fixtures.

## Task 3 — refused USB update preserves old package
Files: tools/portable/usb/NEMESIS.sh, tests/portable_usb.sh.
- [x] Add failing existing unarmed package + AP refusal/failed update cases asserting original hook identity.
- [x] Order read-only preflight before mutation and restore old hook on unsuccessful operations while never overwriting a newly installed hook.
- [x] Run USB fixtures.

## Task 4 — adapter install/readiness transaction
Files: portable Bootstrap.java and Projection/Dipo/Gpm adapters; focused Java fixtures.
- [x] Add failing post-install marker publication/rollback/retry tests using production code and host boundaries.
- [x] Keep rollback ownership until readiness is published, avoid duplicate install on retry, preserve existing successful installation.
- [x] Run host/ARM loader and adapter tests.

## Integration
- [x] Independently review all four changes and resolve findings.
- [x] Run appropriate full shell/Python/JVM regression on current code; do not call skipped physical tests verified.
- [x] Assemble a fresh uniquely named candidate, verify engine inputs and complete file inventory, preserve older outputs.
- [x] Record verified scope, limitations and next action in KnowledgeHub.

Completion evidence: `emu/development/20261114-112838-v039-portable/DEVELOPMENT-RESULT.ko.md`; full-regression-v2 exit0. Private local-hotspot install lacked stock and was skipped; vehicle checks remain separate.
