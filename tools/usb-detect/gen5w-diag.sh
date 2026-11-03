#!/system/bin/sh
# Read-only diagnosis: consent screen, wireless CarPlay, Bluetooth audio.
# Writes only to the USB. Lines with MAC addresses, SSIDs, passwords or serials are dropped.
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
[ "$(getprop sys.boot_completed 2>/dev/null)" = 1 ] || exit 1
[ ! -L GEN5W-REPORT ] || exit 1
mkdir -p GEN5W-REPORT || exit 1
[ ! -L GEN5W-REPORT/DIAG.txt ] || exit 1
O=GEN5W-REPORT/DIAG.txt
PRIV='([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}|ssid|SSID|pass|psk|PSK|serial|Serial|imei|IMEI|iccid|msisdn|vin|VIN'
KEYS='ConsentScreen|DiPO|Dipo|CarPlay|carplay|Iap2|iap2|IAP2|GPM|A2dp|A2DP|a2dp|Avrcp|AVRCP|BluetoothA2dp|BtAudio|BTAudio|AudioPolicy|AudioFlinger|audio_hw|hostapd|SoftAp|softap|WifiService|WifiStateMachine|wpa_supplicant|gen5w|Gen5wWireless|EV6CPWL|MicomAudio|AudioService'
{
    echo "== props"
    getprop | grep -E 'boot_completed|ium|wifi.state|wifi.interface|bluetooth|a2dp|audio|carplay|dipo|hotspot|softap' | grep -v -E "$PRIV"
    echo "== permissions"
    ls /system/etc/permissions | grep -i -E 'wireless|wifi|hotspot'
    echo "== net"
    ls /sys/class/net
    echo "== processes"
    ps | grep -i -E 'gen5w|timer|bridge|dipo|iap2|gpm|hostapd|wpa|bluetooth'
    echo "== nemesis packages"
    ls /data/nemesis/apps
    echo "== bridge startup errors"
    grep -E 'FAIL bridge|Error|Exception|Permission Denial' /data/nemesis/logs/gen5w.kr.bridge/bridge.log 2>/dev/null | grep -v -E "$PRIV"
    echo "== timer service events"
    grep -E 'timer:' /data/nemesis/logs/gen5w.kr.timer/timer.log 2>/dev/null | grep -v -E "$PRIV"
    echo "== logcat main"
    logcat -d -v time 2>&1 | grep -E "$KEYS" | grep -v -E "$PRIV"
    echo "== logcat system"
    logcat -d -v time -b system 2>&1 | grep -E "$KEYS" | grep -v -E "$PRIV"
} > "$O" 2>&1
sync
am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "Gen5W KR: 진단 저장 완료. USB를 빼도 됩니다." --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
exit 0
