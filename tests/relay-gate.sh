#!/bin/bash
set -u
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT=$(pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
PKG=$W/package
mkdir -p "$PKG/app" "$PKG/bin"

relay_status() { bash "$ROOT/packages/wireless-bridge/scripts/relay-gate.sh" "$PKG" >/dev/null 2>&1; }

rc=0; relay_status; rc=$?
check 'relay stays disabled without an attested V039 completion marker' test "$rc" = 77

printf 'gen5w.kr.bridge:v039-relay-1\n' > "$PKG/app/relay-v039.complete"
touch "$PKG/app/bridge.dex" "$PKG/app/wireless-host.apk" "$PKG/bin/iap2-bt-patch-v039" "$PKG/bin/dipo-patch-v039"
check 'relay gate rejects the marker until every V039 artifact exists' eval 'relay_status; test "$?" = 1'

cat > "$PKG/bin/relay-v039-structural-check" <<'SH'
#!/bin/sh
[ "$#" = 3 ] && [ -f "$1" ] && [ -f "$2" ] && [ -f "$3" ] || exit 1
touch "$(dirname "$1")/check-ran"
SH
chmod +x "$PKG/bin/relay-v039-structural-check" "$PKG/bin/iap2-bt-patch-v039" "$PKG/bin/dipo-patch-v039"
check 'relay gate accepts complete V039 artifacts only after the structural verifier runs' eval 'relay_status; test "$?" = 0 && test -f "$PKG/app/check-ran"'

printf 'gen5w.kr.bridge:v035-relay-1\n' > "$PKG/app/relay-v039.complete"
check 'relay gate rejects a non-V039 completion marker' eval 'relay_status; test "$?" = 1'
printf 'gen5w.kr.bridge:v039-relay-1\n' > "$PKG/app/relay-v039.complete"

rm "$PKG/bin/dipo-patch-v039"
check 'relay gate rejects a missing DiPO relay artifact' eval 'relay_status; test "$?" = 1'

touch "$PKG/bin/dipo-patch-v039"
rm "$PKG/bin/relay-v039-structural-check"
ln -s "$PKG/app/bridge.dex" "$PKG/bin/relay-v039-structural-check"
check 'relay gate rejects symlinked artifacts' eval 'relay_status; test "$?" = 1'

# An artifact set with a failing structural proof stays disabled.
rm "$PKG/bin/relay-v039-structural-check"
printf '#!/bin/sh\nexit 1\n' > "$PKG/bin/relay-v039-structural-check"
chmod +x "$PKG/bin/relay-v039-structural-check"
touch "$PKG/bin/dipo-patch-v039"
check 'relay gate rejects artifacts that fail structural verification' eval 'relay_status; test "$?" = 1'

done_tests relay-gate