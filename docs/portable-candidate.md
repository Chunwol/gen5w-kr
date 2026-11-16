# Gen5W on-unit portability candidate

This is a separate, explicitly installed validation build. It preserves rc.1q. Manufacturer apps, ODEX files and libraries are read
from the vehicle during preparation and are not included in the candidate.

Runtime preflight waits for the initial Android framework to be ready before
running the native-supervised Dalvik test. The seal records the current boot ID
and all eight runtime artifact digests; it never reads the caller's console
stdin. Open-input and changed-artifact regressions cover this contract. The
framework-stopped transaction retains its independent 60-second recovery limit.
For an unreconciled stock boot, preparation runs while Android remains available.
The stopped transaction reuses it only when its boot ID and exact manifest agree;
apply still validates every source immediately before binding. Runtime prerequisite
checks share one fully validated overlay snapshot within the same invocation.

## Build and PC verification

Build `python tools/portable/build.py`. Build the independently authored Dalvik
engine with `python tools/portable/dalvik/build.py --java-home JDK --ndk NDK
--d8 D8_JAR --stock-system PRIVATE_SYSTEM --android-jar ANDROID_JAR
--output .build/portable/dalvik`. The private system is a local build input only.
Build the portable authored core/host variants with `python tools/portable/build_apps.py
--java-home JDK --output .build/portable/apps` (fresh output only).
Place dex-patch, dalvik/ and apps/ under one private input directory, then run
`python tools/portable/candidate.py --runtime --inputs INPUTS --output .build/portable/NEW`.
Build the optional regional audio helper with `python tools/audio/build_regions.py
--reference-lib PRIVATE_SYSTEM/lib --output NEW_AUDIO_BUILD --ndk NDK`. The private
build reference is the reviewed KR V039 baseline; no reference bytes are packaged.
Copy `audio-region-patch` into `INPUTS/audio/` before assembling a fresh candidate.
The candidate records `audio_compatibility=reviewed-elf-regions`. Failed audio
builds are refused. Whole-file reference digests establish recipe provenance at
build time, not runtime compatibility.

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
The portable regional audio helper checks the reviewed selector spans, ELF loader
mappings, constants/PLT/relocations and dependency loadable ABI regions. It accepts
unrelated selector-library code and nonloaded metadata differences; it does not
accept arbitrary decoder implementation changes. Legacy exact audio profiles
remain independent fallbacks; unknown audio is skipped independently. Runtime hooks require a 32-bit Dalvik
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

## Candidate admission and recovery

The user selected **persistent automatic wireless operation**. Installation arms
`mode=auto` for the next boot and clears the authored UI wireless hold. Existing
AP reset evidence and safety inhibits are preserved, not erased to force wireless.
A healthy marker is software readiness, never proof of vehicle safety.
`arm --trial` remains available as an optional, explicitly radio-held one-shot;
it is not the installation default.

Late failures: session exit (including exit 0 without explicit disable), loss of
the current DiPO/runtime view, and an orphaned session supervisor stop authored
services without restarting Android while driving. The session records the cause
in `health-lost`; the root controller then watches Android for 60 seconds. If
Android stays up and is not shutting down (`sys.powerctl` empty, zygote running),
automatic operation latches off (`session-ended-latched`) and re-arm is explicit
after inspection. If Android starts shutting down or power is cut first — the
expected ignition-off sequence may stop DiPO/host before power loss — operation
stays armed (`session-ended-at-shutdown`) and the start budget below bounds any
repeat. Whether this vehicle performs an Android shutdown at ignition off is
unverified.

Kernel reset evidence: the controller also checks bounded last_kmsg/ramoops panic
text and `ro.boot.bootreason`. The V039 kernel and boot image provide **none of
these** (no ram_console/ramoops backend, no bootreason on the cmdline), so on this
vehicle that check is harmless but detects nothing. Missing evidence never proves
a clean shutdown; the start budget is the actual bound.

