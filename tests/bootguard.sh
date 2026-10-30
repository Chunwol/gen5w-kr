#!/bin/bash
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
SYS="$W/system"
DATA="$W/data"
CACHE="$W/cache"
mkdir -p "$SYS/framework" "$SYS/priv-app" "$SYS/app" "$SYS/lib" \
    "$SYS/etc/gen5w-kr-backup/hotspot" \
    "$SYS/etc/gen5w-kr-backup/notice" \
    "$SYS/etc/gen5w-kr-backup/bridge" \
    "$SYS/etc/gen5w-kr-backup/audio" \
    "$DATA/nemesis/gen5wkr.bootguard" "$CACHE/dalvik-cache" "$W/bin"
cat > "$W/nemesis" <<'SH'
#!/bin/sh
echo "nemesis $*" >> "$BG_TEST_DATA/calls"
exit 0
SH
chmod +x "$W/nemesis"
write_pair() {
    local backup=$1 target=$2
    printf 'stock-%s\n' "$target" > "$backup"
    printf 'patched-%s\n' "$target" > "$target"
}
write_pair "$SYS/etc/gen5w-kr-backup/hotspot/original" "$SYS/framework/services.odex"
write_pair "$SYS/etc/gen5w-kr-backup/notice/original" "$SYS/priv-app/SystemUI.odex"
write_pair "$SYS/etc/gen5w-kr-backup/bridge/original" "$SYS/app/Iap2ServerApp.odex"
write_pair "$SYS/etc/gen5w-kr-backup/bridge/dipooriginal" "$SYS/app/HKMC_DiPO.odex"
write_pair "$SYS/etc/gen5w-kr-backup/bridge/gpmoriginal" "$SYS/app/HKMC_GPM.odex"
write_pair "$SYS/etc/gen5w-kr-backup/audio/original" "$SYS/lib/libCarPlayAudio.so"
for name in services SystemUI Iap2ServerApp HKMC_DiPO HKMC_GPM; do
    printf stale > "$CACHE/dalvik-cache/${name}.cache"
done
printf 0 > "$DATA/nemesis/gen5wkr.bootguard/count"
printf 3 > "$DATA/nemesis/gen5wkr.bootguard/max"
printf armed > "$DATA/nemesis/gen5wkr.bootguard/armed"
BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" \
BG_TEST_DALVIK="$CACHE/dalvik-cache" \
mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/out" 2>&1
check 'bootguard restores services ODEX' cmp -s "$SYS/framework/services.odex" "$SYS/etc/gen5w-kr-backup/hotspot/original"
check 'bootguard restores SystemUI ODEX' cmp -s "$SYS/priv-app/SystemUI.odex" "$SYS/etc/gen5w-kr-backup/notice/original"
check 'bootguard restores bridge ODEX' cmp -s "$SYS/app/Iap2ServerApp.odex" "$SYS/etc/gen5w-kr-backup/bridge/original"
check 'bootguard restores DiPO ODEX' cmp -s "$SYS/app/HKMC_DiPO.odex" "$SYS/etc/gen5w-kr-backup/bridge/dipooriginal"
check 'bootguard restores GPM ODEX' cmp -s "$SYS/app/HKMC_GPM.odex" "$SYS/etc/gen5w-kr-backup/bridge/gpmoriginal"
check 'bootguard restores audio library' cmp -s "$SYS/lib/libCarPlayAudio.so" "$SYS/etc/gen5w-kr-backup/audio/original"
for name in services SystemUI Iap2ServerApp HKMC_DiPO HKMC_GPM; do
    check "bootguard removes stale ${name} cache" test ! -e "$CACHE/dalvik-cache/${name}.cache"
done
check 'bootguard records recovery marker' grep -qx 'recovered rc=0' "$DATA/nemesis/gen5wkr.bootguard/recovered"

rm -f "$DATA/nemesis/gen5wkr.bootguard/armed"
rm -f "$DATA/nemesis/gen5wkr.bootguard/recovered"
check 'bootguard refuses unarmed recovery' eval '! BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh"'
check 'unarmed recovery leaves no success marker' test ! -e "$DATA/nemesis/gen5wkr.bootguard/recovered"

mkdir -p "$W/integrated" "$W/integrated-data" "$W/integrated-system"
cp "$ROOT/tools/integrated/common.sh" "$ROOT/tools/integrated/report.sh" "$ROOT/tools/integrated/hotspot-repair.sh" "$W/integrated/"
check 'bootguard arm creates an atomic armed marker' env IT_DATA="$W/integrated-data" IT_SYSTEM="$W/integrated-system" bash -c "cd '$W/integrated' && . ./common.sh && bootguard_arm"
rm -rf "$W/integrated-data/nemesis/gen5wkr.bootguard"
check 'bootguard arm failure is fail-closed' env IT_DATA="$W/integrated-data" IT_SYSTEM="$W/integrated-system" IT_BOOTGUARD_FAIL=1 bash -c "cd '$W/integrated' && . ./common.sh && ! bootguard_arm"
check 'failed arm leaves no guard directory' test ! -e "$W/integrated-data/nemesis/gen5wkr.bootguard.tmp" -a ! -e "$W/integrated-data/nemesis/gen5wkr.bootguard"
done_tests bootguard
