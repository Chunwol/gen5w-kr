# OEM Wireless Projection Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a bonded, currently linked phone enter the V039 OEM first-registration or saved-profile path for wireless CarPlay and wireless Android Auto, while observing projection Wi-Fi readiness without owning the AP or transport.

**Architecture:** Extend the pure Java session controller with separate bootstrap, profile, Wi-Fi, and final-connection deadlines. Keep reflection and Android broadcasts in narrow adapters, and keep `WirelessBridge` as the generation-checked coordinator. OEM PhoneProjection remains the only owner of SPP, profile creation, AP startup, iAP2, and Android Auto transport.

**Tech Stack:** Java 8 source, Android API 18/19 host APK, V039 hidden OEM APIs through reflection, NEMESIS package scripts, shell/JVM integration tests.

**Spec:** `docs/superpowers/specs/2026-11-04-oem-wireless-projection-bootstrap-design.md`

## Global Constraints

- Support OEM profile type `1` as CarPlay and type `2` as Android Auto; do not infer the platform before a profile exists.
- Send package-scoped `android.bluetooth.device.action.START_SPP_CONNECT_FOR_CONNECTIVITY` to `com.daudio.app.phoneprojection` with only `ADDRESS`, then invoke `PPManager.requestConnectSPP(String)` exactly once per candidate generation.
- Reconnect a ready profile through package-scoped `com.daudio.app.PhoneProjection.Wireless.SEND_CONNECTION_PHONEPROJECTION` with only `deviceAddress`.
- Observe `ConnectivitySSID` and `ConnectivityPSK` only as present/missing booleans; never log or retain values, lengths, hashes, or comparisons with ordinary hotspot credentials.
- Never call `setWifiApEnabled`, `setWifiApEnabledForConnectivity`, `setWifiApConfiguration`, hostapd, direct RFCOMM, private iAP2, or custom Android Auto transport from the stock bridge path.
- Do not modify PhoneProjection, Bluetooth, framework, `services.odex`, `SystemUI.odex`, boot/recovery, LK, kernel, or MICOM.
- Wired projection, foreign OEM ownership, Bluetooth off, candidate loss, shutdown, and stale callbacks invalidate the generation before dispatch.
- Code and CI completion do not claim vehicle success; CarPlay, Android Auto, AP, audio/calls, and wired fallback require separate vehicle acceptance.

## Review Focus

- A profile can appear after bootstrap while a late callback from the previous poll is still queued; only the current generation may advance or dispatch.
- Wi-Fi configuration access can be unavailable rather than truly empty; `UNKNOWN` must remain distinct from `MISSING` so reflection failure is not reported as missing credentials.
- An OEM `CONNECTED` state is authoritative even if the AP broadcast was missed; AP observation must never demote a confirmed active projection.
- CarPlay and Android Auto connected-address getters can disagree or hold stale addresses; only the getter selected by the current profile type may match the candidate.
- A service restart during a pending bootstrap must inspect OEM state from scratch and must not replay a persisted pending generation.

---

### Task 1: Pure session lifecycle for profile bootstrap and Wi-Fi boundaries

**Files:**
- Modify: `packages/wireless-bridge/src/kr/gen5w/wireless/StockProjectionSession.java`
- Modify: `packages/wireless-bridge/test/StockProjectionSessionTest.java`

**Interfaces:**
- Consumes: a bonded/linked candidate address and monotonic milliseconds supplied by `WirelessBridge`.
- Produces: `Port.inspect(long,String)`, `Port.bootstrap(long,String)`, and `Port.requestConnect(long,String,int)` commands; generation-checked callbacks `inspected(...)`, `bootstrapped(...)`, and `requested(...)`.
- Produces: phases `IDLE`, `INSPECTING`, `BOOTSTRAP_REQUESTED`, `WAITING_PROFILE`, `CONNECT_REQUESTED`, `WAITING_WIFI`, `ACTIVE`, `BLOCKED`, `FAILED`, `CANCELLED`.
- Produces: public constants `PROFILE_BOOTSTRAP_TIMEOUT_MS=60000L`, `WIFI_TIMEOUT_MS=30000L`, `REQUEST_TIMEOUT_MS=20000L`, and poll interval `1000L`.
- Produces: `Observation(Result, boolean serviceAvailable, int profileType, ProfileState profileState, boolean active, boolean connecting, boolean otherActive, WifiCredentialState credentials, int apState)` where credential state is `UNKNOWN`, `MISSING`, or `PRESENT`.

