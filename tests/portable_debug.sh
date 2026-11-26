#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/g5debug.XXXXXX)
runner=
trap 'rc=$?; [ -z "$runner" ] || { kill "$runner" 2>/dev/null || :; wait "$runner" 2>/dev/null || :; }; rm -rf "$t"; exit $rc' EXIT
R=$t/root; B=$R/data/bundle
mkdir -p "$B/bin" "$R/data/nemesis" "$R/data/local/gen5w-portable" "$t/props"
cp tools/portable/debug.sh "$B/"
cp .build/portable/dex-patch-host "$B/bin/dex-patch"
for limit in $(sed -n 's/.*dex-patch"[[:space:]]*supervise[[:space:]]*\([0-9][0-9]*\).*/\1/p' tools/portable/debug.sh); do
    "$B/bin/dex-patch" supervise "$limit" /bin/true /bin/true
done
"$B/bin/dex-patch" lock-run "$t/free.lock" /bin/true unused
cat > "$t/adapter" <<'SH'
#!/bin/bash
case "$1" in
get) cat "$PROPS/$2" 2>/dev/null || :;;
set) printf '%s\n' "$3" > "$PROPS/$2";;
capture)
    echo recording > "$2"
    trap '' TERM
    while :; do sleep 60 & wait $! || :; done;;
*) exit 1;;
esac
SH
chmod +x "$t/adapter"
export PORTABLE_TEST_ROOT=$R PORTABLE_TEST_DEBUG_ADAPTER=$t/adapter PROPS=$t/props
echo f > "$PROPS/persist.iap2.debug.service"
echo custom > "$PROPS/log.tag.CarPlay_"
mksh "$B/debug.sh" on
grep -qx t "$PROPS/persist.iap2.debug.service"
grep -qx 1 "$PROPS/debug.gen5wkr.trace"
grep -qx V "$PROPS/log.tag.CarPlay_"
[ -f "$R/data/nemesis/gen5wkr.debug-on" ]
mksh "$B/debug.sh" on
echo foreign > "$PROPS/log.tag.CarPlay_"
mksh "$B/debug.sh" off
grep -qx f "$PROPS/persist.iap2.debug.service"
grep -qx foreign "$PROPS/log.tag.CarPlay_"
[ ! -e "$R/data/nemesis/gen5wkr.debug-on" ]
# The registered background service invokes the script with no arguments.
mksh "$B/debug.sh" on
mksh "$B/debug.sh" > "$t/worker.log" 2>&1 & runner=$!
for i in $(seq 100); do [ -s "$R/data/local/gen5w-portable/debug/logcat.log" ] && [ -s "$R/data/local/gen5w-portable/debug/focus.log" ] && break; sleep .1; done
[ -s "$R/data/local/gen5w-portable/debug/logcat.log" ] || { cat "$t/worker.log"; exit 1; }
[ -s "$R/data/local/gen5w-portable/debug/focus.log" ] || { cat "$t/worker.log"; exit 1; }
capture_file=$R/data/local/gen5w-portable/debug/capture
focus_capture_file=$R/data/local/gen5w-portable/debug/capture-focus
for i in $(seq 100); do [ -s "$capture_file" ] && [ -s "$focus_capture_file" ] && break; sleep .05; done
old_capture=$(cat "$capture_file")
old_focus=$(cat "$focus_capture_file")
kill -KILL "$runner"; wait "$runner" 2>/dev/null || :; runner=
# The capture child survives its parent here, as on an abrupt service kill.
# It must not retain FD9 and prevent a replacement from taking the worker lock.
mksh "$B/debug.sh" > "$t/worker.log" 2>&1 & runner=$!
for i in $(seq 100); do
    [ "$(cat "$capture_file" 2>/dev/null)" != "$old_capture" ] && [ -s "$capture_file" ] && [ "$(cat "$focus_capture_file" 2>/dev/null)" != "$old_focus" ] && [ -s "$focus_capture_file" ] && break
    sleep .1
