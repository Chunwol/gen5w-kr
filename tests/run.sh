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
for t in tests/notice.sh tests/legacy-notice.sh tests/detect.sh tests/collect.sh tests/wireless.sh tests/wireless-preserve.sh tests/wireless-legacy.sh tests/hotspot.sh tests/hotspot_profile.sh tests/core.sh tests/hud-variant-report.sh tests/recovery.sh tests/audio.sh tests/bridge.sh tests/dongle.sh tests/dongle-snapshot.sh tests/bootguard.sh tests/bootguard-runtime.sh tests/bootguard-rollback.sh tests/integrated-zip.sh tests/integrated-build.sh tests/integrated.sh tests/fat32-integrated.sh tests/check.sh; do bash "$t" || rc=1; done
python_tests="tests/iap2_control.py tests/dipo_control.py tests/gpm_control.py tests/dongle_runtime.py tests/notice.py tests/hotspot_profile.py tests/fastboot_recovery.py tests/recovery_usb.py"
if command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
    python_tests="$python_tests tests/core_lifecycle.py"
else
    echo "SKIP core_lifecycle.py (need both javac and java)"
fi
for t in $python_tests; do python3 "$t" || rc=1; done

echo "== JVM tests (HUD and probe)"
bash tests/java.sh
jvm_rc=$?
[ "$jvm_rc" = 0 ] || [ "$jvm_rc" = 77 ] || rc=1

if [ $rc != 0 ]; then echo "SOME TESTS FAILED"
elif [ "$jvm_rc" = 77 ]; then echo "SHELL TESTS PASSED; JVM TESTS SKIPPED (run tests/java.sh with a JDK)"
else echo "ALL TESTS PASSED"
fi
exit $rc
