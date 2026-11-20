#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/g5p-rescue.XXXXXX)
trap 'rc=$?; rm -rf "$t"; exit $rc' EXIT
mkdir -p "$t/root/data/bundle" "$t/root/storage/usb0" "$t/root/data/local/gen5w-portable/boot" "$t/actions"
cp tools/portable/rescue-watch.sh "$t/root/data/bundle/"
cat > "$t/adapter" <<'SH'
#!/bin/bash
case "$1" in disable) echo disable >> "$ACTIONS/log"; [ ! -f "$ACTIONS/fail" ];; *) exit 1;; esac
SH
chmod +x "$t/adapter"
export PORTABLE_TEST_ROOT=$t/root PORTABLE_TEST_RESCUE_ADAPTER=$t/adapter ACTIONS=$t/actions
mkdir "$t/no-printf"
printf '#!/bin/sh\nexit 127\n' > "$t/no-printf/printf"
chmod +x "$t/no-printf/printf"
run() { PATH="$t/no-printf:$PATH" mksh "$t/root/data/bundle/rescue-watch.sh" "$@"; }
marker=$t/root/storage/usb0/GEN5W-PORTABLE-RESCUE
j=$t/root/data/local/gen5w-portable/boot
if run check; then echo 'FAIL absent marker accepted'; exit 1; fi
printf wrong > "$marker"
if run check; then echo 'FAIL wrong marker accepted'; exit 1; fi
printf 'disable-portable-v1\n' > "$t/token"
rm "$marker"; ln -s "$t/token" "$marker"
if run check; then echo 'FAIL symlink marker accepted'; exit 1; fi
rm "$marker"; cp "$t/token" "$marker"
run check
# Windows Notepad writes CRLF: 21 bytes must still be recognised.
printf 'disable-portable-v1\r\n' > "$marker"
run check
cp "$t/token" "$marker"
# Even if Android teardown fails, durable disable happens first, with no UI.
echo 1 > "$j/enabled"; touch "$ACTIONS/fail"
if run disable; then echo 'FAIL hid restore failure'; exit 1; fi
[ "$(cat "$j/enabled")" = 0 ] && [ -f "$j/rescue-request" ]
grep -qx restore-required "$j/rescue-result"
rm "$ACTIONS/fail"
run disable
grep -qx restored "$j/rescue-result"
[ "$(cat "$j/enabled")" = 0 ]
# Insertion on another NEMESIS root and stale boot_completed need no manager.
rm "$marker"; mkdir -p "$t/root/mnt/media_rw/usb2"
cp "$t/token" "$t/root/mnt/media_rw/usb2/GEN5W-PORTABLE-RESCUE"
run check
# Bounded input rejects large or additional instructions.
printf 'disable-portable-v1\nexecute\n' > "$t/root/mnt/media_rw/usb2/GEN5W-PORTABLE-RESCUE"
if run check; then echo 'FAIL extra instruction accepted'; exit 1; fi
printf '%010000d' 0 > "$t/root/mnt/media_rw/usb2/GEN5W-PORTABLE-RESCUE"
if run check; then echo 'FAIL oversized marker accepted'; exit 1; fi
# A real watch loop sees insertion without NEMESIS USB execute or a dialog.
rm "$t/root/mnt/media_rw/usb2/GEN5W-PORTABLE-RESCUE"
rm "$j/rescue-result"; echo 1 > "$j/enabled"
run watch > "$ACTIONS/watch.log" 2>&1 & watcher=$!
sleep .1
cp "$t/token" "$marker"
for n in {1..400}; do [ "$(cat "$j/rescue-result" 2>/dev/null)" != restored ] || break; sleep .01; done
kill "$watcher"; wait "$watcher" 2>/dev/null || :
[ "$(cat "$j/enabled")" = 0 ] && grep -qx restored "$j/rescue-result"
echo 'PASS independent USB rescue: exact marker (LF/CRLF), all fixed roots, no Android/UI gate, durable disable before failed teardown, retry, unsafe input refusal'
