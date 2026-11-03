# Stock-first Wireless CarPlay Design

## Purpose

Make the Gen5W wireless CarPlay bridge follow the V039 phone-projection orchestration before attempting its private RFCOMM transport. The change must retain a bounded direct fallback for units where the stock feature gate rejects wireless CarPlay, while preventing the stock and direct paths from owning a connection at the same time.

This design improves correctness and diagnosis without claiming vehicle success before a real connection or HCI trace verifies it.

## Confirmed problem boundary

The v0.3.25 vehicle report failed twice in `BluetoothSocket.connect()` for the advertised CAFE service. It never reached AP setup, native iAP2 authentication, or DiPO startup. v0.3.25 also trusted a non-null cached UUID list without starting a fresh SDP query. The current code fixes that cache defect, but still opens RFCOMM directly and does not reproduce the V039 `PhoneProjection`/`PPManager` preparation flow.

The V039 flow obtains the `phoneprojection` system service, tracks wireless phone-projection and OOB state, and calls `PPManager.requestConnectSPP(address)`. The request is then handled by the OEM projection and Bluetooth services. The direct bridge instead calls `BluetoothDevice.createRfcommSocketToServiceRecord(UUID)` itself.

## Goals

- Request the OEM stock SPP/WPP path first for each freshly connected, bonded iPhone candidate.
- Allow direct RFCOMM only after stock progress is absent for a bounded interval.
- Continue to require a fresh SDP result before direct fallback.
- Guarantee single ownership: stock observation and direct transport must never start native iAP2 concurrently.
- Cancel both paths immediately for wired CarPlay, another projection session, ACL loss, Bluetooth shutdown, or system power-on.
- Log privacy-safe path and state transitions so a single later report distinguishes stock gate rejection, stock timeout, SDP failure, RFCOMM failure, and native iAP2 failure.
- Preserve the existing CAFE/CAFF alternate-service retry and backoff policy for the direct path.

## Non-goals

- Modifying OEM `PhoneProjection`, Bluetooth, DiPO, framework, or system-server binaries.
- Faking `isCPAutoConnectionAvailableDevice()` or changing the user's projection settings.
- Running stock and direct sockets in parallel.
- Claiming successful CarPlay without a vehicle test.
- Logging a Bluetooth address, phone name, serial number, SSID, password, or exception message.

## Considered approaches

### Stock-only

This most closely follows V039, but existing evidence shows the OEM gate can return `bIsPossibleWCP=false`. A stock-only design could therefore stop before any transport attempt on a unit whose Korean feature configuration disables the stock path.

### Direct-only with more retries

This preserves the current architecture, but cannot fix a remote service that is not listening because the OEM OOB/WPP preparation was skipped. More retries would repeat an unprepared connection and obscure the cause.

### Stock-first with bounded direct fallback

This is the selected design. It gives the iPhone and OEM services the expected preparation opportunity, yet retains the custom bridge when only the OEM feature gate is blocking progress. Mutual exclusion and explicit progress signals keep it from becoming two competing connection attempts.

## Architecture

### `StockWppAttempt`

Add a pure-Java state machine with no Android dependencies. It owns only the decision of whether the direct fallback is permitted.

States:

- `IDLE`: no candidate is owned.
- `STOCK_WAIT`: the stock request was issued and the fallback deadline is running.
- `STOCK_PROGRESS`: an OEM or native progress signal was observed; direct fallback is prohibited.
- `DIRECT_ALLOWED`: the deadline expired without progress, or the stock service/request was unavailable; fresh SDP may feed the direct path.
- `COMPLETE`: stock or direct CarPlay authentication succeeded.

The state machine uses a generation token. Late broadcasts or callbacks from an older attempt cannot change the current attempt. It never stores an address in diagnostic output.

The stock wait is 12 seconds. This interval is long enough for the OEM request/broadcast chain to run but remains within the existing 60-second socket phase. An unavailable `phoneprojection` service or a reflection failure permits direct fallback immediately; a returned `isCPAutoConnectionAvailableDevice=false` is recorded but does not bypass the stock request by itself because the stock service may still perform required preparation.

### `StockProjectionAdapter`

Add an Android-facing adapter used only by `WirelessBridge`. It obtains `context.getSystemService("phoneprojection")` and invokes OEM methods reflectively so the APK does not package or link private framework classes.

For a bonded ACL-connected candidate it will:

1. Query `isCPAutoConnectionAvailableDevice(String)` and `isCarPlaySupportOOB()` when those methods exist.
2. Call `requestConnectSPP(String)` exactly once for the generation.
3. Return a privacy-safe result containing method availability, gate value, OOB value, and whether the request invocation completed.
4. Call `requestDisconnectSPP(String)` only when cancelling a stock request that has not handed ownership to an already-active OEM/native session.

Reflection errors are reduced to stable categories such as `service-unavailable`, `method-unavailable`, `security`, and `invocation`; exception text is never logged.

### Progress observation

`WirelessBridge` observes the existing Bluetooth/profile events plus the stock broadcasts already present in V039:

