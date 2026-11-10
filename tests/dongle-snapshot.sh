#!/bin/bash
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/usb" "$W/data/nemesis/gen5w-kr-integrated/prior" "$W/system/etc/gen5w-kr-backup/dongle"
cp "$ROOT/tools/integrated/common.sh" "$ROOT/tools/integrated/report.sh" "$ROOT/tools/integrated/services.sh" "$W/usb/"
export IT_DATA="$W/data" IT_SYSTEM="$W/system"
cd "$W/usb" || exit 1
. ./common.sh
if snapshot gen5w.kr.dongle; then
    bad 'durable-only dongle refuses standard transition before mutation'
else
    ok 'durable-only dongle refuses standard transition before mutation'
fi
check 'refused transition preserves durable dongle backup' test -d "$SYS/etc/gen5w-kr-backup/dongle"
check 'refused transition does not mark a completed snapshot' test ! -e "$TX/prior/complete"
mkdir -p "$APPS/gen5w.kr.dongle"
printf '[nemesis]\nid=gen5w.kr.dongle\n' > "$APPS/gen5w.kr.dongle/NEMESIS.data"
printf '#!/bin/sh\necho test > "$2"\n' > ./zipstore
chmod +x ./zipstore
printf '#!/bin/sh\necho id=gen5w.kr.dongle\n' > "$W/nemesis"
chmod +x "$W/nemesis"
NEM="$W/nemesis"
if snapshot gen5w.kr.dongle; then
    bad 'registered legacy dongle without a file journal refuses transition'
else
    ok 'registered legacy dongle without a file journal refuses transition'
fi
check 'registered legacy refusal does not invoke snapshot' test ! -e "$TX/prior/gen5w.kr.dongle.zip"
done_tests dongle-snapshot
