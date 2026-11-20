#!/bin/bash
# Startup control runs against real private files; only Android/NEMESIS are boundaries.
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/g5p-boot.XXXXXX)
cleanup() {
    # An assertion failure must not leave a modeled session spinning forever.
    [ ! -d "$t/actions" ] || touch "$t/actions/session-stop"
    for owned_job in $(jobs -pr); do kill "$owned_job" 2>/dev/null || :; done
    wait 2>/dev/null || :
    rm -rf "$t"
}
trap 'rc=$?; cleanup; exit $rc' EXIT
if [ "${PORTABLE_BOOT_DEBUG:-0}" = 1 ]; then
 trap 'rc=$?; if [ "$rc" != 0 ]; then find "$t/actions" -name "*.log" -exec tail -n 20 {} \;; [ ! -f "$t/root/data/local/gen5w-portable/boot/timeline" ] || tail -n 30 "$t/root/data/local/gen5w-portable/boot/timeline"; fi; cleanup' EXIT
fi
mkdir -p "$t/root/data/bundle/bin" "$t/root/data/plan" "$t/root/system/app" "$t/actions"
cp tools/portable/boot.sh tools/portable/rescue.sh tools/portable/rescue-watch.sh tools/portable/runtime.sh tools/portable/overlay.sh tools/portable/framework.sh tools/portable/portable.sh tools/portable/ap.sh tools/portable/session.sh tools/portable/wrap-*.sh "$t/root/data/bundle/"
mkdir "$t/root/data/bundle/dalvik"
for name in engine.jar adapter.jar libgen5whook.so hook-vm-test.jar; do echo authored > "$t/root/data/bundle/dalvik/$name"; done
sed -i '1c#!/usr/bin/mksh' "$t/root/data/bundle/boot.sh" "$t/root/data/bundle/rescue.sh"
chmod +x "$t/root/data/bundle/boot.sh" "$t/root/data/bundle/rescue.sh"
printf stock > "$t/root/system/app/Iap2ServerApp.odex"
printf replacement > "$t/root/data/plan/replacement"
echo "$(sha256sum "$t/root/system/app/Iap2ServerApp.odex" | cut -d' ' -f1)" > "$t/root/data/plan/replacement.stock"
hash=$(sha256sum "$t/root/data/plan/replacement" | cut -d' ' -f1)
echo "bt|/data/plan/replacement|/system/app/Iap2ServerApp.odex|$hash|0|0|644|static" > "$t/root/data/plan/manifest"
echo 'projection|/data/plan/xml|/system/etc/permissions|ignored|0|0|755|directory' >> "$t/root/data/plan/manifest"
# Use the production native digest instead of starting Python for every tiny
# fixture file; metadata alone is an Android/root-ownership boundary.
cat > "$t/helper" <<'SH'
#!/bin/sh
case "$1" in
sha256) exec "$PORTABLE_TEST_SUPERVISOR" "$@";;
metadata) echo '0|0|644';;
*) exit 1;;
esac
SH
chmod +x "$t/helper"
cp .build/portable/dex-patch-host "$t/root/data/bundle/bin/dex-patch"
cat > "$t/adapter" <<'SH'
#!/bin/bash
set -e
case "$1" in
boot) cat "$ACTIONS/boot";;
rescue-requested)
 if [ -f "$ACTIONS/rescue-usb-late" ]; then n=$(cat "$ACTIONS/rescue-calls" 2>/dev/null || echo 0); echo $((n+1)) > "$ACTIONS/rescue-calls"; [ "$n" -ge 1 ]
 else test -f "$ACTIONS/rescue-usb"; fi;;
ap-prepare|ap-disable) :;;
ap-check) [ ! -f "$ACTIONS/ap-unsafe" ] || exit 77;;
owned-overlays) test -f "$ACTIONS/owned-overlays";;
dependencies) echo media; echo netd;;
framework) cat "$ACTIONS/framework";;
plan-ready) test -f "$ACTIONS/plan-ready" && cmp -s "$ACTIONS/plan-ready" "$ACTIONS/boot";;
framework-ready)
 test "$(cat "$ACTIONS/healthy")" = 1 && test ! -f "$ACTIONS/framework-notready" || exit 1
 if [ -f "$ACTIONS/slow-framework-after-start" ]; then
  before=$(cat "$ACTIONS/slow-framework-after-start")
  current=$(grep -cx start "$ACTIONS/log" 2>/dev/null || :)
  if [ "$current" -gt "$before" ]; then
   polls=$(cat "$ACTIONS/slow-framework-polls" 2>/dev/null || echo 0)
   polls=$((polls+1)); echo "$polls" > "$ACTIONS/slow-framework-polls"
   [ "$polls" -ge 100 ] || exit 1
  fi
 fi
 if [ -f "$ACTIONS/framework-notready-after-restart" ]; then
  before=$(cat "$ACTIONS/framework-notready-after-restart")
  current=$(grep -cx start "$ACTIONS/log" 2>/dev/null || :)
  [ "$current" -le "$before" ] || exit 1
 fi;;
