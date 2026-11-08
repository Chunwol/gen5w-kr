#!/bin/bash
# Builds the development core APK; no OEM implementations or stubs are bundled.
set -euo pipefail
cd "$(dirname "$0")"
SDK=${ANDROID_SDK:-${ANDROID_HOME:-$HOME/AppData/Local/Android/Sdk}}
BT=$SDK/build-tools/${BUILD_TOOLS:-36.0.0}
JAR=$SDK/platforms/${PLATFORM:-android-36}/android.jar
KS=${GEN5W_KEYSTORE:-$HOME/gen5w-kr-private/probe.keystore}
sep=":"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) sep=";"; JAR=$(cygpath -m "$JAR"); KS=$(cygpath -m "$KS");; esac
t() { for f in "$BT/$1" "$BT/$1.exe" "$BT/$1.bat"; do [ -f "$f" ] && { echo "$f"; return; }; done; echo "missing tool $1" >&2; exit 1; }
if [ ! -f "$KS" ]; then bash ../probe/build.sh; fi
rm -rf build/stubs build/classes build/dex
mkdir -p build/stubs build/classes build/dex
javac -encoding UTF-8 -nowarn --release 8 -cp "$JAR" -d build/stubs \
    $(find stubs ../probe/stubs -name '*.java')
javac -encoding UTF-8 -nowarn --release 8 -cp "$JAR${sep}build/stubs" -d build/classes \
    $(find src ../shared/src -name '*.java') ../probe/src/kr/gen5w/probe/Item.java ../probe/src/kr/gen5w/probe/Convert.java
"$(t d8)" --min-api 18 --release --lib "$JAR" --classpath build/stubs --output build/dex $(find build/classes -name '*.class')
"$(t dexdump)" build/dex/classes.dex > build/dexdump.txt
grep -q "Class descriptor" build/dexdump.txt || { echo "empty dex" >&2; exit 1; }
if grep "Class descriptor" build/dexdump.txt | grep -qv "Lkr/gen5w/"; then echo "non-app class in dex" >&2; exit 1; fi
"$(t aapt2)" link --manifest AndroidManifest.xml -I "$JAR" --min-sdk-version 18 --target-sdk-version 19 \
    -o build/unsigned.apk
PY=$(command -v python3 || command -v python)
"$PY" -I -c 'import zipfile; z=zipfile.ZipFile("build/unsigned.apk","a",zipfile.ZIP_DEFLATED); z.write("build/dex/classes.dex","classes.dex"); z.close()'
"$(t zipalign)" -f -p 4 build/unsigned.apk build/aligned.apk
"$(t apksigner)" sign --ks "$KS" --ks-pass "file:$KS.pass" --ks-key-alias probe \
    --v1-signing-enabled true --v2-signing-enabled false --v3-signing-enabled false \
    --min-sdk-version 18 --out build/gen5w-core.apk build/aligned.apk
"$(t apksigner)" verify --min-sdk-version 18 build/gen5w-core.apk
echo "built app/build/gen5w-core.apk (version from source manifest; vehicle validation pending)"
