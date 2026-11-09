# Exact-V039 GPM USB start guard and recoverable delta installation

Status: scope approved; written-design review pending.

## Intent and boundaries

Prevent GPM from treating a USB drive or hub as a wired Android Auto start,
without disrupting phones, composite devices, unknown devices, or wireless AA.
The user approved extending the existing delta installation/restore mechanism
to GPM. This work does not authorize a public release, version bump, or physical
USB update. Existing uncommitted DiPO fixes must be preserved.

Success requires both the device predicate and a recoverable installation of
the actual generated payload. Source-only changes do not count as delivery.

## Evidence

The reviewed V039 GPM ODEX SHA256 is
`caee2cdf77a101d9b103d850658c85c4ed922e863d6566166b87037a11fd55c8`;
the matching APK SHA256 is
`8e7e9805f237f0690124af4b797466d716df12b55df065142a4f426a567f6bde`.
Its StartReceiver passes USB devices to GalReceiverService with startMode=1.
The separate service-side isMobileDevice check is not a pre-start guard.
Current GPM installation changes only the ODEX for native HUD support.
DiPO already uses a source-verified delta, saved APK/ODEX pair, staging,
preoptimization, recorded live hashes, rollback and bootguard recovery.

Private stock inputs and decompiled code stay outside Git and release assets.

## Alternatives and choice

1. Recommended: extend the existing bridge delta lifecycle to an exact-V039
   GPM APK/ODEX pair, with a narrowly scoped authored service-start wrapper.
   This prevents the incorrect request before the service starts and preserves
   existing HUD changes, at the cost of handling a second app pair.
2. Only guard GalReceiverService.onStartCommand: fewer call-site hooks, but
   service creation may already have occurred. It does not provide equivalent
   protection to a pre-start guard.
3. Suppress USB broadcasts or disable wired AA globally: simpler, but breaks
   legitimate phone/composite-device behavior and is rejected.

## Guard behavior

Only GPM-process calls starting the explicit GalReceiverService component with
integer startMode=1 are candidates. Suppress that service-start request only
when a non-null UsbDevice has at least one interface and every interface is
non-null with class 8 (storage) or 9 (hub). Return null ComponentName when
suppressed, matching an intentionally omitted service start.

Missing component/mode/device, zero interfaces, null interfaces, unavailable
metadata, and any other interface class preserve the original call. Unknown
metadata is not proof of a storage device. Non-target services, boot starts,
wireless starts and all other modes delegate unchanged. Do not log device
names, serial numbers, addresses or payloads; emit only bounded safe reason
codes. Do not retry a delegated start after it throws.

Use an independently authored Java helper. The private builder inventories
the exact stock GPM service-start call sites and replaces only validated
Context.startService-compatible calls with the helper. Fail the build on
ambiguous/unreviewed call sites rather than emitting a partially guarded app.
No runtime hooking framework or system/framework patch is introduced.

## Build and artifact contract

Hash-check original APK and ODEX. Apply and verify the existing GPM HUD recipe
before deodexing, then add the authored guard and verified call-site changes.
Compile for API18, assemble DEX, and produce an ODEX-to-DEX delta using the
existing lpatch format. Publish only the delta and authored tools, never a
manufacturer APK, ODEX, decompiled source, or full rebuilt DEX/APK.

Extend the relay completeness marker/checksum manifest to require the GPM
delta for the new payload version. Retain explicit migration handling for
older owned bridge installs; do not interpret an old complete marker as proof
that the new GPM guard exists. Exact V035 behavior remains unchanged.

## Installation, update and restore

- Classify stock, owned legacy HUD-patched, owned delta-installed, and unknown
  GPM pairs separately. Unknown/foreign pairs or corrupt backups fail closed.
- Save both original GPM APK and original ODEX, verify their identities, and
  retain durable copies under the existing bridge owner model before mutation.
- For legacy owned HUD installs, use the verified original ODEX backup as
  delta input; never apply the delta to an already patched ODEX.
- Assemble and preoptimize in owned staging, preserve original metadata, and
  verify staged results before replacing either live file. Treat the pair as
  recoverable, not as an atomic two-file rename.
- Record generated live hashes and replacement intent durably before changing
  the first live file, so recovery recognizes interrupted mixed pairs.
- Stop affected projection processes using existing lifecycle hooks. If either
  replacement or post-verification fails, restore both original files. Preserve
  backups/ownership and the primary failure if rollback is incomplete.
- Extend remove, update, already-stock cleanup, staged-file cleanup and
  bootguard recovery together. Never delete the only verified original or
  ownership evidence until both live originals are confirmed restored.
- Existing remount failure policy, symlink guards and exclusion locks remain
  in force. Avoid a generic installer refactor unrelated to this second pair.

## Verification and acceptance

Write failing tests before product changes. Execute the actual Java helper
with Android boundary doubles for storage, hub, mixed 8/9, phone, composite,
zero/null/unknown interfaces, metadata failures, unrelated service/mode,
delegate return value and delegate exception/no duplicate start.

Exercise the real shell lifecycle with failure injection: fresh install,
legacy update, repeat install, partial APK/ODEX replacement, dexopt failure,
bad delta/checksum, corrupt or missing backup, symlinks, staging interruption,
rollback failure, remove and bootguard recovery. Assert exact restored bytes
and retained evidence, not only status text.

Reconstruct the shipped delta from exact private stock and verify DEX headers,
guard call edges, original HUD patch and native boundaries. Verify packaged
payload bytes, completeness marker, checksum membership, and absence of OEM
files. Run the full suite and relevant API18/native builds, and request a
read-only review before completion. Report skipped private/device checks.

Physical vehicle connection success and the existing missing-wlan0 symptom
remain separate, unverified outcomes; this guard does not create a Wi-Fi driver.
