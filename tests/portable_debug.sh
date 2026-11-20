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
cat > "$t/adapter" <<'SH'
#!/bin/bash
case "$1" in
get) cat "$PROPS/$2" 2>/dev/null || :;;
set) printf '%s\n' "$3" > "$PROPS/$2";;
capture) echo recording > "$2"; exec sleep 60;;
*) exit 1;;
esac
SH
chmod +x "$t/adapter"
export PORTABLE_TEST_ROOT=$R PORTABLE_TEST_DEBUG_ADAPTER=$t/adapter PROPS=$t/props
echo f > "$PROPS/persist.iap2.debug.service"
echo custom > "$PROPS/log.tag.CarPlay_"
mksh "$B/debug.sh" on
grep -qx t "$PROPS/persist.iap2.debug.service"
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
for i in $(seq 100); do [ -s "$R/data/local/gen5w-portable/debug/logcat.log" ] && break; sleep .1; done
[ -s "$R/data/local/gen5w-portable/debug/logcat.log" ] || { cat "$t/worker.log"; exit 1; }
capture_file=$R/data/local/gen5w-portable/debug/capture
for i in $(seq 100); do [ -s "$capture_file" ] && break; sleep .05; done
old_capture=$(cat "$capture_file")
kill -KILL "$runner"; wait "$runner" 2>/dev/null || :; runner=
# The capture child survives its parent here, as on an abrupt service kill.
# It must not retain FD9 and prevent a replacement from taking the worker lock.
mksh "$B/debug.sh" > "$t/worker.log" 2>&1 & runner=$!
for i in $(seq 100); do
    [ "$(cat "$capture_file" 2>/dev/null)" != "$old_capture" ] && [ -s "$capture_file" ] && break
    sleep .1
done
[ "$(cat "$capture_file")" != "$old_capture" ] || { cat "$t/worker.log"; exit 1; }
kill -0 "$runner"
mksh "$B/debug.sh" off
for i in $(seq 100); do [ ! -f "$R/data/local/gen5w-portable/debug/before.persist.iap2.debug.service" ] && break; sleep .1; done
grep -qx f "$PROPS/persist.iap2.debug.service"
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
