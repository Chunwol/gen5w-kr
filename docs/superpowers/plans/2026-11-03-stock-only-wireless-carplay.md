# Stock-Only Wireless CarPlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Request wireless CarPlay only through V039 OEM PhoneProjection, without changing boot-critical files or starting parallel RFCOMM/iAP2/AP paths.

**Architecture:** A pure Java session controller owns one request per connected-phone generation. The reflection adapter reads the active user's saved `WLDeviceInfo` profile and sends the same package-scoped action as the V039 PhoneProjection UI only for an enabled, auto-connect CarPlay profile. It observes OEM CarPlay state and fails closed on missing profile, service, permission, timeout, or stale callbacks.

**Tech Stack:** Java 8, Android API 18/19 host, V039 reflection, existing shell package scripts, JVM and shell tests.

**Spec:** `docs/superpowers/specs/2026-11-03-stock-first-wireless-carplay-design.md`

## Global Constraints

- Never modify `services.odex`, `SystemUI.odex`, Android framework files, boot/recovery images, LK, or MICOM.
- No direct RFCOMM socket, custom iAP2 connect/start, or custom AP startup for CarPlay.
- PPManager request return is not success; only OEM CarPlay-connected state marks projection active.
- No phone identifiers, names, UUIDs, credentials, route content, or raw exception text in logs.
- No vehicle install, USB update, release publish, or claim of vehicle success.

## Review Focus

- Missing OEM service/method: no direct fallback; stable unavailable result.
- OEM gate false/unknown: no request and no parallel transport.
- Stale callback after disconnect/wired/foreign session: ignored.
- OEM active phone address: compare only in memory and never log.
- Legacy package state: restore only verified backups; stop before writes on unknown/damaged state.

---

### Task 1: Pure stock request lifecycle

**Files:** create `StockProjectionSession.java`, `StockProjectionSessionTest.java`; modify `tests/java.sh`.

- [x] Test one request per generation, profile-denial block, request-return-not-active, OEM-active observation, same-address `CONNECTING`, timeout, cancellation, and stale callback suppression.
- [x] Test dispatch-time timeout races so late reflection work cannot send or restart a request.
- [x] Run the failing tests before implementation.
- [x] Implement the pure Java controller with stable result categories.
- [x] Run the JVM suite.

### Task 2: OEM PhoneProjection reflection adapter

**Files:** create `PhoneProjectionAccess.java`; modify `BridgeHostService.java` and manifest only if required.

**Interface:** resolve `context.getSystemService("phoneprojection")`; reflect the active `UserProfileManager` and `PPManager.getWLDeviceInfo(address, "", userType)`, then send the source-verified PhoneProjection UI action with the address extra. Observe `getWirelessConnectState()` and `getCPConnectedBTAddress()`. Never call OEM disconnect or change profile values.

- [x] Test profile/address/type/setting checks, action/package/extra, and privacy-safe behavior.
- [x] Implement missing/type/security/invocation failure handling.
- [x] Build the bridge DEX and signed host APK. Source audit confirms reflection-only OEM class access.

### Task 3: Remove active direct transport

**Files:** modify `WirelessBridge.java`, `WirelessSession.java` or replace with Task 1 controller; update focused wireless tests.

- [x] Add a stock-only source audit for active direct RFCOMM, custom iAP2, and AP setup.
- [x] Route connected bonded devices through the OEM controller; cancel local attempts on disconnect, wired connection, Bluetooth off, and shutdown.
- [x] Remove active direct socket, custom iAP2, and AP setup from the bridge runtime.
- [x] Run JVM tests and compile the bridge DEX/host APK.

### Task 4: Preserve independent app features and safe package lifecycle

**Files:** modify `tools/iap2/control_patch.py`, `tools/iap2/dipo_patch.py`, their tests, and `packages/wireless-bridge` lifecycle scripts/data as needed. Preserve GPM AA HUD and DiPO call-key fallback if independently patchable.

- [x] Replace the old Iap2ServerApp service-control shim with the exact stock-derived capability-only Wi-FiInformation/RouteGuidance recipe. OEM service methods remain unchanged; Core's route capability gate accepts only the new helper.
- [x] Remove the obsolete DiPO wireless dispatch from V035/V039 recipes while retaining the independent call-key fallback. Regenerated both hash-bound recipes from stock ODEX bytes whose whole-file SHA-256 values match the reviewed source profiles; lifecycle recognizes both previously shipped recipes per version.
- [x] Keep GPM patch separate for Android Auto HUD and retain verified-backup install/update/remove recovery.
- [x] Mock lifecycle tests confirm refused unknown/damaged states and exact restore. Source audit confirms no boot-critical targets in this package's write allowlist.

### Task 5: Final artifact audit

- [x] Run JVM, stock source, and bridge lifecycle checks once after focused tests passed.
- [x] Inspect built DEX/host APK and package scope; no boot-critical ODEX/framework/LK/kernel file is an install target.
- [x] Build the full integrated ZIP set and run the full artifact audit from a clean committed checkout; the generated USB trees remain local to `dist/`.
- [x] Re-read the spec/plan and run `git diff --check`; report vehicle-only unknowns separately.
