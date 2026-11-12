#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/g5p-ap.XXXXXX)
trap 'rm -rf "$t"' EXIT
mkdir -p "$t/root/data/bundle/bin"
cp tools/portable/ap.sh "$t/root/data/bundle/"
cp .build/portable/dex-patch-host "$t/root/data/bundle/bin/dex-patch"
export PORTABLE_TEST_ROOT=$t/root
run() { mksh "$t/root/data/bundle/ap.sh" "$@"; }
run prepare
[ "$(cat "$t/root/data/nemesis/gen5wkr.ap-match")" = match ]
[ "$(stat -c %a "$t/root/data/nemesis/gen5wkr.apguard")" = 700 ]
run check
# Previous success must not hide a later interrupted start, even same boot ID.
echo ok > "$t/root/data/nemesis/gen5wkr.apguard/ok"
echo same-boot > "$t/root/data/nemesis/gen5wkr.apguard/attempt"
rc=0; run check || rc=$?; [ "$rc" = 77 ]
run disable
[ ! -e "$t/root/data/nemesis/gen5wkr.ap-match" ]
[ -f "$t/root/data/nemesis/gen5wkr.apguard/attempt" ]
rm "$t/root/data/nemesis/gen5wkr.apguard/attempt"
# Existing valid mode belongs to someone else; use it but never delete it.
echo match > "$t/root/data/nemesis/gen5wkr.ap-match"
run prepare
run disable
[ -f "$t/root/data/nemesis/gen5wkr.ap-match" ]
rm "$t/root/data/nemesis/gen5wkr.ap-match"
rm "$t/root/data/local/gen5w-portable/ap/match-owner"
run prepare
mv "$t/root/data/nemesis/gen5wkr.ap-match" "$t/root/data/nemesis/prior"
echo match > "$t/root/data/nemesis/gen5wkr.ap-match"
if run disable; then echo 'FAIL removed foreign replacement'; exit 1; fi
[ -f "$t/root/data/nemesis/gen5wkr.ap-match" ]
rm "$t/root/data/nemesis/gen5wkr.ap-match"
ln -s prior "$t/root/data/nemesis/gen5wkr.ap-match"
if run prepare; then echo 'FAIL accepted linked marker'; exit 1; fi
echo 'PASS AP mode ownership, retained restart evidence, same-boot interrupted start, prior success and symlink refusal'
