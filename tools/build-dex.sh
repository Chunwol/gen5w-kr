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
extra_sources=()
if [ "$PKG" = packages/wireless-bridge ]; then
    stubpath="probe/stubs${sep}packages/wireless-bridge/stubs"
fi
javac -encoding UTF-8 -nowarn --release 8 -cp "$JAR" -sourcepath "$stubpath" -d "$PKG/.build/classes" $(find "$PKG/src" -name '*.java') "${extra_sources[@]}"
[ -f "$PKG/.build/classes/${MAIN//.//}.class" ] || { echo "missing main class $MAIN" >&2; exit 1; }
# The stub classes end up compiled too (javac follows the sourcepath); keep only
# our app classes for d8 so nothing from android.* is packaged.
"$(t d8)" --min-api 18 --release --lib "$JAR" --classpath "$PKG/.build/classes" --output "$PKG/.build" $(find "$PKG/.build/classes/kr" -name '*.class')
"$(t dexdump)" "$PKG/.build/classes.dex" > "$PKG/.build/dexdump.txt"
grep -q "Class descriptor" "$PKG/.build/dexdump.txt" || { echo "FAIL: empty dex"; exit 1; }
if grep "Class descriptor" "$PKG/.build/dexdump.txt" | grep -qv "Lkr/gen5w/"; then
    echo "FAIL: non-app class in dex"; exit 1
fi
cp "$PKG/.build/classes.dex" "$PKG/app/$OUT"
rm -rf "$PKG/.build"
echo "built $PKG/app/$OUT"