done
[ "$(cat "$capture_file")" != "$old_capture" ] || { cat "$t/worker.log"; exit 1; }
[ "$(cat "$focus_capture_file")" != "$old_focus" ] || { cat "$t/worker.log"; exit 1; }
kill -0 "$runner"
# Live focus/logcat writers must hold their writer locks inside supervise worker (exact rc=75).
for wlock in "$R/data/local/gen5w-portable/debug/focus-writer.lock" "$R/data/local/gen5w-portable/debug/logcat-writer.lock"; do
    rc=0
    "$B/bin/dex-patch" lock-run "$wlock" /bin/true unused 2>/dev/null || rc=$?
    [ "$rc" = 75 ] || { echo "FAIL $wlock lock-run rc=$rc expected 75"; exit 1; }
done
# Capture rollover while debug remains enabled stops SIGTERM-ignoring writer via rescue+lock-wait first and latches .3 -> .2 -> .1 -> current chronologically.
before_latch_focus=$(cat "$focus_capture_file")
echo oldest-3-line > "$R/data/local/gen5w-portable/debug/focus.log.3"
echo oldest-2-line > "$R/data/local/gen5w-portable/debug/focus.log.2"
echo earlier-1-line > "$R/data/local/gen5w-portable/debug/focus.log.1"
for i in $(seq 100); do
    [ -s "$R/data/local/gen5w-portable/debug/focus-first.log" ] && [ "$(cat "$focus_capture_file" 2>/dev/null)" != "$before_latch_focus" ] && break
    sleep .1
done
[ -s "$R/data/local/gen5w-portable/debug/focus-first.log" ] || { cat "$t/worker.log"; exit 1; }
grep -qx oldest-3-line "$R/data/local/gen5w-portable/debug/focus-first.log"
grep -qx oldest-2-line "$R/data/local/gen5w-portable/debug/focus-first.log"
grep -qx earlier-1-line "$R/data/local/gen5w-portable/debug/focus-first.log"
grep -qx recording "$R/data/local/gen5w-portable/debug/focus-first.log"
test "$(grep -n '^oldest-3-line$' "$R/data/local/gen5w-portable/debug/focus-first.log" | cut -d: -f1)" -lt "$(grep -n '^oldest-2-line$' "$R/data/local/gen5w-portable/debug/focus-first.log" | cut -d: -f1)"
test "$(grep -n '^oldest-2-line$' "$R/data/local/gen5w-portable/debug/focus-first.log" | cut -d: -f1)" -lt "$(grep -n '^earlier-1-line$' "$R/data/local/gen5w-portable/debug/focus-first.log" | cut -d: -f1)"
test "$(grep -n '^earlier-1-line$' "$R/data/local/gen5w-portable/debug/focus-first.log" | cut -d: -f1)" -lt "$(grep -n '^recording$' "$R/data/local/gen5w-portable/debug/focus-first.log" | cut -d: -f1)"
grep -qx t "$PROPS/persist.iap2.debug.service"
echo later-window > "$R/data/local/gen5w-portable/debug/focus.log"
next_focus=$(cat "$focus_capture_file")
kill "${next_focus%%:*}" 2>/dev/null || :
for i in $(seq 100); do
    [ "$(cat "$focus_capture_file" 2>/dev/null)" != "$next_focus" ] && break
    sleep .1
done
! grep -q later-window "$R/data/local/gen5w-portable/debug/focus-first.log"
mksh "$B/debug.sh" off
for i in $(seq 50); do
    kill -0 "$runner" 2>/dev/null || { echo 'FAIL worker exited unexpectedly'; exit 1; }
    if "$B/bin/dex-patch" lock-run "$R/data/local/gen5w-portable/debug/focus-writer.lock" /bin/true unused 2>/dev/null && \
       "$B/bin/dex-patch" lock-run "$R/data/local/gen5w-portable/debug/logcat-writer.lock" /bin/true unused 2>/dev/null; then
        break
    fi
    sleep .1