- `android.bluetooth.device.action.START_SPP_CONNECT_FOR_CONNECTIVITY`
- `android.hardware.bt.action.IAP2_BT_DEVICE_ATTACHED_FOR_CARPLAY`
- `android.hardware.bt.action.CARPLAY_CLIENT_DEVICE_ATTACHED`
- `android.intent.action.telechips.carplay.over.wireless.connected`

It also polls the already-bound iAP2 service's `Iap2SvcIsIap2Connected()` and the existing projection-port check. Any matching progress signal for the current candidate moves `STOCK_WAIT` to `STOCK_PROGRESS` and cancels the fallback timer. Signals without a safely matchable device are accepted only while exactly one generation is in `STOCK_WAIT` and no wired/foreign session exists.

An ordinary A2DP/HFP connection is not stock CarPlay progress. ACL/profile connectivity merely identifies the candidate.

### Direct fallback

Direct fallback begins only when all of the following are true:

- `StockWppAttempt` is `DIRECT_ALLOWED` for the current generation.
- There is no wired CarPlay signal.
- There is no existing native iAP2 or projection-port session.
- The candidate is still ACL-connected and bonded.
- A new `ACTION_UUID` result for the current ACL session advertises CAFE or CAFF.

The fallback then uses the existing secure `createRfcommSocketToServiceRecord()` behavior. The security mode is not changed without an HCI trace or a known-good V039 socket implementation showing that insecure RFCOMM is required. If both CAFF and CAFE are freshly advertised, the existing alternate-service retry remains in force.

### Ownership and cancellation

One generation owns the candidate, stock attempt, fallback decision, RFCOMM socket, hotspot work, and native iAP2 listener. A transition to wired/foreign projection, ACL loss, Bluetooth off, or system power-on invalidates the generation before resources are closed. Late workers may close their own resources but cannot publish them into the new generation.

If stock progress is observed, the bridge does not call its private native `receiveConnect(1)` path. The OEM stack remains the owner. If direct fallback begins, the bridge first asks the adapter to withdraw only its pending stock request, then owns RFCOMM, AP, and native iAP2 as it does today.

## State and data flow

1. ACL/profile connection identifies a bonded candidate.
2. The bridge starts a new stock attempt and requests fresh SDP in parallel, but does not consume cached UUIDs.
3. `StockProjectionAdapter` records the stock gate/OOB snapshot and requests OEM SPP.
4. Stock progress before 12 seconds suppresses direct fallback and is observed until authentication or cancellation.
5. No progress by 12 seconds moves the attempt to `DIRECT_ALLOWED`.
6. If fresh SDP is already ready, direct RFCOMM starts immediately; otherwise it waits for `ACTION_UUID` within the existing SDP timeout policy.
7. Direct RFCOMM success continues to AP setup and private native iAP2. Authentication marks the generation complete.
8. Any failure closes only resources owned by that generation and enters the existing bounded backoff.

## Diagnostics

Every attempt logs a stable, address-free sequence:

- `path=stock event=request gate={true|false|unknown} oob={true|false|unknown}`
- `path=stock event=progress source={spp|iap2-attached|wireless-connected|native|projection-port}`
- `path=stock event=fallback reason={timeout|service-unavailable|request-unavailable}`
- `path=direct event=sdp caff={true|false} cafe={true|false} selected={caff|cafe|none}`
- Existing stage-specific transport failures, prefixed with `path=direct`.
- `path={stock|direct} event=cancel reason={wired|foreign|acl-lost|bluetooth-off|power-on}`

No raw Intent dump or exception message may be logged.

## Testing

### Pure JVM tests

- A stock request starts in `STOCK_WAIT` and does not permit direct fallback before 12 seconds.
- Stock progress suppresses fallback permanently for the generation.
- Timeout permits direct fallback exactly once.
- An unavailable stock service permits immediate fallback.
- A late progress event from an invalidated generation is ignored.
- Wired/foreign/candidate-loss cancellation prevents fallback.
- A2DP/HFP events do not count as stock CarPlay progress.
- Direct fallback still requires a fresh SDP result and alternates CAFF/CAFE only when both were advertised.
- Authentication completes the generation and rejects late workers.

### Build and package checks

- Compile the Android bridge against the existing public Android SDK without a private `PPManager` stub.
- Run the complete JVM harness, shell/package tests, and repository test runner.
- Inspect the APK/DEX to ensure private OEM types are referenced only by reflection strings and that no raw identifier logging was introduced.

### Vehicle acceptance criteria

The implementation is not declared solved until a vehicle report shows one of these complete paths:

- Stock: request → stock progress → native/projection active.
- Direct: stock timeout/unavailable → fresh SDP → RFCOMM connected → AP setup → native iAP2 authenticated → projection active.

The same report must contain no overlapping stock and direct ownership for one generation. A failure report must identify the last path/state without exposing phone identifiers.

## Rollback

The change remains inside the replaceable wireless-bridge package. Existing package removal restores the previous system state; no OEM APK/ODEX or framework file is modified. If stock-first behavior causes a regression, the package can revert to the previous bridge revision or be removed using the existing recovery workflow.
