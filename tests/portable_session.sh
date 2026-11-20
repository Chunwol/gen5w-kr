#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/gen5w-session.XXXXXX)
trap 'rc=$?; rm -rf "$t"; exit $rc' EXIT
mkdir -p "$t/root/data/bundle/app" "$t/root/data/bundle/dalvik" "$t/actions"
cp tools/portable/session.sh "$t/root/data/bundle/"
for file in bridge.dex wireless-host.apk gen5w-core.apk; do echo authored > "$t/root/data/bundle/app/$file"; done
echo engine > "$t/root/data/bundle/dalvik/engine.jar"
cat > "$t/adapter" <<'SH'
#!/bin/bash
case "$1" in
boot) echo boot-test;;
installed) [ -f "$ACTIONS/existing" ];;
ready|adapter-ready) [ ! -f "$ACTIONS/notready" ];;
install) echo "$2" >> "$ACTIONS/installed";;
busy) [ -f "$ACTIONS/busy" ];;
broker|owner) sleep 2;;
start-host|stop-host|start-core|stop-core)
 echo "$1" >> "$ACTIONS/events"
 [ ! -f "$ACTIONS/fail.$1" ] || exit 1
 if [ "$1" = start-core ] && [ -f "$ACTIONS/hold-core-start" ]; then
  touch "$ACTIONS/core-start-entered"
  while [ ! -f "$ACTIONS/release-core-start" ]; do sleep .02; done
 fi;;
host-ready|broker-ready|wireless-admit) :;;
wireless-enabled) [ ! -f "$ACTIONS/wireless-off" ];;
pause)
 if [ -f "$ACTIONS/hold" ]; then sleep 0.05
 elif [ -f "$ACTIONS/toggle" ]; then
   count=$(cat "$ACTIONS/count" 2>/dev/null || echo 0); count=$((count+1)); echo "$count" > "$ACTIONS/count"
   case "$count" in 1) touch "$ACTIONS/wireless-off";; 2) rm "$ACTIONS/wireless-off";; *) touch "$PORTABLE_TEST_ROOT/data/local/gen5w-portable/session/stop";; esac
 else touch "$PORTABLE_TEST_ROOT/data/local/gen5w-portable/session/stop"; fi;;
*) exit 1;;
esac
SH
chmod +x "$t/adapter"
export ACTIONS=$t/actions PORTABLE_TEST_ROOT=$t/root PORTABLE_TEST_SESSION_ADAPTER=$t/adapter
run() { mksh "$t/root/data/bundle/session.sh" "$@"; }
touch "$ACTIONS/existing"
if run install-apps >/dev/null 2>&1; then echo 'FAIL replaced existing apps'; exit 1; fi
[ ! -f "$ACTIONS/installed" ]
rm "$ACTIONS/existing"
if run install-apps >/dev/null 2>&1; then echo "FAIL used direct pm install on HMG"; exit 1; fi
[ ! -f "$ACTIONS/installed" ]
run ready
run adapter-ready
touch "$ACTIONS/notready"
if run adapter-ready; then echo 'FAIL adapter observation accepted absent readiness'; exit 1; fi
if run run >/dev/null 2>&1; then echo 'FAIL started without hooks/overlay readiness'; exit 1; fi
[ ! -f "$ACTIONS/events" ]
rm "$ACTIONS/notready"
touch "$ACTIONS/busy"
if run run >/dev/null 2>&1; then echo 'FAIL took over existing session'; exit 1; fi
rm "$ACTIONS/busy"
run run
grep -qx start-host "$ACTIONS/events"
grep -qx start-core "$ACTIONS/events"
grep -qx stop-host "$ACTIONS/events"
grep -qx stop-core "$ACTIONS/events"
[ ! -d "$t/root/data/local/gen5w-portable/session/lock" ]
echo 'PASS portable session: authored app install boundary, readiness/ownership refusal, explicit run and owned service cleanup'

