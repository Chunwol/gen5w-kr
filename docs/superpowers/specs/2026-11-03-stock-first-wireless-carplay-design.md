# Stock-Only Wireless CarPlay Design

## Purpose

Make the wireless CarPlay bridge request the V039 OEM PhoneProjection path and leave connection ownership to the OEM stack. The bridge must not start a parallel private RFCOMM/iAP2 transport when the OEM request is unavailable, rejected, or not observed. This favors a single owner and safe failure over automatic fallback.

This is a design change from the earlier stock-first design with a timed direct fallback. The user approved proceeding with the stock-only direction after review of the fallback race risk.

## Confirmed problem boundary

The v0.3.25 vehicle report failed in `BluetoothSocket.connect()` for the advertised CAFE service before AP setup, native iAP2 authentication, or DiPO startup. v0.3.25 also trusted a non-null cached UUID list without starting a fresh SDP query; v0.3.26 fixed that cache defect, but the direct transport remained unsuitable. The new bridge removes that transport and asks V039 PhoneProjection to use its own saved profile.

The V039 framework dump contains the `phoneprojection` service mapping and `PPManager` wrappers for `isCPAutoConnectionAvailableDevice(String)`, `isCarPlaySupportOOB()`, `requestConnectSPP(String)`, and `requestDisconnectSPP(String)`. Their availability in the dump does not prove this app can invoke them at runtime; permission and Binder behavior must be diagnosed on the vehicle.

### Captured V039 request-path findings

The `PPManager.requestConnectSPP(String)` route is not a usable entry point in the captured V039 build: the registered `isCPAutoConnectionAvailableDevice(String)` listener returns `false`, and its callback does not establish an SPP socket in the inspected bytecode. The bridge does not call it.

A separate OEM UI path is present and is now used. `WirelessAlertDialogActivity` sends `com.daudio.app.PhoneProjection.Wireless.SEND_CONNECTION_PHONEPROJECTION` with the `deviceAddress` extra. `WirelessPhoneProjectionService.onCreate()` registers a dynamic receiver for that exact action, and its receiver looks up the active user's `WLDeviceInfo` and routes a matching wireless profile through the OEM connectivity or hotspot handler. That handler uses the saved profile and calls the OEM `PPManager.connectPP(...)` path. The bridge sends the same action only to the PhoneProjection package and only after confirming the connected address matches a saved CarPlay profile whose wireless and auto-connect settings are already enabled. It never changes those settings or the saved Wi-Fi name/key.

This establishes a source-backed OEM request route, not proof of runtime acceptance: the receiver is dynamic, so its service must be registered when the request arrives; reflection and broadcast delivery must work on the installed V039 image; and the profile's saved Wi-Fi credentials must match the phone. Those points remain for vehicle validation. The old `requestConnectSPP` route stays unused.

The captured V039 `PhoneProjectionReceiver` listens for `BOOT_COMPLETED`. Its boot path checks the product step and the OEM wireless-support gate before entering the wireless-service initialization path. The captured system image reports `ro.product.opt.stepofspec=90`, satisfying the Korean step threshold. `isSupportWireless()` returns true when the Android Auto wireless feature, CarPlay wireless feature, or `ro.product.opt.useppwireless` property enables the route. The integrated `wireless-enable` module installs the two wireless feature XML entries and reboots, which is the source-backed prerequisite for the OEM service to register its dynamic request receiver. The bridge itself neither starts that private service nor changes feature flags at runtime. This narrows the startup uncertainty but does not prove that the receiver is live or consumes the request on a vehicle.

The V039 Wi-Fi framework keeps the regular hotspot credentials and phone-projection connectivity credentials in separate `WifiConfiguration` fields: `SSID`/`preSharedKey` and `ConnectivitySSID`/`ConnectivityPSK`. `WifiApConfigStore.setDefaultApConfiguration()` initializes both pairs independently, persists both pairs, and `renewPasskey()` regenerates the connectivity pair. The PhoneProjection helper calls `WifiManager.setWifiApEnabledForConnectivity()` for its AP start/stop path. Thus the user-visible hotspot name is not evidence of the connectivity SSID used by projection.