Android dropbox evidence: on each new boot, entry names in `/data/system/dropbox`
are compared with those recorded at arm/last admitted boot (wall-clock timestamps
are not trusted). A new `system_server_crash` or `system_server_watchdog`, or a new
tombstone/app crash/ANR whose first 64 KiB names a patched process (DiPO,
projection sink, iAP2 server, HKMC WifiSettings), latches operation off before
maintenance (`dropbox-failure-evidence`). Unrelated app crashes and history do
not. `SYSTEM_RESTART` is excluded because our own maintenance restarts the
runtime. Compressed entries are read with the unit's `gzip -d -c`; a stock DiPO
crash unrelated to the patch also latches (conservative). A hard reset may leave
no dropbox entry, so this complements, not replaces, the start budget. Real
vehicle dropbox naming/compression remains unverified.

At most three full-runtime activations are allowed without five minutes of
observed live session/framework/DiPO readiness. A fourth is blocked *before*
maintenance, even if every prior attempt briefly reached healthy and left no
panic report. Continuous stability resets this budget; a tiny healthy window
does not. Three short normal trips/restarts can also exhaust it: this is a
conservative circuit breaker, not perfect reset attribution. Unknown late resets
with no surviving evidence remain a limitation, especially after the stable window.

NEMESIS 1.16.7 or newer must install the authored APKs with its HMG install guard.
Do not use direct `pm install`. Old package ownership must be resolved through its
own uninstall/recovery procedure. Preserve deployed rc.1q USB and backups. Only
private /data replacements and ephemeral bind mounts/app wrappers are used; there
is no OEM/system-partition replacement or OEM dexopt. Authored engine/adapter jars
**can be dexopted on the vehicle**; the PC VM uses `-Xdexopt:none` and cannot prove
that path, startup delay or memory pressure.

The bounded maintenance worker has its own session and an independent native
rescue process, retained outside the deletable package. It stops zygote, changes
the owned view, restarts the local init zygote restart-dependencies (such as media
and netd), then starts zygote. Worker failure, deadline or supervisor death invokes
rescue. `framework.sh ready` supervises stalled Binder/dumpsys queries (15 seconds);
wait loops additionally use monotonic deadlines. Stage times are appended to
`/data/local/gen5w-portable/boot/timeline`. Initial zygote observation allows
90 seconds; initial and restarted framework readiness allow 300 seconds each
(stock ARM VM restart measured 152 seconds). Maintenance itself allows 60 seconds.
These are
separate phases, so 60 seconds is not a total boot-to-ready promise.

Disable records enabled=0 first, waits for exclusively owned session/AP cleanup,
then restores owned wrappers/mounts under supervised maintenance. Foreign state
is preserved and reported. If live restore fails, cold boot clears ephemeral
mounts/wrappers and enabled=0 prevents reapplication. Never delete retained state,
recovery or runtime-payload directories during a transaction. Native uninstall
may ignore a failed preun hook, so wrappers never reference its deletable package.

The root UI retains restore/remove completion across Activity loss. Wireless off
stops the authored host while retaining HUD services. Both authored radio request
paths must durably record attempts before requests; a failed sync or 8-second
flush deadline prevents the request. An unfinished attempt blocks subsequent
wireless activation. AP prepare requires `wifi_ap_on` to read exactly 0; an on,
unknown, null or failed value is a STOP, not permission to guess. OEM boot-time
AP restoration and local hotspot UI are outside those authored request guards.
Do not exercise the separate local-hotspot menu during CarPlay validation.

## One vehicle visit: exact admission sequence

All stages are parked; do not drive while testing framework restarts. Keep stable
vehicle power according to the vehicle service procedure. A stage failure stops
later stages. Preserve the old recovery USB and reports. The new package adds a
root `rescue-watch.sh` restart service which checks all six fixed NEMESIS USB
mount roots every two seconds. It reads only `GEN5W-PORTABLE-RESCUE` containing
exactly `disable-portable-v1` (one line, LF or CRLF); it executes no code from
the USB. Beware Windows hiding a `.txt` extension: the file name must have no
extension. It persists a rescue interlock and enabled=0 *before* Android cleanup
or any lock. It does not rely on NEMESIS USB execute, Manager dialog,
sys.boot_completed or ADB. Boot admission and the pre-apply worker also check the
interlock/token. Automatic (`mode=auto`) maintenance additionally requires the
watcher to be listed as running by `nemesis service list`; otherwise that boot
stays stock with reason `rescue-watch-unavailable` (not a permanent latch).

