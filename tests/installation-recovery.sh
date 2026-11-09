#!/bin/bash
# Removing bundle validation or touching prior on prepare must fail these tests.
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
stubs
mkdir -p "$W/usb" "$W/data/nemesis/gen5w-kr-integrated/prior"
cp "$ROOT/tools/integrated/"*.sh "$W/usb/"
printf 'sentinel\n' > "$W/data/nemesis/gen5w-kr-integrated/prior/preserved"
run() { (cd "$W/usb" && IT_DATA="$W/data" IT_SYSTEM="$W/system" IT_NO_REBOOT=1 IT_SHELL=$(command -v mksh) PATH="$W/bin:$PATH" mksh ${RECOVERY_TRACE:+-x} recovery.sh "$@"); }
run check > "$W/out" 2>&1
check 'missing published runner is refused' test $? != 0
# The builder provides a complete immutable manifest; this small fixture verifies
# the preparation mechanism, never executes a synthetic rollback.
python3 - "$W/usb" <<'PY'
import hashlib,pathlib,sys
p=pathlib.Path(sys.argv[1]); (p/'payload').write_text('verified')
(p/'RECOVERY.md5').write_text(''.join(hashlib.md5(f.read_bytes()).hexdigest()+'  '+f.name+'\n' for f in sorted(p.iterdir()) if f.is_file()))
PY
run prepare > "$W/out" 2>&1
prep_rc=$?; [ "$prep_rc" = 0 ] || cat "$W/out"
check 'verified bundle can be prepared' test "$prep_rc" = 0
check 'prepare preserves prior snapshot' grep -qx sentinel "$W/data/nemesis/gen5w-kr-integrated/prior/preserved"
check 'prepare publishes complete runner' test -f "$W/data/nemesis/gen5wkr.recovery/current/recovery.sh"
printf corrupt >> "$W/usb/payload"
run prepare > "$W/out" 2>&1
check 'corrupt incoming bundle refused' test $? != 0
check 'failed prepare preserves published generation' grep -qx verified "$W/data/nemesis/gen5wkr.recovery/current/payload"
printf recovery-required > "$W/data/nemesis/gen5w-kr-integrated/state"
run check > "$W/out" 2>&1
check 'incomplete snapshot refuses recovery' test $? != 0
check 'incomplete snapshot reason observable' grep -qx snapshot-invalid "$W/out"
ln -s "$W/usb" "$W/data/nemesis/gen5wkr.recovery/foreign"
run unknown > "$W/out" 2>&1
check 'unknown operation refused' test $? != 0
printf '1\n' > "$W/data/nemesis/gen5w-kr-integrated/prior/complete"
printf 'enabled\n' > "$W/data/nemesis/gen5w-kr-integrated/prior/wireless-mode"
: > "$W/data/nemesis/gen5w-kr-integrated/prior/ap-markers"
run check > "$W/out" 2>&1
check 'legacy snapshot without per-file integrity requires USB fallback' test $? != 0
python3 - "$W/data/nemesis/gen5w-kr-integrated/prior" <<'PY'
import pathlib,hashlib,sys
p=pathlib.Path(sys.argv[1]); (p/'RECOVERY.md5').write_text(''.join(hashlib.md5(f.read_bytes()).hexdigest()+'  '+f.name+'\n' for f in sorted(p.iterdir()) if f.is_file() and f.name!='complete'))
PY
run check > "$W/out" 2>&1
check 'valid empty prior transaction can recover' test $? = 0
mkdir "$W/data/nemesis/gen5w-kr-integrated/prior/gen5w.kr.core"
: > "$W/data/nemesis/gen5w-kr-integrated/attempt.gen5w.kr.core"
run check > "$W/out" 2>&1
check 'partial prior package without ZIP is refused' test $? != 0
rmdir "$W/data/nemesis/gen5w-kr-integrated/prior/gen5w.kr.core"
rm "$W/data/nemesis/gen5w-kr-integrated/attempt.gen5w.kr.core"
mkdir "$W/data/nemesis/gen5w-kr-integrated/lock"
echo $$ > "$W/data/nemesis/gen5w-kr-integrated/lock/pid"
run run 123 > "$W/out" 2>&1
check 'live installer lock refuses worker' test $? != 0
rm -f "$W/data/nemesis/gen5w-kr-integrated/lock/pid"
rmdir "$W/data/nemesis/gen5w-kr-integrated/lock"
run run 123 > "$W/out" 2>&1
check 'verified worker restores previous state' test $? = 0
check 'worker final result persisted outside core' grep -qx 'recovery_result=restored' "$W/data/nemesis/gen5wkr.recovery-result"
check 'worker records transaction restored' grep -qx rolled-back "$W/data/nemesis/gen5w-kr-integrated/state"
run run 123 > "$W/out" 2>&1
check 'duplicate request does not rerun restoration' test $? != 0
printf recovery-required > "$W/data/nemesis/gen5w-kr-integrated/state"
mkdir "$W/data/nemesis/gen5wkr.bootguard.previous"
run run 456 > "$W/out" 2>&1
check 'bootguard reconciliation failure remains recoverable' test $? != 0
check 'bootguard failure retains recovery required' grep -qx recovery-required "$W/data/nemesis/gen5w-kr-integrated/state"
check 'bootguard failure is recorded separately' grep -qx 'recovery_result=failed' "$W/data/nemesis/gen5wkr.recovery-result"
check 'failed report offers actionable recovery instructions' grep -q 'recovery-prepare' "$W/data/nemesis/gen5wkr.recovery/current/GEN5W-REPORT/RESULT.md"
done_tests installation-recovery
