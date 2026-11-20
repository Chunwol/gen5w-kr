#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/g5p-ap.XXXXXX)
trap 'rc=$?; chmod -R u+rwx "$t" 2>/dev/null || :; rm -rf "$t"; exit $rc' EXIT
mkdir -p "$t/root/data/bundle/bin" "$t/act"
cp tools/portable/ap.sh "$t/root/data/bundle/"
cp .build/portable/dex-patch-host "$t/root/data/bundle/bin/dex-patch"
R=$t/root; A=$t/act; N=$R/data/nemesis; G=$N/gen5wkr.apguard
HF=$R/data/data/kr.gen5w.wirelesshost/files; S=$R/data/local/gen5w-portable/ap
H=$R/data/bundle/bin/dex-patch
BOOT_NOW=0123abcd-0000-1111-2222-333344445555
BOOT_OLD=fedcba98-0000-1111-2222-333344445555
# AP adapter: the Android boundaries ap.sh needs (settings, boot id, sync).
cat > "$t/ap-adapter" <<SH
#!/bin/bash
case "\$1" in
wifi-ap-on) [ -f "$A/wifi_ap_on" ] || exit 1; cat "$A/wifi_ap_on";;
boot) echo $BOOT_NOW;;
sync) echo sync >> "$A/sync-log"; [ ! -f "$A/sync-fail" ];;
*) echo "unexpected op \$1" >> "$A/errors"; exit 1;;
esac
SH
chmod 755 "$t/ap-adapter"
export PORTABLE_TEST_ROOT=$R PORTABLE_TEST_AP_ADAPTER=$t/ap-adapter
run() { mksh "$R/data/bundle/ap.sh" "$@"; }
fail() { echo "FAIL $*" >&2; exit 1; }
refused() { # what expected-message command...: must fail, and for the expected reason
    local what=$1 why=$2; shift 2
    if run "$@" > "$A/out" 2>&1; then cat "$A/out" >&2; fail "$what"; fi
    grep -qF -- "$why" "$A/out" || { cat "$A/out" >&2; fail "$what: refused for another reason (want: $why)"; }
}

# ---- prepare: initial staged admission requires wifi_ap_on exactly 0 ----
for value in 1 null '' unsupported; do
    printf '%s\n' "$value" > "$A/wifi_ap_on"
    refused "prepare admitted wifi_ap_on='$value'" 'wifi_ap_on' prepare
    [ ! -e "$N/gen5wkr.ap-match" ] && [ ! -e "$G" ] || fail "rejected prepare changed state ($value)"
done
rm -f "$A/wifi_ap_on"
refused 'prepare admitted unreadable wifi_ap_on' 'wifi_ap_on unreadable' prepare
[ ! -e "$N/gen5wkr.ap-match" ] || fail 'unreadable setting changed state'
(unset PORTABLE_TEST_AP_ADAPTER; if mksh "$R/data/bundle/ap.sh" prepare 2>/dev/null; then exit 1; fi) || fail 'fixture prepare without adapter'
echo 0 > "$A/wifi_ap_on"

# ---- existing behaviour ----
run prepare
[ "$(cat "$N/gen5wkr.ap-match")" = match ]
[ "$(stat -c %a "$G")" = 700 ]
run check
# Previous success must not hide a later interrupted start, even same boot ID.
echo ok > "$G/ok"
echo same-boot > "$G/attempt"
rc=0; run check || rc=$?; [ "$rc" = 77 ]
run disable
[ ! -e "$N/gen5wkr.ap-match" ]
[ -f "$G/attempt" ]
rm "$G/attempt"
# Existing valid mode belongs to someone else; use it but never delete it.
echo match > "$N/gen5wkr.ap-match"
run prepare
run disable
[ -f "$N/gen5wkr.ap-match" ]
rm "$N/gen5wkr.ap-match"
rm "$S/match-owner"
run prepare
mv "$N/gen5wkr.ap-match" "$N/prior"
echo match > "$N/gen5wkr.ap-match"
if run disable; then echo 'FAIL removed foreign replacement'; exit 1; fi
[ -f "$N/gen5wkr.ap-match" ]
rm "$N/gen5wkr.ap-match"
ln -s prior "$N/gen5wkr.ap-match"
if run prepare; then echo 'FAIL accepted linked marker'; exit 1; fi
rm "$N/gen5wkr.ap-match" "$N/prior"

