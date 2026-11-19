#!/bin/bash
# state-reset.sh: the one place that retires inactive earlier portable state.
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/g5p-reset.XXXXXX)
trap 'rm -rf "$t"' EXIT
helper=$PWD/.build/portable/dex-patch-host
r=$t/root; S=$r/data/local/gen5w-portable
printf 'this-boot\n' > "$t/boot_id"
printf '#!/bin/sh\ncat "$PROPS/$1" 2>/dev/null || :\n' > "$t/getprop"; chmod +x "$t/getprop"
export PORTABLE_TEST_ROOT=$r PORTABLE_HELPER=$helper PORTABLE_TEST_MOUNTS=$t/mounts \
    PORTABLE_TEST_GETPROP=$t/getprop PORTABLE_TEST_BOOT_ID_FILE=$t/boot_id PROPS=$t/props
reset() { mksh tools/portable/state-reset.sh > "$t/out" 2>&1; }
refuses() {
    local why=$1 before
    before=$(cd "$S" && find . | sort)
    if reset; then echo "FAIL accepted: $why"; cat "$t/out"; exit 1; fi
    [ "$(cd "$S" && find . | sort)" = "$before" ] || { echo "FAIL moved state while refusing: $why"; exit 1; }
}
# The vehicle state of 2026-11-19: earlier generations, a rolled-back
# migration's originals (identical to live /system) and no live view.
car_state() {
    rm -rf "$r" "$t/props"; mkdir -p "$r/system/app" "$t/props"; : > "$t/mounts"
    printf stock-dipo > "$r/system/app/HKMC_DiPO.odex"
    mkdir -p "$S/boot" "$S/overlay" "$S/runtime" "$S/session" "$S/runtime-payload" "$S/plan-old-1" "$S/debug" "$S/ap"
    echo 0 > "$S/boot/enabled"; echo session-ended-latched > "$S/boot/reason"
    echo committed > "$S/overlay/state"; echo old-boot > "$S/overlay/boot"; echo '/system/app/HKMC_DiPO.odex|id' > "$S/overlay/journal"
    echo committed > "$S/runtime/phase"; echo old-boot > "$S/runtime/boot"
    echo 'saved' > "$S/debug/before.persist.iap2.debug.service"; echo owned > "$S/ap/match-owner"
    mkdir -p "$S/persistent/recovery/originals/system/app"
    cp "$r/system/app/HKMC_DiPO.odex" "$S/persistent/recovery/originals/system/app/"
}

rm -rf "$r"; mkdir -p "$r/data"; : > "$t/mounts"
reset; grep -q 'no earlier state' "$t/out"
echo 'PASS no earlier state: nothing to do'

car_state; reset || { cat "$t/out"; echo 'FAIL vehicle residue refused'; exit 1; }
dest=$(ls -d "$S"/retired/this-boot-*)
for name in boot overlay runtime session runtime-payload plan-old-1 persistent; do
    [ ! -e "$S/$name" ] && [ -e "$dest/$name" ] || { echo "FAIL $name not retired"; exit 1; }
done
[ "$(cat "$S/debug/before.persist.iap2.debug.service")" = saved ] && [ "$(cat "$S/ap/match-owner")" = owned ]
[ "$(cat "$dest/boot/reason")" = session-ended-latched ]
reset; grep -q 'no inactive earlier state' "$t/out"; [ "$(ls "$S/retired" | wc -l)" = 1 ]
echo 'PASS vehicle residue retired (not deleted); debug/ap kept; second run is a no-op'

car_state; echo 1 > "$S/boot/enabled"; refuses 'enabled package'
car_state; echo 'tmpfs /data/local/gen5w-portable/overlay/x tmpfs rw 0 0' > "$t/mounts"; refuses 'owned bind mount'
car_state; echo /data/wrap.sh > "$t/props/wrap.com.daudio.app.dipo"; refuses 'wrap property'
car_state; echo this-boot > "$S/runtime/boot"; refuses 'same-boot live runtime'
echo 'PASS live earlier generation (enabled, mounts, wrap, same-boot runtime) refuses without moving anything'

for marker in transaction-in-progress transaction-needs-recovery transaction-committed migration.lock; do
    car_state
    if [ "$marker" = migration.lock ]; then mkdir "$S/persistent/recovery/$marker"; else : > "$S/persistent/recovery/$marker"; fi
    refuses "persistent marker $marker"
done
car_state; echo owner > "$S/persistent/manifest"; refuses 'persistent owner without recovery manifest'
car_state; printf modified > "$r/system/app/HKMC_DiPO.odex"; refuses 'originals differ from live'
car_state; rm "$r/system/app/HKMC_DiPO.odex"; refuses 'original without live file'
echo 'PASS persistent residue without manifest refuses on any marker, owner, or original that differs from live'

car_state; echo 'GEN5W-RECOVERY-MANIFEST|2' > "$S/persistent/recovery/manifest"; printf modified > "$r/system/app/HKMC_DiPO.odex"
reset || { cat "$t/out"; echo 'FAIL installed persistent payload refused'; exit 1; }
[ -f "$S/persistent/recovery/manifest" ] && [ ! -e "$S/boot" ] && [ ! -e "$S/overlay" ]
echo 'PASS installed persistent payload (recovery manifest) kept for its own update path'

car_state; mv "$S" "$t/real"; ln -s "$t/real" "$S"; refuses 'symlinked state root'
[ -L "$S" ] && [ -d "$t/real/boot" ]
echo 'PASS symlinked state root refused'
