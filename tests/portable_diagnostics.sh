#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/g5diag.XXXXXX); trap 'rm -rf "$t"' EXIT
R=$t/root; B=$R/data/bundle
mkdir -p "$B/bin" "$R/data/local/gen5w-portable/boot" "$R/proc/sys/kernel/random" "$R/data/nemesis/gen5wkr.ui" "$t/bin"
cp tools/portable/diagnostics.sh "$B/"
cp .build/portable/dex-patch-host "$B/bin/dex-patch"
echo fixture-boot > "$R/proc/sys/kernel/random/boot_id"
echo '100 50' > "$R/proc/uptime"
echo 'worker=owner exit=23' > "$R/data/local/gen5w-portable/boot/health-lost"
echo details > "$R/data/nemesis/gen5wkr.ui/diag-latest.txt"
cat > "$t/bin/logcat" <<'SH'
#!/bin/sh
echo failure-ring-buffer
SH
chmod +x "$t/bin/logcat"
export PATH="$t/bin:$PATH" PORTABLE_TEST_ROOT=$R
mksh "$B/diagnostics.sh" capture worker-owner
D=$R/data/local/gen5w-portable/diagnostics/failure-fixture-boot
[ -s "$D/DONE" ] && grep -q worker-owner "$D/START" && grep -q 'exit=23' "$D/boot-health-lost"
grep -q failure-ring-buffer "$D/logcat-main.txt"
cp "$D/START" "$t/before"
mksh "$B/diagnostics.sh" capture second
cmp "$t/before" "$D/START"
[ ! -e "$D/second" ]
mksh "$B/diagnostics.sh" active 7
test -s "$R/data/local/gen5w-portable/diagnostics/active-fixture-boot-7/DONE"
cmp "$t/before" "$D/START"
for i in $(seq 8 14); do mkdir "$R/data/local/gen5w-portable/diagnostics/active-fixture-boot-$i"; done
echo exported > "$R/data/local/gen5w-portable/diagnostics/active-fixture-boot-7/EXPORTED"
mksh "$B/diagnostics.sh" active 15
test -s "$R/data/local/gen5w-portable/diagnostics/active-fixture-boot-15/DONE"
test ! -e "$R/data/local/gen5w-portable/diagnostics/active-fixture-boot-7"
test -d "$R/data/local/gen5w-portable/diagnostics/active-fixture-boot-8"
rm -rf "$R/data/local/gen5w-portable/diagnostics"
mkdir "$t/foreign"
ln -s "$t/foreign" "$R/data/local/gen5w-portable/diagnostics"
if mksh "$B/diagnostics.sh" capture forged; then echo FAIL unsafe-link; exit 1; fi
[ -z "$(ls -A "$t/foreign")" ]
echo 'PASS failure snapshot captures logs and local state, preserves first failure, rejects foreign links'