get) case "$2" in init.svc.zygote) cat "$ACTIONS/zygote";; sys.boot_completed) cat "$ACTIONS/healthy";; sys.powerctl) cat "$ACTIONS/powerctl" 2>/dev/null || :;; esac;;
rescue-alive) test ! -f "$ACTIONS/rescue-dead";;
plan|plan-boot|plan-static|apply|runtime-enable|runtime-preflight|runtime-probe|runtime-disable|overlay-disable|commit|commit-static|launch-dipo|session-stop)
 [ "$1" != runtime-enable ] || [ ! -f "$ACTIONS/unsupported" ] || exit 77
 echo "$1" >> "$ACTIONS/log"
 if [ "$1" = apply ] && [ -f "$ACTIONS/hold.before-apply" ]; then touch "$ACTIONS/preapply-window"; sleep 1; fi
 if [ "$1" = runtime-probe ] && [ -f "$ACTIONS/hang.runtime-probe" ]; then touch "$ACTIONS/probe-window"; sleep 30; fi
 [ ! -f "$ACTIONS/fail.$1" ] || exit 1
 case "$1" in plan|plan-boot|plan-static) cp "$ACTIONS/boot" "$ACTIONS/plan-ready";; session-stop) touch "$ACTIONS/session-stop";; apply) touch "$ACTIONS/dirty";; overlay-disable) rm -f "$ACTIONS/dirty" "$ACTIONS/plan-ready";; esac;;
stop-android) echo stop >> "$ACTIONS/log"; echo stopped > "$ACTIONS/zygote";;
start-android) echo start >> "$ACTIONS/log"; echo running > "$ACTIONS/zygote"; echo 1 > "$ACTIONS/healthy"; [ ! -f "$ACTIONS/hold-boot" ] || echo 0 > "$ACTIONS/healthy";;
dipo-ready|probe-ready)
 if [ "$1" = dipo-ready ] && [ -f "$ACTIONS/slow-dipo-polls" ]; then
  polls=$(cat "$ACTIONS/slow-dipo-polls"); polls=$((polls+1)); echo "$polls" > "$ACTIONS/slow-dipo-polls"
  [ "$polls" -ge 35 ] || exit 1
 fi
 test ! -f "$ACTIONS/fail.dipo";;
busy) test -f "$ACTIONS/session-live";;
dirty) test -f "$ACTIONS/dirty";;
active) test -f "$ACTIONS/active";;
session)
 rm -f "$ACTIONS/session-stop"
 touch "$ACTIONS/session-live"
 while [ ! -f "$ACTIONS/session-stop" ]; do
   if [ -f "$ACTIONS/session-exit-code" ]; then code=$(cat "$ACTIONS/session-exit-code"); rm "$ACTIONS/session-live"; exit "$code"; fi
   sleep .05
 done
 rm "$ACTIONS/session-live";;
session-ready)
 if [ -f "$ACTIONS/slow-session-polls" ]; then
  polls=$(cat "$ACTIONS/slow-session-polls"); polls=$((polls+1)); echo "$polls" > "$ACTIONS/slow-session-polls"
  [ "$polls" -ge 20 ] || exit 1
 fi
 test -f "$ACTIONS/session-live";;
pause) if [ -f "$ACTIONS/long-pause" ]; then sleep .05; else sleep .02; fi;;
*) exit 1;;
esac
SH
chmod +x "$t/adapter"
export ACTIONS=$t/actions PORTABLE_TEST_ROOT=$t/root PORTABLE_TEST_BOOT_ADAPTER=$t/adapter PORTABLE_TEST_HELPER=$t/helper
export PORTABLE_TEST_SUPERVISOR=$PWD/.build/portable/dex-patch-host
export PORTABLE_BOOT_TIMEOUT=3 PORTABLE_TEST_STABLE_SECONDS=0 PORTABLE_TEST_LOSS_GRACE=1
(cd "$t/root/data/bundle" && find . -type f ! -name SHA256SUMS -print | sort | while read -r file; do sha256sum "${file#./}"; done) > "$t/root/data/bundle/SHA256SUMS"
boot() { mksh "$t/root/data/bundle/boot.sh" "$@"; }
echo 100:1 > "$ACTIONS/framework"
echo boot1 > "$ACTIONS/boot"; echo running > "$ACTIONS/zygote"; echo 1 > "$ACTIONS/healthy"
boot arm /data/plan/manifest
boot run
[ ! -f "$ACTIONS/log" ] || ! grep -qx stop "$ACTIONS/log"
old_stop=$(grep -cx stop "$ACTIONS/log" || :)
boot disable
[ "$(grep -cx stop "$ACTIONS/log" || :)" = "$old_stop" ]
boot arm /data/plan/manifest
echo boot2 > "$ACTIONS/boot"
# Binder may accept startService before the bounded am client returns. The
# current-boot, live hooked-process marker must decide readiness independently.
touch "$ACTIONS/fail.launch-dipo"
echo 0 > "$ACTIONS/slow-session-polls"
echo 0 > "$ACTIONS/slow-dipo-polls"
grep -cx start "$ACTIONS/log" > "$ACTIONS/slow-framework-after-start" || :
echo 0 > "$ACTIONS/healthy"
mksh "$t/root/data/bundle/boot.sh" run & runner=$!
for unused in $(seq 1 1500); do grep -q '|runtime-preflight-wait$' "$t/root/data/local/gen5w-portable/boot/timeline" 2>/dev/null && break; sleep .02; done
grep -q '|runtime-preflight-wait$' "$t/root/data/local/gen5w-portable/boot/timeline"
! grep -qx runtime-preflight "$ACTIONS/log"
echo 1 > "$ACTIONS/healthy"
for unused in $(seq 1 3000); do grep -q 'healthy' "$t/root/data/local/gen5w-portable/boot/attempt" 2>/dev/null && break; sleep .02; done
grep -q healthy "$t/root/data/local/gen5w-portable/boot/attempt"
grep -q '|dipo-start-request-unconfirmed$' "$t/root/data/local/gen5w-portable/boot/timeline"
rm "$ACTIONS/fail.launch-dipo"
[ "$(cat "$ACTIONS/slow-session-polls")" -ge 20 ]
rm "$ACTIONS/slow-session-polls"
[ "$(cat "$ACTIONS/slow-dipo-polls")" -ge 35 ]
rm "$ACTIONS/slow-dipo-polls"
[ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 1 ]
[ "$(grep -cx stop "$ACTIONS/log")" = 1 ]
timeline=$t/root/data/local/gen5w-portable/boot/timeline
for marker in runtime-preflight-wait framework-initial-ready runtime-preflight overlay-prepared-running framework-stopped identity-verified overlay-planned overlay-applied runtime-retired runtime-selected framework-start framework-running; do
 grep -q "|$marker$" "$timeline" || { echo "FAIL missing transaction stage $marker"; exit 1; }
