# Gen5W on-unit portability candidate

This is a separate, explicitly installed validation build. It preserves rc.1q. Manufacturer apps, ODEX files and libraries are read
from the vehicle during preparation and are not included in the candidate.

## Build and PC verification

Build `python tools/portable/build.py`. Build the independently authored Dalvik
engine with `python tools/portable/dalvik/build.py --java-home JDK --ndk NDK
--d8 D8_JAR --stock-system PRIVATE_SYSTEM --android-jar ANDROID_JAR
--output .build/portable/dalvik`. The private system is a local build input only.
Build the portable authored core/host variants with `python tools/portable/build_apps.py
--java-home JDK --output .build/portable/apps` (fresh output only).
Place dex-patch, dalvik/ and apps/ under one private input directory, then run
`python tools/portable/candidate.py --runtime --inputs INPUTS --output .build/portable/NEW`.
An existing destination, source directory, symlink ancestor or incomplete input
is refused. SHA256SUMS covers every included file except itself; CANDIDATE.json
records the source revision, dirty state, and lack of vehicle verification.

`bash tests/run.sh` covers source shell compatibility, lifecycle mocks, candidate
assembly, host adapter dispatch and existing regressions. Host/ARM structural
comparison is `python tests/portable_patcher.py [--arm]`; it uses local private
stock fixtures. Run preparation ownership tests with
`wsl -u root -e bash -lc 'cd CHECKOUT && bash tests/portable_prepare.sh'`.
The private ARM VM suite is `PORTABLE_VM_RUNNER=PRIVATE_CHROOT_RUNNER
PORTABLE_VM_ROOT=PRIVATE_ROOT bash tests/portable_vm.sh`, as PC root. It creates
private PID/mount namespaces for the old bionic runtime. Its ashmem substitute
and `-Xdexopt:none` are PC-only; bytecode verification remains enabled.

## Support boundary

The native tool accepts bt, route, dipo, gpm and hotspot, reads local metadata and
reviewed instruction shapes, and creates a new private replacement. Unknown or
ambiguous structures leave no output. It enforces a 32 MiB bound, DEX035/ODEX036,
method frames, instruction boundaries, GC-map invalidation and checksums.
The audio helper continues to require its reviewed native-library identities;
unknown audio is skipped independently. Runtime hooks require a 32-bit Dalvik
ABI with the checked native instruction shape, live Method layout, symbols and a
successful isolated dispatch/original/exception/GC/monitor self-test on that VM.
A whole-file libdvm hash is provenance only and no longer gates activation.
This supports recognized structures on new builds; it does not promise arbitrary
firmware compatibility. DiPO discovery installs a complete group or rolls it back.

Preparation defaults to bt, dipo, gpm, hotspot, audio and projection. route is an
alternative to bt for HUD-only work; they cannot share one plan. Unsupported
optional features are reported without discarding unrelated prepared features.
The permissions overlay preserves every original XML byte and metadata, adds only
authored declarations, and privately comments matching feature-removal directives.
No system-partition file, app_process, bootloader or MICOM/CAN state is written.
No persist.* property is set. Stock PhoneProjection owns its normal UI selection.

## Automatic installation and recovery

This separate NEMESIS package is explicitly installed with `nemesis install
/data/gen5w.kr.portable.zip`; copying the archive to a USB alone does not install
it. NEMESIS 1.16.7 or newer is required. Preserve the current rc.1q USB and its
recovery backups. Remove conflicting exact-build host/core/projection packages
through their owning recovery/uninstall procedures first; an existing authored
APK or AP owner is refused. Native NEMESIS extracts ZIP files as 0644; preinstall
sets executable modes only on verified script/helper members before copying. Do not use direct `pm install` on this HMG build:
NEMESIS must perform its guarded APK installation.

The package installs only authored APKs, prepares replacements privately under
/data, seals their original identities and the bundle hashes, then arms the
**next boot**. It does not restart the current Android session during installation.
Check `/data/local/gen5w-portable/plan-*/features.txt` for skipped capabilities.
The portable core APK is built from the authored source with its independent
boot receiver disabled; boot.sh is its sole startup owner. Portable status
selects the matching disable/uninstall explanation and retains completion after
an Android restart. Re-arming ignores old completion records. The standard APK
and deployed rc.1q artifacts are not overwritten.

On the next boot the supervisor waits until init has initially started zygote;
it does not launch Android ahead of the main class. One bounded transaction stops zygote, validates and mounts local
replacements, probes the local VM, sets ephemeral app wrappers, and starts zygote. The local init files supply the zygote onrestart service
list; its service restarts are preserved without editing init or executing its
arbitrary write directives. An ambiguous or changed profile is refused.
An independent native rescue process is armed before maintenance starts; worker
failure, timeout or supervisor death triggers retained recovery outside the
package directory. The normal session starts only after Android and current
DiPO hooks are ready. A pending attempt from a failed previous boot disables
further automatic attempts. Firmware/bundle/required-source drift is refused
before the framework is stopped; optional stock drift removes that feature row.
A capability rejection retains unrelated static features, removes wireless-only
bt/projection declarations, and reports `runtime-unavailable`; it does not claim
CarPlay works. An unchanged unsupported runtime is skipped on later boots until
explicit disable and re-arm, avoiding repeated application failures/restarts. IO/ownership
transaction failures trigger full owned rollback. The operation is intentionally
attempted once, without an automatic restart loop.