- [ ] **Step 1: Write failing state-machine tests**

Add named cases asserting: `missingProfileBootstrapsOncePerGeneration`, `profileAppearanceDispatchesOnceForCarPlay`, `profileAppearanceDispatchesOnceForAndroidAuto`, `wifiUnknownIsNotMissing`, `activeWinsWhenApBroadcastWasMissed`, `bootstrapWifiAndFinalTimeoutsAreDistinct`, `wiredAndStaleCallbacksCancel`, and `restartStartsFromInspectionWithoutPendingState`.

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `bash tests/java.sh`

Expected: compilation failures for the new `Port.bootstrap`, profile/Wi-Fi states, phases, and callbacks.

- [ ] **Step 3: Implement the minimal pure controller**

Use one generation token, one bootstrap issue flag, one connect issue flag, and separate absolute deadlines. A missing profile issues one bootstrap; a ready type `1`/`2` profile issues one OEM connect; `CONNECTED` for the selected platform becomes active regardless of AP observation. Report `wifi-credentials-unavailable` only after a ready profile and accepted OEM connect observe `MISSING`; report `wifi-ap-timeout` only when connection remains inactive through the Wi-Fi deadline.

- [ ] **Step 4: Run the focused test and confirm GREEN**

Run: `bash tests/java.sh`

Expected: all Java tests pass, including the eight new lifecycle cases.

- [ ] **Step 5: Commit the controller task**

```bash
git add packages/wireless-bridge/src/kr/gen5w/wireless/StockProjectionSession.java packages/wireless-bridge/test/StockProjectionSessionTest.java
git commit -m "feat: model OEM projection bootstrap lifecycle"
```

### Task 2: OEM PhoneProjection profile bootstrap and dual-platform observation

**Files:**
- Modify: `packages/wireless-bridge/src/kr/gen5w/wireless/PhoneProjectionAccess.java`
- Modify: `packages/wireless-bridge/test/PhoneProjectionAccessTest.java`

**Interfaces:**
- Consumes: `ServiceProvider.get("phoneprojection")`, current Android context, candidate address, and a generation-checked `ActionSender`.
- Produces: `BootstrapResult bootstrap(ServiceProvider,Object,ActionSender,String)` with stable outcomes `REQUESTED`, `CANCELLED`, `SERVICE_UNAVAILABLE`, `METHOD_UNAVAILABLE`, `SECURITY`, `INVOCATION`.
- Produces: `inspect(ServiceProvider,Object,String)` returning Task 1's observation with profile type and selected CP/AA connected address.
- Produces: `requestCurrentProfile(...)` accepting enabled auto-connect profile types `TYPE_CARPLAY=1` and `TYPE_ANDROID_AUTO=2`.

- [ ] **Step 1: Write failing adapter tests**

Add fake manager/context cases asserting: the bootstrap action is package-scoped to `com.daudio.app.phoneprojection`, carries only `ADDRESS`, and `requestConnectSPP(candidate)` is invoked once; a successful return is `REQUESTED`, not active. Add profile cases proving type `1` uses only `getCPConnectedBTAddress`, type `2` uses only `getAAConnectedBTAddress`, unsupported types fail closed, and Android Auto dispatches the same existing-profile OEM UI action.

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `bash tests/java.sh`

Expected: compilation failures for `BootstrapResult`, `bootstrap`, dual-platform inspection, and the widened profile request.