done
boot disable
wait "$runner"
test "$(cat "$ACTIONS/slow-framework-polls")" -ge 100
rm "$ACTIONS/slow-framework-after-start" "$ACTIONS/slow-framework-polls"
[ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 0 ]
[ "$(cat "$ACTIONS/zygote")" = running ]
[ ! -f "$ACTIONS/session-live" ]
# Interrupted startup disables the next boot without stopping stock Android.
boot arm /data/plan/manifest
echo 'boot2|pending' > "$t/root/data/local/gen5w-portable/boot/attempt"
echo boot3 > "$ACTIONS/boot"
old=$(grep -cx stop "$ACTIONS/log")
if boot run; then echo 'FAIL accepted incomplete prior startup'; exit 1; fi
[ "$(grep -cx stop "$ACTIONS/log")" = "$old" ]
[ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 0 ]
# Firmware drift is refused before Android is stopped.
boot arm /data/plan/manifest
printf new-firmware > "$t/root/system/app/Iap2ServerApp.odex"
echo boot4 > "$ACTIONS/boot"
if boot run; then echo 'FAIL applied obsolete prepared bytes'; exit 1; fi
[ "$(grep -cx stop "$ACTIONS/log")" = "$old" ]
printf stock > "$t/root/system/app/Iap2ServerApp.odex"
boot arm /data/plan/manifest
touch "$ACTIONS/fail.runtime-enable"
echo boot5 > "$ACTIONS/boot"
if boot run; then echo 'FAIL accepted runtime activation failure'; exit 1; fi
[ "$(cat "$ACTIONS/zygote")" = running ]
[ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 0 ]
grep -qx runtime-disable "$ACTIONS/log"; grep -qx overlay-disable "$ACTIONS/log"
echo 'PASS automatic boot: deferred install, one activation, owned session, explicit disable, interrupted boot, firmware drift and rollback'

# An unsupported optional VM leaves independently validated overlays active.
rm "$ACTIONS/fail.runtime-enable"
echo boot5-cold-after-failure > "$ACTIONS/boot"
touch "$ACTIONS/unsupported"
rm -f "$ACTIONS/session-stop"
boot arm /data/plan/manifest
echo boot6 > "$ACTIONS/boot"
old_restore=$(grep -cx overlay-disable "$ACTIONS/log")
boot run
[ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 1 ]
grep -qx runtime-unavailable "$t/root/data/local/gen5w-portable/boot/reason"
[ "$(grep -cx overlay-disable "$ACTIONS/log")" = "$((old_restore+1))" ]
grep -qx commit-static "$ACTIONS/log"
[ ! -f "$ACTIONS/session-live" ]
old_runtime=$(grep -cx runtime-enable "$ACTIONS/log")
echo boot6b > "$ACTIONS/boot"
boot run
[ "$(grep -cx runtime-enable "$ACTIONS/log")" = "$old_runtime" ]
boot disable
[ ! -s "$t/root/data/local/gen5w-portable/boot/boot-manifest" ]
echo 'PASS unsupported runtime removes wireless-only declarations without starting an owner'

# A structurally unknown app cannot hold unrelated features hostage.
rm "$ACTIONS/unsupported"
touch "$ACTIONS/fail.dipo"
boot arm /data/plan/manifest
echo boot7 > "$ACTIONS/boot"
old_restore=$(grep -cx overlay-disable "$ACTIONS/log")
boot run
[ "$(grep -cx overlay-disable "$ACTIONS/log")" = "$((old_restore+1))" ]
[ "$(cat "$ACTIONS/zygote")" = running ]
grep -qx runtime-unavailable "$t/root/data/local/gen5w-portable/boot/reason"
boot disable
echo 'PASS unknown DiPO app removes runtime and wireless-only features safely'

