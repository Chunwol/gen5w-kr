#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export PORTABLE_TEST_ROOT=$t/root PROP_DIR=$t/props
mkdir -p "$PROP_DIR" "$t/bin"
cat > "$t/bin/getprop" <<'SH'
#!/bin/sh
cat "$PROP_DIR/$1" 2>/dev/null || :
SH
cat > "$t/bin/setprop" <<'SH'
#!/bin/sh
[ ! -f "$PROP_DIR/fail-$1" ] || exit 1
printf '%s|%s\n' "$1" "$2" >> "$PROP_DIR/writes"
printf '%s' "$2" > "$PROP_DIR/$1"
SH
chmod +x "$t/bin/"*; export PATH=$t/bin:$PATH
run() { mksh tools/portable/network-adb.sh "$@"; }
legacy=persist.service.adb.tcp.enable; port=persist.adb.tcp.port
value() { cat "$PROP_DIR/$1" 2>/dev/null || :; }
printf 1 > "$PROP_DIR/$legacy"
run apply
[ "$(value "$legacy")" = 0 ]; [ "$(value "$port")" = 5555 ]
run apply
# Recovery remains executable after package removal.
mksh "$PORTABLE_TEST_ROOT/data/local/gen5w-portable/network-adb/restore.sh" restore
[ "$(value "$legacy")" = 1 ]; [ -z "$(value "$port")" ]
for p in 7777 -1 0; do
 printf '%s' "$p" > "$PROP_DIR/$port"
 run apply; [ "$(value "$port")" = "$p" ]; run restore
 [ "$(value "$port")" = "$p" ]
done
printf '' > "$PROP_DIR/$port"
run apply
printf 8888 > "$PROP_DIR/$port"; printf 2 > "$PROP_DIR/$legacy"
run apply
run restore
[ "$(value "$port")" = 8888 ]; [ "$(value "$legacy")" = 2 ]
printf 1 > "$PROP_DIR/$legacy"; printf '' > "$PROP_DIR/$port"
touch "$PROP_DIR/fail-$legacy"
if run apply; then echo 'FAIL accepted failed setprop'; exit 1; fi
[ -z "$(value "$port")" ]; rm "$PROP_DIR/fail-$legacy"
run apply; run restore
# Interrupted after first property write: retained intent permits USB recovery.
state=$PORTABLE_TEST_ROOT/data/local/gen5w-portable/network-adb
printf 'network-adb-v1\n1\n1\n\n5555\n' > "$state/journal"
printf 5555 > "$PROP_DIR/$port"
printf '%s|%s:0\n' "$(cat /proc/sys/kernel/random/boot_id)" $$ > "$state/lock"
run apply
[ "$(value "$port")" = 5555 ]; [ "$(value "$legacy")" = 0 ]
: > "$PROP_DIR/writes"
run restore
[ -z "$(value "$port")" ]; [ "$(value "$legacy")" = 1 ]
[ "$(cat "$PROP_DIR/writes")" = "$port|"$'\n'"$legacy|1" ]
# Malformed journals are rejected without sourcing shell content.
printf 'bad\n' > "$state/journal"
if run restore; then echo 'FAIL accepted malformed journal'; exit 1; fi
[ "$(value "$legacy")" = 1 ]; rm "$state/journal"
# Refuse journal/helper and ancestor symlinks before property writes.
state=$PORTABLE_TEST_ROOT/data/local/gen5w-portable/network-adb
ln -s "$t/foreign" "$state/journal"
if run apply; then echo 'FAIL accepted journal symlink'; exit 1; fi
[ "$(value "$legacy")" = 1 ]; rm "$state/journal"
rm -rf "$PORTABLE_TEST_ROOT/data/local/gen5w-portable/network-adb"
ln -s "$t/foreign" "$state"
if run apply; then echo 'FAIL accepted state symlink'; exit 1; fi
[ "$(value "$legacy")" = 1 ]
echo 'PASS network ADB migration, retained restore, custom/disabled ports, foreign changes, rollback, symlink refusal'
