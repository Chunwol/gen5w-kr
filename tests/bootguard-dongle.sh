#!/bin/bash
# Boot guard puts the stock bcmdhd.ko back on dongle-edition units.
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
SYS="$W/system"
DATA="$W/data"
CACHE="$W/cache"
BG="$DATA/nemesis/gen5wkr.bootguard"
mkdir -p "$SYS/framework" "$SYS/priv-app" "$SYS/app" "$SYS/lib" \
    "$SYS/etc/gen5w-kr-backup/bridge" \
    "$SYS/etc/gen5w-kr-backup/audio" \
    "$DATA/nemesis/gen5wkr.bootguard" "$CACHE/dalvik-cache" "$W/bin"
cat > "$W/nemesis" <<'SH'
#!/bin/sh
echo "nemesis $*" >> "$BG_TEST_DATA/calls"
exit 0
SH
chmod +x "$W/nemesis"
# Simulate the installed per-profile native tools without distributing OEM files.
for entry in 'gen5w.kr.bridge:iap2-route-patch-v039' 'gen5w.kr.bridge:iap2-route-patch-v035' \
    'gen5w.kr.bridge:iap2-patch-v039' 'gen5w.kr.bridge:iap2-patch-v035' 'gen5w.kr.bridge:dipo-patch-v039' \
    'gen5w.kr.bridge:gpm-patch-v039' 'gen5w.kr.audio:audio-patch'; do
    id=${entry%%:*}; tool=${entry#*:}
    mkdir -p "$DATA/nemesis/apps/$id/bin"
    cat > "$DATA/nemesis/apps/$id/bin/$tool" <<'SH'
#!/bin/sh
case "$1" in
    original) grep -q '^stock-' "$2";;
    patched) grep -q '^patched-' "$2";;
    *) exit 1;;
esac
SH
    chmod +x "$DATA/nemesis/apps/$id/bin/$tool"
done
write_pair() {
    local backup=$1 target=$2
    printf 'stock-%s\n' "$target" > "$backup"
    printf 'patched-%s\n' "$target" > "$target"
}
write_pair "$SYS/etc/gen5w-kr-backup/bridge/original" "$SYS/app/Iap2ServerApp.odex"
write_pair "$SYS/etc/gen5w-kr-backup/bridge/dipooriginal" "$SYS/app/HKMC_DiPO.odex"
write_pair "$SYS/etc/gen5w-kr-backup/bridge/gpmoriginal" "$SYS/app/HKMC_GPM.odex"
write_pair "$SYS/etc/gen5w-kr-backup/audio/original" "$SYS/lib/libCarPlayAudio.so"
chmod 640 "$SYS/etc/gen5w-kr-backup/audio/original"
for name in Iap2ServerApp HKMC_DiPO HKMC_GPM; do
    printf stale > "$CACHE/dalvik-cache/${name}.cache"
done
printf keep > "$CACHE/dalvik-cache/SystemUI.cache"
printf 0 > "$DATA/nemesis/gen5wkr.bootguard/count"
printf 3 > "$DATA/nemesis/gen5wkr.bootguard/max"
printf armed > "$DATA/nemesis/gen5wkr.bootguard/armed"
mkdir -p "$SYS/wifi" "$SYS/etc/gen5w-kr-backup/dongle" "$DATA/nemesis/apps/gen5w.kr.dongle"
printf 'stock-bcmdhd\n' > "$SYS/etc/gen5w-kr-backup/dongle/original"
printf 'stand-in\n' > "$SYS/wifi/bcmdhd.ko"
STOCK=$(md5sum < "$SYS/etc/gen5w-kr-backup/dongle/original" | cut -d' ' -f1)
recover() {
    BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" \
    BG_TEST_DONGLE_MD5=$1 mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/out" 2>&1
}
check 'backup that is not the stock module is refused' eval '! recover 00000000000000000000000000000000'
check 'refusal leaves the stand-in in place' grep -qx stand-in "$SYS/wifi/bcmdhd.ko"
check 'refusal leaves other files patched' grep -q '^patched-' "$SYS/app/Iap2ServerApp.odex"
rm -f "$BG/recovery-required"
check 'verified stock backup is restored' recover "$STOCK"
check 'stock bcmdhd.ko back in place' cmp -s "$SYS/wifi/bcmdhd.ko" "$SYS/etc/gen5w-kr-backup/dongle/original"
check 'other files restored too' grep -q '^stock-' "$SYS/app/Iap2ServerApp.odex"
check 'recovery recorded' grep -qx 'recovered rc=0' "$BG/recovered"
# Dongle package registered but its backup is missing: never guess, refuse.
rm -f "$BG/recovered"; printf armed > "$BG/armed"
rm -f "$SYS/etc/gen5w-kr-backup/dongle/original"
check 'missing dongle backup refuses recovery' eval '! recover "$STOCK"'
check 'missing backup marks manual recovery' test -e "$BG/recovery-required"
# Standard unit (no dongle traces) recovers as before.
rm -rf "$SYS/etc/gen5w-kr-backup/dongle" "$DATA/nemesis/apps/gen5w.kr.dongle" "$BG/recovery-required"
check 'standard unit without dongle recovers' recover "$STOCK"
done_tests bootguard-dongle
