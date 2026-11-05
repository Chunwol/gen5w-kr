#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
target=packages/wireless-bridge/app
rm -f "$target/HKMC_DiPO.relay.apk" "$target/relay-v039.md5" "$target/relay-v039.complete"
[ $# -eq 1 ] || { echo 'usage: stage-private-v039-relay.sh <reviewed relay APK>' >&2; exit 2; }
source=$1
[ -f "$source" ] || { echo 'private relay APK missing' >&2; exit 1; }
python - "$source" <<'PY'
import sys,zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    if 'classes.dex' not in z.namelist(): raise SystemExit('relay APK has no classes.dex')
PY
cp "$source" "$target/HKMC_DiPO.relay.apk"
(cd packages/wireless-bridge && md5sum \
    app/bridge.dex app/wireless-host.apk app/HKMC_DiPO.relay.apk \
    bin/iap2-bt-patch-v039 bin/dipo-patch-v039 | sed 's/ \*/  /' > app/relay-v039.md5)
printf '%s\n' 'gen5w.kr.bridge:v039-relay-2' > "$target/relay-v039.complete"
echo 'staged private exact-V039 relay payload'
