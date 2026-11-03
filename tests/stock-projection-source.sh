#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bridge=packages/wireless-bridge/src/kr/gen5w/wireless/WirelessBridge.java
for forbidden in BluetoothSocket createRfcommSocketToServiceRecord Iap2SvcInit Iap2SvcTransportReadDone ApBrokerClient ApProfiles PROJECTION_ACTION; do
    if grep -q "$forbidden" "$bridge"; then
        echo "FAIL stock projection owns no private transport: found $forbidden"
        exit 1
    fi
done
if grep -q 'ApBroker\|root 1000 -c' packages/wireless-bridge/scripts/service.sh; then
    echo 'FAIL stock projection starts no privileged AP broker'
    exit 1
fi
grep -q 'SEND_CONNECTION_PHONEPROJECTION' packages/wireless-bridge/src/kr/gen5w/wireless/PhoneProjectionAccess.java
grep -q 'getWLDeviceInfo' packages/wireless-bridge/src/kr/gen5w/wireless/PhoneProjectionAccess.java
grep -q 'getWLDAutoConnection' packages/wireless-bridge/src/kr/gen5w/wireless/PhoneProjectionAccess.java
grep -q 'getCPConnectedBTAddress' packages/wireless-bridge/src/kr/gen5w/wireless/PhoneProjectionAccess.java
grep -Fq 'com.hkmc.software.connectivity.carplay_wireless' packages/wireless-enable/files/permissions/com.hkmc.software.connectivity.carplay_wireless.xml
grep -Fq 'com.hkmc.software.connectivity.androidauto_wireless' packages/wireless-enable/files/permissions/com.hkmc.software.connectivity.androidauto_wireless.xml
grep -q 'WirelessBridge.java' tools/build-dex.sh
grep -q 'PhoneProjectionAccess.java' tools/build-dex.sh
echo 'PASS stock-only PhoneProjection source audit'
