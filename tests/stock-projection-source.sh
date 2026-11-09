#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bridge=packages/wireless-bridge/src/kr/gen5w/wireless/WirelessBridge.java
wireless=packages/wireless-bridge/src/kr/gen5w/wireless
require_bridge() {
    grep -Fq "$1" "$bridge" || { echo "FAIL bridge integration missing: $1"; exit 1; }
}
require_bridge 'registerAction("android.net.wifi.WIFI_AP_STATE_CHANGED")'
require_bridge 'ProjectionWifiAccess.inspect('
require_bridge 'private ProjectionWifiAccess.CredentialStatus inspectWifiCredentials()'
require_bridge 'session.claimBootstrapBroadcast('
require_bridge 'session.claimBootstrapInvocation('
require_bridge 'session.claimRequest('
require_bridge 'PhoneProjectionAccess.bootstrap('
require_bridge 'BluetoothDevice.ACTION_UUID'
require_bridge 'fetchUuidsWithSdp()'
require_bridge 'Boolean.TRUE.equals(appleCarPlay.get(address))'
require_bridge 'session.bootstrapped('
require_bridge 'ProjectionWifiAccess.ApProgress apProgress'
for code in platform-carplay platform-android-auto profile-bootstrap-timeout wifi-ap-timeout projection-timeout wifi-credentials-unavailable wifi-ap-ready; do
    require_bridge "\"$code\""
done
for forbidden in BluetoothSocket createRfcommSocketToServiceRecord Iap2SvcInit Iap2SvcTransportReadDone ApBrokerClient ApProfiles PROJECTION_ACTION; do
    if grep -q "$forbidden" "$bridge"; then
        echo "FAIL stock projection path owns no private transport: found $forbidden"
        exit 1
    fi
done
for forbidden in RequestAction dispatchIfRequestAllowed dispatchIfBootstrapAllowed createRfcommSocket connectRfcomm AndroidAutoTransport java.net.Socket setWifiEnabled setWifiApEnabled setWifiApState setWifiApConfiguration startSoftAp stopSoftAp hostapd requestWLDeviceInfoAdd requestWLDeviceInfoUpdate; do
    if grep -q "$forbidden" "$bridge"; then
        echo "FAIL stock projection source contains forbidden mutation/transport: $forbidden"
        exit 1
    fi
done
# Only the read-only observer may name credential fields, and only as field reads.
if grep -nE 'ConnectivitySSID|ConnectivityPSK' "$wireless"/*.java | grep -vE 'ProjectionWifiAccess.java:[0-9]+: *Field (ssidField|pskField) = configuration.getClass\(\).getField\("Connectivity(SSID|PSK)"\);'; then
    echo 'FAIL credential fields outside observer reads'; exit 1
fi
if grep -nEi '(log\(|Log\.[idwev]\(|DriveLog\.).*(getAddress\(|\+ *(address|value|ssid[a-z0-9_]*|psk[a-z0-9_]*|configuration|connected|candidate)\b)|([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' "$wireless"/*.java; then
    echo 'FAIL wireless identifier or credential logging'; exit 1
fi
grep -Fq 'relay-gate.sh' packages/wireless-bridge/scripts/service.sh
grep -Fq 'relay_v039 true' packages/wireless-bridge/scripts/service.sh
# Exercise the gate contract rather than freezing a previous marker spelling.
bash tests/relay-gate.sh
grep -q 'SEND_CONNECTION_PHONEPROJECTION' packages/wireless-bridge/src/kr/gen5w/wireless/PhoneProjectionAccess.java
grep -q 'getWLDeviceInfo' packages/wireless-bridge/src/kr/gen5w/wireless/PhoneProjectionAccess.java
grep -q 'getWLDAutoConnection' packages/wireless-bridge/src/kr/gen5w/wireless/PhoneProjectionAccess.java
grep -q 'getCPConnectedBTAddress' packages/wireless-bridge/src/kr/gen5w/wireless/PhoneProjectionAccess.java
grep -q 'StockProjectionSession.safeDiagnosticToken(value)' "$bridge"
grep -Fq 'com.hkmc.software.connectivity.carplay_wireless' packages/wireless-enable/files/permissions/com.hkmc.software.connectivity.carplay_wireless.xml
grep -Fq 'com.hkmc.software.connectivity.androidauto_wireless' packages/wireless-enable/files/permissions/com.hkmc.software.connectivity.androidauto_wireless.xml
grep -q 'WirelessBridge.java' tools/build-dex.sh
grep -q 'PhoneProjectionAccess.java' tools/build-dex.sh
echo 'PASS stock-only PhoneProjection source audit'
