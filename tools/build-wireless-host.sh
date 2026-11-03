#!/bin/bash
# Package the already-built bridge classes as a registered Android app.
set -euo pipefail
cd "$(dirname "$0")/.."
SDK=${ANDROID_SDK:-${ANDROID_HOME:-$HOME/AppData/Local/Android/Sdk}}
BT=$SDK/build-tools/${BUILD_TOOLS:-36.0.0}
JAR=$SDK/platforms/${PLATFORM:-android-36}/android.jar
KS=${GEN5W_KEYSTORE:-$HOME/gen5w-kr-private/probe.keystore}
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) JAR=$(cygpath -m "$JAR"); KS=$(cygpath -m "$KS");; esac
t() { for f in "$BT/$1" "$BT/$1.exe" "$BT/$1.bat"; do [ -f "$f" ] && { echo "$f"; return; }; done; echo "missing $1" >&2; exit 1; }
[ -f "$KS" ] || bash probe/build.sh
mkdir -p .build/wireless-host packages/wireless-bridge/app
"$(t aapt2)" link --manifest packages/wireless-bridge/host/AndroidManifest.xml -I "$JAR" --min-sdk-version 18 --target-sdk-version 19 -o .build/wireless-host/unsigned.apk
PY=$(command -v python3 || command -v python)
"$PY" -I -c 'import zipfile; z=zipfile.ZipFile(".build/wireless-host/unsigned.apk","a",zipfile.ZIP_DEFLATED); z.write("packages/wireless-bridge/app/bridge.dex","classes.dex"); z.close()'
"$(t zipalign)" -f -p 4 .build/wireless-host/unsigned.apk .build/wireless-host/aligned.apk
"$(t apksigner)" sign --ks "$KS" --ks-pass "file:$KS.pass" --ks-key-alias probe --v1-signing-enabled true --v2-signing-enabled false --v3-signing-enabled false --min-sdk-version 18 --out packages/wireless-bridge/app/wireless-host.apk .build/wireless-host/aligned.apk
"$(t apksigner)" verify --min-sdk-version 18 packages/wireless-bridge/app/wireless-host.apk
