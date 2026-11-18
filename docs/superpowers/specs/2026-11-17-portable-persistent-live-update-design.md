# Portable persistent live activation and active update design

Date: 2026-11-17
Status: revised design for review; product code and vehicle unchanged
Project: `kona-gen5w-research`, active checkout `gen5w-kr-stock-first`

## User outcome and constraints

Solve both reported issues before dongle expansion:

1. Normal boots must not blank the display because the portable package stops/restarts zygote or the Android framework.
2. A new USB version must replace the currently armed portable package safely, without the old installer refusing it as already installed.
3. Installation/update applies the system changes once and then automatically restarts the head unit once so Android loads them. Normal later starts do not repeat the patch transaction.
4. Do not modify bootloader, boot partition, boot image, ramdisk, init files or other boot-chain files. Do not stop/restart Android or zygote during install/update; use one normal reboot after successful installation/update to load the persistent changes.

Keep existing recovery behavior and exact file ownership checks where possible. If required features or wrappers are still unavailable after the one planned reboot, fail closed and state the exact limitation; do not silently claim success.

### Hard recovery gate (added 2026-11-17)

Do not modify persistent system files or request the planned reboot unless a recovery path has been demonstrated to work when normal Android UI/zygote cannot start. The in-package USB watcher is a NEMESIS service and is not enough by itself. NEMESIS 1.16's official run-script documentation (commit `a7dc770`, 2026-11-01) describes a root `type=execute` script that runs while Android is down when the USB root contains `NEMESIS.emergency`; the historical vehicle version was 1.16.3. The project's current portable and integrated USB installers intentionally omit that marker, and the integrated entrypoint rejects `sys.boot_completed != 1`; those ordinary sticks are not Android-down recovery sticks. A harmless probe USB now exists at `tools/portable/recovery-usb/probe/` and `.build/portable-recovery-probe.zip`, but has not been run on the vehicle. The repository's PC fastboot path is only a read-only helper; actual vehicle enumeration and stock-image restoration remain unverified.

Before implementation can be considered safe for a vehicle candidate, first demonstrate that the probe USB executes on the target vehicle with Android UI/zygote unavailable. Then build a dedicated recovery-only USB entry using the documented emergency execute path, with independently retained exact originals and a fixed restore script; test its refuse/partial-write/restore behavior on host fixtures; finally demonstrate exact restoration of every modified `/system` target. Keep it physically separate from the installer and require an explicit recovery marker so it cannot install or patch. If any gate fails, this design cannot meet the user's recovery condition and persistent system-write implementation remains blocked. No software design can guarantee recovery from independent hardware/eMMC/power failure; this gate addresses failures caused by this patch and requires a practical independent recovery path.

## Current evidence

