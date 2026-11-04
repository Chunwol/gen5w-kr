# OEM Wireless CarPlay and Android Auto Bootstrap Design

## Status

Approved in chat on 2026-11-04. This design supersedes the connection scope of `2026-11-03-stock-first-wireless-carplay-design.md`: the earlier design handled only an already-saved CarPlay profile, while this design covers first registration and both CarPlay and Android Auto. The stock-only ownership and boot-safety constraints remain unchanged.

## Purpose

Make wireless CarPlay and wireless Android Auto reach the V039 OEM PhoneProjection registration and connection paths from a bonded, currently connected phone. A missing `WLDeviceInfo` profile is a bootstrap state, not a permanent block. The bridge must still leave SPP, WPP/OOB, projection Wi-Fi credentials, AP startup, iAP2, and Android Auto transport ownership to the OEM stack.

## Confirmed V039 paths

- `PhoneProjectionReceiver` enables wireless service initialization when either `com.hkmc.software.connectivity.carplay_wireless`, `com.hkmc.software.connectivity.androidauto_wireless`, or `ro.product.opt.useppwireless` is enabled. The existing wireless-enable package supplies both feature declarations and requires a reboot.
- `WirelessPhoneProjectionService` dynamically receives `android.bluetooth.device.action.START_SPP_CONNECT_FOR_CONNECTIVITY` with the `ADDRESS` extra. Its receiver records the Bluetooth candidate used by the OEM auto-connection path.
- `PPManager.requestConnectSPP(String)` forwards the address to the registered OEM `IWLDeviceListener`. The real V039 listener checks the connected Bluetooth device and invokes the OEM SPP helper; the no-op proxy class in the dump is not the service listener.
- The OEM service exposes `requestWLDeviceInfoAdd`, `requestWLDeviceInfoUpdate`, and status callbacks. Profile creation remains an OEM result of pairing; this project does not construct or insert `WLDeviceInfo` itself.
- `SEND_CONNECTION_PHONEPROJECTION` with `deviceAddress` is the OEM UI connection action for an existing profile. Its receiver accepts both CarPlay and Android Auto profile types and routes them to `PPManager.connectPP(...)`.
- The OEM `connectPP` route supports type `1` for CarPlay and type `2` for Android Auto. Connected addresses are exposed separately as `getCPConnectedBTAddress()` and `getAAConnectedBTAddress()`.
- Projection Wi-Fi uses `WifiConfiguration.ConnectivitySSID` and `ConnectivityPSK`, separate from the user-visible hotspot `SSID` and `preSharedKey`. PhoneProjection starts that AP through `WifiManager.setWifiApEnabledForConnectivity(...)`.

These source paths establish the intended calls and state boundaries. They do not prove that a particular phone accepts pairing or that a vehicle radio completes AP startup; those remain vehicle acceptance items.

## Goals

- Bootstrap the OEM first-registration path when a bonded, linked phone has no saved wireless projection profile.
- Reconnect an existing enabled profile through the OEM UI action.
- Support profile type `1` CarPlay and type `2` Android Auto without guessing the platform before the OEM profile identifies it.
- Verify code-visible Wi-Fi prerequisites and progress without reading, changing, or logging SSID or password values.
- Keep one candidate generation and one OEM connection owner.
- Preserve wired CarPlay and wired Android Auto.
- Avoid boot-critical files and retain exact package rollback.

## Non-goals

- Creating `WLDeviceInfo` with guessed serial numbers, device names, user types, SSIDs, or passwords.
- Copying normal hotspot credentials into projection connectivity credentials.
- Direct RFCOMM sockets, a private iAP2 transport, custom Android Auto transport, or custom SoftAP ownership.
- Bypassing phone-side confirmation required by CarPlay or Android Auto pairing.
- Reporting a successful connection from a sent broadcast, Bluetooth audio, an enabled AP, or a running process alone.
- Modifying PhoneProjection, Bluetooth, framework, `services.odex`, `SystemUI.odex`, boot/recovery, LK, kernel, or MICOM.