# An unconfirmed request without a real marker is still a hard failure.
echo dipo-unconfirmed-control > "$ACTIONS/boot"
boot arm /data/plan/manifest
echo dipo-unconfirmed-trial > "$ACTIONS/boot"
touch "$ACTIONS/fail.launch-dipo"
if boot run; then echo 'FAIL accepted unconfirmed DiPO without readiness'; exit 1; fi
[ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 0 ]
grep -qx dipo-start-failed "$t/root/data/local/gen5w-portable/boot/reason"
[ "$(cat "$ACTIONS/zygote")" = running ]
rm "$ACTIONS/fail.launch-dipo"
echo 'PASS unconfirmed DiPO requires actual readiness or disables and restores'

# Disable while sys.boot_completed is pending must cancel before app launch.
rm "$ACTIONS/fail.dipo"
echo dipo-unconfirmed-restored-cold > "$ACTIONS/boot"
grep -cx start "$ACTIONS/log" > "$ACTIONS/framework-notready-after-restart"
touch "$ACTIONS/hold-boot"
boot arm /data/plan/manifest
echo boot8 > "$ACTIONS/boot"
old_launch=$(grep -cx launch-dipo "$ACTIONS/log")
mksh "$t/root/data/bundle/boot.sh" run & runner=$!
for unused in $(seq 1 1500); do [ "$(cat "$ACTIONS/healthy")" = 0 ] && break; sleep .01; done
[ "$(cat "$ACTIONS/healthy")" = 0 ]
rm "$ACTIONS/framework-notready-after-restart" "$ACTIONS/hold-boot"
boot disable
wait "$runner"
[ "$(grep -cx launch-dipo "$ACTIONS/log")" = "$old_launch" ]
[ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 0 ]
[ "$(cat "$ACTIONS/zygote")" = running ]
echo 'PASS disable cancels pending startup before launching any CarPlay owner'
echo boot8-cold-after-cancel > "$ACTIONS/boot"

# A slower healthy framework is admitted above, but an unavailable framework
# must still reach its monotonic deadline and restore stock without a session.
boot arm /data/plan/manifest
grep -cx start "$ACTIONS/log" > "$ACTIONS/framework-notready-after-restart"
echo boot8-never-ready > "$ACTIONS/boot"
if PORTABLE_TEST_DEADLINE_CAP=1 boot run; then echo 'FAIL unbounded framework readiness'; exit 1; fi
grep -qx boot-timeout "$t/root/data/local/gen5w-portable/boot/reason"
[ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 0 ]
[ "$(cat "$ACTIONS/zygote")" = running ]
[ ! -f "$ACTIONS/dirty" ]
[ ! -f "$ACTIONS/session-live" ]
rm "$ACTIONS/framework-notready-after-restart"
echo boot8-cold-after-timeout > "$ACTIONS/boot"
echo 'PASS slow framework allowed; missing framework remains bounded and restores stock'

# Unexpected session exits latch automatic operation off, without restarting
# Android while driving; a cold boot must remain stock for exit 0 and a crash.
for code in 0 7; do
 rm -f "$ACTIONS/hold-boot" "$ACTIONS/framework-notready" "$ACTIONS/session-stop" "$ACTIONS/session-exit-code"
 echo 1 > "$ACTIONS/healthy"
 boot arm /data/plan/manifest
 echo "boot-session-$code" > "$ACTIONS/boot"
 mksh "$t/root/data/bundle/boot.sh" run & runner=$!
 for unused in $(seq 1 1500); do grep -q healthy "$t/root/data/local/gen5w-portable/boot/attempt" && break; sleep .01; done
 grep -q healthy "$t/root/data/local/gen5w-portable/boot/attempt"
 old_stop=$(grep -cx stop "$ACTIONS/log")
 echo "$code" > "$ACTIONS/session-exit-code"
 rc=0; wait "$runner" || rc=$?
 [ "$rc" != 0 ]
 [ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 0 ]
 grep -q degraded "$t/root/data/local/gen5w-portable/boot/attempt"
 [ "$(grep -cx stop "$ACTIONS/log")" = "$old_stop" ]
 boot run
 [ "$(grep -cx stop "$ACTIONS/log")" = "$old_stop" ]
 echo "boot-after-session-$code" > "$ACTIONS/boot"
 boot run
 [ "$(grep -cx stop "$ACTIONS/log")" = "$old_stop" ]
 grep -qx session-ended-latched "$t/root/data/local/gen5w-portable/boot/reason"
 boot disable
done
rm -f "$ACTIONS/session-exit-code"
echo 'PASS session exit latches next boot off, records degradation and avoids mid-drive restart'

