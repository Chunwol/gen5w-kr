#!/bin/bash
set -u
cd "$(dirname "$0")/.."
. tests/lib.sh
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/data/nemesis" "$W/mods" "$W/firmware" "$W/sys/class/net/wlan0/device" \
    "$W/sys/bus/usb/devices/1-1" "$W/sys/class/ieee80211/phy0" "$W/props"
echo dongle > "$W/props/persist.gen5w.wifi.backend"
echo 0cf3 > "$W/sys/bus/usb/devices/1-1/idVendor"
echo 7010 > "$W/sys/bus/usb/devices/1-1/idProduct"
ln -s ath9k_htc "$W/sys/class/net/wlan0/device/driver"
ln -s ../../ieee80211/phy0 "$W/sys/class/net/wlan0/phy80211"
for module in gen5w-average ccm ctr seqiv mac80211 ath ath9k_hw ath9k_common ath9k_htc carl9170 p54common p54usb rt2x00lib rt2x00usb rt2800lib rt2800usb eeprom_93cx6 rtl8187; do
    : > "$W/mods/$module.ko"
done
cat > "$W/mods/modules.alias" <<'EOF'
alias usb:v0CF3p7010d*dc*dsc*dp*ic*isc*ip*in* ath9k_htc
alias usb:v0CF3p9271d*dc*dsc*dp*ic*isc*ip*in* ath9k_htc
alias usb:v1B75p9170d*dc*dsc*dp*ic*isc*ip*in* carl9170
alias usb:v2001p3704d*dc*dsc*dp*ic*isc*ip*in* p54usb
alias usb:v148Fp3572d*dc*dsc*dp*ic*isc*ip*in* rt2800usb
EOF
cat > "$W/mods/modules.profile" <<'EOF'
ath9k_htc|gen5w-average ccm ctr seqiv mac80211 ath ath9k_hw ath9k_common ath9k_htc|htc_7010.fw htc_9271.fw|2.4GHz,5GHz|yes|ready
carl9170|gen5w-average ccm ctr seqiv mac80211 ath carl9170|carl9170-1.fw|2.4GHz,5GHz|yes|ready
p54usb|gen5w-average ccm ctr seqiv mac80211 p54common p54usb|isl3887usb isl3886usb|2.4GHz,5GHz|no|ready
rt2800usb|gen5w-average ccm ctr seqiv mac80211 rt2x00lib rt2x00usb rt2800lib rt2800usb|rt2870.bin|2.4GHz,5GHz|yes|ready
rtl8187|ccm ctr seqiv mac80211 eeprom_93cx6 rtl8187||2.4GHz|no|ready
EOF
echo 'usb:v0CF3p7010d0000dc00dsc00dp00ic00isc00ip00in00' > "$W/sys/bus/usb/devices/1-1/modalias"
for firmware in htc_7010.fw htc_9271.fw carl9170-1.fw isl3887usb isl3886usb rt2870.bin; do : > "$W/firmware/$firmware"; done
cat > "$W/bin/getprop" <<EOF
#!/bin/sh
cat "$W/props/\$1" 2>/dev/null
EOF
cat > "$W/bin/setprop" <<EOF
#!/bin/sh
echo "\$2" > "$W/props/\$1"
EOF
cat > "$W/bin/insmod" <<EOF
#!/bin/sh
echo "\$1" >> "$W/data/insmod.log"
[ -z "\${DONGLE_TEST_FAIL_MODULE:-}" ] || [ "\${1##*/}" != "\$DONGLE_TEST_FAIL_MODULE.ko" ] || exit 1
exit 0
EOF
cat > "$W/bin/rmmod" <<EOF
#!/bin/sh
echo "\$1" >> "$W/data/rmmod.log"
[ -z "\${DONGLE_TEST_BUSY_MODULE:-}" ] || [ "\$1" != "\$DONGLE_TEST_BUSY_MODULE" ] || exit 1
exit 0
EOF
cat > "$W/bin/hostapd" <<EOF
#!/bin/sh
[ "\$1" = -B ] && [ "\$2" = -P ] || exit 2
pidfile=\$3; config=\$4
grep -q '^channel=36$' "\$config" || grep -q '^channel=1$' "\$config" || exit 3
grep -q '^ssid=GEN5W-DONGLE-TEST$' "\$config" || exit 4
grep -q '^ctrl_interface=' "\$config" || exit 5
(sleep 120) >/dev/null 2>&1 &
echo \$! > "\$pidfile"
exit 0
EOF
cat > "$W/bin/hostapd_cli" <<EOF
#!/bin/sh
[ "\$2" = "$W/data/nemesis/gen5w-dongle-test-ctrl" ] || exit 2
if [ "\$3" = status ]; then [ "\$MOCK_AP_DISABLED" = 1 ] && echo 'state=DISABLED' || echo 'state=ENABLED'; echo "freq=\${MOCK_AP_FREQ:-5180}"; exit 0; fi
[ "\$3" = all_sta ] || exit 2
[ -f "$W/stations" ] && echo 'Station aa:bb:cc:dd:ee:ff' || true
EOF
chmod +x "$W/bin/"*
export PATH="$W/bin:$PATH" DONGLE_TEST_SYS="$W/sys" \
    DONGLE_TEST_SYS_BUS="$W/sys/bus/usb/devices" DONGLE_TEST_DATA="$W/data" \
    DONGLE_TEST_REPORT="$W/data/test.log" DONGLE_TEST_NET_ROOT="$W/sys/class/net" \
    DONGLE_TEST_MOD_DIR="$W/mods" DONGLE_TEST_FIRMWARE_DIR="$W/firmware" \
    DONGLE_TEST_PROC_MODULES="$W/proc-modules" DONGLE_TEST_BOUND_DRIVER=ath9k_htc DONGLE_TEST_HOSTAPD="$W/bin/hostapd" DONGLE_TEST_HOSTAPD_CLI="$W/bin/hostapd_cli" \
    DONGLE_TEST_WAIT=1 MOCK_STA="$W/stations"

