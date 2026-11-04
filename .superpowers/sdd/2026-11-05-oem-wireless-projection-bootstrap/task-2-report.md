# Task 2: OEM PhoneProjection adapter report

## Outcome

Implemented package-scoped V039 first-registration bootstrap and profile-aware CarPlay/Android Auto observation and dispatch in `PhoneProjectionAccess`.

## RED evidence

After adding the adapter tests first, `bash tests/java.sh` initially returned `SKIP JVM tests (need both javac and java)` because Windows `bash.exe` resolved to the WSL launcher. Running the same requested script through Git Bash produced the intended RED: compilation failed because the three-argument `inspect` overload and `bootstrap` method were missing. No production changes existed at that point.

## GREEN evidence

- Git Bash `tests/java.sh`: all Java tests passed, including `PhoneProjectionAccessTest`, `StockProjectionSessionTest`, and the remaining JVM harness suites.
- `git diff --check`: passed.
- Added assertions cover CarPlay selecting only `getCPConnectedBTAddress`, Android Auto selecting only `getAAConnectedBTAddress`, unsupported profile fail-closed behavior, Android Auto's existing-profile UI action, and exactly one `requestConnectSPP(candidate)` after a package-scoped bootstrap action carrying only `ADDRESS`.

## Self-review

- Bootstrap resolves `requestConnectSPP(String)` before dispatch, then uses the supplied action sender for the generation-checked OEM broadcast and invokes the OEM method once only after that dispatch succeeds. A false dispatch returns `CANCELLED`; successful invocation returns `OEM_REQUESTED`, not an active state.
- Reflection distinguishes missing methods, service absence, security failures, and invocation failures. No `requestWLDeviceInfoAdd` or `requestWLDeviceInfoUpdate` call was added.
- Existing `inspect(ServiceProvider,String)` remains as a CarPlay compatibility entry point. The new `inspect(ServiceProvider,Object,String)` uses the saved OEM profile to select the platform getter. `WirelessBridge` still calls the compatibility entry point; wiring its call site to the new overload is outside Task 2's allowed file list.
- APK/device and vehicle behavior were not validated in this task.

## Files and commit

- `packages/wireless-bridge/src/kr/gen5w/wireless/PhoneProjectionAccess.java`
- `packages/wireless-bridge/test/PhoneProjectionAccessTest.java`
- Commit: `1e1adde33cb0e72c2fa8a65ff055cbbae94bfce0` (`feat: bootstrap OEM wireless projection profiles`)

## Review fix round 1

- RED: added cases for a missing profile becoming a valid idle CarPlay profile, a valid idle Android Auto profile with no connected address, a cancelled bootstrap that must not invoke `requestConnectSPP`, and a missing `requestConnectSPP` method that must not dispatch the action. The first full JVM run failed at the new CarPlay readiness assertion: the adapter reported `UNKNOWN` because the selected connected address was empty.
- GREEN: profile readiness now depends on the saved profile address/type and its enabled/auto-connect settings. The per-platform connected address only determines active/connecting/foreign ownership. Cancelled bootstrap and missing-method cases also pass with no `requestConnectSPP` call or broadcast, respectively.
- Verification: Git Bash `tests/java.sh` passed all JVM suites; `git diff --check` passed.
- Remaining validation boundary: no APK build or vehicle test was run.
