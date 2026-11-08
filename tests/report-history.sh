#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
work=$(mktemp -d /tmp/gen5w-report-history.XXXXXX)
trap 'rm -rf "$work"' EXIT
if [ ! -f tools/integrated/history.sh ]; then echo 'FAIL missing report preservation';exit 1;fi
mkdir -p "$work/usb" "$work/errors"
cp tools/integrated/{history.sh,errors.sh} "$work/usb/"
export ERR_DIR=$work/errors
cd "$work/usb"
echo first-failure > EXEC_LOG.txt
mkdir GEN5W-REPORT
mv EXEC_LOG.txt GEN5W-REPORT/
mksh -c '. ./errors.sh; . ./history.sh; report_attempt_begin install'
grep -q first-failure GEN5W-REPORT/HISTORY/0/EXEC_LOG.txt
echo second-failure > GEN5W-REPORT/EXEC_LOG.txt
mksh -c '. ./errors.sh; . ./history.sh; report_attempt_begin update'
grep -q first-failure GEN5W-REPORT/HISTORY/0/EXEC_LOG.txt
grep -q second-failure GEN5W-REPORT/HISTORY/1/EXEC_LOG.txt
for n in $(seq 1 12); do mksh -c '. ./errors.sh; . ./history.sh; report_attempt_begin install';done
[ "$(find GEN5W-REPORT/HISTORY -mindepth 1 -maxdepth 1 -type d | wc -l)" = 8 ]
# Do not destroy an unowned slot or follow links while rotating.
next=$(cat GEN5W-REPORT/HISTORY/next)
echo evidence > "GEN5W-REPORT/HISTORY/$next/unowned"
if mksh -c '. ./errors.sh; . ./history.sh; report_attempt_begin install';then echo 'FAIL discarded unowned archive entry';exit 1;fi
test -f "GEN5W-REPORT/HISTORY/$next/unowned"
mkdir stream
printf 'FAIL safe marker\nSSID=secret password=hidden\n' | mksh -c '. ./history.sh; report_stream stream/EXEC_LOG.txt'
grep -q 'FAIL safe marker' stream/EXEC_LOG.txt
! grep -q 'secret\|hidden' stream/EXEC_LOG.txt
# Bounded active report stream, including long lines and repeated noise.
python3 -c 'print("FAIL " + "x"*200000);[print("STEP test: bounded message") for _ in range(12000)]' | mksh -c '. ./history.sh; report_stream stream/EXEC_LOG.txt'
for file in stream/*;do [ "$(wc -c < "$file")" -le 65536 ];done
ln -s "$work/evidence" stream/symlink
if echo FAIL | mksh -c '. ./history.sh; report_stream stream/symlink';then echo 'FAIL followed report link';exit 1;fi
test ! -e "$work/evidence"
echo 'PASS report preservation/eight slots/privacy/bounds/symlinks'
