#!/bin/bash
# Builds everything into dist/: package zips and ready-to-copy USB folders.
set -euo pipefail
cd "$(dirname "$0")/.."
# Binary revision and source archive must describe the code being compiled.
if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo 'Release build requires a clean committed source checkout.' >&2
    exit 1
fi
PY=$(command -v python3 || command -v python)
SDK=${ANDROID_SDK:-${ANDROID_HOME:-$HOME/AppData/Local/Android/Sdk}}
NDK=${ANDROID_NDK_HOME:-$SDK/ndk/27.2.12479018}
rm -rf dist; mkdir -p dist
bash probe/build.sh
mkdir -p probe/package/app
cp probe/build/gen5w-probe.apk probe/package/app/gen5w-probe.apk
"$PY" -I tools/mkpkg.py probe/package dist/gen5w.kr.probe.zip

# hotspot-match: compile the Java program to a dex and put it in the package
"$PY" -I tools/hotspot/build.py --ndk "$NDK"
bash tools/build-dex.sh packages/hotspot-match kr.gen5w.hotspot.HotspotMatch match.dex
"$PY" -I tools/mkpkg.py packages/hotspot-match dist/gen5w.kr.hotspot.zip
"$PY" -I tools/mkpkg.py packages/wireless-enable dist/gen5w.kr.wireless.zip

"$PY" -I tools/audio/build.py --ndk "$NDK"
"$PY" -I tools/mkpkg.py packages/audio-format dist/gen5w.kr.audio.zip
"$PY" -I tools/iap2/build.py --ndk "$NDK"
bash tools/build-dex.sh packages/wireless-bridge kr.gen5w.wireless.WirelessBridge bridge.dex
"$PY" -I tools/mkpkg.py packages/wireless-bridge dist/gen5w.kr.bridge.zip

# HUD core and native notice timer, then the public six-module USB bundle.
bash app/build.sh
mkdir -p packages/core/app
cp app/build/gen5w-core.apk packages/core/app/gen5w-core.apk
"$PY" -I tools/mkpkg.py packages/core dist/gen5w.kr.core.zip
"$PY" -I tools/notice/build.py --ndk "$NDK"
"$PY" -I tools/mkpkg.py packages/notice-timer dist/gen5w.kr.notice.zip

# USB Wi-Fi dongle adapter and package
"$PY" -I tools/usb-wifi/hal_adapter/build.py --ndk "$NDK"
"$PY" -I tools/usb-wifi/build_dongle_zip.py

"$PY" -I tools/integrated/build.py --dist dist --output dist/usb-integrated
"$PY" -I tools/integrated/build.py --skip-native --variant standard --dist dist --output dist/gen5w-kr-standard
"$PY" -I tools/integrated/build.py --skip-native --variant dongle --dist dist --output dist/gen5w-kr-dongle
"$PY" -I tools/integrated/build.py --skip-native --variant safe --dist dist --output dist/gen5w-kr-safe

# USB folders: copy the contents of one of these to the root of a USB drive
mkdir -p dist/usb-probe-install/packages dist/usb-probe-collect dist/usb-detect
cp probe/usb/install/NEMESIS.data dist/usb-probe-install/
cp dist/gen5w.kr.probe.zip dist/usb-probe-install/packages/
cp probe/usb/collect/NEMESIS.data probe/usb/collect/NEMESIS.sh dist/usb-probe-collect/
cp tools/usb-detect/NEMESIS.data tools/usb-detect/NEMESIS.sh dist/usb-detect/
git archive --format=zip --prefix=gen5w-kr-source/ -o dist/gen5w-kr-source.zip HEAD
(cd dist && for z in *.zip; do md5sum "$z"; done) | tee dist/MD5SUMS
(cd dist && for z in *.zip; do sha256sum "$z"; done) > dist/SHA256SUMS