done
for i in $(seq 100); do [ ! -f "$R/data/local/gen5w-portable/debug/before.persist.iap2.debug.service" ] && break; sleep .1; done
grep -qx f "$PROPS/persist.iap2.debug.service"
kill -0 "$runner"
# debug.sh off itself releases both writer locks while the worker daemon remains alive.
"$B/bin/dex-patch" lock-run "$R/data/local/gen5w-portable/debug/focus-writer.lock" /bin/true unused
"$B/bin/dex-patch" lock-run "$R/data/local/gen5w-portable/debug/logcat-writer.lock" /bin/true unused
# Re-enabling debug after off clears stale rotated focus rings so .2 does not pre-latch focus-first.log.
echo stale-off-ring > "$R/data/local/gen5w-portable/debug/focus.log.2"
echo stale-off-first > "$R/data/local/gen5w-portable/debug/focus-first.log"
mksh "$B/debug.sh" on
for i in $(seq 100); do
    [ ! -e "$R/data/local/gen5w-portable/debug/focus-reset" ] && [ -s "$R/data/local/gen5w-portable/debug/focus.log" ] && break
    sleep .1
done
[ ! -e "$R/data/local/gen5w-portable/debug/focus-reset" ]
[ ! -e "$R/data/local/gen5w-portable/debug/focus.log.2" ]
[ ! -e "$R/data/local/gen5w-portable/debug/focus-first.log" ]
# Immediate off -> on while capture is live must break inner loop, clear stale focus logs, and NOT delete new session logs after rollover.
echo stale-fast-ring > "$R/data/local/gen5w-portable/debug/focus.log.2"
echo stale-fast-first > "$R/data/local/gen5w-portable/debug/focus-first.log"
mksh "$B/debug.sh" off
mksh "$B/debug.sh" on
for i in $(seq 100); do
    [ ! -e "$R/data/local/gen5w-portable/debug/focus-reset" ] && \
    [ ! -e "$R/data/local/gen5w-portable/debug/focus.log.2" ] && \
    [ ! -e "$R/data/local/gen5w-portable/debug/focus-first.log" ] && \
    [ -s "$R/data/local/gen5w-portable/debug/focus.log" ] && break
    sleep .1
done
[ ! -e "$R/data/local/gen5w-portable/debug/focus-reset" ]
[ ! -e "$R/data/local/gen5w-portable/debug/focus.log.2" ]
[ ! -e "$R/data/local/gen5w-portable/debug/focus-first.log" ]
[ -s "$R/data/local/gen5w-portable/debug/focus.log" ]
mksh "$B/debug.sh" off
for i in $(seq 50); do
    kill -0 "$runner" 2>/dev/null || { echo 'FAIL worker exited unexpectedly'; exit 1; }
    if "$B/bin/dex-patch" lock-run "$R/data/local/gen5w-portable/debug/focus-writer.lock" /bin/true unused 2>/dev/null && \
       "$B/bin/dex-patch" lock-run "$R/data/local/gen5w-portable/debug/logcat-writer.lock" /bin/true unused 2>/dev/null; then
        break
    fi
    sleep .1
done
for i in $(seq 100); do [ ! -f "$R/data/local/gen5w-portable/debug/before.persist.iap2.debug.service" ] && break; sleep .1; done
# Direct flag toggle without debug.sh on (e.g., ui.sh or external switch) also clears stale focus rings.
[ -f "$R/data/local/gen5w-portable/debug/focus-reset" ]
echo stale-ui-ring > "$R/data/local/gen5w-portable/debug/focus.log.2"
echo stale-ui-first > "$R/data/local/gen5w-portable/debug/focus-first.log"
: > "$R/data/nemesis/gen5wkr.debug-on"
for i in $(seq 100); do
    [ ! -e "$R/data/local/gen5w-portable/debug/focus-reset" ] && [ -s "$R/data/local/gen5w-portable/debug/focus.log" ] && break
    sleep .1