The stock-only bridge does not read or write either credential pair. It does not itself correct a previous Wi-Fi name/credential mismatch, and it must not copy the user-visible hotspot values into the connectivity fields. The captured source establishes the separate fields and OEM AP entry point, but does not prove which credentials the connected iPhone currently has or that the live OEM stack delivers them successfully. Confirm that only in an actual vehicle connection test.

The package restores `/system/app/Iap2ServerApp.odex` to its verified original when upgrading from the older custom bridge. Its `/system/app/HKMC_DiPO.odex` recipe changes only the independent missing-call-state fallback in `DipoService.i(II)V`; the OEM wireless receiver and its actions remain byte-identical. The package also may patch `/system/app/HKMC_GPM.odex` for Android Auto HUD. These app-level ODEX edits are not part of the OEM connection request. They remain hash-gated and reversible, but still require vehicle validation. Previously shipped V035/V039 DiPO recipes are recognized during update and removal. No boot-critical ODEX, framework, LK, kernel, PhoneProjection, or Bluetooth binary is changed.

## Goals

- Request OEM PhoneProjection SPP/WPP preparation for an eligible bonded CarPlay device.
- Never initiate the project's direct RFCOMM, custom native iAP2, or custom AP-setup path for that generation.
- Report OEM action submission, OEM-connected state, and failure categories without logging device identifiers.
- Cancel stale attempts on candidate loss, wired/foreign projection, Bluetooth shutdown, or service shutdown.
- Keep the change reversible through the existing package lifecycle and do not deploy it to the vehicle in this task.

## Non-goals

- Automatically falling back to direct RFCOMM after a timeout, gate denial, service absence, or reflection failure.
- Faking OEM feature gates or changing projection settings.
- Modifying OEM PhoneProjection, Bluetooth, framework, DiPO, iAP2, GPM, or other system binaries as a prerequisite for calling the existing API.
- Claiming wireless CarPlay works without a complete vehicle result.

## Architecture

### `PhoneProjectionAccess`

The app-side adapter uses reflection so the APK does not statically link private framework classes. It reads the current `UserProfileManager` user type and calls `PPManager.getWLDeviceInfo(address, "", userType)`. A request is allowed only when the result matches the connected address, has `TYPE_CARPLAY`, and both `getWLDOnOff()` and `getWLDAutoConnection()` are true. Missing, mismatched, disabled, or auto-connect-off profiles fail closed.

For each candidate generation the adapter:

1. Observes `getWirelessConnectState()` and `getCPConnectedBTAddress()`; only the V039 connected state for the same address counts as active. The same candidate's `CONNECTING` state is polled without sending a duplicate request; a different/unknown address, cancel state, or unknown state fails closed.
2. Immediately before sending, rechecks under the session lock that the same candidate generation still owns a pending request, the request has not timed out, and the bridge is not shutting down or wired. It then sends the OEM UI action `com.daudio.app.PhoneProjection.Wireless.SEND_CONNECTION_PHONEPROJECTION`, package-scoped to `com.daudio.app.phoneprojection`, with `deviceAddress`, at most once for that generation. This is the action sent by the captured OEM PhoneProjection UI and received by its dynamically registered service receiver.
3. Treats a successful `sendBroadcast` return as `oem-action-sent`, never as connection success. Only a later OEM connected-state observation is reported as active.
4. Maps exceptions to stable categories without logging exception text or device identifiers. A missing dynamic receiver is indistinguishable from an unconsumed broadcast until timeout and remains a vehicle-validation risk.

The adapter does not use `requestConnectSPP`, call OEM disconnect, toggle profile settings, or write Wi-Fi credentials. Cancellation invalidates local generations and does not tear down an OEM-owned session.