# Ignition off: Android shutdown may stop DiPO/host before power is cut. The
# resulting session end must not latch; a later cold boot applies normally.
for signal in powerctl zygote; do
 rm -f "$ACTIONS/session-stop" "$ACTIONS/session-exit-code" "$ACTIONS/powerctl"
 echo 1 > "$ACTIONS/healthy"; echo running > "$ACTIONS/zygote"
 boot arm /data/plan/manifest
 echo "boot-ignition-$signal" > "$ACTIONS/boot"
 mksh "$t/root/data/bundle/boot.sh" run & runner=$!
 for unused in $(seq 1 1500); do grep -q healthy "$t/root/data/local/gen5w-portable/boot/attempt" && break; sleep .01; done
 grep -q healthy "$t/root/data/local/gen5w-portable/boot/attempt"
 old_stop=$(grep -cx stop "$ACTIONS/log")
 if [ "$signal" = powerctl ]; then echo shutdown,ignition > "$ACTIONS/powerctl"; else echo stopped > "$ACTIONS/zygote"; fi
 echo 7 > "$ACTIONS/session-exit-code"
 rc=0; wait "$runner" || rc=$?
 [ "$rc" != 0 ]
 [ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 1 ]
 grep -qx session-ended-at-shutdown "$t/root/data/local/gen5w-portable/boot/reason"
 grep -qx "boot-ignition-$signal|degraded" "$t/root/data/local/gen5w-portable/boot/attempt"
 [ "$(grep -cx stop "$ACTIONS/log")" = "$old_stop" ]
 rm -f "$ACTIONS/session-exit-code" "$ACTIONS/powerctl"; echo running > "$ACTIONS/zygote"
 echo "boot-after-ignition-$signal" > "$ACTIONS/boot"
 mksh "$t/root/data/bundle/boot.sh" run & runner=$!
 for unused in $(seq 1 1500); do grep -qx "boot-after-ignition-$signal|healthy" "$t/root/data/local/gen5w-portable/boot/attempt" && break; sleep .01; done
 grep -qx "boot-after-ignition-$signal|healthy" "$t/root/data/local/gen5w-portable/boot/attempt"
 boot disable
 wait "$runner" 2>/dev/null || :
done
echo 'PASS health loss during Android shutdown stays armed; the next cold boot applies again'
# The independent USB rescue watcher must be running before automatic
# maintenance; otherwise this boot stays stock without a permanent latch.
rm -f "$ACTIONS/session-stop" "$ACTIONS/session-exit-code"
echo 1 > "$ACTIONS/healthy"; echo running > "$ACTIONS/zygote"
boot arm /data/plan/manifest
echo boot-rescue-dead > "$ACTIONS/boot"
touch "$ACTIONS/rescue-dead"
old_stop=$(grep -cx stop "$ACTIONS/log")
rc=0; boot run || rc=$?
[ "$rc" != 0 ]
[ "$(grep -cx stop "$ACTIONS/log")" = "$old_stop" ]
[ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 1 ]
grep -qx rescue-watch-unavailable "$t/root/data/local/gen5w-portable/boot/reason"
rm "$ACTIONS/rescue-dead"
echo boot-rescue-back > "$ACTIONS/boot"
mksh "$t/root/data/bundle/boot.sh" run & runner=$!
for unused in $(seq 1 1500); do grep -qx 'boot-rescue-back|healthy' "$t/root/data/local/gen5w-portable/boot/attempt" && break; sleep .01; done
grep -qx 'boot-rescue-back|healthy' "$t/root/data/local/gen5w-portable/boot/attempt"
boot disable
wait "$runner" 2>/dev/null || :
echo 'PASS automatic maintenance requires a live USB rescue watcher; absence skips one boot without latching'
# A new panic report after a healthy run must refuse the next activation.
mkdir -p "$t/root/proc"
echo 'old Kernel panic - not syncing: preserved report' > "$t/root/proc/last_kmsg"
boot arm /data/plan/manifest
echo boot-reset-evidence > "$ACTIONS/boot"
# Change identity: an unchanged historical panic must not poison admission.
echo 'new Kernel panic - not syncing: test reset' > "$t/root/proc/last_kmsg"
old_stop=$(grep -cx stop "$ACTIONS/log")
if boot run; then echo 'FAIL ignored new kernel panic evidence'; exit 1; fi
[ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 0 ]
[ "$(grep -cx stop "$ACTIONS/log")" = "$old_stop" ]
grep -qx reset-evidence "$t/root/data/local/gen5w-portable/boot/reason"
rm "$t/root/proc/last_kmsg"
boot disable
echo 'PASS new kernel panic evidence latches next activation off before maintenance'

# Android dropbox: framework crash/watchdog or a crash naming a patched app,
# new since the last admitted boot, latches before maintenance. Historical and
# unrelated entries do not. Compressed entries are inspected too.
db=$t/root/data/system/dropbox
J=$t/root/data/local/gen5w-portable/boot
dropbox_case() { # name content expect(latch|pass)
 rm -rf "$db"; mkdir -p "$db"
 echo 'Process: com.daudio.app.dipo' > "$db/system_app_crash@1000.txt"
 echo old > "$db/system_server_crash@1001.txt"
 boot arm /data/plan/manifest
 echo "boot-dropbox-$4" > "$ACTIONS/boot"
 case "$1" in
 *.gz) printf '%s\n' "$2" | gzip -c > "$db/$1";;
 *) printf '%s\n' "$2" > "$db/$1";;
 esac
 old_stop=$(grep -cx stop "$ACTIONS/log")
 if [ "$3" = latch ]; then
  if boot run; then echo "FAIL ignored dropbox $1"; exit 1; fi
  [ "$(cat "$J/enabled")" = 0 ]
  [ "$(grep -cx stop "$ACTIONS/log")" = "$old_stop" ]
  grep -qx dropbox-failure-evidence "$J/reason"
  boot disable
 else
  mksh "$t/root/data/bundle/boot.sh" run & runner=$!
  for unused in $(seq 1 1500); do grep -qx "boot-dropbox-$4|healthy" "$J/attempt" && break; sleep .01; done
  grep -qx "boot-dropbox-$4|healthy" "$J/attempt"
  boot disable
  wait "$runner" 2>/dev/null || :
 fi
}
dropbox_case system_server_crash@2000.txt 'java.lang.RuntimeException' latch 1
dropbox_case system_server_watchdog@2000.txt.gz 'Blocked in handler' latch 2
dropbox_case SYSTEM_TOMBSTONE@2000.txt.gz 'pid: 9, name: com.google.android.projection.sink' latch 3
dropbox_case data_app_crash@2000.txt 'Process: com.hkmc.wifisettings' latch 4
dropbox_case system_app_crash@2000.txt 'Process: com.example.radio' pass 5
dropbox_case system_app_anr@2000.txt 'Process: com.tcc.iap2server' latch 6
rm -rf "$db"
echo 'PASS new dropbox framework/patched-app failure evidence latches before maintenance; old and unrelated entries do not'