This is **not independent of Android**: it requires a live kernel, the NEMESIS
root service manager, and a USB that the framework has already mounted. NEMESIS
USB execute is no alternative: on 1.16.7 it needs the Manager dialog once
`sys.boot_completed=1`, which a late failure never resets. USB host modules load
after the boot controller starts, so a token present at power-on is normally seen
only after the framework mounts the stick: one hooked startup can still occur in
that boot, and the next boot stays stock. It cannot execute during a kernel freeze
or recover corrupted /data, a dead root daemon, or broken USB storage drivers.
Real vehicle USB visibility/timing remains unverified.
A retained full disable controller survives deletion of the package directory,
but retained files are not an independent init service by themselves.
Never substitute an ignition cycle for a verified cold boot.

### 0. Before changing the target

Use a wired root shell that stays available when zygote stops. Verify the actual
ADB serial/model is this vehicle (never run against a generic selected target).
The following are instructions for the operator, not commands run by the PC build.
On the PC, replace SERIAL and NEW-CANDIDATE with recorded exact values:

```sh
adb -s SERIAL shell id
adb -s SERIAL shell getprop ro.build.fingerprint
adb -s SERIAL shell /system/xbin/nemesis version
adb -s SERIAL shell /system/xbin/nemesis pkg-list
adb -s SERIAL shell pm path kr.gen5w.core
adb -s SERIAL shell pm path kr.gen5w.wirelesshost
```

STOP unless uid=0, a healthy stock session, no conflicting packages/apps/AP owner,
and NEMESIS >=1.16.7 are verified. An old note saying 1.16.3 is not a fresh version
check. If an update is needed, finish the documented official NEMESIS update and
reboot separately; do not mix it with this trial. If wired root access or an
unambiguous cold restart cannot be established, collect diagnostics only.

Record `/proc/sys/kernel/random/boot_id`, `/proc/uptime`, system_server and session
PIDs before/after one ordinary ignition cycle, and before/after `reboot`. Confirm
which operation changes boot_id and which preserves it. If the device suspends,
record that rather than calling it QuickBoot. Keep the phone's wireless CarPlay,
Wi-Fi and Bluetooth off initially.

Stage the audited authored directory and the exact ZIP using this controlled name:

```sh
adb -s SERIAL shell mkdir /data/local/gen5w-stage
adb -s SERIAL shell chown 0:0 /data/local/gen5w-stage
adb -s SERIAL shell chmod 700 /data/local/gen5w-stage
adb -s SERIAL push NEW-CANDIDATE/. /data/local/gen5w-stage/
adb -s SERIAL push FINAL-ZIP /data/gen5w.kr.portable.zip
```

Require a fresh staging directory and root-owned, non-writable ancestors before
pushing. A failed mkdir (existing directory) is a STOP; do not reuse it blindly.
Inside the root shell, confirm the directory really contains the named files:

```sh
B=/data/local/gen5w-stage
ls "$B/boot.sh" "$B/check.sh" "$B/SHA256SUMS"
chmod 755 "$B"/*.sh "$B"/bin/*
"$B/bin/dex-patch" sha256 /data/gen5w.kr.portable.zip
```

Compare the printed ZIP digest with the PC receipt. The supervised probe's arm
also verifies every staged member against SHA256SUMS. Do not infer provenance
from the filename. A fresh `/data/g5p-before` and `/data/g5p-probe` are required;
never overwrite an old baseline.

### 1. Stock baseline and diagnostics

```sh
/system/bin/sh "$B/check.sh" snapshot /data/g5p-before
settings get global wifi_ap_on
cat /proc/sys/kernel/random/boot_id
cat /proc/uptime
```

