#!/bin/bash
# Compile-only check for the dormant exact-V039 component-4 adapter.
set -euo pipefail
cd "$(dirname "$0")/.."
SDK=${ANDROID_SDK:-${ANDROID_HOME:-$HOME/AppData/Local/Android/Sdk}}
JAR=$SDK/platforms/${PLATFORM:-android-36}/android.jar
sep=":"; case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) sep=";"; JAR=$(cygpath -m "$JAR") ;; esac
out=tools/v039-relay/.build
rm -rf "$out"; mkdir -p "$out"
trap 'rm -rf "$out"' EXIT
sourcepath="tools/v039-relay/src${sep}packages/wireless-bridge/src${sep}probe/stubs${sep}packages/wireless-bridge/stubs"
javac -encoding UTF-8 -nowarn --release 8 -cp "$JAR" -sourcepath "$sourcepath" -d "$out" \
    tools/v039-relay/src/kr/gen5w/wireless/V039BtRelayAdapter.java
test -f "$out/kr/gen5w/wireless/V039BtRelayAdapter.class"
echo 'PASS exact-V039 component-4 adapter compile check (not packaged)'
