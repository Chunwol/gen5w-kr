#!/bin/bash
# Real native bind syscall and removal, confined to a private mount namespace.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" != --inside ]; then exec unshare --mount --propagation private bash "$0" --inside; fi
directory=$(mktemp -d /tmp/g5p-native-bind.XXXXXX)
trap 'rc=$?; umount "$directory/target" 2>/dev/null || :; rm -f "$directory/source" "$directory/target"; rmdir "$directory"; exit $rc' EXIT
echo authored > "$directory/source"
echo original > "$directory/target"
qemu-arm .build/portable/dex-patch bind "$directory/source" "$directory/target"
[ "$(cat "$directory/target")" = authored ]
umount "$directory/target"
[ "$(cat "$directory/target")" = original ]
echo 'PASS actual ARM native bind/unmount inside a private mount namespace'
