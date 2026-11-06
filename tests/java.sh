#!/bin/bash
# JVM tests, runnable separately in Git Bash where the Windows JDK is available.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v javac >/dev/null 2>&1 || ! command -v java >/dev/null 2>&1; then
    echo "SKIP JVM tests (need both javac and java)"
    exit 77
fi
mkdir -p .build
work=$(mktemp -d "$PWD/.build/java-tests.XXXXXX")
trap 'rm -rf "$work"' EXIT
javac -encoding UTF-8 -nowarn --release 8 -d "$work" \
    app/src/kr/gen5w/hud/*.java app/src/kr/gen5w/core/StockFlag.java app/src/kr/gen5w/core/HudSwitch.java app/src/kr/gen5w/ui/LogTranslator.java app/src/kr/gen5w/ui/I18n.java app/src/kr/gen5w/ui/StatusModel.java app/src/kr/gen5w/ui/BoundedLines.java app/src/kr/gen5w/ui/SwitchRequest.java app/test/*Test.java \
    packages/wireless-bridge/src/kr/gen5w/wireless/WirelessSession.java \
    packages/wireless-bridge/src/kr/gen5w/wireless/BtRelaySession.java \
    packages/wireless-bridge/src/kr/gen5w/wireless/BtRelayPipe.java \
    packages/wireless-bridge/src/kr/gen5w/wireless/CarPlayHandoverPipe.java \
    packages/wireless-bridge/src/kr/gen5w/wireless/StockProjectionSession.java packages/wireless-bridge/src/kr/gen5w/wireless/PhoneProjectionAccess.java \
    packages/wireless-bridge/test/BtRelaySessionTest.java \
    packages/wireless-bridge/test/BtRelayPipeTest.java \
    packages/wireless-bridge/test/CarPlayHandoverPipeTest.java \
    packages/wireless-bridge/src/kr/gen5w/wireless/BluetoothCandidateScan.java \
    packages/wireless-bridge/src/kr/gen5w/wireless/ProjectionWifiAccess.java \
    packages/wireless-bridge/test/StockProjectionSessionTest.java packages/wireless-bridge/test/PhoneProjectionAccessTest.java \
    packages/wireless-bridge/test/BluetoothCandidateScanTest.java \
    packages/wireless-bridge/test/ProjectionWifiAccessTest.java \
    packages/wireless-bridge/src/kr/gen5w/wireless/SdpRefresh.java packages/wireless-bridge/test/SdpRefreshTest.java \
    packages/wireless-bridge/src/kr/gen5w/hotspot/ApBrokerPolicy.java packages/wireless-bridge/test/ApBrokerPolicyTest.java \
    packages/wireless-bridge/src/kr/gen5w/hotspot/ApBrokerCancellation.java packages/wireless-bridge/test/ApBrokerCancellationTest.java \
    packages/wireless-bridge/src/kr/gen5w/hotspot/ApBrokerParent.java packages/wireless-bridge/test/ApBrokerParentTest.java \
    packages/wireless-bridge/src/kr/gen5w/hotspot/ApProfiles.java packages/wireless-bridge/test/ApProfilesTest.java \
    probe/src/kr/gen5w/probe/Item.java probe/src/kr/gen5w/probe/Dump.java probe/test/DumpTest.java
java -cp "$work" HudTest
java -cp "$work" I18nTest "$PWD/app/src/kr/gen5w/ui/MainActivity.java"
java -cp "$work" PaletteTest "$PWD/app/src/kr/gen5w/ui/MainActivity.java" "$PWD/app/src/kr/gen5w/ui/Widgets.java"
java -cp "$work" V039DipoIconTest
java -cp "$work" HudVariantTest
java -cp "$work" AaRouteCacheTest
java -cp "$work" HighwayIconTest
java -cp "$work" GuidanceParserTest
java -cp "$work" GuidanceDiagnosticsTest
java -cp "$work" GuidanceSessionTest
java -cp "$work" OwnershipTest
java -cp "$work" DumpTest
java -cp "$work" WirelessSessionTest
java -cp "$work" StockProjectionSessionTest
java -cp "$work" kr.gen5w.wireless.BtRelaySessionTest
java -cp "$work" kr.gen5w.wireless.BtRelayPipeTest
java -cp "$work" kr.gen5w.wireless.CarPlayHandoverPipeTest
java -cp "$work" PhoneProjectionAccessTest
java -cp "$work" kr.gen5w.wireless.BluetoothCandidateScanTest
java -cp "$work" kr.gen5w.wireless.ProjectionWifiAccessTest
java -cp "$work" SdpRefreshTest
java -cp "$work" TbtDistanceTest
java -cp "$work" StockFlagTest
java -cp "$work" HudSwitchTest
java -cp "$work" SwitchRequestTest
java -cp "$work" LogTranslatorTest
java -cp "$work" StatusModelTest
java -cp "$work" BoundedLinesTest
java -cp "$work" ApProfilesTest
java -cp "$work" ApBrokerPolicyTest
java -cp "$work" ApBrokerCancellationTest
java -cp "$work" ApBrokerParentTest

PY=$(command -v python3 || command -v python)
"$PY" tests/wireless_bridge_integration.py
