#!/bin/bash
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
BG="$W/data/nemesis/gen5wkr.bootguard"
mkdir -p "$BG"
printf 'armed\n' > "$BG/armed"
printf '2\n' > "$BG/count"
printf '3\n' > "$BG/max"

run_helper() {
    env BOOTGUARD_STATE_DIR="$BG" BOOTGUARD_BOOT_ID="${BOOTGUARD_BOOT_ID:-boot-a}" \
        mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-state.sh" "$@"
}

check 'bootguard helper exists and begins under the limit' run_helper begin
check 'begin increments the durable count' grep -qx '3' "$BG/count"
check 'begin is idempotent within one boot' run_helper begin
check 'duplicate begin does not increment the count' grep -qx '3' "$BG/count"

BOOTGUARD_BOOT_ID=boot-b
run_helper begin
rc=$?
check 'failure limit requests recovery' test "$rc" = 2
check 'limit increment is durable' grep -qx '4' "$BG/count"
run_helper begin
rc=$?
check 'repeated begin above the limit still requests recovery' test "$rc" = 2
check 'repeated recovery request does not increment count' grep -qx '4' "$BG/count"

check 'mark-ok succeeds after a completed boot' run_helper mark-ok
check 'mark-ok resets the consecutive failure count' grep -qx '0' "$BG/count"
check 'mark-ok keeps the guard directory armed for later boots' test -d "$BG"
check 'mark-ok records a durable boot-ok marker' grep -qx 'boot-ok' "$BG/boot-ok"

# A failed count write must not make this boot look already counted on retry.
mkdir -p "$W/bin"
cat > "$W/bin/mv" <<'SH'
#!/bin/sh
case "$*" in *'.count.tmp.'*' /'*'/count') exit 1;; esac
exec /bin/mv "$@"
SH
chmod +x "$W/bin/mv"
BOOTGUARD_BOOT_ID=boot-c
if PATH="$W/bin:$PATH" run_helper begin; then
    bad 'failed count write refuses boot begin'
else
    ok 'failed count write refuses boot begin'
fi
check 'retry counts a boot after interrupted count write' run_helper begin
check 'interrupted count write does not lose the boot attempt' grep -qx '1' "$BG/count"
BOOTGUARD_BOOT_ID=boot-d
PATH="$W/bin:$PATH" run_helper begin >/dev/null 2>&1 || true
BOOTGUARD_BOOT_ID=boot-e
check 'next boot resumes interrupted prior attempt' run_helper begin
check 'next boot counts both attempts once' grep -qx '3' "$BG/count"
if PATH="$W/bin:$PATH" run_helper mark-ok >/dev/null 2>&1; then
    bad 'failed count reset refuses completed boot'
else
    ok 'failed count reset refuses completed boot'
fi
BOOTGUARD_BOOT_ID=boot-f
check 'next boot resumes interrupted successful reset' run_helper begin
check 'successful prior boot reset is not lost' grep -qx '1' "$BG/count"
printf 'boot-g not-a-number\n' > "$BG/attempt"
BOOTGUARD_BOOT_ID=boot-g
if run_helper begin >/dev/null 2>&1; then
    bad 'malformed attempt journal refuses boot begin'
else
    ok 'malformed attempt journal refuses boot begin'
fi
check 'malformed attempt leaves count unchanged' grep -qx '1' "$BG/count"
rm "$BG/attempt"
ln -s /dev/null "$BG/attempt"
if run_helper begin >/dev/null 2>&1; then
    bad 'linked attempt journal refuses boot begin'
else
    ok 'linked attempt journal refuses boot begin'
fi
check 'linked attempt leaves count unchanged' grep -qx '1' "$BG/count"
rm "$BG/attempt"

rm -f "$BG/armed"
if run_helper mark-ok; then
    bad 'mark-ok refuses an unarmed guard'
else
    ok 'mark-ok refuses an unarmed guard'
fi

# No kernel boot id: a per-boot id kept in tmpfs stops service restarts within
# one boot from being counted as more failed boots.
NB="$W/noid/gen5wkr.bootguard"
RID="$W/noid/dev-boot-id"
mkdir -p "$NB"
printf 'armed
' > "$NB/armed"; printf '0
' > "$NB/count"; printf '3
' > "$NB/max"
run_noid() {
    env BOOTGUARD_STATE_DIR="$NB" BOOTGUARD_BOOT_ID= BOOTGUARD_RUNTIME_ID="$RID"         mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-state.sh" "$@"
}
check 'missing boot id begins with a fallback id' run_noid begin
check 'fallback id is kept for this boot' grep -q '^local-[0-9]' "$RID"
run_noid begin; run_noid begin; run_noid begin
check 'service restarts without boot id count one boot' grep -qx '1' "$NB/count"
rm -f "$RID"
check 'a new boot without boot id counts again' run_noid begin
check 'new boot without boot id increments once' grep -qx '2' "$NB/count"
check 'mark-ok works with the fallback id' run_noid mark-ok
check 'restart after a completed boot without boot id stays at zero' run_noid begin
check 'restart after mark-ok does not count' grep -qx '0' "$NB/count"
printf 'local-bad/id
' > "$RID"
check 'malformed fallback id is replaced' run_noid begin
check 'replaced fallback id is well formed' grep -q '^local-[0-9][0-9a-zA-Z-]*$' "$RID"
rm -f "$RID"; ln -s "$W/elsewhere" "$RID"
run_noid begin; rc=$?
check 'symlinked fallback id falls back to counting (safe direction)' test "$rc" = 0 -o "$rc" = 2
check 'symlinked fallback id is not followed' test ! -e "$W/elsewhere"
rm -f "$RID"

done_tests bootguard-runtime
