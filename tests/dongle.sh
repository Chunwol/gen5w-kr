#!/bin/bash
# Mock test for USB Wi-Fi dongle package (gen5w.kr.dongle)
set -u
cd "$(dirname "$0")/.."
. tests/lib.sh

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/pkg/scripts" "$W/pkg/bin" "$W/pkg/files/modules" "$W/pkg/files/firmware"
mkdir -p "$W/sys/lib" "$W/sys/etc/firmware" "$W/sys/wifi" "$W/sys/bin" "$W/data" "$W/bin" "$W/fixture"
mkdir -p "$W/sys/bus/usb/devices/1-1"
mkdir -p "$W/props"
echo builtin > "$W/props/persist.gen5w.wifi.backend"
printf '#!/bin/sh\ncat "%s/props/$1" 2>/dev/null\n' "$W" > "$W/bin/getprop"
printf '#!/bin/sh\necho "$2" > "%s/props/$1"\n' "$W" > "$W/bin/setprop"
chmod +x "$W/bin/getprop" "$W/bin/setprop"

# Copy package files
cp tools/usb-wifi/package/scripts/*.sh "$W/pkg/scripts/"
cp tools/usb-wifi/package/bin/status.sh "$W/pkg/bin/"
echo "mock_shim_module" > "$W/pkg/files/bcmdhd.ko"
echo "mock_module" > "$W/pkg/files/modules/ath9k_htc.ko"
echo "mock_firmware" > "$W/pkg/files/firmware/htc_9271.fw"
echo "mock_loader" > "$W/pkg/bin/gen5w-dongle-load"

echo "stock_original_bcmdhd" > "$W/fixture/stock_hal"
cp "$W/fixture/stock_hal" "$W/sys/wifi/bcmdhd.ko"
echo "stock_wifi_hal" > "$W/sys/lib/libhardware_legacy.so"

cat > "$W/bin/nemesis" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$W/bin/nemesis"

export PATH="$W/bin:$PATH"
export DONGLE_TEST_SYS="$W/sys"
export DONGLE_TEST_DATA="$W/data"
export DONGLE_TEST_NEM="$W/bin/nemesis"
export DONGLE_TEST_SYS_BUS="$W/sys/bus/usb/devices"
export DONGLE_TEST_STOCK_MD5=$(md5sum "$W/fixture/stock_hal" | cut -d' ' -f1)

TARGET=$W/sys/wifi/bcmdhd.ko
PERSIST=$W/sys/etc/gen5w-kr-backup/dongle
MARK=$W/data/nemesis/backup/gen5w.kr.dongle

run() { mksh "$W/pkg/scripts/$1.sh" >/dev/null 2>&1; }

# 1. Preinstall without USB dongle -> skips (exit 77)
if run pre; then
    bad 'dongle pre without dongle rejected'
else
    ok 'dongle pre without dongle rejected'
fi

# 2. Add supported USB dongle (0cf3:9271)
echo "0cf3" > "$W/sys/bus/usb/devices/1-1/idVendor"
echo "9271" > "$W/sys/bus/usb/devices/1-1/idProduct"

check 'dongle pre accepts 0cf3:9271 dongle' run pre
echo 'existing firmware' > "$W/sys/etc/firmware/htc_9271.fw"
check 'dongle refuses to overwrite existing firmware without a backup' eval '! run pre'
check 'existing firmware remains unchanged after refusal' grep -qx 'existing firmware' "$W/sys/etc/firmware/htc_9271.fw"
rm "$W/sys/etc/firmware/htc_9271.fw"
mkdir -p "$W/data/nemesis/backup" "$W/runtime-foreign"
ln -s "$W/runtime-foreign" "$MARK"
check 'dongle refuses linked runtime backup before install' eval '! run pre'
check 'linked runtime backup is not written' test ! -e "$W/runtime-foreign/original"
rm "$MARK"

# 3. Postinstall
check 'dongle postinstall succeeds' run post
check 'dongle backend is selected' grep -qx dongle "$W/props/persist.gen5w.wifi.backend"
check 'dongle bcmdhd.ko replaced with the stand-in' cmp -s "$TARGET" "$W/pkg/files/bcmdhd.ko"
check 'dongle leaves the stock Wi-Fi HAL untouched' grep -qx stock_wifi_hal "$W/sys/lib/libhardware_legacy.so"
check 'dongle keeps no extra stock copy' test ! -e "$W/sys/lib/libhardware_legacy_stock.so"
check 'dongle durable backup created' cmp -s "$PERSIST/original" "$W/fixture/stock_hal"
check 'dongle runtime backup created' cmp -s "$MARK/original" "$W/fixture/stock_hal"
check 'dongle module installed' test -f "$W/sys/wifi/dongle/ath9k_htc.ko"
check 'dongle firmware installed' test -f "$W/sys/etc/firmware/htc_9271.fw"
check 'dongle loader installed' test -f "$W/sys/bin/gen5w-dongle-load"

# 4. Status script
check 'dongle status executes' mksh "$W/pkg/bin/status.sh"

# 5. Idempotent reinstall
check 'dongle reinstall succeeds' run post
check 'dongle reinstall preserves original' cmp -s "$PERSIST/original" "$W/fixture/stock_hal"
cp "$W/fixture/stock_hal" "$TARGET"
echo partial > "$PERSIST/stage.bcmdhd.ko"
check 'interrupted stand-in copy retries' run post
check 'retried stand-in matches package' cmp -s "$TARGET" "$W/pkg/files/bcmdhd.ko"
check 'stale stand-in stage is removed' test ! -e "$PERSIST/stage.bcmdhd.ko"
rm "$W/sys/wifi/dongle/ath9k_htc.ko"
echo partial > "$PERSIST/stage.ath9k_htc.ko"
check 'interrupted module copy retries' run post
check 'retried module matches package' cmp -s "$W/sys/wifi/dongle/ath9k_htc.ko" "$W/pkg/files/modules/ath9k_htc.ko"
check 'stale module stage is removed' test ! -e "$PERSIST/stage.ath9k_htc.ko"

# 5a. Tampered reinstall rejection
echo "foreign module" > "$TARGET"
check 'dongle reinstall rejects a foreign bcmdhd.ko' eval '! run post'
check 'foreign bcmdhd.ko is preserved' grep -qx 'foreign module' "$TARGET"
cp "$W/pkg/files/bcmdhd.ko" "$TARGET"

echo "corrupted_backup" > "$PERSIST/original"
check 'dongle reinstall rejects corrupted durable backup' eval '! run post'
cp "$W/fixture/stock_hal" "$PERSIST/original"

check 'dongle reinstall succeeds after integrity restored' run post
echo 'foreign change' > "$W/sys/wifi/dongle/ath9k_htc.ko"
check 'dongle uninstall refuses an externally changed module' eval '! run preun'
check 'foreign module content is preserved' grep -qx 'foreign change' "$W/sys/wifi/dongle/ath9k_htc.ko"
check 'foreign module refusal preserves stock backup' test -f "$PERSIST/original"
cp "$W/pkg/files/modules/ath9k_htc.ko" "$W/sys/wifi/dongle/ath9k_htc.ko"

# 5b. Preuninstall refuses when all stock backups are missing or corrupted
mv "$PERSIST/original" "$W/fixture/saved_persist"
mv "$MARK/original" "$W/fixture/saved_mark"
check 'dongle uninstall refuses when no stock backup exists' eval '! run preun'
check 'dongle stand-in kept intact when uninstall refused' cmp -s "$TARGET" "$W/pkg/files/bcmdhd.ko"
mv "$W/fixture/saved_persist" "$PERSIST/original"
mv "$W/fixture/saved_mark" "$MARK/original"

# 6. Preuninstall
cat > "$W/bin/rm" <<EOF
#!/bin/sh
if [ "\$1" = -f ] && [ "\$2" = "$W/sys/bin/gen5w-dongle-load" ]; then exit 1; fi
exec /bin/rm "\$@"
EOF
chmod +x "$W/bin/rm"
check 'file deletion failure refuses uninstall success' eval '! run preun'
check 'file deletion failure keeps recovery backup' test -f "$PERSIST/original"
/bin/rm "$W/bin/rm"
cp "$W/pkg/files/bcmdhd.ko" "$TARGET"
echo unrelated > "$W/sys/wifi/dongle/other-owner.dat"
check 'dongle uninstall succeeds' run preun
check 'dongle uninstall restores stock bcmdhd.ko byte-identical' cmp -s "$TARGET" "$W/fixture/stock_hal"
check 'stock Wi-Fi HAL still untouched after uninstall' grep -qx stock_wifi_hal "$W/sys/lib/libhardware_legacy.so"
check 'dongle uninstall removes own module' test ! -e "$W/sys/wifi/dongle/ath9k_htc.ko"
check 'dongle uninstall preserves unrelated module directory content' grep -qx unrelated "$W/sys/wifi/dongle/other-owner.dat"
check 'dongle uninstall removes firmware' test ! -f "$W/sys/etc/firmware/htc_9271.fw"
check 'dongle uninstall removes loader' test ! -f "$W/sys/bin/gen5w-dongle-load"
check 'dongle uninstall cleans durable backup' test ! -d "$PERSIST"
check 'dongle uninstall cleans runtime backup' test ! -d "$MARK"
check 'dongle uninstall restores previous backend setting' grep -qx builtin "$W/props/persist.gen5w.wifi.backend"

# Firmware reinstall: stock bcmdhd.ko, none of our files and no system journal,
# but the runtime copy and backend setting still in /data.
reinstall_system() {
    cp "$W/fixture/stock_hal" "$TARGET"
    /bin/rm -f "$W/sys/wifi/dongle/ath9k_htc.ko" "$W/sys/etc/firmware/htc_9271.fw" "$W/sys/bin/gen5w-dongle-load"
    /bin/rm -rf "$PERSIST"
}
check 'install before system reinstall' run post
reinstall_system
check 'removal after system reinstall' run preun
check 'removal clears the runtime copy' test ! -e "$MARK"
check 'removal clears the dongle backend setting' test -z "$(cat "$W/props/persist.gen5w.wifi.backend")"
check 'removal leaves stock bcmdhd.ko' cmp -s "$TARGET" "$W/fixture/stock_hal"
run post; reinstall_system
check 'reinstall after system reinstall' run post
check 'reinstall records the cleared backend as original' test -z "$(cat "$PERSIST/backend.original")"
check 'removal after that reinstall' run preun
check 'removal after that reinstall is stock' cmp -s "$TARGET" "$W/fixture/stock_hal"
run post; reinstall_system; cp "$W/pkg/files/bcmdhd.ko" "$TARGET"
check 'stand-in without journal refused' eval '! run preun'
check 'refusal keeps the runtime copy' test -f "$MARK/original"
check 'refusal keeps the stand-in' cmp -s "$TARGET" "$W/pkg/files/bcmdhd.ko"
check 'refused state is not reinstalled over' eval '! run post'

echo "== dongle: $PASS passed, $FAIL failed"
exit $FAIL