STOP before activation unless wifi_ap_on is exactly 0. Do not blindly overwrite a
stock setting. Turn stock hotspot off through its UI if needed, investigate null
or failed reads and take a new baseline after any intentional stock change.
Record stock wired CarPlay latency, audio, navigation, HUD, camera behavior,
`/proc/meminfo`, `dumpsys meminfo com.daudio.app.dipo`, dmesg, logcat and LMK events.
Preserve `/data/system/dropbox/logcat.txt*`, `/storage/log/*` and `/proc/last_kmsg`
(if present) privately on the PC before they rotate. Record missing logs as missing;
absence does not establish absence of resets. Do not export OEM code/data.

### 2. Supervised identical-ODEX / no-hook premise trial

```sh
/system/bin/sh "$B/check.sh" prepare-probe /data/g5p-probe
/system/bin/sh "$B/boot.sh" probe /data/g5p-probe/manifest > /data/g5p-probe.log 2>&1
/system/bin/sh "$B/boot.sh" status
/system/bin/sh "$B/check.sh" probe-loaded
```

This is a state-changing trial, not read-only diagnostics. Only a single byte-
identical DiPO ODEX row is allowed. It retains accessible payload and rescue,
sets a no-hook wrapper, restarts Android with its service dependencies, launches
DiPO and checks the native marker plus active copy dev:ino in DiPO's namespace.
PASS requires reason `probe-ready-one-shot`, actual wired projection and normal
stock behavior. Compare latency, but do not extrapolate no-hook speed to full
`-Xint`/adapter operation. On any error preserve /data/g5p-probe.log and timeline.

```sh
/system/bin/sh "$B/boot.sh" disable
reboot
```

After verified new boot_id, run `check.sh restored /data/g5p-before`. PASS requires
stock bytes/properties, normalized wifi_ap_on and absence of newly retained target
mounts. Interface/module/profile differences are reported for review, not ignored.
If Android does not return, use the recovery rules below; do not continue.

### 3. Install automatic wireless operation

```sh
/system/xbin/nemesis install /data/gen5w.kr.portable.zip
B=/data/nemesis/apps/gen5w.kr.portable
/system/bin/sh "$B/boot.sh" status
```

Require install exit 0, mode|auto, enabled|1 and armed-next-boot. No authored
wireless hold should remain. Inspect the locally prepared plan and optional skips.
Installation does not restart this Android session; do a verified cold restart.
Require current-boot healthy and committed overlays/runtime, then test wireless
CarPlay directly: connection, BT handover, audio, HUD, navigation and camera.
Record timing, memory, kernel/application logs and unexpected restarts. Test
ordinary ignition reconnection separately from an actual cold restart.

### 4. Prove the USB rescue path during the same parked visit

Put a root file named `GEN5W-PORTABLE-RESCUE` on the rescue USB containing:

```text
disable-portable-v1
```

Insert it. No confirmation on the Android screen is needed by the package's
root watcher. The first poll disables automatic operation; active restoration
can take considerably longer (session cleanup, maintenance and framework ready).
Read `/data/local/gen5w-portable/boot/rescue-result`: `restore-required` means
completion is not proven; `restored` means the disable controller succeeded.
If live restore cannot finish, leave the token present, perform the verified cold
restart, and let the watcher retry. Confirm enabled=0 and run the original
`check.sh restored /data/g5p-before` comparison. Do not call a restored file alone
proof of hardware functionality; confirm stock camera/audio/navigation too.

Only after removing the token, a deliberate disable/re-arm selects auto again:

```sh
/system/bin/sh "$B/boot.sh" disable
/system/bin/sh "$B/boot.sh" arm /data/local/gen5w-portable/plan-EXACT/manifest
```

Use the actual recorded plan. AP evidence requires its separate reviewed rearm
procedure; none of these operations deletes reset evidence automatically.

## Stop and recovery

- After any unexpected reset, read `settings get global wifi_ap_on` first; if not
  exactly 0, preserve evidence and stop. A disabled authored host alone does not prove
  OEM AP boot restoration cannot occur.
- Any unexpected reset, repeating crash, abnormal camera/audio/navigation, memory
  pressure or unresponsive screen beyond measured bounds: stop, turn phone radios
  off, preserve evidence, do not re-arm.
