#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v mksh >/dev/null || exit 78
t=$(mktemp -d /tmp/gen5w-bootguard.XXXXXX)
trap 'rm -rf "$t"' EXIT
root=$t/root
guard=$root/data/local/gen5w-portable/persistent/bootguard
state=$root/data/local/gen5w-portable/boot
mkdir -p "$guard/bin" "$state"
cat > "$t/getprop" <<'SH'
#!/bin/sh
case "$1" in
sys.boot_completed) echo "${TEST_COMPLETED:-0}";;
init.svc.zygote) echo "${TEST_ZYGOTE:-running}";;
esac
SH
# Restore dispatch is isolated here; the real restore has its own fixture suite.
cat > "$guard/restore.sh" <<'SH'
#!/bin/sh
[ "$GEN5W_RECOVERY_USB_ROOT" = "$PORTABLE_TEST_ROOT/data/local/gen5w-portable/persistent/bootguard" ] || exit 90
echo called >> "$GEN5W_RECOVERY_USB_ROOT/calls"
exit "${TEST_RESTORE_RC:-0}"
SH
cat > "$guard/bin/dex-patch" <<'SH'
#!/bin/sh
[ "$1" = size ] || exit 2
wc -c < "$2"
SH
chmod +x "$t/getprop" "$guard/bin/dex-patch"
run() {
    PORTABLE_TEST_ROOT="$root" PORTABLE_TEST_GETPROP="$t/getprop" PORTABLE_TEST_SH=/bin/sh \
    GEN5W_BOOTGUARD_WAIT=2 GEN5W_BOOTGUARD_STABLE=0 \
    mksh tools/portable/bootguard.sh
}
run
[ "$(cat "$guard/count")" = 1 ]
run
[ "$(cat "$guard/count")" = 2 ]
TEST_COMPLETED=1 run
[ "$(cat "$guard/count")" = 0 ]
TEST_COMPLETED=1 TEST_ZYGOTE=stopped run
[ "$(cat "$guard/count")" = 1 ]
dd if=/dev/zero of="$guard/guard.log" bs=65536 count=1 2>/dev/null
run
[ -f "$guard/guard.log.1" ]
[ "$(wc -c < "$guard/guard.log.1")" = 65536 ]
echo 'PASS bootguard bounded log rotation via installed size helper'
echo 'PASS bootguard increments, incomplete/unstable boot retains count, stable boot clears'
echo 3 > "$guard/count"
run
[ "$(cat "$guard/count")" = 4 ]
[ ! -e "$guard/tripped" ] && [ ! -e "$guard/calls" ]
TEST_RESTORE_RC=7 run && { echo 'FAIL restore failure accepted'; exit 1; }
[ ! -e "$guard/tripped" ]
[ "$(cat "$guard/count")" = 5 ]
run
[ -f "$guard/tripped" ]
[ "$(cat "$state/enabled")" = 0 ]
[ "$(cat "$state/reason")" = bootguard-restored ]
[ "$(wc -l < "$guard/calls")" = 2 ]
before=$(cat "$guard/count")
run
[ "$(cat "$guard/count")" = "$before" ]
[ "$(wc -l < "$guard/calls")" = 2 ]
echo 'PASS bootguard threshold, restore environment, failure retry, latch'
rm "$guard/tripped"
for name in count count.new tripped guard.log restore.sh bin bin/dex-patch; do
    path=$guard/$name
    if [ -e "$path" ]; then mv "$path" "$t/saved"; fi
    ln -s "$t/outside" "$path"
    printf untouched > "$t/outside"
    snapshot=$(find "$root" -type f -exec sha256sum {} \; | sort)
    run
    [ "$(cat "$t/outside")" = untouched ]
    [ "$(find "$root" -type f -exec sha256sum {} \; | sort)" = "$snapshot" ]
    rm "$path"
    if [ -e "$t/saved" ]; then mv "$t/saved" "$path"; fi
done
mv "$guard" "$t/real-guard"
ln -s "$t/real-guard" "$guard"
snapshot=$(find "$t/real-guard" -type f -exec sha256sum {} \; | sort)
run
[ "$(find "$t/real-guard" -type f -exec sha256sum {} \; | sort)" = "$snapshot" ]
echo 'PASS bootguard symlinked guard and files exit without writes'
