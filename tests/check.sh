#!/bin/bash
# Read-only pre-install check: verdicts from fake verifiers, and nothing on the unit changes.
cd "$(dirname "$0")/.."
SH=${MOCK_SH:-mksh}
. tests/unit/shim.sh
unit_shim_setup || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"; unit_shim_cleanup' EXIT
pass=0; fail=0
check() { local name=$1; shift; if "$@"; then pass=$((pass+1)); else echo "FAIL $name"; fail=$((fail+1)); fi; }

U=$W/usb; S=$W/sys; D=$W/data; B=$W/stub; F=$W/sysfs
mkdir -p "$U" "$S/framework" "$S/priv-app" "$S/lib" "$S/app" "$S/etc/permissions" "$D/nemesis/apps" "$B"
cp tools/integrated/check.sh "$U/"
echo 0123456789abcdef > "$U/BUILD-REVISION"
tool() { # checks/<id>/bin/<name>: original if first line "stock", patched if "patched"
    mkdir -p "$U/checks/$1/bin"
    cat > "$U/checks/$1/bin/$2" <<'EOF'
#!/bin/sh
case "$1" in original) grep -q '^stock' "$2";; patched) grep -q '^patched' "$2";; *) exit 2;; esac
EOF
    chmod 755 "$U/checks/$1/bin/$2"
}
# SHA-256 checker for the two boot-critical files (stock V039 hashes only).
mkdir -p "$U/checks/gen5w.kr.timer/bin"
cat > "$U/checks/gen5w.kr.timer/bin/sha256-check" <<'EOF'
#!/bin/sh
case "$1:$3" in verify:63cf*|verify:97e7*) grep -q '^stock' "$2";; *) exit 1;; esac
EOF
chmod 755 "$U/checks/gen5w.kr.timer/bin/sha256-check"
tool gen5w.kr.audio audio-patch
for t in iap2 dipo gpm; do tool gen5w.kr.bridge $t-patch-v039; done
cat > "$B/getprop" <<'EOF'
#!/bin/sh
case "$1" in ro.build.product) echo OSHEV.KOR;; ro.build.display.id) echo V039.001.260902;; *) echo;; esac
EOF
printf '#!/bin/sh\necho 0\n' > "$B/settings"
printf '#!/bin/sh\nexit 0\n' > "$B/am"
printf '#!/bin/sh\nexit 0\n' > "$B/dmesg"
chmod 755 "$B"/*
stock() {
    for f in framework/services.odex priv-app/SystemUI.odex lib/libCarPlayAudio.so app/Iap2ServerApp.odex app/HKMC_GPM.odex; do echo stock > "$S/$f"; done
    printf 'stock\ncarplay_wireless\n' > "$S/app/HKMC_DiPO.odex"
}
run() {
    rm -rf "$U/GEN5W-REPORT"
    (cd "$U" && IT_DATA=$D IT_SYSTEM=$S CK_TEST_SYSFS=$F CK_TEST_PATH="$B:$GEN5W_UNIT_SHIM/bin:/usr/bin:/bin" "$SH" ./check.sh) >/dev/null 2>&1
}
snapshot() { (cd "$W" && find sys data -type f -exec md5sum {} + | sort); }

stock
before=$(snapshot)
check 'stock V039 passes' run
check 'verdict says install' grep -q '판정: 설치 가능' "$U/GEN5W-REPORT/CHECK.md"
check 'no unreleased edition is recommended' eval '! grep -q safe-wireless "$U/GEN5W-REPORT/CHECK.md"'
check 'unknown Wi-Fi recommends the standard edition' grep -q '받을 파일: 기본형 `gen5w-kr-standard.zip`' "$U/GEN5W-REPORT/CHECK.md"
check 'unknown Wi-Fi explains the installer re-check' grep -q '무선만 빼고 설치한 뒤 결과 화면에서 동글형을 안내' "$U/GEN5W-REPORT/CHECK.md"
check 'records the recommendation' grep -qx 'recommend=standard' "$U/GEN5W-REPORT/CHECK.txt"
mkdir -p "$F/bus/usb/devices/1-1"; echo 0cf3 > "$F/bus/usb/devices/1-1/idVendor"; echo 9271 > "$F/bus/usb/devices/1-1/idProduct"
run
check 'dongle without built-in Wi-Fi recommends the dongle edition' grep -q '받을 파일: 동글형 `gen5w-kr-dongle.zip`' "$U/GEN5W-REPORT/CHECK.md"
check 'records the dongle' grep -qx 'dongle_seen=yes' "$U/GEN5W-REPORT/CHECK.txt"
mkdir -p "$F/class/net/wlan0"
run
check 'built-in Wi-Fi recommends the standard edition even with a dongle' grep -qx 'recommend=standard' "$U/GEN5W-REPORT/CHECK.txt"
check 'built-in Wi-Fi is explained' grep -q '내장 Wi-Fi가 확인됐습니다' "$U/GEN5W-REPORT/CHECK.md"
mkdir -p "$D/nemesis/apps/gen5w.kr.dongle"; echo 'id=gen5w.kr.dongle' > "$D/nemesis/apps/gen5w.kr.dongle/NEMESIS.data"
run
check 'installed dongle edition keeps the dongle recommendation' grep -qx 'recommend=dongle' "$U/GEN5W-REPORT/CHECK.txt"
rm -rf "$F" "$D/nemesis/apps/gen5w.kr.dongle"
run
check 'records SystemUI stock' grep -qx 'systemui_odex=stock-v039' "$U/GEN5W-REPORT/CHECK.txt"
check 'records services stock' grep -qx 'services_odex=stock-v039' "$U/GEN5W-REPORT/CHECK.txt"
check 'records firmware' grep -qx 'firmware=OSHEV.KOR' "$U/GEN5W-REPORT/CHECK.txt"
check 'wireless code found' grep -qx 'wireless_code=yes' "$U/GEN5W-REPORT/CHECK.txt"
check 'nothing on the unit changed' test "$before" = "$(snapshot)"

echo junk > "$S/priv-app/SystemUI.odex"
check 'unknown SystemUI fails' eval '! run'
check 'unknown SystemUI says do not install' grep -q '판정: 설치하지 마세요' "$U/GEN5W-REPORT/CHECK.md"
check 'unknown SystemUI reason' grep -q 'SystemUI' "$U/GEN5W-REPORT/CHECK.md"

stock; echo patched > "$S/priv-app/SystemUI.odex"
check 'changed SystemUI fails' eval '! run'

stock; echo junk > "$S/app/HKMC_GPM.odex"
check 'unknown bridge target fails' eval '! run'
check 'bridge reason names file' grep -q 'HKMC_GPM' "$U/GEN5W-REPORT/CHECK.md"

stock; echo junk > "$S/framework/services.odex"
check 'unknown services.odex blocks' eval '! run'
check 'services.odex reason' grep -q 'services.odex' "$U/GEN5W-REPORT/CHECK.md"
stock; echo patched > "$S/framework/services.odex"
check 'changed services.odex blocks' eval '! run'

stock; echo stock > "$S/app/HKMC_DiPO.odex"
check 'no wireless code still installable' run
check 'no wireless code means wired-only' grep -q '유선 전용' "$U/GEN5W-REPORT/CHECK.md"

stock; mkdir -p "$D/nemesis/apps/wireless.carplay.aa"
check 'other package passes with warning' run
check 'other package listed' grep -q 'wireless.carplay.aa' "$U/GEN5W-REPORT/CHECK.md"
rm -rf "$D/nemesis/apps/wireless.carplay.aa"

stock; echo off > "$D/nemesis/gen5wkr.apguard.off"
check 'AP guard off still installable' run
check 'AP guard off recorded' grep -qx 'apguard_off=yes' "$U/GEN5W-REPORT/CHECK.txt"
check 'AP guard off warned' grep -q '무선이 자동으로 꺼져' "$U/GEN5W-REPORT/CHECK.md"
rm -f "$D/nemesis/gen5wkr.apguard.off"

mkdir -p "$D/nemesis/gen5wkr.bootguard"; : > "$D/nemesis/gen5wkr.bootguard/recovery-required"
check 'recovery-required fails' eval '! run'
rm -rf "$D/nemesis/gen5wkr.bootguard"

mkdir -p "$D/nemesis/gen5w-kr-integrated"; echo applying > "$D/nemesis/gen5w-kr-integrated/state"
check 'interrupted transaction warns' eval 'run && grep -q "state=applying" "$U/GEN5W-REPORT/CHECK.md"'

ln -s "$W/elsewhere" "$U/GEN5W-REPORT.tmp" 2>/dev/null; rm -rf "$U/GEN5W-REPORT"; ln -s "$W" "$U/GEN5W-REPORT"
check 'symlinked report dir refused' eval '! (cd "$U" && IT_DATA=$D IT_SYSTEM=$S CK_TEST_SYSFS=$F CK_TEST_PATH="$B:$GEN5W_UNIT_SHIM/bin:/usr/bin:/bin" "$SH" ./check.sh) >/dev/null 2>&1'
rm -f "$U/GEN5W-REPORT" "$U/GEN5W-REPORT.tmp"

unit_shim_report || fail=$((fail+1))
echo "== check: $pass passed, $fail failed"
[ "$fail" = 0 ]