check 'test mode rejects a missing driver selection' eval '! mksh tools/usb-wifi/package/bin/dongle-test.sh start'
check 'test mode refuses an unlisted driver' eval '! mksh tools/usb-wifi/package/bin/dongle-test.sh start unknown'
check 'unlisted driver loads no modules' test ! -s "$W/data/insmod.log"
check 'test mode lists packaged driver profiles' mksh tools/usb-wifi/package/bin/dongle-test.sh list
export DONGLE_TEST_FAIL_MODULE=ath9k_htc
check 'module load failure is reported' eval '! mksh tools/usb-wifi/package/bin/dongle-test.sh start ath9k_htc'
check 'failed start clears diagnostic mode after complete rollback' grep -qx 0 "$W/props/gen5w.dongle.test"
check 'failed start rolls back only newly loaded modules' test -s "$W/data/rmmod.log"
unset DONGLE_TEST_FAIL_MODULE
: > "$W/data/insmod.log"; : > "$W/data/rmmod.log"
export DONGLE_TEST_BOUND_DRIVER=wrong DONGLE_TEST_BUSY_MODULE=ath9k_hw
check 'binding failure is reported' eval '! mksh tools/usb-wifi/package/bin/dongle-test.sh start ath9k_htc'
check 'binding failure retains diagnostic hold when rollback is incomplete' grep -qx 1 "$W/props/gen5w.dongle.test"
check 'binding failure preserves busy modules in cleanup journal' grep -qx ath9k_hw "$W/data/nemesis/gen5w-dongle-test-loaded"
unset DONGLE_TEST_BOUND_DRIVER DONGLE_TEST_BUSY_MODULE
check 'incomplete binding cleanup can be retried' mksh tools/usb-wifi/package/bin/dongle-test.sh stop
check 'successful retry releases diagnostic hold' grep -qx 0 "$W/props/gen5w.dongle.test"
: > "$W/data/insmod.log"; : > "$W/data/rmmod.log"
check 'test mode starts the selected ath9k driver' mksh tools/usb-wifi/package/bin/dongle-test.sh start ath9k_htc
check 'driver selection loads the chosen module' grep -q '/ath9k_htc.ko' "$W/data/insmod.log"
check 'test mode flag set' grep -qx 1 "$W/props/gen5w.dongle.test"
check 'report captures USB ID' grep -q 'USB 0cf3:7010' "$W/data/test.log"
check 'report captures bound driver' grep -q 'WLAN driver=ath9k_htc' "$W/data/test.log"
check 'automatic mode selects a driver from USB modalias metadata' mksh tools/usb-wifi/package/bin/dongle-test.sh start auto
check 'automatic mode reports selected USB driver' grep -q 'Driver selected=ath9k_htc' "$W/data/test.log"
export MOCK_AP_DISABLED=1
check 'AP start rejects a hostapd process that is not enabled' eval '! mksh tools/usb-wifi/package/bin/dongle-test.sh ap-start'
check 'failed AP start cleans up the hostapd process marker' test ! -e "$W/data/nemesis/gen5w-dongle-test-hostapd.pid"
unset MOCK_AP_DISABLED
export MOCK_AP_FREQ=2412
check 'AP start rejects a radio that reports 2.4GHz for the 5GHz test' eval '! mksh tools/usb-wifi/package/bin/dongle-test.sh ap-start'
check 'wrong-band AP attempt removes its process marker' test ! -e "$W/data/nemesis/gen5w-dongle-test-hostapd.pid"
unset MOCK_AP_FREQ
check 'test AP starts on a 5 GHz channel' mksh tools/usb-wifi/package/bin/dongle-test.sh ap-start
check 'report confirms observed 5 GHz AP frequency' grep -q 'AP channel=36 frequency=5180 (5GHz confirmed' "$W/data/test.log"
check 'AP config requests WPA2 and channel 36' grep -q '^wpa=2$' "$W/data/nemesis/gen5w-dongle-test-hostapd.conf"
check 'AP test uses conservative legacy 5 GHz mode' test "$(grep -c '^ieee80211n=' "$W/data/nemesis/gen5w-dongle-test-hostapd.conf")" = 0
check 'AP test does not report a phone before association' eval '! mksh tools/usb-wifi/package/bin/dongle-test.sh ap-status'
printf 'Station aa:bb:cc:dd:ee:ff (on wlan0)\n\tauthorized: yes\n' > "$W/stations"
check 'AP status recognizes an authorized phone station' mksh tools/usb-wifi/package/bin/dongle-test.sh ap-status
check 'report distinguishes AP start from phone association' grep -q 'AP station=associated' "$W/data/test.log"
AP_PID=$(cat "$W/data/nemesis/gen5w-dongle-test-hostapd.pid")
export DONGLE_TEST_BUSY_MODULE=ath9k_htc
check 'busy module prevents unsafe cleanup completion' eval '! mksh tools/usb-wifi/package/bin/dongle-test.sh stop'
check 'busy module remains journaled for retry' grep -qx ath9k_htc "$W/data/nemesis/gen5w-dongle-test-loaded"
check 'busy module keeps auto-loader test hold active' grep -qx 1 "$W/props/gen5w.dongle.test"
unset DONGLE_TEST_BUSY_MODULE
check 'test mode stops AP and restores its test flag' mksh tools/usb-wifi/package/bin/dongle-test.sh stop
check 'test flag cleared' grep -qx 0 "$W/props/gen5w.dongle.test"
check 'AP process stopped' eval '! kill -0 "$AP_PID" 2>/dev/null'
echo 0cf3 > "$W/sys/bus/usb/devices/1-1/idVendor"; echo 9271 > "$W/sys/bus/usb/devices/1-1/idProduct"
echo 'usb:v0CF3p9271d0000dc00dsc00dp00ic00isc00ip00in00' > "$W/sys/bus/usb/devices/1-1/modalias"
export DONGLE_TEST_BOUND_DRIVER=ath9k_htc
check '2.4GHz-only AR9271 starts in dongle diagnostic mode' mksh tools/usb-wifi/package/bin/dongle-test.sh start ath9k_htc
check 'AP test rejects an unsupported band selector' eval '! mksh tools/usb-wifi/package/bin/dongle-test.sh ap-start 6g'
export MOCK_AP_FREQ=5180
check '2.4GHz AP test rejects a radio reporting 5GHz' eval '! mksh tools/usb-wifi/package/bin/dongle-test.sh ap-start 2g'
check 'wrong-band 2.4GHz AP attempt removes its process marker' test ! -e "$W/data/nemesis/gen5w-dongle-test-hostapd.pid"
export MOCK_AP_FREQ=2412 MOCK_AP_CHANNEL=1
check 'AP test starts on 2.4GHz when requested' mksh tools/usb-wifi/package/bin/dongle-test.sh ap-start 2g
check 'report confirms observed 2.4GHz AP frequency' grep -q 'AP channel=1 frequency=2412 (2.4GHz confirmed' "$W/data/test.log"
check '2.4GHz AP config uses channel 1' grep -q '^channel=1$' "$W/data/nemesis/gen5w-dongle-test-hostapd.conf"
check '2.4GHz AP config uses g mode' grep -q '^hw_mode=g$' "$W/data/nemesis/gen5w-dongle-test-hostapd.conf"
check '2.4GHz report limits result to AP and phone association' grep -q '2.4GHz radio test only; not concurrent CarPlay/Bluetooth validation' "$W/data/test.log"
printf 'Station aa:bb:cc:dd:ee:ff (on wlan0)\n' > "$W/stations"
check '2.4GHz station is reported as association only' mksh tools/usb-wifi/package/bin/dongle-test.sh ap-status
check '2.4GHz association report names its band' grep -q 'AP station=associated band=2.4GHz channel=1' "$W/data/test.log"
check '2.4GHz test mode cleanup succeeds' mksh tools/usb-wifi/package/bin/dongle-test.sh stop
unset DONGLE_TEST_BOUND_DRIVER MOCK_AP_FREQ MOCK_AP_CHANNEL
echo 1b75 > "$W/sys/bus/usb/devices/1-1/idVendor"; echo 9170 > "$W/sys/bus/usb/devices/1-1/idProduct"
echo 'usb:v1B75p9170d0000dc00dsc00dp00ic00isc00ip00in00' > "$W/sys/bus/usb/devices/1-1/modalias"
export DONGLE_TEST_BOUND_DRIVER=carl9170
check 'CARL9170 alias selects its matching USB device' mksh tools/usb-wifi/package/bin/dongle-test.sh start carl9170
check 'CARL9170 module loaded from the selected profile' grep -q '/carl9170.ko' "$W/data/insmod.log"
check 'CARL9170 selection cleans up' mksh tools/usb-wifi/package/bin/dongle-test.sh stop
echo 2001 > "$W/sys/bus/usb/devices/1-1/idVendor"; echo 3704 > "$W/sys/bus/usb/devices/1-1/idProduct"
echo 'usb:v2001p3704d0000dc00dsc00dp00ic00isc00ip00in00' > "$W/sys/bus/usb/devices/1-1/modalias"
export DONGLE_TEST_BOUND_DRIVER=p54usb
check 'P54USB alias selects its matching USB device' mksh tools/usb-wifi/package/bin/dongle-test.sh start p54usb
check 'P54USB selection cleans up' mksh tools/usb-wifi/package/bin/dongle-test.sh stop
echo 148f > "$W/sys/bus/usb/devices/1-1/idVendor"; echo 3572 > "$W/sys/bus/usb/devices/1-1/idProduct"
echo 'usb:v148Fp3572d0000dc00dsc00dp00ic00isc00ip00in00' > "$W/sys/bus/usb/devices/1-1/modalias"
export DONGLE_TEST_BOUND_DRIVER=rt2800usb
check 'RT2800USB alias selects its matching USB device' mksh tools/usb-wifi/package/bin/dongle-test.sh start rt2800usb
check 'RT2800USB selection cleans up' mksh tools/usb-wifi/package/bin/dongle-test.sh stop
echo 9999 > "$W/sys/bus/usb/devices/1-1/idVendor"; echo 0001 > "$W/sys/bus/usb/devices/1-1/idProduct"
echo 'usb:v9999p0001d0000dc00dsc00dp00ic00isc00ip00in00' > "$W/sys/bus/usb/devices/1-1/modalias"
export DONGLE_TEST_BOUND_DRIVER=rtl8187
check 'manual driver trial accepts an attached USB device absent from modalias catalog' mksh tools/usb-wifi/package/bin/dongle-test.sh start rtl8187
check 'unmatched manual USB trial is reported as diagnostic only' grep -q 'without a matching packaged USB alias' "$W/data/test.log"
check 'manual USB trial cleanup succeeds' mksh tools/usb-wifi/package/bin/dongle-test.sh stop
echo 1234 > "$W/sys/bus/usb/devices/1-1/idVendor"; echo 5678 > "$W/sys/bus/usb/devices/1-1/idProduct"
echo 'usb:v1234p5678d0000dc00dsc00dp00ic00isc00ip00in00' > "$W/sys/bus/usb/devices/1-1/modalias"
echo 'alias usb:v1234p5678d*dc*dsc*dp*ic*isc*ip*in* partial_usb' >> "$W/mods/modules.alias"
echo 'partial_usb|ccm ctr seqiv partial_usb|unavailable.fw|2.4GHz|no|incomplete' >> "$W/mods/modules.profile"
: > "$W/mods/partial_usb.ko"
export DONGLE_TEST_BOUND_DRIVER=partial_usb
check 'automatic diagnosis can try a compiled profile with missing firmware' mksh tools/usb-wifi/package/bin/dongle-test.sh start auto
check 'incomplete-profile trial is explicitly recorded as diagnostic only' grep -q 'trying incomplete profile partial_usb' "$W/data/test.log"
check 'incomplete-profile trial loads its candidate module' grep -q '/partial_usb.ko' "$W/data/insmod.log"
check 'incomplete-profile diagnostic cleanup succeeds' mksh tools/usb-wifi/package/bin/dongle-test.sh stop
echo "== dongle test mode: $PASS passed, $FAIL failed"
exit "$FAIL"