## Architecture

### 1. Platform-neutral candidate

`WirelessBridge` continues to select a bonded Bluetooth device that is currently linked by ACL/HFP evidence. Until the OEM profile exists, the candidate platform is `UNKNOWN`. The bridge must not infer iPhone versus Android from the name, vendor ID, UUID cache, or previous session.

One generation token owns the candidate. ACL loss, Bluetooth off, a wired projection cable, another active OEM projection address, service shutdown, or a changed candidate invalidates the generation and suppresses late callbacks.

### 2. OEM bootstrap for a missing profile

When `getWLDeviceInfo(address, "", userType)` returns null:

1. Recheck under the generation lock that the candidate is still current and no wired or foreign projection owns the system.
2. Send the package-scoped OEM Bluetooth action `android.bluetooth.device.action.START_SPP_CONNECT_FOR_CONNECTIVITY` with only the `ADDRESS` extra.
3. Call `PPManager.requestConnectSPP(address)` through reflection once for that generation.
4. Poll `getWLDeviceInfo` and OEM connection state with bounded intervals.
5. If a valid profile appears, transition to the existing-profile flow. If it does not appear before the bootstrap deadline, stop with `profile-bootstrap-timeout` and wait for a new Bluetooth generation.

The bootstrap action and PPManager request are preparation requests. Neither counts as registration or connection success. Repeated polling must not send duplicate bootstrap requests.

### 3. Existing-profile connection

Accept only a profile whose stored address matches the current candidate, whose type is CarPlay (`1`) or Android Auto (`2`), and whose wireless setting is enabled. Respect an explicit auto-connect-off setting for automatic reconnection. A profile created during the current bootstrap may proceed when the OEM reports it enabled and ready; the bridge never changes those flags.

Immediately before dispatch, revalidate the generation and cable/ownership guards. Send `com.daudio.app.PhoneProjection.Wireless.SEND_CONNECTION_PHONEPROJECTION`, scoped to `com.daudio.app.phoneprojection`, with only `deviceAddress`.

### 4. Per-platform observation

- CarPlay (`type=1`): match `getCPConnectedBTAddress()` and the OEM wireless connection state.
- Android Auto (`type=2`): match `getAAConnectedBTAddress()` and the OEM wireless connection state.
- Unknown or unsupported profile types fail closed.
- A connecting state for the current address is observed without issuing a second request.
- Only the OEM connected state for the matching per-platform address becomes `projection-active`.

### 5. Projection Wi-Fi readiness

The bridge observes Wi-Fi without becoming the AP owner:

- Feature readiness: both configured wireless feature declarations are checked at package/install time; runtime reports which platform feature is present.
- Credential readiness: reflect the current AP configuration and record only whether `ConnectivitySSID` and `ConnectivityPSK` are non-empty. Never record their values, lengths, hashes, or equality with normal hotspot credentials.
- AP progress: observe `WIFI_AP_STATE_CHANGED` and OEM PhoneProjection state. AP enabled is `wifi-ap-ready`, not projection success.
- OEM ownership: the bridge never calls `setWifiApEnabled`, `setWifiApEnabledForConnectivity`, writes `WifiConfiguration`, or invokes hostapd directly.
- A normal hotspot error or BlueLink subscription state does not substitute for projection connectivity state, because the two credential pairs and entry points are separate.

If connectivity credentials are absent before bootstrap, that is an expected pre-registration state. If they remain absent after an OEM profile is created and the OEM connection request is accepted, report `wifi-credentials-unavailable` and stop retrying for that generation. If the AP never reaches an enabled state before the connection deadline, report `wifi-ap-timeout`.

### 6. Session phases

The pure Java controller uses these observable phases:

`IDLE -> INSPECTING -> BOOTSTRAP_REQUESTED -> WAITING_PROFILE -> CONNECT_REQUESTED -> WAITING_WIFI -> ACTIVE`

