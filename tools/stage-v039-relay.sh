#!/bin/bash
# Stage the V039 relay payload into packages/wireless-bridge: a binary delta that the head
# unit applies to its own stock DiPO ODEX (no manufacturer file is shipped), plus lpatch.
set -euo pipefail
cd "$(dirname "$0")/.."
target=packages/wireless-bridge/app
rm -f "$target/HKMC_DiPO.relay.lpd" "$target/HKMC_GPM.guard.lpd" "$target/relay-v039.md5" "$target/relay-v039.complete" \
    packages/wireless-bridge/bin/lpatch
[ $# -eq 1 ] || { echo 'usage: stage-v039-relay.sh <ndk dir>' >&2; exit 2; }
PY=$(command -v python3 || command -v python)
"$PY" -I tools/lpatch/build.py --ndk "$1"
cp tools/v039-relay/HKMC_DiPO.relay.lpd "$target/HKMC_DiPO.relay.lpd"
cp tools/v039-relay/HKMC_GPM.guard.lpd "$target/HKMC_GPM.guard.lpd"
(cd packages/wireless-bridge && md5sum \
    app/bridge.dex app/wireless-host.apk app/HKMC_DiPO.relay.lpd app/HKMC_GPM.guard.lpd \
    bin/iap2-bt-patch-v039 bin/dipo-patch-v039 bin/gpm-patch-v039 bin/lpatch | sed 's/ \*/  /' > app/relay-v039.md5)
printf '%s\n' 'gen5w.kr.bridge:v039-relay-4' > "$target/relay-v039.complete"
echo 'staged V039 relay delta payload'