# ---- classify / rearm ----
mkdir -p "$HF" "$R/storage/log" "$R/data/system/dropbox" "$R/proc/net" "$R/data/local/gen5w-portable/boot"
: > "$R/proc/net/unix"
evidence() { # fresh unfinished-start evidence from an earlier boot
    rm -rf "$S/archive" "$S/rearm.lock" "$R/storage/log"/* "$R/data/system/dropbox"/* "$R/proc"/[0-9]* "$N/gen5wkr.apguard.off"
    : > "$R/proc/net/unix"; echo 0 > "$R/data/local/gen5w-portable/boot/enabled"
    printf '%s\n' "$BOOT_OLD" > "$G/attempt"
    printf '%s\n' "$BOOT_OLD" > "$HF/ap-attempt"
    touch -d '2026-11-10 10:00:00' "$G/attempt" "$HF/ap-attempt"
    rm -f "$A/sync-fail" "$A/sync-log"
}
token() { run classify > "$A/classify" 2>&1 || :; sed -n 's/^ap|ack|//p' "$A/classify"; }
intact() { # evidence must be byte-identical and nothing archived
    [ "$(cat "$G/attempt")" = "$BOOT_OLD" ] && [ "$(cat "$HF/ap-attempt")" = "$BOOT_OLD" ] || fail "evidence changed: $1"
    [ -z "$(ls -A "$S/archive" 2>/dev/null)" ] || fail "archive written: $1"
    rc=0; run check 2>/dev/null || rc=$?; [ "$rc" = 77 ] || fail "guard released: $1"
}

rm -f "$G/attempt" "$HF/ap-attempt"
rc=0; run classify > "$A/classify" || rc=$?
[ "$rc" = 0 ] && grep -qx 'ap|class|clear' "$A/classify" || fail 'clear classify'
refused 'rearm without evidence' 'no unfinished-start record' rearm "$(sed -n 's/^ap|ack|//p' "$A/classify")" reviewed-no-reset

evidence
rc=0; run classify > "$A/classify" || rc=$?
[ "$rc" = 77 ] || fail "classify rc $rc"
grep -qx "ap|current-boot|$BOOT_NOW" "$A/classify" || fail 'current boot shown'
grep -q "^ap|record|/data/nemesis/gen5wkr.apguard/attempt|$("$H" sha256 "$G/attempt")|37|boot=$BOOT_OLD|earlier-boot$" "$A/classify" || fail 'broker record listed'
grep -q '^ap|record|/data/data/kr.gen5w.wirelesshost/files/ap-attempt|' "$A/classify" || fail 'host record listed'
grep -qx 'ap|panic-scan|none-found|absence-is-not-proof' "$A/classify" || fail 'absence is not proof'
grep -qx 'ap|class|unfinished-start' "$A/classify" || fail 'class'
grep -Eq '^ap\|ack\|[0-9a-f]{64}$' "$A/classify" || fail 'token'
tok=$(token)
[ "$tok" = "$(token)" ] || fail 'token is not stable'

# Argument and acknowledgement errors never change anything.
refused 'missing arguments' 'usage: ap.sh rearm' rearm; intact args0
refused 'missing ack' 'usage: ap.sh rearm' rearm "$tok"; intact args1
refused 'extra argument' 'usage: ap.sh rearm' rearm "$tok" reviewed-no-reset extra; intact args3
refused 'free-form ack' 'acknowledgement must be' rearm "$tok" yes; intact ack
refused 'malformed token' 'malformed acknowledgement token' rearm "${tok%?}" reviewed-no-reset; intact malformed
refused 'panic ack without panic files' 'must be reviewed-no-reset' rearm "$tok" reviewed-panic-unrelated; intact wrong-ack

# Inventory changed after review: the old acknowledgement is void.
printf '%s\n' "$BOOT_NOW" > "$HF/ap-attempt"
refused 'changed inventory accepted' 'evidence changed since' rearm "$tok" reviewed-no-reset
[ "$(cat "$HF/ap-attempt")" = "$BOOT_NOW" ] && [ -f "$G/attempt" ] || fail 'changed inventory touched'
evidence
# A dump that appears after review voids the acknowledgement, even one dated older.
tok=$(token)
echo 'Kernel panic - not syncing' > "$R/storage/log/kpanic_2026-11-11_10:00:00.txt"
touch -d '2026-11-01 10:00:00' "$R/storage/log/kpanic_2026-11-11_10:00:00.txt"
refused 'new panic accepted with old token' 'evidence changed since' rearm "$tok" reviewed-panic-unrelated; intact new-panic
# A dump newer than the attempt record is reset evidence: never released here.
touch -d '2026-11-11 10:00:00' "$R/storage/log/kpanic_2026-11-11_10:00:00.txt"
refused 'newer panic accepted with old token' 'newer than the attempt record' rearm "$tok" reviewed-panic-unrelated; intact new-panic2
tok=$(token)
grep -q '^ap|panic|/storage/log/kpanic_2026-11-11_10:00:00.txt|[0-9a-f]\{64\}|27|mtime-newer-wall-clock-unreliable$' "$A/classify" || fail 'panic listed newer'
grep -qx 'ap|class|reset-evidence-newer' "$A/classify" || fail 'reset class'
refused 'reset evidence released' 'newer than the attempt record' rearm "$tok" reviewed-panic-unrelated; intact reset
refused 'reset evidence released (no-reset ack)' 'newer than the attempt record' rearm "$tok" reviewed-no-reset; intact reset2
# An older panic dump needs the explicit panic acknowledgement.
touch -d '2026-11-01 10:00:00' "$R/storage/log/kpanic_2026-11-11_10:00:00.txt"
tok=$(token)
grep -qx 'ap|class|unfinished-start' "$A/classify" && grep -q '|mtime-older-wall-clock-unreliable$' "$A/classify" || fail 'older panic class'
refused 'older panic released without panic ack' 'must be reviewed-panic-unrelated' rearm "$tok" reviewed-no-reset; intact older-panic

evidence; tok=$(token)
echo 'gen5wkr.ap.broker.v1' > "$R/proc/net/unix"
refused 'active broker owner' 'owner is active' rearm "$tok" reviewed-no-reset; intact broker
: > "$R/proc/net/unix"; mkdir -p "$R/proc/4321"; printf 'kr.gen5w.wirelesshost\0' > "$R/proc/4321/cmdline"
refused 'active host owner' 'owner is active' rearm "$tok" reviewed-no-reset; intact host
rm -rf "$R/proc/4321"; echo 1 > "$R/data/local/gen5w-portable/boot/enabled"
refused 'enabled automatic installation' 'disable the automatic installation' rearm "$tok" reviewed-no-reset; intact enabled
echo 0 > "$R/data/local/gen5w-portable/boot/enabled"; : > "$N/gen5wkr.apguard.off"
tok=$(token)
grep -q '^ap|switch|/data/nemesis/gen5wkr.apguard.off' "$A/classify" || fail 'switch listed'
refused 'guard-off switch present' 'explicit switch' rearm "$tok" reviewed-no-reset; intact switch
[ -e "$N/gen5wkr.apguard.off" ] || fail 'switch removed'
rm "$N/gen5wkr.apguard.off"; tok=$(token)
mkdir -p "$t/elsewhere"; ln -s "$t/elsewhere" "$S/archive"
refused 'linked archive' 'unsafe path' rearm "$tok" reviewed-no-reset
[ -z "$(ls -A "$t/elsewhere")" ] || fail 'wrote through linked archive'
rm "$S/archive"; intact linked-archive
echo file > "$S/archive"
refused 'archive is a file' 'not a plain directory' rearm "$tok" reviewed-no-reset
[ "$(cat "$S/archive")" = file ] || fail 'archive file replaced'
rm "$S/archive"; intact archive-file
# Copy verification failure (helper refuses to hash the archived copy).
cat > "$t/helper" <<SH
#!/bin/bash
case "\$1:\${2:-}" in sha256:*.part) exit 1;; esac
exec "$H" "\$@"
SH
chmod 755 "$t/helper"
PORTABLE_HELPER=$t/helper refused 'copy verification failure' 'archive copy of' rearm "$tok" reviewed-no-reset
[ "$(cat "$G/attempt")" = "$BOOT_OLD" ] && [ "$(cat "$HF/ap-attempt")" = "$BOOT_OLD" ] || fail 'copy failure removed evidence'
rc=0; run check 2>/dev/null || rc=$?; [ "$rc" = 77 ] || fail 'copy failure released the guard'
touch "$A/sync-fail"
refused 'flush failure' 'archive flush failed' rearm "$tok" reviewed-no-reset
[ "$(cat "$G/attempt")" = "$BOOT_OLD" ] && [ "$(cat "$HF/ap-attempt")" = "$BOOT_OLD" ] || fail 'flush failure removed evidence'
rc=0; run check 2>/dev/null || rc=$?; [ "$rc" = 77 ] || fail 'flush failure released the guard'
evidence; tok=$(token)
mkdir "$S/rearm.lock"
refused 'concurrent rearm' 'rearm locked' rearm "$tok" reviewed-no-reset; rmdir "$S/rearm.lock"; intact lock

# Unsafe or unsupported evidence is refused instead of scanned or followed.
evidence; rm "$HF/ap-attempt"; ln -s "$G/attempt" "$HF/ap-attempt"
rc=0; run classify > /dev/null 2>&1 || rc=$?; [ "$rc" = 1 ] || fail 'linked record classified'
refused 'linked record' 'evidence unsafe or unsupported' rearm "$tok" reviewed-no-reset
rm "$HF/ap-attempt"; evidence
head -c 300 /dev/zero > "$G/attempt"
rc=0; run classify > /dev/null 2>&1 || rc=$?; [ "$rc" = 1 ] || fail 'oversized record classified'
evidence
for i in $(seq 1 17); do echo "panic $i" > "$R/storage/log/kpanic-$i"; done
rc=0; run classify > /dev/null 2>&1 || rc=$?; [ "$rc" = 1 ] || fail 'unbounded panic set classified'
evidence; mkdir "$R/storage/log/subdir"
rc=0; run classify > /dev/null 2>&1 || rc=$?; [ "$rc" = 1 ] || fail 'unsupported panic entry classified'
evidence; echo live > "$R/data/system/dropbox/logcat.txt"
tok=$(token)
grep -qx 'ap|logcat|/data/system/dropbox/logcat.txt|present|not-hashed-review-manually' "$A/classify" || fail 'logcat listed'
echo more >> "$R/data/system/dropbox/logcat.txt"
[ "$tok" = "$(token)" ] || fail 'live logcat changes the acknowledgement token'

# ---- successful, evidence-preserving rearm ----
evidence
echo 'old dump' > "$R/data/system/dropbox/SYSTEM_LAST_KMSG@1000.txt"
touch -d '2026-11-01 10:00:00' "$R/data/system/dropbox/SYSTEM_LAST_KMSG@1000.txt"
echo ok > "$HF/ap-ok"
tok=$(token)
run rearm "$tok" reviewed-panic-unrelated > "$A/out"
dir=$(sed -n 's/^ap|rearmed|//p' "$A/out")
[ -n "$dir" ] && [ -d "$R$dir" ] || fail 'archive reported'
[ "$(cat "$R$dir/guard-attempt")" = "$BOOT_OLD" ] && [ "$(cat "$R$dir/host-ap-attempt")" = "$BOOT_OLD" ] || fail 'exact copies'
grep -qx "token=$tok" "$R$dir/MANIFEST" && grep -qx 'ack=reviewed-panic-unrelated' "$R$dir/MANIFEST" || fail 'manifest'
grep -q '^ap|panic|/data/system/dropbox/SYSTEM_LAST_KMSG@1000.txt|' "$R$dir/MANIFEST" || fail 'manifest panic inventory'
[ ! -e "$G/attempt" ] && [ ! -e "$HF/ap-attempt" ] || fail 'records still present'
[ -f "$R/data/system/dropbox/SYSTEM_LAST_KMSG@1000.txt" ] && [ -f "$HF/ap-ok" ] && [ -f "$G/ok" ] || fail 'panic/ok evidence touched'
[ "$(grep -c sync "$A/sync-log")" -ge 2 ] || fail 'archive and removal flushed'
[ "$(stat -c %a "$S/archive")" = 700 ] || fail 'archive mode'
run check
run status | grep -qx 'ap|admitted' || fail 'status after rearm'
# Without panic files, the plain acknowledgement is the one accepted.
evidence; tok=$(token)
run rearm "$tok" reviewed-no-reset > "$A/out"
[ "$(ls "$S/archive" | wc -l)" = 1 ] || fail 'second archive'
run check
[ ! -s "$A/errors" ] || { cat "$A/errors" >&2; fail 'unexpected adapter ops'; }
echo 'PASS AP mode ownership, wifi_ap_on staged admission, retained restart evidence, explicit evidence-preserving rearm and its fail-closed refusals'