Terminal phases are `BLOCKED`, `FAILED`, and `CANCELLED`. Each transition is generation-checked. Deadlines are separate for profile bootstrap, AP readiness, and final projection connection so diagnostics identify the actual boundary.

### 7. Diagnostics and privacy

Stable events include:

- `platform={unknown|carplay|android-auto}`
- `profile={missing|ready|disabled|auto-connect-disabled|mismatch|unsupported}`
- `bootstrap={requested|profile-created|timeout|security|invocation}`
- `wifi={credentials-missing|credentials-ready|ap-enabling|ap-ready|ap-timeout}`
- `request={oem-action-sent|cancelled|security|invocation}`
- `result={projection-active|timeout|unavailable|cancelled}`

Do not log Bluetooth addresses, phone names, serial numbers, SSIDs, passwords, credential lengths or hashes, UUIDs, raw Intent contents, or exception messages. Numeric drive-log events use enumerated platform, phase, and result codes only.

## Failure handling

- Missing PhoneProjection service or reflection method: fail closed; do not start a private transport.
- Missing profile: one bootstrap attempt per generation, followed by bounded observation.
- Security or invocation failure: record a stable category and stop that generation.
- Profile disabled or auto-connect disabled: respect the OEM/user setting.
- Wi-Fi credentials or AP unavailable after OEM preparation: stop at the Wi-Fi-specific boundary.
- Wired connection or another projection owner: cancel before any new OEM request.
- Service restart: do not persist a pending generation; inspect current OEM state again.

## Package and boot safety

The connection controller is delivered in the replaceable `wireless-host.apk` and its NEMESIS service script. No new ODEX patch is required for registration or Wi-Fi startup. Existing iAP2/DiPO/GPM recipes remain separate retained features for CarPlay capabilities, steering-wheel call handling, and HUD behavior. Their hash gates, verified backups, Dalvik handling, boot guard, uninstall, and rollback behavior must remain unchanged.

## Testing

### Pure JVM tests

- Missing profile sends exactly one bootstrap action and one `requestConnectSPP` per generation.
- A bootstrap return does not create synthetic success.
- Profile appearance advances once to the connection request.
- CarPlay and Android Auto profiles select their respective connected-address getters.
- Unsupported, mismatched, disabled, and auto-connect-off profiles never dispatch.
- Wi-Fi credential booleans and AP transitions produce correct phases without exposing values.
- Bootstrap, AP, and final connection timeouts remain distinct.
- Candidate loss, wired/foreign ownership, Bluetooth off, shutdown, and stale callbacks cancel safely.
- No source path calls direct RFCOMM, custom iAP2, custom Android Auto transport, or AP mutation APIs.

### Build and package checks

- Compile against Android API 18/19 with reflection-only OEM APIs.
- Build the host APK and bridge DEX.
- Audit the APK/DEX and scripts for forbidden transport/AP calls and sensitive log strings.
- Run focused JVM tests, bridge/package lifecycle tests, integrated build, and artifact audit.
- Verify install/update/remove and rollback preserve exact original app-level ODEX bytes.

### Vehicle acceptance

Code completion is not vehicle completion. A vehicle report must separately prove:

- CarPlay first registration, reconnect, projection AP readiness, and active projection.
- Android Auto first registration, reconnect, projection AP readiness, and active projection.
- Wired CarPlay and Android Auto still work.
- Normal hotspot and projection connectivity remain distinct.
- Bluetooth audio and calls remain usable before, during, and after projection.
- No repeated bridge restart, overlapping owner, sensitive diagnostic data, or boot failure.

## Rollback

Removing the bridge stops and uninstalls `wireless-host.apk`, clears only its own non-sensitive state, and restores verified originals for any independently retained app-level recipes through the existing transaction. It does not delete OEM wireless profiles or rewrite OEM Wi-Fi credentials.
