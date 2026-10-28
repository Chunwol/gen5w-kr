#!/bin/bash
# Runs every mock test. Needs bash and mksh (WSL or Linux).
cd "$(dirname "$0")/.."
rc=0
echo "== shell syntax (mksh -n)"
for f in $(find packages probe/package probe/usb tools -name '*.sh'); do
    mksh -n "$f" || { echo "FAIL syntax $f"; rc=1; }
done
for f in $(find packages probe/package probe/usb tools -name '*.sh' -o -name '*.data' -o -name '*.xml'); do
    grep -q $'\r' "$f" && { echo "FAIL CRLF in $f"; rc=1; }
done
for t in tests/notice.sh tests/legacy-notice.sh tests/detect.sh tests/collect.sh tests/wireless.sh tests/hotspot.sh tests/hotspot_profile.sh tests/core.sh tests/recovery.sh tests/audio.sh tests/bridge.sh tests/dongle.sh tests/integrated-zip.sh tests/integrated-build.sh tests/integrated.sh tests/fat32-integrated.sh; do bash "$t" || rc=1; done
for t in tests/iap2_control.py tests/dipo_control.py tests/gpm_control.py tests/notice.py tests/hotspot_profile.py; do python3 "$t" || rc=1; done

echo "== JVM tests (HUD and probe)"
bash tests/java.sh
jvm_rc=$?
[ "$jvm_rc" = 0 ] || [ "$jvm_rc" = 77 ] || rc=1

if [ $rc != 0 ]; then echo "SOME TESTS FAILED"
elif [ "$jvm_rc" = 77 ]; then echo "SHELL TESTS PASSED; JVM TESTS SKIPPED (run tests/java.sh with a JDK)"
else echo "ALL TESTS PASSED"
fi
exit $rc
