#!/bin/bash
# Real control flow; fake only exact-byte patcher and privileged mount boundary.
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/gen5w-hotspot-remount.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/system/app" "$fixture/system/etc" "$fixture/data" "$fixture/bin"
cat > "$fixture/patch" <<'EOF'
#!/bin/sh
case "$1" in
 verify) [ "$(cat "$2")" = apk ];;
 original) [ -f "$2" ] && [ "$(cat "$2")" = original ];;
 patched) [ -f "$2" ] && [ "$(cat "$2")" = patched ];;
 apply) [ "$(cat "$2")" = original ] && echo patched > "$3";;
 *) exit 1;;
esac
EOF
cat > "$fixture/nemesis" <<'EOF'
#!/bin/sh
echo "$*" >> "$CASE_DIR/mount-calls"
[ "$2" = ro ] || exit 0
n=$(cat "$CASE_DIR/count" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$CASE_DIR/count"
case "$MODE" in
 retry) [ "$n" -ge 2 ] && exit 0; echo 'remount: Device or resource busy' >&2;;
 busy) echo 'remount: Device or resource busy' >&2;;
 denied) echo 'remount: Permission denied' >&2;;
 huge) python3 -c 'import sys;sys.stderr.write("Permission denied password=hotspot-private " + "x"*262144)' ;;
 unknown) :;;
 corrupt) if [ "$n" -le 3 ]; then echo corrupted > "$CASE_DIR/system/app/HKMC_WifiSettings.odex"; fi; echo 'remount: Device or resource busy' >&2;;
esac
exit 1
EOF
printf '#!/bin/sh\nexit 0\n' > "$fixture/bin/sleep"
printf '#!/bin/sh\nexit 0\n' > "$fixture/bin/chown"
chmod 755 "$fixture/patch" "$fixture/nemesis" "$fixture/bin/sleep" "$fixture/bin/chown"
export CASE_DIR="$fixture" HOTSPOT_TEST_SYS="$fixture/system" HOTSPOT_TEST_DATA="$fixture/data"
export HOTSPOT_TEST_PATCH="$fixture/patch" HOTSPOT_TEST_NEM="$fixture/nemesis" HOTSPOT_TEST_MOUNTS="$fixture/mounts"
export PATH="$fixture/bin:$PATH"
echo apk > "$fixture/system/app/HKMC_WifiSettings.apk"
target="$fixture/system/app/HKMC_WifiSettings.odex"
control=tools/local-hotspot/package/scripts/control.sh
reset_case() {
 echo original > "$target"
 rm -f "$fixture/count" "$fixture/mount-calls"
 echo "/dev/block/system $fixture/system ext4 rw,relatime 0 0" > "$fixture/mounts"
}
run() { mksh "$control" "$1" > "$fixture/output" 2>&1; }
reset_case; export MODE=unknown
run remove || { cat "$fixture/output"; echo 'FAIL already-stock removal must not remount'; exit 1; }
test ! -e "$fixture/mount-calls"
test ! -e "$fixture/system/etc/gen5w-kr-backup/local-hotspot"
test "$(cat "$target")" = original
backup="$fixture/system/etc/gen5w-kr-backup/local-hotspot"
mkdir -p "$backup"
cp "$control" "$backup/recover.sh"
cp "$fixture/patch" "$backup/hotspot-patch"
printf '#!/bin/sh\ncase "$2" in */hotspot-patch) exit 1;; esac\nexec /bin/chmod "$@"\n' > "$fixture/bin/chmod"
/bin/chmod 755 "$backup/hotspot-patch" "$fixture/bin/chmod"
env -u HOTSPOT_TEST_PATCH mksh "$backup/recover.sh" remove > "$fixture/output" 2>&1 ||
 { cat "$fixture/output"; echo 'FAIL executable durable helper must not be chmodded on stock removal'; exit 1; }
test ! -e "$fixture/mount-calls"
rm "$fixture/bin/chmod"
reset_case; export MODE=busy
run install || { cat "$fixture/output"; echo 'FAIL verified busy install rejected'; exit 1; }
test "$(cat "$target")" = patched
test "$(cat "$fixture/count")" = 3
grep -q 'WARN:.*read-only' "$fixture/output"
grep -q 'reason=busy\|Device or resource busy' "$fixture/output"
grep -q 'ext4 rw,relatime' "$fixture/output"
run remove
test "$(cat "$target")" = original
rm -f "$fixture/mount-calls"
export MODE=unknown
run remove # Already-stock cleanup must not trap integrated rollback in failure.
test ! -e "$fixture/mount-calls"
test "$(cat "$fixture/system/etc/gen5w-kr-backup/local-hotspot/original.odex")" = original
reset_case; export MODE=retry
run install
test "$(cat "$target")" = patched
test "$(cat "$fixture/count")" = 2
for MODE in denied unknown corrupt; do
 export MODE; reset_case
 if run install; then echo "FAIL unsafe $MODE accepted"; exit 1; fi
 test "$(cat "$target")" = original
done
reset_case; export MODE=huge
if run install; then echo 'FAIL huge permission failure accepted'; exit 1; fi
test "$(cat "$target")" = original
! grep -q hotspot-private "$fixture/output"
test "$(wc -c < "$fixture/output")" -lt 16384
reset_case; export MODE=busy
echo '/dev/block/system /different ext4 rw 0 0' > "$fixture/mounts"
if run install; then echo 'FAIL busy with unknown mount accepted'; exit 1; fi
test "$(cat "$target")" = original
echo 'PASS hotspot remount retry/busy/permission/unknown/corruption/rollback'
