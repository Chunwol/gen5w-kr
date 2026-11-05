#!/bin/bash
# Compiles a package's src (against its stubs) into <pkgdir>/app/<out>.dex.
# The stubs are compile-only declarations of system classes; they are never
# placed in the dex (checked). Usage: build-dex.sh <pkgdir> <mainclass> <out.dex>
set -euo pipefail
PKG=$1; MAIN=$2; OUT=$3
cd "$(dirname "$0")/.."
SDK=${ANDROID_SDK:-${ANDROID_HOME:-$HOME/AppData/Local/Android/Sdk}}
BT=$SDK/build-tools/${BUILD_TOOLS:-36.0.0}
JAR=$SDK/platforms/${PLATFORM:-android-36}/android.jar
sep=":"; case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) sep=";"; JAR=$(cygpath -m "$JAR") ;; esac
t() { for f in "$BT/$1" "$BT/$1.bat" "$BT/$1.exe"; do [ -f "$f" ] && { echo "$f"; return; }; done; echo "missing $1" >&2; exit 1; }

rm -rf "$PKG/.build"; mkdir -p "$PKG/.build/stubs" "$PKG/.build/classes" "$PKG/app"
# Compile our app with the stub sources on the sourcepath: a source class always
# overrides a same-named class in android.jar, so our extra fields/methods win.
stubpath="$PKG/stubs"
if [ "$PKG" = packages/wireless-bridge ]; then
    stubpath="probe/stubs${sep}packages/wireless-bridge/stubs"
    sourcepath="$PKG/src${sep}$stubpath"
    # Keep unfinished relay prototypes out of the vehicle DEX. They are
    # compiled separately by verify-v039-relay-adapter.sh until every adapter
    # and the atomic package lifecycle are complete.
    sources="$PKG/src/kr/gen5w/wireless/BridgeHostService.java $PKG/src/kr/gen5w/wireless/WirelessBridge.java $PKG/src/kr/gen5w/wireless/PhoneProjectionAccess.java $PKG/src/kr/gen5w/wireless/StockProjectionSession.java $PKG/src/kr/gen5w/wireless/BluetoothCandidateScan.java $PKG/src/kr/gen5w/wireless/ProjectionWifiAccess.java $PKG/src/kr/gen5w/wireless/DriveLog.java"
else
    sourcepath="$stubpath"
    sources=$(find "$PKG/src" -name '*.java')
fi
javac -encoding UTF-8 -nowarn --release 8 -cp "$JAR" -sourcepath "$sourcepath" -d "$PKG/.build/classes" $sources
[ -f "$PKG/.build/classes/${MAIN//.//}.class" ] || { echo "missing main class $MAIN" >&2; exit 1; }
# The stub classes end up compiled too (javac follows the sourcepath); keep only
# our app classes for d8 so nothing from android.* is packaged.
# A jar keeps the kr/gen5w input boundary independent of host command limits.
jar cf "$PKG/.build/app-classes.jar" -C "$PKG/.build/classes" kr
"$(t d8)" --min-api 18 --release --lib "$JAR" --classpath "$PKG/.build/classes" --output "$PKG/.build" "$PKG/.build/app-classes.jar"
"$(t dexdump)" "$PKG/.build/classes.dex" > "$PKG/.build/dexdump.txt"
grep -q "Class descriptor" "$PKG/.build/dexdump.txt" || { echo "FAIL: empty dex"; exit 1; }
if grep "Class descriptor" "$PKG/.build/dexdump.txt" | grep -qv "Lkr/gen5w/"; then
    echo "FAIL: non-app class in dex"; exit 1
fi
cp "$PKG/.build/classes.dex" "$PKG/app/$OUT"
rm -rf "$PKG/.build"
echo "built $PKG/app/$OUT"