- If root shell works, run `boot.sh disable`. If it hangs/fails, set the minimal
  next-boot switch with `echo 0 > /data/local/gen5w-portable/boot/enabled`, then
  `sync` and the verified cold restart. This prevents reapply, not immediate
  unmount. Never live-unmount mapped code by hand.
- If screen works but shell does not, use this package's screen restore/remove.
- If screen and ADB do not work, insert the prepared rescue-token USB. The
  independent root watcher disables auto before attempting restoration. If the
  kernel is frozen, keep the token present through a verified cold restart.
  If NEMESIS/USB cannot run either, software recovery is not guaranteed: use the
  unit service recovery procedure rather than assuming a token was consumed.
- A current maintenance marker refuses new arm/run/activate while independent
  rescue may still own the view. An unfinished attempt from this same boot
  requires a verified cold restart before re-arm. Never invoke internal
  transact/recover commands directly; they require native supervision.
- Never remove guard evidence to bypass a reset. After disable, `ap.sh classify`
  reports an inventory/token (77 means retained records). Review the exact files,
  kernel/persistent logs and timeline. Only for a demonstrated clean interruption,
  `ap.sh rearm TOKEN reviewed-no-reset` archives exact records before removal.
  Panic mtime is an unreliable RTC wall-clock ordering hint, never proof of age.
  Judge dump contents, boot identifiers and persistent logs.
  Existing unrelated panic files require `reviewed-panic-unrelated`; apparently newer
  panic evidence, inventory drift, live owners or unsafe paths refuse rearm.
  Missing logs alone are not proof. Inspect the reported archive before re-arming.

If disable reports `startup still busy`, auto-start is already off; wait for the
  existing bounded recovery/readiness (up to 60+300 seconds) and re-read status. Do
not start a competing restore. The wireless-off flag is shared with rc.1q and is
retained: restoring that older package may leave its wireless intentionally off;
review and change that preference only after clean restoration.

Uninstall can retain `/data/local/gen5w-portable` (including private OEM-derived
plan files), runtime payload/rescue, guard evidence, authored jar dex caches and
DiPO readiness/cache files. These are not shipped or automatically exported.
Retain them until restoration and incident evidence are resolved.

PC/qemu tests do not establish real Binder/SMP timing, mount propagation, dexopt,
actual radio/suspend behavior, latency, memory safety under vehicle load or display
receipt. Vehicle verification remains false in CANDIDATE.json until separately
recorded target evidence exists.


## Recovery changes (2026-11-14)

An Android service-start client timeout is not proof that ActivityManager rejected
the request. Full runtime startup still requires the current-boot live DiPO
process and loaded hook marker within 180 seconds; an unconfirmed request without
that evidence disables operation and restores stock. Client completion alone
never marks the package healthy.

The app-marker observation is independently guarded for eight seconds and does
not repeatedly hash every overlay while waiting for a cold app process. The
full overlay/runtime validation still gates session startup and commit, and
continues during session health monitoring.

First session startup may optimize the three authored helper classpaths. It has
a separate 90-second allowance; Android start commands are supervised for 30
seconds. Cancellation is checked between startup steps. Restoration waits for
the owned startup/cleanup worker to exit (up to 120 seconds), and failed cleanup
retains its ownership journal for explicit retry. Cleanup service commands have
10-second guards, with the existing 22-second AP drain retained.

Session lock ownership is published with the lock so a killed worker cannot leave
an ownerless lock that blocks every later start. Live and concurrent owners remain
exclusive. USB updates complete read-only preflight before stopping owned apps or
changing the old preuninstall hook; failure restores the old hook only while the
temporary replacement is still ours. A newly installed hook is preserved.
Adapter installation remains provisional until the readiness marker is published.
Failure rolls back only this attempt's group. A failed rollback retains ownership
and requires process restart; it never reports a clean uninstalled state.

Read-only runtime preflight retires its previous proof before observing Android.
A transient readiness failure returns75 and gets a30-second retry budget before
framework maintenance. The final individual readiness/ABI call has its own
15/20-second bounds, so this is not a30-second total boot deadline. ABI rejection
still returns77; seal and other failures remain fatal. No stopped-framework
transaction deadline is extended by these read-only retries.
