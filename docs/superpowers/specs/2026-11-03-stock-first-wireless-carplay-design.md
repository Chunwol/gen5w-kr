# Stock-Only Wireless CarPlay Design

## Purpose

Make the wireless CarPlay bridge request the V039 OEM PhoneProjection path and leave connection ownership to the OEM stack. The bridge must not start a parallel private RFCOMM/iAP2 transport when the OEM request is unavailable, rejected, or not observed. This favors a single owner and safe failure over automatic fallback.

This is a design change from the earlier stock-first design with a timed direct fallback. The user approved proceeding with the stock-only direction after review of the fallback race risk.

## Confirmed problem boundary

The v0.3.25 vehicle report failed in `BluetoothSocket.connect()` for the advertised CAFE service before AP setup, native iAP2 authentication, or DiPO startup. v0.3.25 also trusted a non-null cached UUID list without starting a fresh SDP query; v0.3.26 fixes that cache defect. The current bridge still opens RFCOMM directly and bypasses the V039 `PhoneProjection`/`PPManager` preparation flow.

The V039 framework dump contains the `phoneprojection` service mapping and `PPManager` wrappers for `isCPAutoConnectionAvailableDevice(String)`, `isCarPlaySupportOOB()`, `requestConnectSPP(String)`, and `requestDisconnectSPP(String)`. Their availability in the dump does not prove this app can invoke them at runtime; permission and Binder behavior must be diagnosed on the vehicle.

The current bridge package also applies authored patches to `/system/app/Iap2ServerApp.odex` and `/system/app/HKMC_DiPO.odex`, and may patch `/system/app/HKMC_GPM.odex`. Those existing package effects must be audited and kept separate from the new stock request path. The new path must not require changing `PhoneProjection`, Bluetooth, framework, LK, or other OEM source/binaries.

## Goals

- Request OEM PhoneProjection SPP/WPP preparation for an eligible bonded CarPlay device.
- Never initiate the project's direct RFCOMM, custom native iAP2, or custom AP-setup path for that generation.
- Report request invocation, gate/OOB observations, OEM progress, and failure categories without logging device identifiers.
- Cancel stale attempts on candidate loss, wired/foreign projection, Bluetooth shutdown, or service shutdown.
- Keep the change reversible through the existing package lifecycle and do not deploy it to the vehicle in this task.

## Non-goals

- Automatically falling back to direct RFCOMM after a timeout, gate denial, service absence, or reflection failure.
- Faking OEM feature gates or changing projection settings.
- Modifying OEM PhoneProjection, Bluetooth, framework, DiPO, iAP2, GPM, or other system binaries as a prerequisite for calling the existing API.
- Claiming wireless CarPlay works without a complete vehicle result.

## Architecture

### `StockProjectionAdapter`

Add an app-side adapter used by `WirelessBridge`. It obtains `context.getSystemService("phoneprojection")` and invokes the V039 `PPManager` wrappers reflectively, so the APK does not link private framework classes.

For each candidate generation it:

1. Reads `isCPAutoConnectionAvailableDevice(address)` and `isCarPlaySupportOOB()` when available.
2. Calls `requestConnectSPP(address)` at most once for that generation when the OEM service and method are available. A normal return means only that invocation returned; it is not evidence that the OEM accepted or completed the connection.
3. Maps exceptions to stable categories (`service-unavailable`, `method-unavailable`, `security`, `invocation`) without logging exception text or addresses.
4. Calls `requestDisconnectSPP(address)` only if the bridge can prove it owns an outstanding request and cancellation cannot affect an OEM-owned active session. If that ownership cannot be established, it invalidates its local generation and does not call OEM disconnect.

An OEM gate value of `false` is reported as a blocked/unsupported stock attempt. It never authorizes a direct transport attempt.

### Stock-only ownership

Remove the direct-transport start from the wireless bridge flow: no `createRfcommSocketToServiceRecord`, custom `Iap2SvcInit`/`receiveConnect`, or custom hotspot AP setup is started by the CarPlay connection attempt. The bridge may observe OEM state only through signals whose V039 source and app-level delivery are verified. Broadcast strings found in a dump are not sufficient proof that a broadcast is sent, externally receivable, or safely device-matchable.

Until reliable OEM progress/completion signals are verified, diagnostics distinguish `request-invoked` from `projection-active`; they must not report a successful connection based only on method return, A2DP/HFP, a running process, or an iAP2 marker of unknown ownership.

One generation token owns the candidate and all local observation/callback state. Wired/foreign projection, ACL loss, Bluetooth off, or shutdown invalidates it before cleanup. Late callbacks from old generations are ignored.

### Existing system ODEX patches

The new stock request path itself must not require system ODEX replacement. Before changing package installation behavior, trace the existing `Iap2ServerApp`, DiPO, and GPM patches and classify each as required by an independent retained feature or by the old direct-transport path. Do not silently remove an existing user-facing feature. The stock-only connection package must not apply an ODEX patch solely to enable the removed direct RFCOMM path.

## Diagnostics

Log a stable, address-free sequence:

- `path=stock event=service result={available|unavailable}`
- `path=stock event=state gate={true|false|unknown} oob={true|false|unknown}`
- `path=stock event=request result={invoked|blocked|method-unavailable|security|invocation}`
- `path=stock event=progress source={verified-source}` only for a source verified in V039 and delivered to this app
- `path=stock event=result={projection-active|timeout|cancelled|unavailable}`
- `path=stock event=cancel reason={wired|foreign|acl-lost|bluetooth-off|shutdown}`

Do not log MAC/Bluetooth addresses, phone names, serial numbers, SSID, passwords, raw Intent data, UUID lists, or exception messages.

## Testing

### Pure JVM tests

- One stock request is made at most once per generation.
- Gate false, service unavailable, method unavailable, security exception, and invocation exception never call direct transport.
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

- PPManager service/method access outcome and gate/OOB values.
- OEM request progress and final projection state, or a clear fail-closed result.
- No private direct RFCOMM or custom native-iAP2 start was attempted.
- No overlapping connection owner and no phone identifiers in diagnostics.

Vehicle acceptance is separate from compile, unit, and package verification. This task does not install or publish the change.

## Rollback

The app-side change is delivered through the replaceable wireless bridge package and must use its existing backup/restore lifecycle. Any existing OEM ODEX modifications remain a separate package effect: removal must restore the recorded original bytes. No additional OEM source or binary replacement is part of the stock-only request path.
