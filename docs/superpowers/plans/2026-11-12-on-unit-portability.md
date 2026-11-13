# On-unit portability implementation plan

**Goal:** Continue the previously requested complete PC implementation of on-unit structural patching, reversible overlays, and app-local DiPO/GPM adapters, without changing the current vehicle/USB installation.

**Architecture:** Keep the current exact-build release intact. Build a separate opt-in portability candidate. A bounded native DEX/ODEX tool discovers reviewed instruction shapes from local files and reseals checksums; a journaled overlay applies only validated outputs. Unknown structures skip their dependent feature. Code-adding adapters require a verified app-local Dalvik integration and must not be claimed supported solely from symbol availability.

**Constraints:** Android 4.4 ARMv7/API19, mksh/toolbox; no OEM files in source or public artifacts, no system partition writes, no MICOM/CAN/bootloader changes, no change to existing dirty files. PC verification and vehicle verification are separate claims. Preserve rc.1q artifacts.

**Execution:** subagent-driven-development, in the existing isolated gen5w-kr-stock-first worktree. The user's current instruction continues the previously approved overall approach and requests completion without another scope approval.

## Tasks

- [x] Native structural patcher: iAP2 Bluetooth/capabilities, route-only, DiPO call key, GPM HUD, local hotspot. Host/ARM builds, byte-for-byte differential tests against existing generators on private stock; malformed/ambiguous inputs leave no output.
- [x] Overlay lifecycle: prepare/apply/status/commit/disable, local source identity checks, durable boot journal, safe recovery, per-feature status, mock mount tests. Automatic next-boot activation only after the on-unit VM probe and sealed local validation; explicit disable, per-feature rejection and retained recovery.
- [x] Dalvik adapter: inspect exact local ABI and current authored adapters; implement and test the required app-local loading/dispatch where evidence supports it. Explicitly report any ABI/VM limitation instead of shipping an untested hook as supported.
- [x] Candidate integration: separate build command and manifest, dependency-aware feature selection, documentation, tests, artifact audit. Run relevant existing regressions and new tests.
- [x] Review fixes and KnowledgeHub session/brief update with evidence and unresolved vehicle checks.

## Review focus

Truncated tables/ULEB and arithmetic overflow; wrong register or instruction boundaries; stale GC maps; interrupted mounts/boots; unsupported optional feature disabling unrelated features; accidental OEM content or release artifact replacement; hook thread/exception/original-call correctness.

## 2026-11-13 integration decisions and evidence

- Final requested lifecycle: automatic reapply each boot, explicit disable to restore; cold boot and normal ignition proof remain vehicle-only.
- Native guardian rescues a bounded maintenance worker on timeout/failure/parent death. SIGPIPE is ignored so the parent waits for rescue even after descheduling.
- Local init profile supplies onrestart service dependencies. Framework readiness uses a fresh system_server identity plus current ActivityManager booted state and PackageManager, outside the framework-down timeout.
- Native NEMESIS version/app ownership/hash preflight, guarded APK installation, verified executable permissions, portable core boot receiver disabled, next-boot arm, retained readable wrappers outside uninstallable package.
- Boot-aware PID/starttime locks treat zombies as dead and atomically publish complete owner records. Status does not unmount live code; visible rollback requires stopped Android.
- Unsupported VM/app drops wireless-only features and retains independent static entries. Optional stock drift/GPM absence or foreign GPM wrapper does not discard DiPO. Unsupported runtime stays skipped until re-arm; transient healthy-session exit retries only next boot.
- Claude: initial independent 15-command validation passed; two reviews exposed real lifecycle defects which were reproduced and fixed. Patcher hardening has 32 new unknown-shape rejection cases, stock differential outputs unchanged.
- PC ARM VM validates dispatch/original/exception/GC/monitors/app loader/bootstrap/no-hook marker and stock DiPO discovery (15 hooks). It does not establish vehicle startup, radio/Binder, quickboot or display success.
- Final PC validation complete: full-isolated-final.log ended ALL TESTS PASSED (exit0); real-controller multi-boot, fresh ARM VM and patcher, UI/Java and final APKs passed. UI fixture cmdline collided with legacy /proc safety checks in an earlier run; reproduced, serialized/reaped the fixture and reran the whole suite successfully without weakening production guards.
- Code checkpoint 336f996; final 42-member authored ZIP audited after writing/reopening. Details and hash: docs/portable-verification.md. Vehicle/USB untouched; the one-visit vehicle checklist remains pending and vehicle_verified remains false.