- Current portable startup binds patched `/system` views from `/data`, then intentionally stops and starts zygote. The ephemeral mounts disappear on a kernel boot, which is why the same transaction runs on every boot (`tools/portable/boot.sh`, `tools/portable/overlay.sh`).
- The portable candidate includes patched `Iap2ServerApp.odex`, `HKMC_DiPO.odex`, optional `HKMC_GPM.odex` and `HKMC_WifiSettings.odex`, optional `libCarPlayAudio.so`, plus wireless permission XML and feature configuration. `portable.sh apply` rejects a running zygote because already loaded code cannot be replaced safely.
- Wireless feature declarations are read as Android system configuration when `SystemConfig` is constructed and are passed into PackageManager at `PackageManagerService` construction. The AOSP source shows the feature map is obtained from that startup-created configuration, not live-reloaded by editing the XML afterward ([`SystemConfig.java`](https://android.googlesource.com/platform/frameworks/base/%2B/bedb566/services/core/java/com/android/server/SystemConfig.java), [`PackageManagerService.java`](https://android.googlesource.com/platform/frameworks/base/%2B/288e3f5/services/core/java/com/android/server/pm/PackageManagerService.java)).
- The last vehicle log from 0.3.67 records `framework-stop` at 26s, `framework-start` at 37s, and readiness at 52s; this matches the source transaction and confirms the display interruption is the deliberate runtime restart. It does not establish that every feature will remain available if that restart is removed.
- The project's existing wireless installer performs hash-owned, atomic `/system` configuration writes with backups and exact rollback (`packages/wireless-enable/scripts/common.sh`, `recovery.sh`). The existing GPM bridge replaces an ODEX on `/system`, force-stops only `com.google.android.projection.sink`, and verifies its live state (`packages/wireless-bridge/scripts/gpm-relay.sh`). These are precedents, not proof that the whole portable target set is safe for the same treatment.
- The local private V039 APK manifests identify `Iap2ServerApp.apk` as `com.tcc.iap2server` with service `Iap2Service`, DiPO as `com.daudio.app.dipo` with `DipoService`/`CarPlayService`, and GPM as `com.google.android.projection.sink` with `GalReceiverService`; DiPO and GPM have boot-completed receivers. These local manifests do not prove the live vehicle APK hashes or runtime behavior. A V039 stock `HKMC_WifiSettings.apk` was not present in that directory, so its optional process mapping remains unknown.
- The current USB `finish(ok)` already requests one automatic reboot after successful NEMESIS installation; its current alert warns of a possible screen blink. Existing installer tests cover success reboot and reboot-command failure. The required behavior is to retain this single post-install reboot, revise its alert, and remove repeated framework transactions from future boots.
- The USB updater currently refuses `enabled|1`; its existing tests encode this. Existing active disable would run the framework transaction and therefore cannot be reused for a no-restart update.

## Approaches

### A. Persistent, journaled `/system` replacements; one install-time restart (recommended)

Convert the currently mounted, hash-verified portable payload into durable `/system` file replacements once. Record exact original bytes, metadata and owner; stage and verify every file before switching; remount `/system` read-only on all exits. Persist the wireless permission/feature configuration and put the required `wrap.*` launcher values into `/system/build.prop`. Android 4.4 init loads `/system/build.prop` before processing the boot actions, and the V039-era Zygote reads `wrap.<process>` when spawning each app, so wrappers can be present before OEM apps launch without a per-boot service mutation ([AOSP init](https://android.googlesource.com/platform/system/core/%2B/android-4.4.4_r2/init/init.c), [AOSP property service](https://android.googlesource.com/platform/system/core/%2B/android-4.4.2_r2/init/property_service.c), [AOSP ZygoteConnection](https://android.googlesource.com/platform/frameworks/base/%2B/1f392c468ae40589474ea906cffa05658741c3e0/core/java/com/android/internal/os/ZygoteConnection.java)). After all writes, verification and package update succeed, notify the user and request one normal device reboot. Do not stop `zygote` or `system_server` in the running session.

After installation, normal boot must not copy or bind patched files, set properties from a service, alter the global feature list, or run the current framework transaction. The ODEX, native library, permission XML, feature configuration, and wrapper properties are persistent `/system` state. The first install and each package update request one normal reboot only after successful package/file verification; repeated future starts perform no patch transaction and no Android/zygote restart. `/system/build.prop` is an early-loaded system property file, not a boot image, ramdisk, bootloader, or init configuration file; the user explicitly excludes those boot-chain files.

The USB update must handle an armed install: validate all inputs, acquire the portable lock, stop only the portable package's own workers, stage the current owned overlay contents, convert owned targets to persistent files, add/update the two wrapper properties in `/system/build.prop`, preserve and verify rollback material, replace the NEMESIS package without running its old framework-restart preun path, and verify the new package/scripts/metadata. Only then show “설치가 완료되어 시스템이 재시작됩니다.” and request one reboot. A failure before the reboot leaves the old package and its prior owned state usable, or an explicit recovery-required marker with backups retained; it must not reboot after a failed install.

### B. Keep runtime bind mounts but restart only target apps

This avoids persistent `/system` writes, but permission XML and feature declarations still require the planned cold boot, and ephemeral mounts would again require activation on each future start. It also cannot persist `wrap.*` values across boots without an early property source. Not sufficient as the default.

### C. Keep current bind mounts and keep restarting zygote

Preserves current behavior but directly violates the reported screen interruption. Rejected.

## Recommended live migration sequence

1. Read-only admission: verify the USB ZIP/hash/version, NEMESIS compatibility, package/owner markers, current live `pm list features`, owned mounts, `/system` identity/free space, and no concurrent maintenance lock. Refuse unknown or foreign mounts.
2. Copy every owned live overlay source to private staging and verify hashes and metadata. Verify the original backup and ownership journal for every target; never infer live originals from a firmware image.
3. Stop only portable-owned workers. Keep Android, `zygote`, `system_server`, Wi-Fi service, and unrelated apps running. Existing OEM processes may continue using already-loaded code until the planned reboot.
4. Unmount only targets whose bind identity matches the portable journal, then remount `/system` read-write through the supported path. Atomically back up each original once and replace each allowlisted target, including `/system/build.prop` with exactly the two owned wrapper properties. Verify content, owner, mode and SELinux label after each write; keep a durable per-file journal and rollback all writes if any step fails.
5. Verify the feature declaration files and live PackageManager gates, and prove wrapper commands point to stable, readable bundle paths and fit V039 property-name/value limits. Do not restart the currently running system server to refresh its in-memory feature set.
6. Remount `/system` read-only and verify. Neutralize the old preun hook only for the bounded NEMESIS update, install with `nemesis install --update`, and verify package/scripts/owner state. Preserve the previous package and backups until verification passes.
7. Write the final owner manifest atomically. Show the approved restart notice and request one normal reboot only after every check passes. Never call `ctl.stop zygote`, `ctl.start zygote`, or `ctl.restart system_server`.
8. On any failure before reboot, restore the prior package and exact prior owned file state, or retain all backups and a recovery-required marker. USB recovery restores only targets whose live hashes still equal this portable owner's applied hashes; after a successful restore, request a normal reboot so Android reloads stock files/properties.

## Rollback and invariants

- Never change boot, init, ramdisk, bootloader or boot-chain files.
- Every `/system` target must be allowlisted, original-hash identified, owner-journaled, and atomically replaceable. Unknown modified files refuse migration.
- Backups are never overwritten by an update. Restore only targets whose live hash equals this package's recorded patched hash; preserve foreign changes and report them.
- `/system` is returned to read-only on every exit. Failure to remount read-only is a hard failure with report, not success.
- Do not kill/restart zygote/system_server as a fallback. The one normal reboot after a successful install/update is the only planned service reload.
- Never use direct `pm install`; retain NEMESIS >=1.16.7 and HMG package guard.
- The update result reports successful automatic restart only after package, persistent files, feature declarations, wrapper properties and read-only remount all verify.

## Required tests before vehicle candidate

- Regression: normal boot never calls `stop-android`, `start-android`, reboot, or system_server restart. Installer requests exactly one reboot after success and none after refusal/failure.
- Live-overlay migration tests for source hash mismatch, foreign mount, symlink, foreign owner, duplicate target, missing backup space, partial replace, power-cut points, remount-ro failure, rollback of each target, and backup retention across multiple updates.
- Feature gate tests: current live CarPlay/AA features present; one missing; unreadable; existing persistent declarations; post-install cold-boot configuration parses the same feature list.
- Wrapper tests: build.prop preserves unrelated properties, adds exactly the owned `wrap.*` keys, survives repeated cold-boot property loading, and points at stable readable wrapper files before DiPO/GPM first launch.
- Active updater tests for currently armed version, live session, active lock, NEMESIS refusal, postinstall failure, old preun restoration, package mismatch, package re-arm failure, exactly one reboot after success, and no reboot after any failure.
- Full preserved repository regression and package integrity audit.
- Vehicle checks: compare live originals and backup hashes; confirm `/system` returns ro; inspect wrapper properties and `pm list features`; update over installed 0.3.71 and verify the installer requests one reboot after success; cold-start vehicle repeatedly and confirm no patch transaction, `framework-stop`/`framework-start`, or extra display blank cycle.

## Decision gate

The user approved the implementation direction subject to the hard recovery gate above. The design avoids bootloader, boot image, ramdisk and init modifications. It proposes one normal reboot after successful install/update, then no per-boot patching or framework restart, using permanent journaled `/system` replacements including two app wrapper properties in `/system/build.prop`. Official NEMESIS documentation supplies a plausible Android-down USB execution mechanism, but the project's installer deliberately does not enable it and no target-vehicle recovery run is verified. Preparation of a dedicated recovery-only USB path may proceed; persistent system-write implementation and a vehicle-installable candidate remain blocked until target-vehicle emergency execution and exact restore are demonstrated. The user's approval does not waive this gate.

## Pre-zygote boot guard (2026-11-18)

Persistent `/system` changes have no per-boot zygote restart, so a bad change could otherwise repeat on every boot. V039 init already runs a stock root script before zygote: `init.tcc897x.rc` `on post-fs-data` → `start qb_uid_check` → `/system/bin/sh /system/etc/qb_runtime.sh check_fixed_uid` (oneshot, root). Its output appears in the real vehicle dmesg at about 2.9–3.3 s on every boot.

- `prepare.sh` stages `qb_runtime.sh` as the exact stock bytes plus one background line after the shebang. The file is recorded as a normal recovery-manifest row (`bootguard`), so the restore USB and the guard restore it like every other target. An unrecognized stock script is skipped.
- `package-post.sh` installs `guard.sh`, `restore.sh` and `bin/dex-patch` into `/data/local/gen5w-portable/persistent/bootguard`, outside the NEMESIS package.
- Each boot increments a counter. The counter is cleared when `sys.boot_completed` stays set for 30 s. After 4 boots without a stable Android, the guard disables automatic start, runs the fixed-function restore (which reboots once), and latches.
- Init does not wait for the oneshot service and does not kill the process group of an exited oneshot service. The guard therefore never delays zygote. That the background child survives must still be confirmed in the VM and in the vehicle log.
- The boot partition, LK and `init.rc` are never modified.
