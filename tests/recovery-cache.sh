#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
W=$(mktemp -d)
stubs
mkdir -p "$W/usb" "$W/data/nemesis" "$W/foreign"
echo untouched > "$W/foreign/sentinel"
echo verified > "$W/usb/payload"
(cd "$W/usb" && md5sum payload > RECOVERY.md5 && md5sum RECOVERY.md5 | cut -d' ' -f1 > RECOVERY.receipt)
cp tools/integrated/recovery-lib.sh "$W/lib.sh"
run() { (cd "$W/usb" && IT_DATA="$W/data" PATH="$W/bin:$PATH" mksh -c 'umask 0002; . "$1"; r_prepare' _ "$W/lib.sh" > "$W/out" 2>&1); }
check 'first runner preparation succeeds with group-writable process umask' run
check 'new runner root is private despite inherited umask' test "$(stat -c %a "$W/data/nemesis/gen5wkr.recovery/current")" = 700
RB="$W/data/nemesis/gen5wkr.recovery"
ln -s "$W/foreign" "$RB/previous"
mkdir "$RB/staging"
echo partial-cache > "$RB/staging/evidence"
echo next-generation > "$W/usb/payload"
(cd "$W/usb" && md5sum payload > RECOVERY.md5 && md5sum RECOVERY.md5 | cut -d' ' -f1 > RECOVERY.receipt)
check 'new verified generation replaces stale cache without executing old contents' run
check 'foreign symlink target is unchanged' grep -qx untouched "$W/foreign/sentinel"
check 'active runner is exactly the new verified generation' grep -qx next-generation "$RB/current/payload"
check 'partial staging cache evidence is retained' eval 'test "$(find "$RB" -name evidence | wc -l)" = 1'
check 'stale linked previous cache is retained without following it' eval 'test "$(find "$RB" -maxdepth 1 -type l | wc -l)" = 1'
mv "$RB/current" "$W/retained-current"
cp "$W/usb/payload" "$W/usb/RECOVERY.md5" "$W/usb/RECOVERY.receipt" "$W/foreign/"
ln -s "$W/foreign" "$RB/current"
check 'matching manifest cannot make a linked active runner trusted' run
check 'published active runner is private and not a symbolic link' eval 'test ! -L "$RB/current" && test "$(stat -c %a "$RB/current")" = 700'
check 'replacing a linked current cache never alters its foreign target' grep -qx untouched "$W/foreign/sentinel"
echo tampered >> "$W/usb/payload"
check 'unverified replacement refuses without changing active generation' eval '! run && grep -qx next-generation "$RB/current/payload"'
rm -rf "$W"
done_tests recovery-cache
