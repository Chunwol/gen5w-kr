#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
W=$(mktemp -d)
mkdir "$W/private"

# Android 4.4 toolbox ls omits the POSIX hard-link-count column.
mksh -c '. tools/diagnostics/errors.sh; ls() { print -r -- "-rw------- 0 0 123 2026-11-10 22:00 errors.0"; }; err_size /fixture' > "$W/android-size" 2>&1
check 'Android toolbox size without link count is read correctly' grep -qx 123 "$W/android-size"
mksh -c '. tools/diagnostics/errors.sh; ls() { print -r -- "-rw------- 1 0 0 456 Nov 10 22:00 errors.0"; }; err_size /fixture' > "$W/posix-size" 2>&1
check 'POSIX size with link count remains supported' grep -qx 456 "$W/posix-size"
echo sentinel > "$W/private/errors.0"
ERR_DIR="$W/private" mksh -c '. tools/diagnostics/errors.sh; err_size() { return 1; }; err_event core install apply failed 9 unknown' > "$W/out" 2>&1
check 'private persistence failure identifies size-inspection boundary' grep -q 'persistence=failed stage=size' "$W/out"
check 'persistence failure preserves safe original operation code' grep -q 'operation=apply result=failed rc=9' "$W/out"
mksh -c '. tools/diagnostics/errors.sh; print -r -- "mount(/dev/block/example -> /system remount ro) errno=16/16/16" | err_classify_stream; exit $?' > "$W/out" 2>&1
check 'official numeric remount EBUSY is classified without raw output' test $? = 11
mksh -c '. tools/diagnostics/errors.sh; print -r -- "mount(/dev/block/example -> /system remount ro) errno=16/13/16" | err_classify_stream; exit $?' > "$W/out" 2>&1
check 'mixed numeric errors never authorize busy-only exception' test $? = 0
rm -rf "$W"
done_tests error-persistence