- [ ] **Step 3: Implement the reflection adapter**

Resolve `requestConnectSPP(String)`, `getCPConnectedBTAddress()`, `getAAConnectedBTAddress()`, `getWirelessConnectState()`, and existing `getWLDeviceInfo(...)` through reflection. Classify missing methods separately from service, security, and invocation errors. Do not call `requestWLDeviceInfoAdd` or `requestWLDeviceInfoUpdate`.

- [ ] **Step 4: Run the focused test and confirm GREEN**

Run: `bash tests/java.sh`

Expected: all Java tests pass and both profile types dispatch only after exact address/type/setting validation.

- [ ] **Step 5: Commit the OEM adapter task**

```bash
git add packages/wireless-bridge/src/kr/gen5w/wireless/PhoneProjectionAccess.java packages/wireless-bridge/test/PhoneProjectionAccessTest.java
git commit -m "feat: bootstrap OEM wireless projection profiles"
```

### Task 3: Read-only projection Wi-Fi observer

**Files:**
- Create: `packages/wireless-bridge/src/kr/gen5w/wireless/ProjectionWifiAccess.java`
- Create: `packages/wireless-bridge/test/ProjectionWifiAccessTest.java`
- Modify: `packages/wireless-bridge/host/AndroidManifest.xml`
- Modify: `tests/java.sh`
- Modify: `tools/build-dex.sh`

**Interfaces:**
- Consumes: `Context.getSystemService(Context.WIFI_SERVICE)`, reflected `getWifiApConfiguration()`, and AP-state broadcast integers.
- Produces: `CredentialObservation inspect(Object wifiManager)` with status `UNKNOWN`, `MISSING`, or `PRESENT` and no credential material.
- Produces: `ApProgress classifyApState(int state)` mapping `12` to `ENABLING`, `13` to `READY`, `14` to `FAILED`, `10/11` to `OFF`, and other values to `UNKNOWN`.

- [ ] **Step 1: Write failing privacy and AP-state tests**

Assert null service/reflection failure is `UNKNOWN`; null/blank either connectivity field is `MISSING`; two non-blank fields are `PRESENT`; no result exposes a string field; AP states map exactly as listed. Add a source assertion that the class contains no AP mutation method name.

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `bash tests/java.sh`

Expected: failure because `ProjectionWifiAccess` and its test are not compiled yet.

- [ ] **Step 3: Implement the read-only adapter and build wiring**

Add only `android.permission.ACCESS_WIFI_STATE` to the host manifest. Read hidden connectivity fields reflectively and immediately collapse them into an enum. Add the source and test to the explicit `javac` lists in `tools/build-dex.sh` and `tests/java.sh`.

- [ ] **Step 4: Run JVM and host builds and confirm GREEN**

Run: `bash tests/java.sh && bash tools/build-dex.sh packages/wireless-bridge kr.gen5w.wireless.WirelessBridge bridge.dex && bash tools/build-wireless-host.sh`

Expected: Java tests pass, bridge DEX builds, and APK signature verification succeeds.

- [ ] **Step 5: Commit the Wi-Fi observer task**

```bash
git add packages/wireless-bridge/src/kr/gen5w/wireless/ProjectionWifiAccess.java packages/wireless-bridge/test/ProjectionWifiAccessTest.java packages/wireless-bridge/host/AndroidManifest.xml tests/java.sh tools/build-dex.sh
git commit -m "feat: observe OEM projection wifi readiness"
```

### Task 4: Integrate generation-safe bootstrap, Wi-Fi events, and diagnostics

**Files:**
- Modify: `packages/wireless-bridge/src/kr/gen5w/wireless/WirelessBridge.java`
- Modify: `tests/stock-projection-source.sh`
- Modify: `tests/bridge.sh`

