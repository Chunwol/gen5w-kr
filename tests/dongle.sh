#!/bin/bash
# Mock test for USB Wi-Fi dongle package (gen5w.kr.dongle)
set -u
cd "$(dirname "$0")/.."
. tests/lib.sh

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/pkg/scripts" "$W/pkg/bin" "$W/pkg/files/modules" "$W/pkg/files/firmware"
mkdir -p "$W/sys/lib" "$W/sys/etc/firmware" "$W/sys/wifi" "$W/sys/bin" "$W/data" "$W/bin" "$W/fixture"
mkdir -p "$W/sys/bus/usb/devices/1-1"

# Copy package files
cp tools/usb-wifi/package/scripts/*.sh "$W/pkg/scripts/"
cp tools/usb-wifi/package/bin/status.sh "$W/pkg/bin/"
echo "mock_adapter_lib" > "$W/pkg/files/libhardware_legacy.so"
echo "mock_module" > "$W/pkg/files/modules/ath9k_htc.ko"
echo "mock_firmware" > "$W/pkg/files/firmware/htc_9271.fw"
echo "mock_loader" > "$W/pkg/bin/gen5w-dongle-load"

echo "stock_original_hal" > "$W/fixture/stock_hal"
cp "$W/fixture/stock_hal" "$W/sys/lib/libhardware_legacy.so"

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

TARGET=$W/sys/lib/libhardware_legacy.so
STOCK_COPY=$W/sys/lib/libhardware_legacy_stock.so
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

# 3. Postinstall
check 'dongle postinstall succeeds' run post
check 'dongle target replaced with adapter' cmp -s "$TARGET" "$W/pkg/files/libhardware_legacy.so"
check 'dongle stock HAL copy placed' cmp -s "$STOCK_COPY" "$W/fixture/stock_hal"
check 'dongle durable backup created' cmp -s "$PERSIST/original" "$W/fixture/stock_hal"
check 'dongle runtime backup created' cmp -s "$MARK/original" "$W/fixture/stock_hal"
check 'dongle module installed' test -f "$W/sys/wifi/dongle/ath9k_htc.ko"
check 'dongle firmware installed' test -f "$W/sys/etc/firmware/htc_9271.fw"
check 'dongle loader installed' test -f "$W/sys/bin/gen5w-dongle-load"

# 4. Status script
check 'dongle status executes' mksh "$W/pkg/bin/status.sh"

# 5. Idempotent reinstall
check 'dongle reinstall succeeds' run post
check 'dongle reinstall preserves original' cmp -s "$STOCK_COPY" "$W/fixture/stock_hal"

# 5a. Tampered reinstall rejection
echo "corrupted_stock" > "$STOCK_COPY"
check 'dongle reinstall rejects corrupted stock copy' eval '! run post'
cp "$W/fixture/stock_hal" "$STOCK_COPY"

echo "corrupted_backup" > "$PERSIST/original"
check 'dongle reinstall rejects corrupted durable backup' eval '! run post'
cp "$W/fixture/stock_hal" "$PERSIST/original"

check 'dongle reinstall succeeds after integrity restored' run post

# 6. Preuninstall
check 'dongle uninstall succeeds' run preun
check 'dongle uninstall restores stock HAL byte-identical' cmp -s "$TARGET" "$W/fixture/stock_hal"
check 'dongle uninstall removes stock copy' test ! -f "$STOCK_COPY"
check 'dongle uninstall removes modules' test ! -d "$W/sys/wifi/dongle"
check 'dongle uninstall removes firmware' test ! -f "$W/sys/etc/firmware/htc_9271.fw"
check 'dongle uninstall removes loader' test ! -f "$W/sys/bin/gen5w-dongle-load"
check 'dongle uninstall cleans durable backup' test ! -d "$PERSIST"
check 'dongle uninstall cleans runtime backup' test ! -d "$MARK"

echo "== dongle: $PASS passed, $FAIL failed"
exit $FAIL
