# Task 3: Read-only projection Wi-Fi observer

## Result

Implemented a pure Java observer that collapses `ConnectivitySSID` and `ConnectivityPSK` immediately to `UNKNOWN`, `MISSING`, or `PRESENT`. It never returns, stores in its result, or logs credential material. AP integers map exactly to `OFF` (10/11), `ENABLING` (12), `READY` (13), `FAILED` (14), or `UNKNOWN` (all other values). The host manifest adds only `ACCESS_WIFI_STATE`; no AP mutation call or hostapd integration was added.

## Files

- Added `packages/wireless-bridge/src/kr/gen5w/wireless/ProjectionWifiAccess.java`.
- Added `packages/wireless-bridge/test/ProjectionWifiAccessTest.java`.
- Updated the host manifest and the explicit Java source/test lists in `tools/build-dex.sh` and `tests/java.sh`.

## TDD evidence

RED was recorded after writing the test and wiring it into the Java runner, before adding the production adapter.

Command:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tests/java.sh
```

Output:

```text
error: file not found: packages\wireless-bridge\src\kr\gen5w\wireless\ProjectionWifiAccess.java
Usage: javac <options> <source files>
use --help for a list of possible options
exit_code=1
```

This was the expected missing-class compile failure. An earlier attempt through the default `bash` resolved to WSL, where `javac` was not on that shell's path; it was discarded as environment setup and the RED above was rerun through Git Bash.

GREEN and build command, after implementation:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -lc 'tests/java.sh && tools/build-dex.sh packages/wireless-bridge kr.gen5w.wireless.WirelessBridge bridge.dex && tools/build-wireless-host.sh'
git diff --check
```

Output highlights from the full JVM suite:

```text
PASS StockProjectionSessionTest
PASS PhoneProjectionAccessTest
PASS BluetoothCandidateScanTest
PASS ProjectionWifiAccessTest
PASS SdpRefreshTest
TbtDistanceTest 23 assertions passed
ApBrokerPolicyTest passed
ApBrokerCancellationTest passed
ApBrokerParentTest passed
built packages/wireless-bridge/app/bridge.dex
exit_code=0
```

All existing HUD, guidance, wireless, and AP broker checks in `tests/java.sh` also completed successfully. `build-wireless-host.sh` completed APK signature verification successfully. `git diff --check` returned exit 0. The build emitted the existing `WirelessBridge.java` deprecated-API note and JDK 25 Conscrypt restricted-native-access warnings during APK signing; they did not fail either build.

## Self-review

- Null service, missing getter, null configuration, and reflection/runtime failures return `UNKNOWN`; null or whitespace-only values in either field return `MISSING`; two nonblank fields return `PRESENT`.
- The observation exposes only an enum field. Each reflected credential value is reduced to a boolean at the point of read; no content, length, or hash is emitted.
- AP mapping is a pure switch. The observer has no mutation method and does not contain AP mutation APIs or hostapd references.
- The manifest change adds `ACCESS_WIFI_STATE`; it does not add `CHANGE_WIFI_STATE`.
- Tests and build source lists are explicit as required.
- JVM and host APK builds passed. This is host-side validation only; no vehicle or runtime AP state was exercised.

## Commit

Commit: `feat: observe OEM projection wifi readiness` (the final SHA is reported in the task handoff).
