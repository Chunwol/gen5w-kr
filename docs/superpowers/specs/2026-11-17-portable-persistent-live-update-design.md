# Portable persistent live activation and active update design

Date: 2026-11-17
Status: revised design for review; product code and vehicle unchanged
Project: `kona-gen5w-research`, active checkout `gen5w-kr-stock-first`

## User outcome and constraints

Solve both reported issues before dongle expansion:

1. Normal boots must not blank the display because the portable package stops/restarts zygote or the Android framework.
2. A new USB version must replace the currently armed portable package safely, without the old installer refusing it as already installed.
3. Do not modify bootloader, boot partition, boot image, ramdisk, init files or other boot-chain files. Do not restart Android/zygote to apply the update. Restart only directly affected OEM application processes when their ODEX/native code must be reloaded.

Keep existing behavior where possible. If a required platform feature is unavailable without restarting system_server, fail closed and state the exact limitation; do not silently ship a partially working wireless package.

## Current evidence

- Current portable startup binds patched `/system` views from `/data`, then intentionally stops and starts zygote. The ephemeral mounts disappear on a kernel boot, which is why the same transaction runs on every boot (`tools/portable/boot.sh`, `tools/portable/overlay.sh`).
- The portable candidate includes patched `Iap2ServerApp.odex`, `HKMC_DiPO.odex`, optional `HKMC_GPM.odex` and `HKMC_WifiSettings.odex`, optional `libCarPlayAudio.so`, plus wireless permission XML and feature configuration. `portable.sh apply` rejects a running zygote because already loaded code cannot be replaced safely.
- Wireless feature declarations are read as Android system configuration when `SystemConfig` is constructed and are passed into PackageManager at `PackageManagerService` construction. The AOSP source shows the feature map is obtained from that startup-created configuration, not live-reloaded by editing the XML afterward ([`SystemConfig.java`](https://android.googlesource.com/platform/frameworks/base/%2B/bedb566/services/core/java/com/android/server/SystemConfig.java), [`PackageManagerService.java`](https://android.googlesource.com/platform/frameworks/base/%2B/288e3f5/services/core/java/com/android/server/pm/PackageManagerService.java)).
- The last vehicle log from 0.3.67 records `framework-stop` at 26s, `framework-start` at 37s, and readiness at 52s; this matches the source transaction and confirms the display interruption is the deliberate runtime restart. It does not establish that every feature will remain available if that restart is removed.
- The project's existing wireless installer performs hash-owned, atomic `/system` configuration writes with backups and exact rollback (`packages/wireless-enable/scripts/common.sh`, `recovery.sh`). The existing GPM bridge replaces an ODEX on `/system`, force-stops only `com.google.android.projection.sink`, and verifies its live state (`packages/wireless-bridge/scripts/gpm-relay.sh`). These are precedents, not proof that the whole portable target set is safe for the same treatment.
- The USB updater currently refuses `enabled|1`; its existing tests encode this. Existing active disable would run the framework transaction and therefore cannot be reused for a no-restart update.

## Approaches

### A. Persistent, journaled `/system` replacements; process-local reloads (recommended)

Convert the currently mounted, hash-verified portable payload into durable `/system` file replacements once. Record exact original bytes, metadata and owner; stage and verify every file before switching; remount `/system` read-only on all exits. Preserve current PackageManager feature state during migration (it was loaded by the currently installed candidate's framework transaction), and persist the same wireless feature XML/configuration so future cold boots load those features before PackageManager starts. Stop only the OEM app processes that own replaced ODEX/native code, then allow their normal OEM/NEMESIS lifecycle to start them again. Do not stop `zygote` or `system_server`.

After migration, normal boot only reinstalls transient `wrap.*` app-launch properties if required and starts the existing observers; it must not bind patched files, alter the global feature list, or run a framework transaction. Since patched files are already on `/system`, new app processes see them from their first launch on each future boot.

The USB update must handle an armed install: validate all inputs, acquire the portable lock, stop our own session, stage the current live overlay contents, convert owned targets to persistent files, preserve and verify rollback material, replace the NEMESIS package, verify new scripts/metadata, re-arm only after the live system state is proven, and restart affected app processes. No Android or zygote restart is requested. A failed update leaves either the old package and old owned state usable, or an explicit recovery-required marker with backups retained.

### B. Keep runtime bind mounts but restart only target apps

This avoids persistent `/system` writes, but permissions XML and feature declarations cannot be made visible to the already-running PackageManager/SystemServer by changing files after startup. It is viable only if the live system already advertises every required feature before the portable service starts and no configuration overlay is needed. Existing historical logs show wireless features on a vehicle after prior installation, but do not prove the current base/boot state or guarantee future cold boots. Not sufficient as the default.

### C. Keep current bind mounts and keep restarting zygote

Preserves current behavior but directly violates the reported screen interruption. Rejected.

## Recommended live migration sequence

1. Read-only admission: verify the USB ZIP/hash/version, NEMESIS compatibility, current package and owner markers, current live `pm list features`, mounted targets, storage, `/system` identity, and no concurrent wireless session/maintenance lock. Refuse unknown or foreign mounts.
2. Copy each patched overlay source to a private staging directory and verify its expected digest and file metadata. Identify the current underlying original for every target; do not infer an original from a stock firmware image if the live target is unknown.
3. Stop only affected OEM app processes (package names resolved and tested for this firmware) and our own bridge/session services. Leave Android, `zygote`, `system_server`, Wi-Fi service and unrelated apps running.
4. Temporarily remount `/system` read-write using the project's supported NEMESIS path. For every target, atomically save and hash the original once, then atomically replace with the staged candidate and verify bytes, owner, mode and SELinux label. Maintain a durable per-file journal and complete rollback before touching the NEMESIS package.
5. Ensure live PackageManager currently exposes the required CarPlay/AA features. Because the current system server loaded those through the old overlay before this migration, the existing in-memory state should remain available; if the live feature gate fails, stop before removing the old candidate's only working configuration and report that a one-time system-server restart or an already-persisted feature source would be required.
6. Remount `/system` read-only and verify. Only then neutralize the old preun hook for the package swap, install the staged ZIP with `nemesis install --update`, and verify the new package, scripts and updater state. Preserve the old package and all backups until this completes.
7. Publish the new owner manifest and persistent mode atomically. Set launch wrappers for future process starts, restart only the verified target application processes, and confirm their expected package/service state. Do not call reboot, `ctl.stop zygote`, `ctl.start zygote`, or `ctl.restart system_server`.
8. If a target process cannot be safely restarted, leave the old application lifecycle intact, keep the new files in a recoverable state, and report that an ignition cycle may be needed; do not restart the framework to force success.

## Rollback and invariants

- Never change boot, init, ramdisk, bootloader or boot-chain files.
- Every `/system` target must be allowlisted, original-hash identified, owner-journaled, and atomically replaceable. Unknown modified files refuse migration.
- Backups are never overwritten by an update. Restore only targets whose live hash equals this package's recorded patched hash; preserve foreign changes and report them.
- `/system` is returned to read-only on every exit. Failure to remount read-only is a hard failure with report, not success.
- Do not kill or restart zygote/system_server as a fallback. If global feature state is missing, mark wireless unsupported until an explicitly approved separate solution.
- Never use direct `pm install`; retain NEMESIS >=1.16.7 and HMG package guard.
- The update result states “updated live; Android was not rebooted” only after package, persistent files, feature gate, process relaunch and read-only remount all verify.

## Required tests before vehicle candidate

- Regression: no path through boot run/activate/update calls `stop-android`, `start-android`, `ctl.restart zygote`, reboot or system_server restart.
- Live-overlay migration tests for source hash mismatch, foreign mount, symlink, foreign owner, duplicate target, missing backup space, partial replace, power-cut points, remount-ro failure, rollback of each target, and backup retention across multiple updates.
- Feature gate tests: current live CarPlay/AA features present; one missing; unreadable; existing persistent declarations; post-migration cold-boot configuration parses the same feature list.
- Per-process lifecycle tests for every actual package owning each ODEX/native library; a running DiPO/GPM/iAP2/WifiSettings process must load patched code after only its own process restart.
- Active updater tests for currently armed version, live session, active lock, NEMESIS refusal, postinstall failure, old preun restoration, package mismatch, re-arm failure and successful no-reboot replacement.
- Full preserved repository regression and package integrity audit.
- Vehicle checks: compare live originals and backup hashes; confirm `/system` returns ro; inspect `pm list features`; update over installed 0.3.71 without reboot; verify only affected app PIDs changed; cold-start vehicle repeatedly and confirm no `framework-stop`/`framework-start` and no display blank cycle.

## Decision gate

This design avoids all boot-chain files and framework/Android restarts, but changes the portable candidate from ephemeral `/data` bind overlays to permanent, rollback-journaled `/system` replacements. It is a major persistence and recovery change. No implementation begins until the user approves this design and the exact target process mapping/system recovery plan is reviewed.