# Healthy is not enough to forgive repeated sudden early resets. No panic log
# or graceful userspace exit is available in this injected scenario.
export PORTABLE_TEST_STABLE_SECONDS=300
boot arm /data/plan/manifest
for n in 1 2 3; do
 echo "rapid-reset-$n" > "$ACTIONS/boot"
 mksh "$t/root/data/bundle/boot.sh" run & runner=$!
 for unused in $(seq 1 1500); do grep -qx "rapid-reset-$n|healthy" "$t/root/data/local/gen5w-portable/boot/attempt" && [ ! -d "$t/root/data/local/gen5w-portable/boot/lock" ] && break; sleep .01; done
 grep -qx "rapid-reset-$n|healthy" "$t/root/data/local/gen5w-portable/boot/attempt"
 kill -KILL "$runner"; wait "$runner" 2>/dev/null || :
 touch "$ACTIONS/session-stop"
 for unused in $(seq 1 1500); do [ -f "$ACTIONS/session-live" ] || break; sleep .01; done
 [ ! -f "$ACTIONS/session-live" ]
done
echo rapid-reset-4 > "$ACTIONS/boot"
old_stop=$(grep -cx stop "$ACTIONS/log")
mksh "$t/root/data/bundle/boot.sh" run & runner=$!
for unused in $(seq 1 1500); do
 [ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" != 0 ] || break
 if grep -qx 'rapid-reset-4|healthy' "$t/root/data/local/gen5w-portable/boot/attempt"; then
  kill -KILL "$runner"; wait "$runner" 2>/dev/null || :
  echo 'FAIL repeated fourth unobserved early reset'; exit 1
 fi
 sleep .01
done
rc=0; wait "$runner" || rc=$?
[ "$rc" != 0 ]
[ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 0 ]
[ "$(grep -cx stop "$ACTIONS/log")" = "$old_stop" ]
grep -qx rapid-start-limit "$t/root/data/local/gen5w-portable/boot/reason"
boot disable
export PORTABLE_TEST_STABLE_SECONDS=0
echo 'PASS repeated post-healthy early resets without logs stop before fourth activation'

# Optional stock drift drops only that feature before maintenance.
printf stock-audio > "$t/root/system/app/audio-fixture.so"
printf patched-audio > "$t/root/data/plan/audio"
echo "$(sha256sum "$t/root/system/app/audio-fixture.so" | cut -d' ' -f1)" > "$t/root/data/plan/audio.stock"
echo "audio|/data/plan/audio|/system/app/audio-fixture.so|$(sha256sum "$t/root/data/plan/audio" | cut -d' ' -f1)|0|0|644|static" >> "$t/root/data/plan/manifest"
rm -f "$ACTIONS/session-stop"
boot arm /data/plan/manifest
printf updated-audio > "$t/root/system/app/audio-fixture.so"
echo boot-optional > "$ACTIONS/boot"
mksh "$t/root/data/bundle/boot.sh" run & runner=$!
for unused in $(seq 1 1500); do grep -q healthy "$t/root/data/local/gen5w-portable/boot/attempt" && break; sleep .01; done
grep -q healthy "$t/root/data/local/gen5w-portable/boot/attempt"
grep -qx 'audio|skipped|stock-changed' "$t/root/data/local/gen5w-portable/boot/skipped"
grep -q '^bt|' "$t/root/data/local/gen5w-portable/boot/boot-manifest"
if grep -q '^audio|' "$t/root/data/local/gen5w-portable/boot/boot-manifest"; then echo 'FAIL retained optional drift'; exit 1; fi
# The controller appends startup-healthy right after the attempt marker.
for unused in $(seq 1 1500); do grep -q startup-healthy "$t/root/data/local/gen5w-portable/boot/timeline" && break; sleep .01; done
rm "$t/root/data/local/gen5w-portable/boot/timeline"
ln -s /dev/full "$t/root/data/local/gen5w-portable/boot/timeline"
boot disable
[ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 0 ]
rm "$t/root/data/local/gen5w-portable/boot/timeline"
wait "$runner"
printf stock-audio > "$t/root/system/app/audio-fixture.so"
# Retained wrappers and libraries survive deletion of their NEMESIS package.
payload=$t/root/data/local/gen5w-portable/runtime-payload
[ -x "$payload/wrap-dipo.sh" ] && [ -x "$payload/bin/dex-patch" ]
cmp -s "$payload/dalvik/engine.jar" "$t/root/data/bundle/dalvik/engine.jar"
[ "$(stat -c %a "$payload")" = 755 ]
echo 'PASS optional stock drift, independent plan selection and retained accessible runtime payload'
old_stop=$(grep -cx stop "$ACTIONS/log")
if boot transact; then echo 'FAIL unsupervised internal maintenance'; exit 1; fi
[ "$(grep -cx stop "$ACTIONS/log")" = "$old_stop" ]
# A current guardian marker fences re-arm even when its original caller died.
echo "$(cat "$ACTIONS/boot")" > "$t/root/data/local/gen5w-portable/boot/maintenance"
if boot arm --trial /data/plan/manifest; then echo 'FAIL arm raced retained guardian'; exit 1; fi
rm "$t/root/data/local/gen5w-portable/boot/maintenance"

# A successful one-shot vehicle trial must never apply on another boot.
boot arm --trial /data/plan/manifest
[ -f "$t/root/data/nemesis/gen5wkr.ui-wireless-off" ]
echo boot-trial > "$ACTIONS/boot"
mksh "$t/root/data/bundle/boot.sh" run & runner=$!
for unused in $(seq 1 1500); do grep -q healthy "$t/root/data/local/gen5w-portable/boot/attempt" && break; sleep .01; done
grep -q healthy "$t/root/data/local/gen5w-portable/boot/attempt"
for unused in $(seq 1 1500); do [ ! -d "$t/root/data/local/gen5w-portable/boot/lock" ] && break; sleep .01; done
[ ! -d "$t/root/data/local/gen5w-portable/boot/lock" ]
old_stop=$(grep -cx stop "$ACTIONS/log")
# Model loss of the prior userspace without a graceful disable.
kill -KILL "$runner"; wait "$runner" 2>/dev/null || :
echo trial-next > "$ACTIONS/boot"
if boot run; then echo 'FAIL repeated a consumed trial'; exit 1; fi
[ "$(grep -cx stop "$ACTIONS/log")" = "$old_stop" ]
grep -qx trial-consumed "$t/root/data/local/gen5w-portable/boot/reason"
boot disable
echo 'PASS trial consumes before maintenance and next boot remains stock even after healthy'

# Trial must not replay when a resume reuses its boot id but loses state.
rm "$t/root/data/nemesis/gen5wkr.ui-wireless-off"
boot arm --trial /data/plan/manifest
[ -f "$t/root/data/nemesis/gen5wkr.ui-wireless-off" ]
echo boot-trial-resume > "$ACTIONS/boot"
mksh "$t/root/data/bundle/boot.sh" run & runner=$!
for unused in $(seq 1 1500); do grep -q healthy "$t/root/data/local/gen5w-portable/boot/attempt" && break; sleep .01; done
grep -q healthy "$t/root/data/local/gen5w-portable/boot/attempt"
for unused in $(seq 1 1500); do [ ! -d "$t/root/data/local/gen5w-portable/boot/lock" ] && break; sleep .01; done
[ ! -d "$t/root/data/local/gen5w-portable/boot/lock" ]
old_apply=$(grep -cx apply "$ACTIONS/log")
if boot run; then echo 'FAIL replayed consumed same-id trial'; exit 1; fi
grep -qx trial-consumed-restored "$t/root/data/local/gen5w-portable/boot/reason"
[ ! -f "$ACTIONS/dirty" ]
[ "$(cat "$ACTIONS/zygote")" = running ]
[ "$(grep -cx apply "$ACTIONS/log")" = "$old_apply" ]
boot disable
wait "$runner" || :
echo 'PASS same-id resume never re-enters consumed trial maintenance'

# Probe uses the same retained rescue and service dependency window before arm.
cp "$t/root/system/app/Iap2ServerApp.odex" "$t/root/system/app/HKMC_DiPO.odex"
cp "$t/root/system/app/HKMC_DiPO.odex" "$t/root/data/plan/probe.odex"
sha256sum "$t/root/system/app/HKMC_DiPO.odex" | cut -d' ' -f1 > "$t/root/data/plan/probe.odex.stock"
echo "probe|/data/plan/probe.odex|/system/app/HKMC_DiPO.odex|$(cat "$t/root/data/plan/probe.odex.stock")|0|0|644|static" > "$t/root/data/plan/probe-manifest"
boot probe /data/plan/probe-manifest
grep -qx probe-ready-one-shot "$t/root/data/local/gen5w-portable/boot/reason"
grep -qx runtime-probe "$ACTIONS/log"
[ "$(cat "$ACTIONS/zygote")" = running ]
[ "$(stat -c %a "$payload/wrap-probe.sh")" = 755 ]
echo probe-next > "$ACTIONS/boot"
old_stop=$(grep -cx stop "$ACTIONS/log")
if boot run; then echo 'FAIL replayed a no-hook probe'; exit 1; fi
[ "$(grep -cx stop "$ACTIONS/log")" = "$old_stop" ]
boot disable
echo 'PASS supervised explicit probe, accessible payload, no next-boot replay'

# A failed no-hook activation is recovered by the independent native guardian.
touch "$ACTIONS/fail.runtime-probe"
if boot probe /data/plan/probe-manifest; then echo 'FAIL accepted failed probe activation'; exit 1; fi
[ "$(cat "$ACTIONS/zygote")" = running ]
[ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 0 ]
[ ! -e "$t/root/data/local/gen5w-portable/boot/maintenance" ]
rm "$ACTIONS/fail.runtime-probe"
boot disable
if boot arm --trial /data/plan/probe-manifest; then echo 'FAIL re-armed unfinished same-boot attempt'; exit 1; fi
echo probe-retry-cold > "$ACTIONS/boot"
# Killing the entire calling terminal group during the stopped window must
# still invoke the retained guardian in its independent session.
touch "$ACTIONS/hang.runtime-probe"
setsid "$t/root/data/bundle/boot.sh" probe /data/plan/probe-manifest > "$ACTIONS/probe-killed.log" 2>&1 & probe_runner=$!
for unused in $(seq 1 1500); do [ -f "$ACTIONS/probe-window" ] && break; sleep .01; done
if [ ! -f "$ACTIONS/probe-window" ]; then
 cat "$ACTIONS/probe-killed.log" >&2
 boot status >&2
 echo "FAIL probe did not reach controlled kill window; zygote=$(cat "$ACTIONS/zygote")" >&2
 exit 1
fi
[ "$(cat "$ACTIONS/zygote")" = stopped ]
kill -KILL -- "-$probe_runner"
wait "$probe_runner" 2>/dev/null || :
for unused in $(seq 1 1500); do
 [ "$(cat "$ACTIONS/zygote")" = running ] && [ ! -e "$t/root/data/local/gen5w-portable/boot/maintenance" ] && break
 sleep .01
done
[ "$(cat "$ACTIONS/zygote")" = running ]
[ ! -e "$t/root/data/local/gen5w-portable/boot/maintenance" ]
[ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 0 ]
rm "$ACTIONS/hang.runtime-probe" "$ACTIONS/probe-window"
boot disable
echo 'PASS killed probe caller process group still restores stock Android via retained rescue'
# Caller-only death can leave the native worker alive before its apply. Disable
# must wait for the marker even while dirty is still false.
echo disable-guard-cold > "$ACTIONS/boot"
touch "$ACTIONS/hold.before-apply" "$ACTIONS/long-pause"
setsid "$t/root/data/bundle/boot.sh" probe /data/plan/probe-manifest > "$ACTIONS/disable-race.log" 2>&1 & probe_runner=$!
for unused in $(seq 1 1500); do [ -f "$ACTIONS/preapply-window" ] && break; sleep .01; done
[ -f "$ACTIONS/preapply-window" ] && [ ! -f "$ACTIONS/dirty" ]
kill -KILL "$probe_runner"
wait "$probe_runner" 2>/dev/null || :
boot disable
premature=0
[ ! -f "$t/root/data/local/gen5w-portable/boot/maintenance" ] || premature=1
# Reap the surviving fixture worker even when running the old faulty ordering.
for unused in $(seq 1 1500); do [ ! -f "$t/root/data/local/gen5w-portable/boot/maintenance" ] && break; sleep .01; done
[ "$premature" = 0 ] || { echo 'FAIL disable reported restored before guardian finished'; exit 1; }
[ ! -f "$ACTIONS/dirty" ] && [ "$(cat "$ACTIONS/zygote")" = running ]
grep -qx disabled-restored "$t/root/data/local/gen5w-portable/boot/reason"
rm "$ACTIONS/hold.before-apply" "$ACTIONS/preapply-window" "$ACTIONS/long-pause"
echo 'PASS disable waits for surviving maintenance even before first apply'

echo probe-modified-cold > "$ACTIONS/boot"
old_stop=$(grep -cx stop "$ACTIONS/log")
printf altered > "$t/root/data/plan/probe.odex"
if boot probe /data/plan/probe-manifest; then echo 'FAIL accepted modified premise file'; exit 1; fi
[ "$(grep -cx stop "$ACTIONS/log")" = "$old_stop" ]
echo 'PASS failed probe restores Android; modified premise rejected before stop'

# A rescue token inserted while arm is running must win over arm's enabled=1.
rm -f "$ACTIONS/rescue-calls"; touch "$ACTIONS/rescue-usb-late"
if boot arm /data/plan/manifest; then echo 'FAIL arm overruled a token inserted during arm'; exit 1; fi
[ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 0 ]
grep -qx usb-rescue-requested "$t/root/data/local/gen5w-portable/boot/reason"
rm -f "$ACTIONS/rescue-usb-late" "$ACTIONS/rescue-calls"
echo 'PASS rescue token inserted during arm stays disabled'

# Corrupted runtime payload is rejected before stopping stock Android.
rm -f "$ACTIONS/hold-boot"
echo 1 > "$ACTIONS/healthy"
boot arm /data/plan/manifest
echo boot9 > "$ACTIONS/boot"
old=$(grep -cx stop "$ACTIONS/log")
printf corrupted >> "$t/root/data/bundle/overlay.sh"
if boot run; then echo 'FAIL accepted changed sealed bundle'; exit 1; fi
[ "$(grep -cx stop "$ACTIONS/log")" = "$old" ]
grep -qx bundle-changed "$t/root/data/local/gen5w-portable/boot/reason"
echo 'PASS sealed bundle integrity checked before framework maintenance'

# Rescue insertion fences re-arm and run before framework maintenance.
touch "$ACTIONS/rescue-usb"
old_stop=$(grep -cx stop "$ACTIONS/log")
if boot arm /data/plan/manifest; then echo 'FAIL armed with rescue USB'; exit 1; fi
boot run
[ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 0 ]
[ "$(grep -cx stop "$ACTIONS/log")" = "$old_stop" ]
rm "$ACTIONS/rescue-usb"
echo 'PASS rescue USB fences arm and startup before maintenance'
