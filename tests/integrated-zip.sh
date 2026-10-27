#!/bin/bash
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
# The production helper archives our installed package, never /data user contents.
cp "$ROOT/tools/integrated/bin/zipstore-host" "$W/zipstore"
mkdir -p "$W/tree/sub"; echo metadata > "$W/tree/NEMESIS.data"; echo body > "$W/tree/sub/test.sh"
check 'installed package snapshot ZIP helper' eval '"$W/zipstore" "$W/tree" "$W/prior.zip" && python3 -c '\''import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); assert z.read("sub/test.sh")==b"body\n"; assert z.testzip() is None'\'' "$W/prior.zip"'
ln -s /etc/passwd "$W/tree/foreign"
check 'snapshot refuses symbolic links' eval '! "$W/zipstore" "$W/tree" "$W/bad.zip"'
if command -v qemu-arm >/dev/null; then
 rm "$W/tree/foreign"
 check 'ARM API19 static snapshot executes' eval 'qemu-arm "$ROOT/tools/integrated/bin/zipstore" "$W/tree" "$W/arm.zip" && python3 -c '\''import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); assert z.read("sub/test.sh")==b"body\n"; assert z.testzip() is None'\'' "$W/arm.zip"'
fi
done_tests integrated-zip
