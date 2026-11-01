#!/bin/bash
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/data/nemesis/backup/gen5w.kr.wireless" "$W/data/nemesis/gen5w-kr-integrated/prior" "$W/system"
printf 'legacy\n' > "$W/data/nemesis/backup/gen5w.kr.wireless/saved"
run_check() { (cd "$ROOT/tools/integrated" && IT_DATA="$W/data" IT_SYSTEM="$W/system" mksh -c '. ./common.sh; "$@"' _ "$@"); }
check 'legacy backup without registration refuses wireless removal' eval '! run_check safe_remove gen5w.kr.wireless'
check 'legacy backup without registration refuses snapshot' eval '! run_check snapshot gen5w.kr.wireless'
check 'refusal retains legacy backup' test -f "$W/data/nemesis/backup/gen5w.kr.wireless/saved"
done_tests wireless-legacy
