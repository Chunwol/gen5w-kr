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

## Candidate admission and recovery

This candidate is for a guarded first vehicle visit. Installation arms a **one-shot
next-boot trial with wireless off**, not permanent automatic activation. The trial
is durably consumed before any framework stop. A same-id resume with lost wrappers/mounts also cannot repeat activation; any
remaining owned partial view is restored under the retained supervisor. If that
restore fails, stop using the unit and require a true cold restart. After any later cold boot it backs
off with `trial-consumed`, even if the first boot reached `healthy` and a reset
happened much later. Do not change it to automatic mode before target validation.
A successful trial marker is software readiness, never a vehicle safety approval.

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
rescue. `framework.sh ready` supervises stalled Binder/dumpsys queries (8 seconds);
wait loops additionally use monotonic deadlines. Stage times are appended to
`/data/local/gen5w-portable/boot/timeline`. Initial zygote observation and framework
readiness allow 90 seconds each; maintenance itself allows 60 seconds. These are
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
Do not enable local hotspot during the staged trial.

## One vehicle visit: exact admission sequence

All stages are parked; do not drive while testing framework restarts. Keep stable
vehicle power according to the vehicle service procedure. A stage failure stops
later stages. Retain the old recovery USB separately, but **it does not recover
this portable package**. No screen/ADB-independent rescue for a permanently armed
late-reset loop is claimed; this candidate avoids repeat trials using one-shot
admission. Never substitute an ignition cycle for a verified cold boot.

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

### 3. Install one-shot full-runtime trial, wireless held off

```sh
/system/xbin/nemesis install /data/gen5w.kr.portable.zip
ls /data/nemesis/apps/gen5w.kr.portable/boot.sh
B=/data/nemesis/apps/gen5w.kr.portable
/system/bin/sh "$B/boot.sh" status
ls /data/nemesis/gen5wkr.ui-wireless-off
```

Confirm the real NEMESIS installation directory; if it differs, correct B before
continuing. Require install exit 0, `mode|trial`, `enabled|1`, `armed` in the current
boot and the wireless-off flag. Inspect the new plan's features.txt, not an older
plan: bt, dipo and projection must be prepared for the intended runtime trial;
record optional skips explicitly. Installation does not stop this Android session.
Then perform the verified cold boot. Require `healthy`, `startup-healthy`, committed
overlay/runtime and a running session with this boot/PID's DiPO readiness marker.

With the authored host off, connect phone Bluetooth only and observe driver/interface
state. STOP if an unexpected AP/driver starts: stock autonomous entry is not proven
blocked. Verify wired CarPlay/audio/navigation/HUD/camera and observe at least ten
minutes without reset, crash or LMK churn. Record full-mode PSS, free memory and
startup delay; `-Xint` affects the whole wrapped app and increases possible CPU/RAM
cost compared with zygote fork. A healthy marker alone does not satisfy this stage.

### 4. Explicit wireless admission

Only after stage 3 succeeds, while parked:

```sh
rm /data/nemesis/gen5wkr.ui-wireless-off
```

Enable phone wireless CarPlay; observe actual session and expected BT handover,
audio/navigation, HUD turns/distances/lanes and stock navigation ownership changes.
Observe at least fifteen minutes. Wait >=60 seconds after AP start and verify no
unfinished guard attempt remains **before** any ignition or cold reboot. Require:

```sh
/system/bin/sh "$B/ap.sh" status
settings get global wifi_ap_on
```

The outputs must be `ap|admitted` and exactly `0`; otherwise STOP and preserve
evidence. Record
boot-to-CarPlay time, kernel log, radio state and memory. The 45-second AP settling
window is a guard heuristic, not proof that hardware cannot reset later.

### 5. Reconnection, restore and final disposition

An ordinary ignition resume can be tested in the same trial only when boot_id is
unchanged. If it is a cold boot the trial is consumed and must stay stock. This is
expected protection, not a reconnect PASS. After a passed trial, disable/restore,
record all results, and explicitly arm another trial for a second cold boot:

```sh
/system/bin/sh "$B/boot.sh" disable
/system/bin/sh "$B/boot.sh" arm --trial /data/local/gen5w-portable/plan-EXACT/manifest
reboot
```

Every `arm --trial` recreates the wireless-off hold. Verify
`ls /data/nemesis/gen5wkr.ui-wireless-off` before restarting; STOP if absent.
Replace plan-EXACT with the recorded new plan, not a glob. Re-open wireless only
after confirming admission state, and repeat the actual projection/HUD/restore
checks. Finally disable, cold boot and run the original `check.sh restored`
baseline comparison. Failure at any point leaves automatic operation disabled.

Permanent boot-time CarPlay is the final product setting. **Only after the full
vehicle checklist passes**, explicitly disable and `boot.sh arm MANIFEST` without
--trial, then cold boot and verify it. Reboot now reapplies features; restoration
requires `boot.sh disable` (or screen restore). Automatic mode still backs off on
unfinished startup/AP evidence, but a late reset after healthy/AP guard clearance
has no guaranteed ADB-independent escape. Do not promote if this residual risk is
unacceptable or if root access/recovery was not proven. Keep the one-shot result
and permanent-mode validation distinct in the report.

## Stop and recovery

- After any unexpected reset, read `settings get global wifi_ap_on` first; if not
  exactly 0, preserve evidence and stop. A consumed trial alone does not prove
  OEM AP boot restoration cannot occur.
- Any unexpected reset, repeating crash, abnormal camera/audio/navigation, memory
  pressure or unresponsive screen beyond measured bounds: stop, turn phone radios
  off, preserve evidence, do not re-arm.
- If root shell works, run `boot.sh disable`. If it hangs/fails, set the minimal
  next-boot switch with `echo 0 > /data/local/gen5w-portable/boot/enabled`, then
  `sync` and the verified cold restart. This prevents reapply, not immediate
  unmount. Never live-unmount mapped code by hand.
- If screen works but shell does not, use this package's screen restore/remove.
- If neither works, wait for maintenance rescue. A cold restart clears the trial's
  ephemeral changes and its consumed marker prevents repetition. Normal ignition
  without a changed boot_id may not do this. If a true cold restart is unavailable,
  do not claim recovery; stop using the unit and use its service recovery process.
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
existing bounded recovery/readiness (up to 60+90 seconds) and re-read status. Do
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
