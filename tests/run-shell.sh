#!/bin/bash
# Shell-package tests. They need mksh, so run.sh starts this under WSL when the
# host shell (Git Bash) has none. Slowest tests come first for shorter wall time.
cd "$(dirname "$0")/.."
command -v mksh >/dev/null 2>&1 || { echo "mksh not found"; exit 78; }
rc=0
bash tests/local-hotspot.sh || rc=1
bash tests/local-hotspot-remount.sh || rc=1
mksh tests/error-journal.sh || rc=1
bash tests/error-boundaries.sh || rc=1
bash tests/report-history.sh || rc=1
bash tests/entry-errors.sh || rc=1
mksh tests/bridge-retry.sh || rc=1
echo "== shell syntax (mksh -n)"
files=$(find packages probe/package probe/usb tools -name '*.sh')
for f in $files; do
    mksh -n "$f" || { echo "FAIL syntax $f"; rc=1; }
done
for f in $(find packages probe/package probe/usb tools -name '*.sh' -o -name '*.data' -o -name '*.xml'); do
    grep -q $'\r' "$f" && { echo "FAIL CRLF in $f"; rc=1; }
done
echo "== shell package tests (parallel)"
bash tests/par.sh bash \
    tests/integrated.sh#3 tests/integrated.sh#1 tests/integrated-edge.sh tests/bridge.sh tests/timer.sh tests/dongle.sh tests/check.sh \
    tests/drivelog.sh tests/wireless.sh tests/audio.sh tests/bootguard.sh tests/system-reinstall.sh \
    tests/recovery.sh tests/integrated.sh#2 tests/integrated-build.sh tests/bootguard-runtime.sh tests/wireless-preserve.sh \
    tests/relay-gate.sh tests/bootguard-rollback.sh tests/bootguard-dongle.sh tests/bluelink.sh \
    tests/fat32-integrated.sh tests/dongle-snapshot.sh tests/diag.sh tests/core.sh tests/uilog.sh tests/wireless-legacy.sh \
    tests/integrated-zip.sh tests/hud-variant-report.sh tests/detect.sh tests/collect.sh \
    tests/stock-projection-source.sh tests/standalone.sh tests/request-envelope.sh tests/adb-health.sh || rc=1
# Python tests that start mksh themselves.
bash tests/par.sh python3 tests/dongle_runtime.py tests/broker_diagnostics.py || rc=1
exit $rc