# A stop during a slow Android start command must fence all later launches.
: > "$ACTIONS/events"
touch "$ACTIONS/hold-core-start" "$ACTIONS/hold"
run run > "$ACTIONS/cancel-start.log" 2>&1 & cancelled_runner=$!
for n in {1..100}; do [ ! -f "$ACTIONS/core-start-entered" ] || break; sleep .02; done
[ -f "$ACTIONS/core-start-entered" ]
run stop
touch "$ACTIONS/release-core-start"
cancel_rc=0; wait "$cancelled_runner" || cancel_rc=$?
[ "$cancel_rc" != 0 ] || { echo 'FAIL cancelled startup returned success'; exit 1; }
! grep -qx start-host "$ACTIONS/events"
grep -qx stop-core "$ACTIONS/events"
[ ! -d "$t/root/data/local/gen5w-portable/session/lock" ]
rm "$ACTIONS/hold-core-start" "$ACTIONS/hold" "$ACTIONS/core-start-entered" "$ACTIONS/release-core-start"
echo 'PASS cancellation during Android startup fences later host launch and releases ownership'

touch "$ACTIONS/fail.stop-core"
run run > "$ACTIONS/cleanup-failed.log" 2>&1 || :
[ -f "$t/root/data/local/gen5w-portable/session/epoch" ]
[ -f "$t/root/data/local/gen5w-portable/session/lock/owner" ]
rm "$ACTIONS/fail.stop-core"
run stop
[ ! -f "$t/root/data/local/gen5w-portable/session/epoch" ]
[ ! -d "$t/root/data/local/gen5w-portable/session/lock" ]
echo 'PASS failed owned cleanup retains its epoch and supports an explicit retry'

# Legacy interruption before epoch publication must not permanently wedge boot.
state=$t/root/data/local/gen5w-portable/session
mkdir "$state/lock"
run run > "$ACTIONS/empty-lock.log" 2>&1 || { cat "$ACTIONS/empty-lock.log"; echo 'FAIL empty pre-epoch lock recovery'; exit 1; }
[ ! -d "$state/lock" ]
echo 'PASS empty pre-epoch lock recovers without service takeover'

# Published ownership is authoritative even before the public epoch exists.
mkdir "$state/lock"
start=$(awk '{print $22}' /proc/$$/stat)
echo "boot-test|$$:$start" > "$state/lock/owner"
: > "$ACTIONS/events"
if run run > "$ACTIONS/live-lock.log" 2>&1; then echo 'FAIL took live pre-epoch lock'; exit 1; fi
[ -f "$state/lock/owner" ] && [ ! -s "$ACTIONS/events" ]
rm "$state/lock/owner"; rmdir "$state/lock"
# Killed publisher and cold boot owners are safely recoverable without epoch.
for previous in 'boot-test|999999999:1' 'previous-boot|1:1'; do
    mkdir "$state/lock"; echo "$previous" > "$state/lock/owner"
    run run > "$ACTIONS/stale-publish.log" 2>&1 || { cat "$ACTIONS/stale-publish.log"; exit 1; }
    [ ! -d "$state/lock" ]
done
# Failure writing the public journal releases already-published ownership.
mkdir "$state/epoch"
if run run > "$ACTIONS/publish-fail.log" 2>&1; then echo 'FAIL epoch directory accepted'; exit 1; fi
[ ! -d "$state/lock" ]; rmdir "$state/epoch"
run run > "$ACTIONS/retry-publish.log" 2>&1
# Failed rename publication withdraws the staged owner and allows a retry.
mkdir "$t/commands"
cat > "$t/commands/mv" <<'SH'
#!/bin/sh
case "$1" in */lock.claim.*) exit 1;; esac
exec /bin/mv "$@"
SH
chmod +x "$t/commands/mv"
if PATH="$t/commands:$PATH" run run > "$ACTIONS/rename-fail.log" 2>&1; then echo 'FAIL failed lock rename admitted'; exit 1; fi
[ ! -e "$state/lock" ]
[ -z "$(find "$state" -maxdepth 1 -name 'lock.claim.*' -print)" ]
run run > "$ACTIONS/retry-rename.log" 2>&1
# A real concurrent start cannot disturb an active worker or start extra apps.
touch "$ACTIONS/hold"; : > "$ACTIONS/events"
run run > "$ACTIONS/concurrent.log" 2>&1 & concurrent=$!
for n in {1..100}; do [ ! -f "$state/ready" ] || break; sleep .02; done
[ -f "$state/ready" ]
if run run > "$ACTIONS/contender.log" 2>&1; then echo 'FAIL concurrent session admitted'; exit 1; fi
[ "$(grep -c '^start-core$' "$ACTIONS/events")" = 1 ]
run stop; wait "$concurrent"
rm "$ACTIONS/hold"
echo 'PASS live pre-epoch ownership, killed/cold owner recovery, journal/rename failures and concurrent exclusion'