### Stock-only ownership

The wireless bridge has no `createRfcommSocketToServiceRecord`, custom `Iap2SvcInit`/`receiveConnect`, or custom hotspot AP setup. The OEM action is permitted because both its UI sender and dynamically registered receiver are present in the captured V039 bytecode; delivery and acceptance by the live service still require vehicle validation.

Diagnostics distinguish `oem-action-sent` from `projection-active`; they must not report a successful connection based only on broadcast submission, a remembered connected address without `PHONEPROJECTION_CONNECT_STATE_CONNECTED`, A2DP/HFP, a running process, or an iAP2 marker of unknown ownership.

One generation token owns the candidate and all local observation/callback state. Wired/foreign projection, ACL loss, Bluetooth off, or shutdown invalidates it before cleanup. Late callbacks from old generations are ignored.

### Existing system ODEX patches

The new stock request path itself must not require system ODEX replacement. Before changing package installation behavior, trace the existing `Iap2ServerApp`, DiPO, and GPM patches and classify each as required by an independent retained feature or by the old direct-transport path. Do not silently remove an existing user-facing feature. The stock-only connection package must not apply an ODEX patch solely to enable the removed direct RFCOMM path.

## Diagnostics

Log a stable, address-free sequence:

- `path=stock event=service result={available|unavailable}`
- `path=stock event=request result={oem-action-sent|profile-unavailable|profile-mismatch|profile-disabled|auto-connect-disabled|cancelled|security|invocation}`
- `path=stock event=progress source={phoneprojection-state}` only after the OEM reports the candidate as connected
- `path=stock event=progress result=connecting` while the same candidate is already in the OEM connecting state; this is observation only and does not start a second request
- `path=stock event=result={projection-active|timeout|cancelled|unavailable}`
- `path=stock event=cancel reason={wired|foreign|acl-lost|bluetooth-off|shutdown}`

Do not log MAC/Bluetooth addresses, phone names, serial numbers, SSID, passwords, raw Intent data, UUID lists, or exception messages.

## Testing

### Pure JVM tests

- One stock request is made at most once per generation.
- Missing/mismatched/non-CarPlay/disabled/auto-connect-off profile, stale/expired request, service unavailable, security exception, and invocation exception never send the OEM action or call direct transport.
- An eligible profile sends exactly the source-verified action, scoped to the OEM package, with only the connected address extra.
- A returned request invocation does not mark projection active.
- A verified stock progress/completion event is associated with the current generation; stale-generation events are ignored.
- Candidate loss, wired/foreign projection, Bluetooth off, and shutdown cancel local observation and prevent later callbacks from publishing success.
- A2DP/HFP, process presence, and unowned iAP2 state alone do not count as CarPlay success.
- Diagnostics never contain device identifiers or exception text.

### Build and package checks

- Compile the bridge against the current public Android SDK without private PPManager stubs.
- Run focused JVM tests and the existing bridge/package checks once; CI is the full-suite automation.
- Inspect built DEX/APK for reflective-only OEM type references and verify the stock-only path has no active direct RFCOMM or native-iAP2 start path.
- Audit package recipes and generated artifacts to verify exactly which ODEX files remain modified and why; package checks must match the documented scope.

### Vehicle acceptance

Do not declare solved until a vehicle report proves:

- Profile lookup and OEM action delivery outcome.
- OEM request progress and final projection state, or a clear fail-closed result.
- No private direct RFCOMM or custom native-iAP2 start was attempted.
- No overlapping connection owner and no phone identifiers in diagnostics.

Vehicle acceptance is separate from compile, unit, and package verification. This task does not install or publish the change.

## Rollback

The app-side change is delivered through the replaceable wireless bridge package and must use its existing backup/restore lifecycle. Any existing OEM ODEX modifications remain a separate package effect: removal must restore the recorded original bytes. No additional OEM source or binary replacement is part of the stock-only request path.