**Interfaces:**
- Consumes: Task 1 controller commands, Task 2 OEM operations, Task 3 credential/AP observations, Bluetooth candidate events, and `android.net.wifi.WIFI_AP_STATE_CHANGED`.
- Produces: stable privacy-safe events for platform, profile, bootstrap, Wi-Fi, request, and result; numeric drive-log codes only.

- [ ] **Step 1: Add failing source and package assertions**

Assert the bridge registers `WIFI_AP_STATE_CHANGED`; bootstrap and request dispatch both pass through the final generation/cable/foreign-owner gate; diagnostics include both platform codes and Wi-Fi boundary codes. Extend the forbidden scan across all `kr/gen5w/wireless/*.java` for direct RFCOMM, iAP2 transport, Android Auto transport, AP mutation, hostapd, credential field logging, and raw address logging.

- [ ] **Step 2: Run focused checks and confirm RED**

Run: `bash tests/stock-projection-source.sh && bash tests/bridge.sh`

Expected: failure for missing Wi-Fi registration/bootstrap wiring and new stable codes.

- [ ] **Step 3: Integrate the adapters into `WirelessBridge`**

Keep all OEM calls on the executor and all session callbacks on the main handler. Cache only the last AP-state enum, never credentials or identifiers. Send bootstrap and connect broadcasts through `dispatchIfRequestAllowed`-equivalent generation gates; introduce a separate controller gate if Task 1 distinguishes bootstrap from connect. Do not let an AP-ready event report projection success.

- [ ] **Step 4: Run focused checks and confirm GREEN**

Run: `bash tests/java.sh && bash tests/stock-projection-source.sh && bash tests/bridge.sh && bash tools/build-wireless-host.sh`

Expected: all commands pass; dexdump contains only `Lkr/gen5w/...` application classes.

- [ ] **Step 5: Commit the integration task**

```bash
git add packages/wireless-bridge/src/kr/gen5w/wireless/WirelessBridge.java tests/stock-projection-source.sh tests/bridge.sh
git commit -m "feat: coordinate OEM projection bootstrap and wifi"
```

### Task 5: Release metadata, full regression, and evidence record

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `docs/bt-wireless-start.md`
- Modify: all tracked `NEMESIS.data` files whose `package-version` must match the changelog release
- Test: `.github/workflows/ci.yml` commands, locally

**Interfaces:**
- Consumes: completed Tasks 1-4.
- Produces: version `0.3.35` source metadata and build artifacts whose package versions match the changelog.

- [ ] **Step 1: Update user-facing evidence boundaries**

Document that first registration now requests the OEM SPP path, supports CarPlay and Android Auto profiles, and observes projection Wi-Fi separately from the normal hotspot. State that vehicle connection remains unverified until acceptance logs prove it.

- [ ] **Step 2: Bump release metadata to `0.3.35`**

Change every shipped package's `package-version` required by `tools/audit-artifacts.py` and prepend the changelog entry. Do not create a GitHub release or copy to a vehicle USB in this task.

- [ ] **Step 3: Commit source and metadata before the clean build**

```bash
git add CHANGELOG.md docs/bt-wireless-start.md probe/package/NEMESIS.data packages/*/NEMESIS.data tools/usb-wifi/package/NEMESIS.data
git commit -m "chore: prepare v0.3.35 wireless projection build"
```

- [ ] **Step 4: Run the full clean verification once**

Run: `bash tests/run.sh && bash tools/build-all.sh && python tools/audit-artifacts.py dist`

Expected: all shell and JVM suites pass, all standard/dongle/safe/check bundles build from a clean commit, and artifact audit reports success.

- [ ] **Step 5: Inspect final evidence and repository state**

Run: `git status --short && git log --oneline -6 && git diff HEAD~5..HEAD --stat`

Expected: no tracked or untracked source changes other than ignored build output; commits are task-scoped; no boot-critical files or OEM app recipes changed.

- [ ] **Step 6: Record verified scope**

Create the required KnowledgeHub session note and update the project brief with commit IDs and exact test/build results. Keep `last_verified` unchanged because this task does not verify a vehicle.