done
[ ! -e "$R/data/local/gen5w-portable/debug/focus-reset" ]
[ ! -e "$R/data/local/gen5w-portable/debug/focus.log.2" ]
[ ! -e "$R/data/local/gen5w-portable/debug/focus-first.log" ]
mksh "$B/debug.sh" off
for i in $(seq 50); do
    kill -0 "$runner" 2>/dev/null || { echo 'FAIL worker exited unexpectedly'; exit 1; }
    if "$B/bin/dex-patch" lock-run "$R/data/local/gen5w-portable/debug/focus-writer.lock" /bin/true unused 2>/dev/null && \
       "$B/bin/dex-patch" lock-run "$R/data/local/gen5w-portable/debug/logcat-writer.lock" /bin/true unused 2>/dev/null; then
        break
    fi
    sleep .1
done
for i in $(seq 100); do [ ! -f "$R/data/local/gen5w-portable/debug/before.persist.iap2.debug.service" ] && break; sleep .1; done
kill "$runner"; wait "$runner"; runner=
# Boot ID change clears stale rotated focus rings even when debug remained enabled across reboot.
mkdir -p "$R/proc/sys/kernel/random"
echo boot-1 > "$R/data/local/gen5w-portable/debug/boot-id"
echo boot-2 > "$R/proc/sys/kernel/random/boot_id"
: > "$R/data/nemesis/gen5wkr.debug-on"
echo stale-boot-ring > "$R/data/local/gen5w-portable/debug/focus.log.2"
echo stale-boot-first > "$R/data/local/gen5w-portable/debug/focus-first.log"
mksh "$B/debug.sh" > "$t/worker2.log" 2>&1 & runner=$!
for i in $(seq 100); do
    grep -qx boot-2 "$R/data/local/gen5w-portable/debug/boot-id" 2>/dev/null && [ -s "$R/data/local/gen5w-portable/debug/focus.log" ] && break
    sleep .1
done
grep -qx boot-2 "$R/data/local/gen5w-portable/debug/boot-id"
[ ! -e "$R/data/local/gen5w-portable/debug/focus.log.2" ]
[ ! -e "$R/data/local/gen5w-portable/debug/focus-first.log" ]
mksh "$B/debug.sh" off
for i in $(seq 50); do
    kill -0 "$runner" 2>/dev/null || { echo 'FAIL worker2 exited unexpectedly'; exit 1; }
    if "$B/bin/dex-patch" lock-run "$R/data/local/gen5w-portable/debug/focus-writer.lock" /bin/true unused 2>/dev/null && \
       "$B/bin/dex-patch" lock-run "$R/data/local/gen5w-portable/debug/logcat-writer.lock" /bin/true unused 2>/dev/null; then
        break
    fi
    sleep .1
done
for i in $(seq 100); do [ ! -f "$R/data/local/gen5w-portable/debug/before.persist.iap2.debug.service" ] && break; sleep .1; done
kill "$runner"; wait "$runner"; runner=
# Stale transaction locks and interrupted temporary snapshots do not commit.
echo '99999999:1' > "$R/data/local/gen5w-portable/debug/properties.lock"
: > "$R/data/local/gen5w-portable/debug/before.persist.iap2.debug.service.tmp.interrupted"
mksh "$B/debug.sh" on
mksh "$B/debug.sh" off
grep -qx f "$PROPS/persist.iap2.debug.service"
mkdir "$t/foreign"
ln -s "$t/foreign" "$R/data/nemesis/gen5wkr.debug-on"
if mksh "$B/debug.sh" on; then echo FAIL unsafe-flag; exit 1; fi
[ -z "$(ls -A "$t/foreign")" ]
echo 'PASS debug properties: enable, idempotent snapshot, restore, foreign edit and symlink preservation'