# A killed supervisor cannot service its stop marker; its sealed epoch permits
# cleanup of the exclusively owned app services without signalling a stale PID.
state=$t/root/data/local/gen5w-portable/session
mkdir "$state/lock"
echo 'boot-test|999999999:1' > "$state/epoch"
echo 'boot-test|999999999:1' > "$state/ready"
: > "$ACTIONS/events"
run stop
grep -qx stop-host "$ACTIONS/events"
grep -qx stop-core "$ACTIONS/events"
[ ! -e "$state/epoch" ] && [ ! -d "$state/lock" ]
: > "$ACTIONS/events"
run stop
[ ! -s "$ACTIONS/events" ]
echo 'PASS stale owned session cleanup and no takeover without an epoch'

: > "$ACTIONS/events"
touch "$ACTIONS/wireless-off"
run run
! grep -q host "$ACTIONS/events"
grep -qx start-core "$ACTIONS/events"
grep -qx stop-core "$ACTIONS/events"
rm "$ACTIONS/wireless-off"
: > "$ACTIONS/events"
touch "$ACTIONS/toggle"
run run
[ "$(grep -c '^start-host$' "$ACTIONS/events")" = 2 ]
[ "$(grep -c '^stop-host$' "$ACTIONS/events")" = 2 ]
[ "$(grep -c '^start-core$' "$ACTIONS/events")" = 1 ]
echo 'PASS wireless disable and live toggle preserve HUD supervisor'

rm "$ACTIONS/toggle"; : > "$ACTIONS/events"; touch "$ACTIONS/hold"
bash -c 'mksh "$1" run & echo "$!" > "$2"; wait' _ "$t/root/data/bundle/session.sh" "$ACTIONS/session-pid" & parent=$!
for n in {1..100}; do [ ! -f "$state/ready" ] || break; sleep 0.02; done
[ -f "$state/ready" ] || { kill "$parent"; echo 'FAIL parent-watch fixture readiness'; exit 1; }
kill -9 "$parent"; wait "$parent" 2>/dev/null || :
for n in {1..100}; do [ -d "$state/lock" ] || break; sleep 0.02; done
[ ! -d "$state/lock" ] || { echo 'FAIL orphan supervisor remained'; exit 1; }
grep -qx stop-host "$ACTIONS/events"; grep -qx stop-core "$ACTIONS/events"
echo 'PASS killed boot parent triggers session-owned host/HUD cleanup'

# Runtime/DiPO health loss after readiness records evidence and cleans owned
# services. Latching is the controller's decision after it confirms Android is
# not shutting down (ignition off may stop DiPO first).
rm -f "$ACTIONS/events" "$ACTIONS/notready"
mkdir -p "$t/root/data/local/gen5w-portable/boot"
echo 1 > "$t/root/data/local/gen5w-portable/boot/enabled"
run run > "$ACTIONS/late-health.log" 2>&1 & runner=$!
for n in {1..100}; do [ ! -f "$state/ready" ] || break; sleep .02; done
[ -f "$state/ready" ]
touch "$ACTIONS/notready"
rc=0; wait "$runner" || rc=$?
[ "$rc" != 0 ]
[ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 1 ]
grep -q '|runtime health lost$' "$t/root/data/local/gen5w-portable/boot/health-lost"
grep -qx stop-host "$ACTIONS/events"
echo 'PASS post-ready runtime health failure records evidence for the controller and cleans owned services'

# Opening Manager without a foreground session must not wedge disable/update.
rm -f "$state/epoch" "$state/ready" "$state/owner"
[ ! -d "$state/lock" ]
: > "$ACTIONS/events"
run stop-maintenance
grep -qx stop-core "$ACTIONS/events" || { echo 'FAIL idle Manager process not stopped'; exit 1; }
grep -qx stop-host "$ACTIONS/events" || { echo 'FAIL idle authored host not stopped'; exit 1; }
echo 'PASS explicit stop cleans authored apps with no session epoch'
