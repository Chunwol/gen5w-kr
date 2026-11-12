#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/gen5w-session.XXXXXX)
trap 'rm -rf "$t"' EXIT
mkdir -p "$t/root/data/bundle/app" "$t/root/data/bundle/dalvik" "$t/actions"
cp tools/portable/session.sh "$t/root/data/bundle/"
for file in bridge.dex wireless-host.apk gen5w-core.apk; do echo authored > "$t/root/data/bundle/app/$file"; done
echo engine > "$t/root/data/bundle/dalvik/engine.jar"
cat > "$t/adapter" <<'SH'
#!/bin/bash
case "$1" in
boot) echo boot-test;;
installed) [ -f "$ACTIONS/existing" ];;
ready) [ ! -f "$ACTIONS/notready" ];;
install) echo "$2" >> "$ACTIONS/installed";;
busy) [ -f "$ACTIONS/busy" ];;
broker|owner) sleep 2;;
start-host|stop-host|start-core|stop-core) echo "$1" >> "$ACTIONS/events";;
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
touch "$ACTIONS/notready"
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