Automatic reapplication persists across reboots. To disable and restore:

```sh
/system/bin/sh /data/nemesis/apps/gen5w.kr.portable/boot.sh disable
/system/bin/sh /data/nemesis/apps/gen5w.kr.portable/boot.sh status
```

Disable records enabled=0 first, cancels pending startup, stops exclusively owned
services, and uses bounded maintenance to remove owned wrappers and mounts before
restarting Android. Foreign mounts/properties are retained and reported. If live
cleanup cannot complete, enabled=0 still prevents the next startup; reboot then
clears ephemeral mounts/wrappers. Reboot **without disabling** reapplies features.
Readiness after a restart requires a new system_server identity, live package
and activity services, and that ActivityManager's `mBooted=true` from `dumpsys
activity p`; the stale sys.boot_completed property alone is insufficient. This
readiness wait is outside the supervised framework-down window. Native NEMESIS
uninstall calls the same disable flow and waits for PackageManager readiness. Do not delete private /data
state or the retained recovery directory while a transaction may be running.

A session exit stops its owned services, marks the current boot degraded, and
retains automatic application for the next boot. It does not retry in that same
boot or restart Android while driving. Mounted code remains until explicit
disable or the next reboot. Report this degraded state and restore deliberately. Cold boot, quickboot and real wireless transport timing
still require the vehicle checks below.

## Screen controls and radio admission

The independent root UI service publishes bounded, fresh status and filtered logs
for the existing screen. Wireless off stops only the wireless host, preserving
HUD; switching on admits the radio only if restart evidence is clean. Timer,
Bluelink and Wi-Fi ADB are unknown/disabled because this package does not manage
those features. Screen restore/remove invokes only this package's disable flow;
NEMESIS owns the subsequent package uninstall. Diagnosis exports only bounded
status/log data to a verified FAT/fuse USB mount, never OEM files.

Installation prepares match mode for stock services and a system-UID private AP
restart guard. Before starting the driver, the authored adapter must durably
record an attempt and complete the stock sync command after its atomic rename;
failure prevents radio activation. An unfinished attempt,
including one with the same QuickBoot boot ID or an older success record, blocks
wireless on the next activation. Evidence is retained on disable. Only a match
marker created by this installation and still having its recorded inode/content
is removed. Foreign markers are retained.

Host readiness requires this boot's PID and process start time. The supervisor
waits for the broker socket before starting the host and watches its boot-service
parent. Host shutdown grants the relay's bounded 20-second AP cleanup queue
22 seconds before force-stop; disable waits for that cleanup before unmounting.
A stalled/failed worker cannot cause an automatic same-boot restart loop.

## One final vehicle visit

1. Restore the old installation through its owning recovery path. On healthy
   stock Android record `check.sh snapshot /data/g5p-before` from a fresh staged
   bundle. Keep the exact version, boot ID and timestamped logcat.
2. In the existing bounded maintenance flow, run `check.sh prepare-probe
   /data/g5p-probe`, `portable.sh plan /data/g5p-probe/manifest`, then with Android
   stopped `portable.sh apply` and `runtime.sh enable probe`. Restart Android and
   open DiPO. `check.sh probe-loaded` requires both the current native marker and
   actual ODEX inode mapping. Compare stock versus probe app-ready latency; the
   monotonic marker is library-load time alone. Reboot and compare with
   `check.sh restored /data/g5p-before`. These premise checks use identical ODEX
   bytes and a no-hook wrapper. They do not arm automatic startup.
3. Install the complete package through NEMESIS, inspect the feature report and
   `boot.sh status`, then cold boot. Record boot-to-CarPlay time, current overlay,
   runtime and session status, DiPO marker and logs. Verify wireless connection,
   expected Bluetooth disconnect handover, audio/navigation stability, actual HUD
   turn/distance/lane output and stock navigation ownership transitions. Test
   Android Auto/hotspot with their phone/UI if those capabilities are selected.
4. In the same visit test a normal ignition/quickboot reconnect and another cold
   boot. A healthy status is software readiness, not proof of a radio session or
   HUD receipt. Finally run explicit disable, reboot, and compare the baseline
   again. Re-arm only after recording all results; retaining the setup after a
   passing check is an explicit product choice, not inferred from a test marker.

Retain only diagnostics, hashes, feature reasons and timings in shareable reports.
Manufacturer ODEX/APK/native files generated under /data remain private and must
not be exported. The PC ARM VM proves dispatch, loader and stock class discovery
on the extracted V039 VM, with a PC ashmem substitute and dexopt disabled. It does
not prove Binder registration, mount propagation to real zygote, startup latency,
radio handover, normal ignition behavior or vehicle displays. Vehicle verification
is deliberately recorded separately in CANDIDATE.json.
