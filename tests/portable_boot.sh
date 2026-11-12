#!/bin/bash
# Startup control runs against real private files; only Android/NEMESIS are boundaries.
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/g5p-boot.XXXXXX)
trap 'rm -rf "$t"' EXIT
mkdir -p "$t/root/data/bundle/bin" "$t/root/data/plan" "$t/root/system/app" "$t/actions"
cp tools/portable/boot.sh tools/portable/rescue.sh tools/portable/runtime.sh tools/portable/overlay.sh tools/portable/framework.sh tools/portable/wrap-*.sh "$t/root/data/bundle/"
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
cat > "$t/helper" <<'PY'
#!/usr/bin/python3
import hashlib,os,stat,sys
if sys.argv[1]=='sha256': print(hashlib.sha256(open(sys.argv[2],'rb').read()).hexdigest())
elif sys.argv[1]=='metadata': print('0|0|644')
else: sys.exit(1)
PY
chmod +x "$t/helper"
cp .build/portable/dex-patch-host "$t/root/data/bundle/bin/dex-patch"
cat > "$t/adapter" <<'SH'
#!/bin/bash
set -e
case "$1" in
boot) cat "$ACTIONS/boot";;
ap-prepare|ap-disable) :;;
ap-check) [ ! -f "$ACTIONS/ap-unsafe" ] || exit 77;;
owned-overlays) test -f "$ACTIONS/owned-overlays";;
dependencies) echo media; echo netd;;
framework) cat "$ACTIONS/framework";;
framework-ready) test "$(cat "$ACTIONS/healthy")" = 1 && test ! -f "$ACTIONS/framework-notready";;
get) case "$2" in init.svc.zygote) cat "$ACTIONS/zygote";; sys.boot_completed) cat "$ACTIONS/healthy";; esac;;
plan|plan-boot|plan-static|apply|runtime-enable|runtime-disable|overlay-disable|commit|commit-static|launch-dipo|session-stop)
 [ "$1" != runtime-enable ] || [ ! -f "$ACTIONS/unsupported" ] || exit 77
 echo "$1" >> "$ACTIONS/log"
 [ ! -f "$ACTIONS/fail.$1" ] || exit 1
 case "$1" in session-stop) touch "$ACTIONS/session-stop";; apply) touch "$ACTIONS/dirty";; overlay-disable) rm -f "$ACTIONS/dirty";; esac;;
stop-android) echo stop >> "$ACTIONS/log"; echo stopped > "$ACTIONS/zygote";;
start-android) echo start >> "$ACTIONS/log"; echo running > "$ACTIONS/zygote"; echo 1 > "$ACTIONS/healthy"; [ ! -f "$ACTIONS/hold-boot" ] || echo 0 > "$ACTIONS/healthy";;
dipo-ready) test ! -f "$ACTIONS/fail.dipo";;
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
session-ready) test -f "$ACTIONS/session-live";;
pause) sleep .02;;
*) exit 1;;
esac
SH
chmod +x "$t/adapter"
export ACTIONS=$t/actions PORTABLE_TEST_ROOT=$t/root PORTABLE_TEST_BOOT_ADAPTER=$t/adapter PORTABLE_TEST_HELPER=$t/helper
export PORTABLE_TEST_SUPERVISOR=$PWD/.build/portable/dex-patch-host
export PORTABLE_BOOT_TIMEOUT=3
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
boot run & runner=$!
for unused in $(seq 1 200); do grep -q 'healthy' "$t/root/data/local/gen5w-portable/boot/attempt" 2>/dev/null && break; sleep .02; done
grep -q healthy "$t/root/data/local/gen5w-portable/boot/attempt"
[ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 1 ]
[ "$(grep -cx stop "$ACTIONS/log")" = 1 ]
boot disable
wait "$runner"
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

