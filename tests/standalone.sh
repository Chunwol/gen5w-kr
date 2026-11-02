#!/bin/bash
# Packages that reboot after install refuse a standalone NEMESIS install: only
# the release bundle arms the boot-loop guard, and it creates the
# reboot-suppression file before running any package check.
cd "$(dirname "$0")/.." || exit 1
ROOT=$(pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fail=0; pass=0
ok()  { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$W/bin"
for c in getprop setprop svc am settings reboot; do
    printf '#!/bin/sh\necho "%s $*" >> "$CALLS"\n' "$c" > "$W/bin/$c"
    chmod 755 "$W/bin/$c"
done
MSG='install this package with the release bundle'
for item in 'wireless-enable EN_TEST_DATA' 'wireless-bridge BRIDGE_TEST_DATA' 'audio-format AUDIO_TEST_DATA'; do
    set -- $item; pkg=$1; datavar=$2
    data=$W/$pkg-data; mkdir -p "$data/nemesis"
    calls=$W/$pkg.calls; : > "$calls"
    out=$(cd "packages/$pkg" && env -u EN_TEST_SYS -u BRIDGE_TEST_SYS -u AUDIO_TEST_SYS \
        PATH="$W/bin:$PATH" CALLS="$calls" "$datavar=$data" mksh scripts/pre.sh 2>&1)
    rc=$?
    if [ "$rc" = 1 ] && [[ "$out" == *"$MSG"* ]]; then ok "$pkg refuses a standalone install"
    else bad "$pkg standalone rc=$rc: $out"; fi
    # Nothing ran before the refusal (the wireless probe would call svc/setprop).
    if ! grep -q -E '^(svc|setprop|reboot|settings) ' "$calls"; then ok "$pkg refuses before any change"
    else bad "$pkg changed state before refusing: $(cat "$calls")"; fi
    : > "$data/nemesis/gen5wkr.noreboot"
    out=$(cd "packages/$pkg" && env -u EN_TEST_SYS -u BRIDGE_TEST_SYS -u AUDIO_TEST_SYS \
        PATH="$W/bin:$PATH" CALLS="$calls" "$datavar=$data" mksh scripts/pre.sh 2>&1)
    [[ "$out" != *"$MSG"* ]] && ok "$pkg passes the guard inside a bundle step" || bad "$pkg refused inside a bundle step"
done
echo "== standalone install guard: $pass passed, $fail failed"
[ "$fail" = 0 ]
