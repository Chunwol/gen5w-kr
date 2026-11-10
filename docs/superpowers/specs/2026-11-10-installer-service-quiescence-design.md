# Installation service quiescence using supported NEMESIS controls

Date: 2026-11-10
Status: Proposed; official-update direction selected by the user, detailed spec awaiting review.

## 검토용 요약

현재 복구부터 끝낸 뒤 공식 NEMESIS 업데이트를 별도 단계로 진행하고, 지원되는 서비스 정지 API로 우리 서비스만 멈추는 방향이다. 구버전 관리자를 강제로 조작하거나 순정 서비스를 일괄 종료하지 않는다. 종료·재시작 억제·잔여 프로세스 확인 중 하나라도 입증되지 않으면 파일 교체 전에 중단한다.

핫스팟 순정 no-op 수정은 구현·시험한 별도 변경이며, 서비스 제어 기능은 아직 구현하지 않았다. 이 문서는 상세 구현 계획을 작성하기 전 검토할 설계안이다. NEMESIS 파일은 PC에만 준비했고 USB 업데이트나 차량 업데이트를 실행하지 않았다.

## Intent and verified failure

Prevent our existing services from overlapping package replacement, without stopping vehicle services or defeating recovery guards. The user requested stopping existing modules before installation and delegated the approach choice.

The vehicle is on NEMESIS 1.16.3. Its latest installation reaches localhotspot cleanup, reports an already-original target, makes /system writable, and fails all read-only remount attempts with an unknown reason. Rollback hits that same cleanup and retains recovery-required. Separate ERR persistence=failed lines do not establish why remount failed.

The bounded hotspot fix is separate: under the existing lock and exact APK/ODEX checks, remove of an original target does not remount or change system files. Existing backups and temporary evidence stay intact. An already-executable durable helper does not require chmod. Actual patch installation/removal still requires the original safety checks; unknown remount failures remain failures.

## Alternatives and decision

1. **Supported NEMESIS control, recommended.** First recover the current transaction with the corrected compatible kit. Prepare the official NEMESIS update separately. Only then implement service quiescence against supported, verified stop semantics. Adds an explicit platform prerequisite but avoids manipulating NEMESIS internals.
2. **Stop calls alone on 1.16.3, rejected.** An older supervisor may restart the service. A successful stop command or missing parent PID does not prove its children or Android service stopped.
3. **Modify service registry or stop the NEMESIS supervisor/watchdog, rejected.** This expands recovery ownership and can interfere with the USB runner itself.

Official history documents stop persistence and uninstall fixes in 1.16.4. The current official Update descriptor selects 1.16.7. Our local upstream_reference checkout is the published 1.15 source, not the vehicle binary. Neither version text nor current upstream source alone proves physical-car behavior.

## Proposed lifecycle

1. Validate the complete kit and current transaction state. A recovery-required transaction cannot start a new install. Do not erase failure history or its snapshot.
2. Acquire the existing transaction lock. Capture the relevant service inventory before any hook or package mutation. Normal install/update requires supported NEMESIS stop semantics; unknown/older capability refuses before changing packages and gives an actionable update message.
3. Stop only an explicit allowlist of our package services through NEMESIS. Do not stop built-in services, other packages, the supervisor, watchdog, USB handler, or stock Android components.
4. Verify actual quiescence, not just command exit status. Check service status, exact owned process identities and their descendants, and known app service components. Never use killall or kill an unverified/reused PID. Unreadable or contradictory ownership data refuses mutation. The inspection implementation must be tested against the target toolbox.
5. Perform snapshot and package work while quiescent. NEMESIS may start a newly installed package's services after its postinstall hook, so check and stop them again before the next module's mutation. A supervisor restart invalidates the previous quiescence proof and requires a fresh check before continuing.
6. Keep the installer worker and its bounded USB diagnostics alive independently of the core collector. Quiescing the core cannot terminate the worker doing package replacement or discard its final report.
7. On success, finalize verified files, bootguard state and suppression ownership, then request a cold reboot. Service startup after that reboot must be verified on the supported platform, not assumed from the stop API.
8. On failure, follow the existing rollback and recovery-required rules. Only a verified consistent restored state may resume previously running services; unresolved recovery must not restart a mixed generation. An interruption preserves the snapshot, quiescence journal, original failure and a USB recovery route.

## Journal and safety requirements

- Add bounded root-owned transaction records for service identity, prior state, stop/check results and resumption decisions. Reject symlinks, truncation and unknown state.
- No phone IDs, arbitrary command lines, secrets, unbounded output or raw log exports.
- Do not rewrite NEMESIS private pid/stop/registry files to bypass its API.
- Keep legacy USB recovery available: a new normal-install prerequisite must not strand a vehicle that needs recovery on 1.16.3. Legacy recovery cannot claim full service quiescence without proof.
- No automatic NEMESIS updater execution inside our install or rollback. The official updater and our kit remain separate root-level USB workflows; changing one descriptor must never accidentally invoke the other.

## Verification before implementation completion

Behavior tests must exercise our real entry points with controlled NEMESIS/process boundaries:

- Old/unknown platform refuses a new install before hooks or snapshot replacement, without blocking the approved legacy recovery route.
- Only allowlisted services stop, with failures and malformed inventory failing closed.
- Automatic restart, remaining children, Android instance services, PID reuse and supervisor restart cannot pass quiescence checks falsely.
- New module autostart is quiesced before the next module's writes.
- Core service stop does not stop the installer worker or diagnostics.
- Success, rollback, interrupted cleanup and recovery-required preserve the correct prior service states and original error.
- Full mock/JVM suite, clean build, artifact audit and independent review precede release or USB changes. Vehicle stop/restart and remount behavior remain a separate test gate.

## Current handoff boundary

No service-quiescence product code or platform update is implemented/applied by this spec. The official 1.16.7 files are staged only on the PC with pinned upstream blob verification. The current vehicle still needs recovery; its USB has not been changed during this fix.

Review this spec before writing the detailed implementation plan and selecting execution. The bounded hotspot fix can be reviewed and committed independently, but does not establish that a new hotspot patch will remount read-only successfully on the vehicle.

## Primary references

- https://github.com/xwtk/hmg_nemesis/blob/70e72d2dce4b39795d618ce46074be96f0294185/README.md
- https://github.com/xwtk/hmg_nemesis/blob/70e72d2dce4b39795d618ce46074be96f0294185/Sources/native/svc.c
- https://github.com/xwtk/hmg_nemesis/blob/70e72d2dce4b39795d618ce46074be96f0294185/Sources/native/pkg.c
- https://github.com/xwtk/hmg_nemesis/blob/70e72d2dce4b39795d618ce46074be96f0294185/Update/NEMESIS.data