# Disable while sys.boot_completed is pending must cancel before app launch.
rm "$ACTIONS/fail.dipo"
touch "$ACTIONS/framework-notready"
touch "$ACTIONS/hold-boot"
boot arm /data/plan/manifest
echo boot8 > "$ACTIONS/boot"
old_launch=$(grep -cx launch-dipo "$ACTIONS/log")
boot run & runner=$!
for unused in $(seq 1 200); do [ "$(cat "$ACTIONS/healthy")" = 0 ] && break; sleep .01; done
[ "$(cat "$ACTIONS/healthy")" = 0 ]
rm "$ACTIONS/framework-notready" "$ACTIONS/hold-boot"
boot disable
wait "$runner"
[ "$(grep -cx launch-dipo "$ACTIONS/log")" = "$old_launch" ]
[ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 0 ]
[ "$(cat "$ACTIONS/zygote")" = running ]
echo 'PASS disable cancels pending startup before launching any CarPlay owner'

# Session exits are ephemeral: no mid-session framework restart and next boot
# remains armed, for both a clean exit and a crash.
for code in 0 7; do
 rm -f "$ACTIONS/hold-boot" "$ACTIONS/framework-notready" "$ACTIONS/session-stop" "$ACTIONS/session-exit-code"
 echo 1 > "$ACTIONS/healthy"
 boot arm /data/plan/manifest
 echo "boot-session-$code" > "$ACTIONS/boot"
 boot run & runner=$!
 for unused in $(seq 1 300); do grep -q healthy "$t/root/data/local/gen5w-portable/boot/attempt" && break; sleep .01; done
 grep -q healthy "$t/root/data/local/gen5w-portable/boot/attempt"
 old_stop=$(grep -cx stop "$ACTIONS/log")
 echo "$code" > "$ACTIONS/session-exit-code"
 rc=0; wait "$runner" || rc=$?
 [ "$rc" != 0 ]
 [ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 1 ]
 grep -q degraded "$t/root/data/local/gen5w-portable/boot/attempt"
 [ "$(grep -cx stop "$ACTIONS/log")" = "$old_stop" ]
 if boot run; then echo 'FAIL retried degraded session within same boot'; exit 1; fi
 boot disable
done
rm -f "$ACTIONS/session-exit-code"
echo 'PASS session exit keeps next boot armed, records degradation and avoids mid-drive restart'
# Optional stock drift drops only that feature before maintenance.
printf stock-audio > "$t/root/system/app/audio-fixture.so"
printf patched-audio > "$t/root/data/plan/audio"
echo "$(sha256sum "$t/root/system/app/audio-fixture.so" | cut -d' ' -f1)" > "$t/root/data/plan/audio.stock"
echo "audio|/data/plan/audio|/system/app/audio-fixture.so|$(sha256sum "$t/root/data/plan/audio" | cut -d' ' -f1)|0|0|644|static" >> "$t/root/data/plan/manifest"
rm -f "$ACTIONS/session-stop"
boot arm /data/plan/manifest
printf updated-audio > "$t/root/system/app/audio-fixture.so"
echo boot-optional > "$ACTIONS/boot"
boot run & runner=$!
for unused in $(seq 1 300); do grep -q healthy "$t/root/data/local/gen5w-portable/boot/attempt" && break; sleep .01; done
grep -q healthy "$t/root/data/local/gen5w-portable/boot/attempt"
grep -qx 'audio|skipped|stock-changed' "$t/root/data/local/gen5w-portable/boot/skipped"
grep -q '^bt|' "$t/root/data/local/gen5w-portable/boot/boot-manifest"
if grep -q '^audio|' "$t/root/data/local/gen5w-portable/boot/boot-manifest"; then echo 'FAIL retained optional drift'; exit 1; fi
boot disable
wait "$runner"
printf stock-audio > "$t/root/system/app/audio-fixture.so"
# Retained wrappers and libraries survive deletion of their NEMESIS package.
payload=$t/root/data/local/gen5w-portable/runtime-payload
[ -x "$payload/wrap-dipo.sh" ] && [ -x "$payload/bin/dex-patch" ]
cmp -s "$payload/dalvik/engine.jar" "$t/root/data/bundle/dalvik/engine.jar"
[ "$(stat -c %a "$payload")" = 755 ]
echo 'PASS optional stock drift, independent plan selection and retained accessible runtime payload'
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
