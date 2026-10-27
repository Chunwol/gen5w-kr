#!/bin/bash
# Builds probe/build/gen5w-probe.apk (Git Bash on Windows or Linux).
# Needs: JDK, Android SDK build-tools (d8, aapt2, zipalign, apksigner) and platform android-36.
# Signing key: $GEN5W_KEYSTORE (default ~/gen5w-kr-private/probe.keystore, made on first run;
# password in the file next to it). The key never goes into the repo.
set -euo pipefail
cd "$(dirname "$0")"
SDK=${ANDROID_SDK:-${ANDROID_HOME:-$HOME/AppData/Local/Android/Sdk}}
BT=$SDK/build-tools/${BUILD_TOOLS:-36.0.0}
JAR=$SDK/platforms/${PLATFORM:-android-36}/android.jar
KS=${GEN5W_KEYSTORE:-$HOME/gen5w-kr-private/probe.keystore}
ext=""; case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) ext=".bat"; sep=";" ;; *) sep=":" ;; esac
[ -f "$JAR" ] || { echo "missing $JAR"; exit 1; }
# a build tool by name: d8.bat / aapt2.exe on Windows, plain name elsewhere
t() { for f in "$BT/$1" "$BT/$1.bat" "$BT/$1.exe"; do [ -f "$f" ] && { echo "$f"; return; }; done; echo "missing build tool $1" >&2; exit 1; }
# Windows tools want Windows paths
if [ -n "$ext" ]; then JAR=$(cygpath -m "$JAR"); KS=$(cygpath -m "$KS"); fi

rm -rf build; mkdir -p build/stubs build/classes build/dex build/test
javac -encoding UTF-8 -nowarn --release 8 -cp "$JAR" -d build/stubs $(find stubs -name '*.java')
javac -encoding UTF-8 -nowarn --release 8 -cp "$JAR${sep}build/stubs" -d build/classes $(find src -name '*.java')
[ -f build/classes/kr/gen5w/probe/ProbeService.class ] || { echo "compile failed"; exit 1; }

"$(t d8)" --min-api 18 --release --lib "$JAR" --classpath build/stubs --output build/dex $(find build/classes -name '*.class')
# the declarations in stubs/ must not end up in the app: only kr.gen5w classes may be defined
"$(t dexdump)" build/dex/classes.dex > build/dexdump.txt
grep -q "Class descriptor" build/dexdump.txt || { echo "FAIL: empty dex"; exit 1; }
if grep "Class descriptor" build/dexdump.txt | grep -qv "Lkr/gen5w/"; then
    echo "FAIL: non-app class packaged"; exit 1
fi

"$(t aapt2)" link --manifest AndroidManifest.xml -I "$JAR" --min-sdk-version 18 --target-sdk-version 19 \
    --version-code 1 --version-name 0.1 -o build/unsigned.apk
python3 -I -c 'import sys,zipfile; z=zipfile.ZipFile(sys.argv[1],"a",zipfile.ZIP_DEFLATED); z.write(sys.argv[2],"classes.dex"); z.close()' \
    build/unsigned.apk build/dex/classes.dex 2>/dev/null \
  || python -I -c 'import sys,zipfile; z=zipfile.ZipFile(sys.argv[1],"a",zipfile.ZIP_DEFLATED); z.write(sys.argv[2],"classes.dex"); z.close()' \
    build/unsigned.apk build/dex/classes.dex
"$(t zipalign)" -f -p 4 build/unsigned.apk build/aligned.apk

if [ ! -f "$KS" ]; then
    mkdir -p "$(dirname "$KS")"
    head -c 24 /dev/urandom | base64 | tr -d '/+=' > "$KS.pass"
    keytool -genkeypair -keystore "$KS" -storepass "$(cat "$KS.pass")" -keypass "$(cat "$KS.pass")" \
        -alias probe -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=gen5w-kr probe" >/dev/null
    echo "made signing key $KS"
fi
"$(t apksigner)" sign --ks "$KS" --ks-pass "file:$KS.pass" --ks-key-alias probe \
    --v1-signing-enabled true --v2-signing-enabled false --v3-signing-enabled false \
    --min-sdk-version 18 --out build/gen5w-probe.apk build/aligned.apk
"$(t apksigner)" verify --min-sdk-version 18 build/gen5w-probe.apk
echo "built probe/build/gen5w-probe.apk"
