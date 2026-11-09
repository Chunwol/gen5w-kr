#!/bin/bash
set -u
cd "$(dirname "$0")/.."
. tests/lib.sh
export GEN5W_TEST_DIGEST=md5sum
ROOT=$(pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
PKG=$W/package
mkdir -p "$PKG/app" "$PKG/bin"

relay_status() { bash "$ROOT/packages/wireless-bridge/scripts/relay-gate.sh" "$PKG" >/dev/null 2>&1; }
manifest() { (cd "$PKG" && md5sum app/bridge.dex app/wireless-host.apk app/HKMC_DiPO.relay.lpd app/HKMC_GPM.guard.lpd bin/iap2-bt-patch-v039 bin/dipo-patch-v039 bin/gpm-patch-v039 bin/lpatch | sed 's/ \*/  /' > app/relay-v039.md5); }

rc=0; relay_status; rc=$?
check 'relay stays disabled without an attested V039 completion marker' test "$rc" = 77

printf 'gen5w.kr.bridge:v039-relay-4\n' > "$PKG/app/relay-v039.complete"
touch "$PKG/app/bridge.dex" "$PKG/app/wireless-host.apk" "$PKG/bin/iap2-bt-patch-v039" "$PKG/bin/dipo-patch-v039" "$PKG/bin/gpm-patch-v039" "$PKG/bin/lpatch"
check 'relay gate rejects the marker until the delta exists' eval 'relay_status; test "$?" = 1'

printf dex > "$PKG/app/HKMC_DiPO.relay.lpd"
printf gpm > "$PKG/app/HKMC_GPM.guard.lpd"
manifest
check 'relay gate accepts one complete hash-bound V039 payload' relay_status
grep -v 'HKMC_GPM.guard.lpd' "$PKG/app/relay-v039.md5" > "$W/omitted"
cp "$W/omitted" "$PKG/app/relay-v039.md5"
check 'relay gate rejects omitted required checksum' eval 'relay_status; test "$?" = 1'
manifest
echo gen5w.kr.bridge:v039-relay-3 > "$PKG/app/relay-v039.complete"
check 'old complete marker cannot attest new GPM payload' eval 'relay_status; test "$?" = 1'
echo gen5w.kr.bridge:v039-relay-4 > "$PKG/app/relay-v039.complete"
rm "$PKG/app/HKMC_GPM.guard.lpd"
check 'relay gate rejects missing GPM delta' eval 'relay_status; test "$?" = 1'
printf gpm > "$PKG/app/HKMC_GPM.guard.lpd";manifest

printf 'gen5w.kr.bridge:v035-relay-3\n' > "$PKG/app/relay-v039.complete"
check 'relay gate rejects a non-V039 completion marker' eval 'relay_status; test "$?" = 1'
printf 'gen5w.kr.bridge:v039-relay-4\n' > "$PKG/app/relay-v039.complete"

printf tampered >> "$PKG/app/HKMC_DiPO.relay.lpd"
check 'relay gate rejects a changed delta' eval 'relay_status; test "$?" = 1'
printf dex > "$PKG/app/HKMC_DiPO.relay.lpd"; manifest

rm "$PKG/bin/dipo-patch-v039"
check 'relay gate rejects a missing DiPO verifier' eval 'relay_status; test "$?" = 1'
touch "$PKG/bin/dipo-patch-v039"; manifest
rm "$PKG/bin/lpatch"
check 'relay gate rejects a missing lpatch' eval 'relay_status; test "$?" = 1'
touch "$PKG/bin/lpatch"; manifest

rm "$PKG/app/bridge.dex"; ln -s "$PKG/app/HKMC_DiPO.relay.lpd" "$PKG/app/bridge.dex"
check 'relay gate rejects symlinked artifacts' eval 'relay_status; test "$?" = 1'

done_tests relay-gate
