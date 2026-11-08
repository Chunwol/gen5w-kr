# Error Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Preserve classified first failure, recovery outcomes and bounded private diagnostics across all important existing feature boundaries.
**Architecture:** Shared shell event/command helper shipped independently with each module; a pure Java safe diagnostic formatter/rate gate used by core and bridge. Existing reporter and collectors export bounded, sanitized records and distinguish collection failures from empty output. No blanket error-policy relaxation.
**Tech Stack:** Android 4.4/API18-compatible Java8, mksh/toolbox, Python build/test tooling, qemu ARM where matching fixtures exist.
**Spec:** `docs/superpowers/specs/2026-11-08-error-observability-design.md`

## Global Constraints

- Preserve existing dirty hotspot fix and USB evidence. No push, release or USB mutation.
- No raw credentials, addresses, phone/media/navigation content, shell command arguments, arbitrary throwable messages or payloads.
- Keep expected probe/cleanup failures separate from critical operation failures; preserve original rc and fail-closed decisions.
- Shared helper copies are generated mechanically from one canonical source and validated for identity; runtime modules remain standalone.
- Diagnostic journals: 65536 bytes per segment, four segments, 4096 bytes maximum one sanitized record. Archive eight owned report attempts; never delete unknown files.
- First failure stays immutable for each attempt; recovery events never replace it. Diagnostics failure cannot interrupt cleanup.

## Review Focus

- Stdout-parsing caller: logging must not contaminate parsed values (Task1/3).
- Symlink or read-only destination: never follow links or falsely report persistence (Task1/4).
- Huge/secret-bearing stderr: bounded input/output, redacted marker and original rc (Task1/3).
- Restart or concurrent writers: no indefinite locks, root cause and archive ownership remain valid (Task1/4).
- Logging during transport cleanup: observer failure must not prevent actual stop/disconnect (Task2/5).

## Task 1: Standalone shell diagnostic boundary

Files: create `tools/diagnostics/errors.sh`, `tools/diagnostics/sync.py`, `tests/error-journal.sh`; module `scripts/errors.sh` copies; modify `tests/run-shell.sh`.
Interfaces: `err_event module stage operation result rc reason`, `err_run module stage operation command [args...]`, `err_mount module mode command`; `ERR_DIR` defaults to private `/data/nemesis/gen5wkr.errors`; stdout preserved, diagnostic events on stderr. `err_run` command stdout stays streamed; bounded stderr must not be injected into stdout.
- [ ] Write failing real mksh tests: rc13/127, empty vs failed, stdout unchanged, first error vs recovery, permission/busy classification, secrets absent, >64KiB input bounded, segment rotation, symlink refusal, observer write failure preserves command rc.
- [ ] Run `wsl ... mksh tests/error-journal.sh`; observe RED before implementation.
- [ ] Implement helper and identity sync, shell-only toolbox-compatible operations; no unbounded command substitution of arbitrary output.
- [ ] Run focused tests and `python tests/unit_commands.py`; run whole suite; commit explicitly selected files.

## Task 2: Java safe diagnostic contract

Files: create `shared/src/kr/gen5w/diag/SafeDiagnostic.java`, `tests/SafeDiagnosticTest.java`; modify app/bridge compilation and host test harness where needed.
Interfaces: static bounded safe token/class formatter; static rate gate keyed only by fixed code with at most64 entries, repeated code emitted on change or after30000ms. Java transport logging uses fixed context, exception class and generation, never exception message.
- [ ] Test RED: credentials in exception message never emitted, invalid code rejected, 1000 repeated events bounded, clock rollback, capacity bound.
- [ ] Implement pure Java class and build wiring; real consumer tests must exercise emitted diagnostic and unchanged failure result.
- [ ] Run JVM/bridge/core tests and API18 app/DEX builds; commit.

## Task 3: Install/remove/recovery/module command instrumentation

Files: wireless/audio/bridge/dongle/hotspot common/post/preun and bootguard scripts; `tools/integrated/common.sh`; timer/bluelink/core/drive-log scripts as inventory requires.
Interfaces: Task1 helper; fixed module/stage/operation IDs. First failure and rollback are separate events; byte verification and NEMESIS registration not conflated.
- [ ] Add RED failure injection at real remount rw/ro, failed hook, missing helper, failed snapshot, failed rollback, AP broker exit boundaries.
- [ ] Instrument critical suppressed command outputs and unlabelled failure returns, preserve existing control flow. Keep expected probes quiet but report terminal all-probes-failed conditions.
- [ ] Route broker stdout/stderr to bounded sanitized diagnostic sink, preserve supervisor PID and retry behavior.
- [ ] Run module/integrated/recovery/bootguard tests plus full suite; commit.

## Task 4: Report history and collector reliability

Files: `tools/integrated/NEMESIS.sh`, `report.sh`, `diag.sh`, `check.sh`, `packages/core/scripts/uilog.sh`; build packaging; new report/collector tests.
Interfaces: Task1 journal, attempt IDs consisting only of boot/uptime/counter, eight owned archive slots. Current report filenames preserved for compatibility.
- [ ] RED: run two failed attempts and prove first retained; inject command absent/permission/empty stdout, USB write failure and symlink archive; root cause distinct from rollback.
- [ ] Add archive ownership/rotation, private bounded fallback and explicit export status. Include bounded diagnostic records and command acquisition statuses in report/diag/UI deep save.
- [ ] Keep stdout needed by parsing functions unchanged; redact secrets before any persistent export.
- [ ] Run integrated/FAT32/diag/uilog/collector tests and full suite; commit.

## Task 5: Runtime feature boundaries

Files: bridge Java AP broker/client/profiles/adapter, core StockOwner/StockGuidance/CoreService, UI SwitchRequest/HudSwitch/BoundedLines; service scripts per audit.
Interfaces: Task2 safe diagnostic and Task1 module log sink; stage/code/generation/uptime connected to boot/build via collection header.
- [ ] RED real consumer tests: provider timeout vs query exception, AP rejection vs binder exception, BT start/write/stop failure, UI write failure, missing optional API; assert safe diagnostic and unchanged fail-closed/cleanup behavior.
- [ ] Instrument terminal/important failures; intentionally silent expected validation misses, optional fallback selection and secondary close exceptions remain documented.
- [ ] Verify USB logger refusal/write/EOF reasons are collected; preserve opt-in numeric-only USB records and do not log payloads.
- [ ] Run feature integrations, full suite and builds; commit.

## Task 6: Whole-tree audit and final verification

Files: `docs/error-observability-audit-2026-11-08.md`, final regression coverage/build checks, this plan status.
Interfaces: all tasks; audit matrix per module classifies changed/intentional/audited/unresolved with test evidence.
- [ ] Rescan all suppressed stderr/ignored catches, review each critical path; record explicit remaining limitations without completion inflation.
- [ ] Run full `tests/run.sh`, command compatibility, app/bridge builds, complete clean-tree build-all, APK version and artifact audit.
- [ ] Request fresh whole-branch review using executing-plans skill, address Important/Critical with RED/GREEN plus green full suite, ledger any Minor/rulings.
- [ ] Commit final verified work; update KnowledgeHub, goal and self-contained user report. No release/USB mutation.

## Execution note

The user approved the design and asked to set a goal and report when finished. Execute inline to completion; do not add another conversational approval checkpoint. Remaining uncertainty is settled against the approved spec and recorded in the ledger, not hidden.
