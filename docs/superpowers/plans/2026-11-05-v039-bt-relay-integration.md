# V039 Bluetooth Relay Wireless CarPlay Implementation Plan

**Goal:** Complete the exact-V039 Bluetooth SPP to iAP2 and DiPO handover path, then start a credential-matched projection AP without changing boot-critical files.

**Spec:** `docs/superpowers/specs/2026-11-05-v039-bt-relay-integration-design.md`

## Constraints

- Implement only against exact, hash-matched Korean V039 inputs.
- Do not ship a partial iAP2 or DiPO patch.
- Keep Android Auto and wired CarPlay outside the relay.
- Never log phone identifiers, credentials, or transport payloads.
- Preserve transaction, backup, Dalvik, bootguard, uninstall, and rollback guarantees.

## Task 1: Pure relay lifecycle

- Add an Android-independent `BtRelaySession` with generation-checked events and commands.
- Cover SPP, component 4, component 5, AP readiness, activation, timeouts, cancellation, duplicates, and stale callbacks with JVM tests.
- Keep it dormant until all adapters are available.

## Task 2: BTCM adapter boundary

- Define a narrow adapter for the existing Broadcom SPP service.
- Add fake-based tests for one owner, ordered forwarding, disconnect, write failure, and payload-free diagnostics.
- Do not restore the former direct `BluetoothSocket` path.

## Task 3: iAP2 recipe integration

- Add private structural tests for `bt-v039.json` and reject V035 in the first release.
- Connect the recipe to build/install only behind a complete-relay artifact gate.
- Verify DEX integrity and exact stock/patched hashes.

## Task 4: DiPO process-local adapter

- Build an independently authored V039 adapter for the existing native iAP send/receive boundaries.
- Merge it with retained call-key and HUD changes in one deterministic artifact.
- Add structural tests proving component-5 handover and preserving wired component 1.

## Task 5: AP broker reactivation

- Compile the existing hotspot sources into the host artifact.
- First prove a bounded system-UID launcher for the broker; its current UID-1000 requirement is not satisfied by either the root supervisor or the application-UID host.
- Start the privileged broker only through that verified path after boot completion.
- Connect it only after valid connectivity credentials and component-5 readiness.
- Test WPA2 enforcement, UID/parent checks, cancellation, ordinary hotspot restoration, AP boot guard, and secret-free logs.

## Task 6: Atomic package lifecycle

- Apply Iap2ServerApp and DiPO changes in one transaction.
- Reject partial or mixed revisions.
- Run the validated Dalvik cleanup and cold-boot path, arm bootguard, and verify byte-identical uninstall/rollback. Do not claim an explicit preopt step because the current package does not have one.
- Keep the public package disabled until the complete-relay gate passes.

## Task 7: Regression and release candidate

- Run focused JVM and shell suites during implementation.
- Run one full clean build and artifact audit after all tasks are committed.
- Update Korean docs and version metadata.
- Prepare a diagnostic vehicle candidate only after code review; do not claim success until the vehicle matrix passes.
