#!/bin/bash
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/work/packages" "$W/data/nemesis/apps" "$W/system"
cp "$ROOT/tools/integrated/"*.sh "$W/work/"
cat > "$W/nemesis" <<'SH'
#!/bin/sh
case "$1" in
    pkg-info) name=${2##*/}; printf 'id=%s\n' "${name%.zip}";;
    install) name=${2##*/}; id=${name%.zip}; mkdir -p "$IT_DATA/nemesis/apps/$id"; printf 'id=%s\n' "$id" > "$IT_DATA/nemesis/apps/$id/NEMESIS.data";;
    *) exit 1;;
esac
SH
chmod +x "$W/nemesis"
for name in wireless audio bridge core timer bluelink; do
    touch "$W/work/packages/gen5w.kr.$name.zip"
done
cat > "$W/work/exercise.sh" <<'SH'
. ./common.sh
reset_results() { :; }
result() { printf '%s %s\n' "$1" "$2" >> "$IT_DATA/results"; }
report() { :; }
check_stage() { :; }
begin() { mkdir -p "$TX"; }
set_state() { :; }
gate() { case "$1" in */gen5w.kr.wireless) return 78;; *) return 0;; esac; }
safe_remove() { printf '%s\n' "$1" >> "$IT_DATA/removed"; }
hook() { :; }
finish() { :; }
rollback_transaction() { :; }
sync() { :; }
install_transaction
SH
run_case() { (cd "$W/work" && IT_DATA="$W/data" IT_SYSTEM="$W/system" IT_NEM="$W/nemesis" mksh ./exercise.sh); }
for name in wireless audio; do
    mkdir -p "$W/data/nemesis/apps/gen5w.kr.$name"
    printf '[nemesis]\nid=gen5w.kr.%s\n' "$name" > "$W/data/nemesis/apps/gen5w.kr.$name/NEMESIS.data"
done
check 'inconclusive detection continues independent modules' run_case
check 'inconclusive detection preserves wireless module' grep -qx 'gen5w.kr.wireless preserved' "$W/data/results"
check 'inconclusive detection preserves wireless audio' grep -qx 'gen5w.kr.audio preserved' "$W/data/results"
check 'preserved wireless modules are not removed' eval '! grep -Eq "gen5w.kr.(wireless|audio)" "$W/data/removed"'
check 'wired bridge still updates' grep -qx gen5w.kr.bridge "$W/data/removed"
rm -rf "$W/data/nemesis/apps/gen5w.kr.audio"
: > "$W/data/results"
check 'inconclusive detection accepts missing optional modules' run_case
check 'absent audio is reported skipped' grep -qx 'gen5w.kr.audio skipped' "$W/data/results"
touch "$W/data/nemesis/gen5wkr.wireless-disabled"
check 'inconsistent wired-only marker refuses preserve mode' eval '! run_case'
done_tests wireless-preserve
