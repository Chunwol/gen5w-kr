# V039 Bluetooth Relay Wireless CarPlay Integration Design

**Status:** source and private-package integration implemented; vehicle success is not yet claimed.

## Goal

Make wireless CarPlay complete on the exact Korean Kona V039 build after the stock first-registration path stops at `isPossibleWCP=false`. Keep wired CarPlay, Android Auto, Bluetooth audio/calls, the normal hotspot, and boot-critical files independent.

## Evidence boundary

The current v0.3.35 path already asks the stock PhoneProjection stack to create or use a wireless profile and observes projection Wi-Fi state. Vehicle logs prove that the stock stack reaches Broadcom SPP and then rejects the unregistered wireless profile before iAP2 starts. This makes more retries of the same OEM request insufficient.

Static analysis also proves that the existing `bt_patch.py` recipe only adds an iAP2 session entry for components 4 and 5. It does not carry SPP bytes into iAP2 and does not hand the later CarPlay channel back to DiPO. Shipping that recipe alone would therefore be incomplete.

The archived V039 candidate and the public HMG reference are behavior evidence only. New public code must be independently authored and the repository must not contain OEM APK/ODEX files, decrypted firmware, keys, credentials, or copied third-party implementation code.

## Chosen architecture

### 1. One connection owner

The existing `wirelesshost` remains the supervisor and diagnostics owner. It selects one bonded phone generation and starts one relay attempt. The old direct RFCOMM path stays disabled. The OEM bootstrap and the relay may not open competing SPP sessions.

### 2. Pure relay state machine

An Android-independent controller owns the phases:

`IDLE -> SPP_CONNECTING -> IAP2_BLUETOOTH -> CARPLAY_HANDOVER -> ACTIVE`

Terminal or cleanup phases are `STOPPING`, `FAILED`, and `CANCELLED`. Every callback carries a generation token. Wired projection, another OEM owner, Bluetooth loss, phone loss, service shutdown, or a stale callback cancels the current generation before another transport action.

The controller emits commands but never handles raw transport data. It permits one component-4 session, one component-5 handover, and one AP start per generation. Timeouts identify SPP, iAP2, handover, and projection activation separately.

### 3. Broadcom SPP adapter

An independently authored adapter binds the existing Broadcom BTCM service and exposes connect, disconnect, read, and write events. It does not create a Java `BluetoothSocket`. Raw frames are forwarded only between the selected peer and the current iAP2 component. Payloads, addresses, phone names, serials, SSIDs, and keys are never logged.

### 4. iAP2 app entry

The exact V039 Iap2ServerApp recipe supplies the missing component 4/5 start and stop entry. Installation is allowed only when the complete relay is present and the exact stock input hash matches. The recipe remains disabled in release packages until the DiPO handover adapter and structural verification are complete.

### 5. DiPO process-local handover

Wireless CarPlay channel callbacks are process-local to DiPO, so an external app alone cannot complete the handover. An exact-V039, independently authored app-level adapter must connect these existing boundaries:

- DiPO CarPlay native outbound iAP message -> iAP2 component 5
- iAP2 component-5 inbound message -> DiPO CarPlay native receive method
- wireless disconnect -> one generation cleanup

This is an application-level change only. The design does not alter `services.odex`, `SystemUI.odex`, framework, kernel, LK, recovery, MICOM, or radio firmware.

### 6. Projection AP broker

The existing UID-checked `ApBroker` and `AndroidWifiAp` code is a candidate for reuse after its launcher identity is proven. It currently requires UID 1000, while the NEMESIS supervisor is root and the host APK has an application UID; the broker must remain disconnected until a bounded system-UID launch path is demonstrated and tested. It starts the connectivity AP only after iAP2 has supplied valid `ConnectivitySSID` and `ConnectivityPSK`.

On V039 match mode, the actual AP beacon must use the connectivity pair, because stock AP startup reads ordinary `SSID` and `preSharedKey`. The broker temporarily starts with the connectivity pair, then restores the saved ordinary hotspot values without changing the already-running projection AP. The normal hotspot and projection AP remain separate user concepts.

The broker is fail-closed: WPA2 is required, secrets are never logged, the caller UID and parent supervisor are verified, cancellation closes the operation, and repeated AP-start boot failures disable wireless until recovery.

### 7. Android Auto and wired isolation

Android Auto remains on the OEM path and never enters the CarPlay component-4/5 relay. Wired CarPlay component 1 is unchanged. The relay cancels immediately when a cable or another projection owner is detected.

## Install and recovery safety

- V039 exact hashes only for the first implementation; V035 remains unsupported until separately reconstructed and reviewed.
- Snapshot both APK and ODEX identities before any app-level change.
- Apply all relay app changes in one transaction; a partial relay is never registered as installed.
- Rebuild a private exact-V039 DiPO APK, preopt it with the reviewed Android 4.4 invocation, clear only the relevant Dalvik cache, verify the APK/ODEX pair, and cold boot. PC mocks cover command failure and rollback; the vehicle invocation remains an acceptance item.
- Arm bootguard before reboot. Repeated failure restores every app-level original byte-for-byte and requests a cold boot.
- Start the runtime only after `sys.boot_completed=1`.
- Removal and edition switching stop the runtime first, restore originals, clear only project-owned state, and preserve OEM profiles and user hotspot settings.

## Diagnostics

Record only stable categories and numeric drive-log events:

- `relay=spp-requested|spp-connected|spp-timeout`
- `iap2=component4-started|component5-started|timeout`
- `handover=requested|active|timeout`
- `wifi=credentials-ready|ap-started|ap-timeout`
- `result=active|cancelled|failed`

Do not record transport payloads, credentials, identifiers, exception messages, or hashes derived from private values.

## Verification gates

1. Pure controller tests cover every phase, timeout, stale callback, duplicate callback, cable/owner cancellation, and cleanup order.
2. Adapter tests use fakes for BTCM, iAP2, DiPO, and AP operations; no vehicle libraries are packaged into tests.
3. Private structural tests apply recipes only to hash-matched stock V039 inputs and inspect the resulting DEX call graph and integrity fields.
4. Install/update/remove/rollback tests prove byte-identical restoration and reject partial artifacts.
5. Full package build and artifact audit must pass from a clean commit.
6. Vehicle acceptance separately proves first pairing, reconnect, 30-minute audio, calls and steering buttons, wired CarPlay, Android Auto, normal hotspot, projection AP, HUD, ignition-cycle reconnect, and removal.

## Release boundary

Source completion and CI do not make a public or vehicle-ready release. The README remains marked as under vehicle verification until the vehicle acceptance record is complete.
