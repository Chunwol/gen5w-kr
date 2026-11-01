#!/system/bin/sh
# Read-only pre-install check. Changes nothing on the unit: no remount, no
# package install, no Wi-Fi toggle, no setprop. Writes GEN5W-REPORT/CHECK.txt
# (facts) and CHECK.md (verdict) to the USB only. Fixed allowlist: properties,
# file hashes, verifier verdicts, package ids. No VIN, serials, phone data,
# hotspot credentials, keys or /data file contents.
#
# check.sh --verify (run by the safe installers before any change): repeat the
# check into CHECK-NOW.txt and pass only if CHECK.txt exists, came from the same
# build, said "install", and every stable fact still matches exactly.
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
export PATH=${CK_TEST_PATH:-/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin}
DATA=${IT_DATA:-/data}
SYS=${IT_SYSTEM:-/system}
APPS=$DATA/nemesis/apps
TX=$DATA/nemesis/gen5w-kr-integrated
BOOTGUARD=$DATA/nemesis/gen5wkr.bootguard
OUT=GEN5W-REPORT
MODE=check
[ "$1" = --verify ] && MODE=verify
[ ! -L "$OUT" ] || exit 1
mkdir -p "$OUT" || exit 1
for f in CHECK.txt CHECK.md CHECK-NOW.txt; do [ ! -L "$OUT/$f" ] || exit 1; done
if [ "$MODE" = verify ]; then
    [ -f "$OUT/CHECK.txt" ] || { echo 'REFUSED no pre-install check report (GEN5W-REPORT/CHECK.txt): run gen5w-kr-check first'; exit 1; }
    FACTS=$OUT/CHECK-NOW.txt
else
    FACTS=$OUT/CHECK.txt
fi
: > "$FACTS" || exit 1

fact() { echo "$1=$2" >> "$FACTS"; }
clean() { tr -d '\r\n' | cut -c1-96 | sed 's/[^a-zA-Z0-9_.:/ -]/?/g'; }
prop() { getprop "$1" 2>/dev/null | clean; }
digest() { local v; v=$(md5 "$1" 2>/dev/null) || v=$(md5sum "$1" 2>/dev/null) || return 1; set -- $v; echo "$1"; }

# Verdict of the bundled verifiers for one target: stock-v039, patched-v039,
# stock-v035, patched-v035, unknown or missing.
verify() {
    local file=$SYS/$1 dir=checks/$2/bin v39=$3 v35=$4 tool
    [ -f "$file" ] && [ ! -L "$file" ] || { echo missing; return; }
    for tool in "$dir/$v39" "$dir/$v35"; do
        [ -f "$tool" ] && [ ! -L "$tool" ] && chmod 755 "$tool" 2>/dev/null
    done
    if [ -f "$dir/$v39" ]; then
        "$dir/$v39" original "$file" >/dev/null 2>&1 && { echo stock-v039; return; }
        "$dir/$v39" patched "$file" >/dev/null 2>&1 && { echo patched-v039; return; }
    fi
    if [ -f "$dir/$v35" ]; then
        "$dir/$v35" original "$file" >/dev/null 2>&1 && { echo stock-v035; return; }
        "$dir/$v35" patched "$file" >/dev/null 2>&1 && { echo patched-v035; return; }
    fi
    echo unknown
}
# Boot-critical files no edition changes: compare with the stock SHA-256 only.
verify_hash() {
    local file=$SYS/$1 tool=checks/gen5w.kr.timer/bin/sha256-check
    [ -f "$file" ] && [ ! -L "$file" ] || { echo missing; return; }
    [ -f "$tool" ] && [ ! -L "$tool" ] && chmod 755 "$tool" 2>/dev/null || { echo unknown; return; }
    "$tool" verify "$file" "$2" >/dev/null 2>&1 && { echo stock-v039; return; }
    "$tool" verify "$file" "$3" >/dev/null 2>&1 && { echo stock-v035; return; }
    echo unknown
}
# Passive only: the installer may briefly turn Wi-Fi on to look; this check never does.
wifi_seen() {
    local entry class
    for entry in /sys/class/net/wlan*; do [ -e "$entry" ] && { echo yes; return; }; done
    for entry in /sys/bus/sdio/devices/*/class; do
        [ -r "$entry" ] || continue
        IFS= read -r class < "$entry"
        [ "$class" = 0x07 ] && { echo yes; return; }
    done
    case "$(dmesg 2>/dev/null)" in *'Firmware up'*) echo yes;; *) echo unknown;; esac
}
wireless_code() {
    local a
    for a in "$SYS/app/HKMC_DiPO.odex" "$SYS/app/PhoneProjection.odex" "$SYS/app/Iap2ServerApp.odex"; do
        [ -f "$a" ] || continue
        grep -aqE "carplay_wireless|androidauto_wireless|ConnectivitySSID" "$a" 2>/dev/null && { echo yes; return; }
    done
    echo no
}

# --- facts -----------------------------------------------------------------
fact bundle_revision "$(head -n 1 BUILD-REVISION 2>/dev/null | clean)"
fact firmware "$(prop ro.build.product)"
fact display_id "$(prop ro.build.display.id)"
fact incremental "$(prop ro.build.version.incremental)"
fact targetdir "$(prop ro.mobis.targetdir)"
fact hardware "$(prop ro.hardware)"
fact android "$(prop ro.build.version.release)"
[ -x "$SYS/xbin/nemesis" ] && fact nemesis yes || fact nemesis no

S_HOTSPOT=$(verify_hash framework/services.odex 63cf432dd4597a916ce9faa0c26b5f7ad29affba3976cf4c8cf316dc16107c4f 64fe8286ff39ba52223bf04d7c98fe7e4c2579ad06a090f7a4b80a34faa1e0ca)
S_SYSUI=$(verify_hash priv-app/SystemUI.odex 97e7e258df34d76ed61a714f83de4bf0fbc3d6b6188055c941ad2689f72595af 3de39c29f10c8db3ec786f59378f5b716b04e6be473b42989f40ef828ef0867b)
S_AUDIO=$(verify lib/libCarPlayAudio.so gen5w.kr.audio audio-patch audio-patch-v035)
S_IAP2=$(verify app/Iap2ServerApp.odex gen5w.kr.bridge iap2-patch-v039 iap2-patch-v035)
S_DIPO=$(verify app/HKMC_DiPO.odex gen5w.kr.bridge dipo-patch-v039 dipo-patch-v035)
S_GPM=$(verify app/HKMC_GPM.odex gen5w.kr.bridge gpm-patch-v039 gpm-patch-v035)
fact services_odex "$S_HOTSPOT"
fact systemui_odex "$S_SYSUI"
fact carplay_audio_so "$S_AUDIO"
fact iap2_odex "$S_IAP2"
fact dipo_odex "$S_DIPO"
fact gpm_odex "$S_GPM"
for f in framework/services.odex priv-app/SystemUI.odex lib/libCarPlayAudio.so app/Iap2ServerApp.odex app/HKMC_DiPO.odex app/HKMC_GPM.odex; do
    [ -f "$SYS/$f" ] && fact "md5:$f" "$(digest "$SYS/$f")"
done

W_CODE=$(wireless_code)
W_HW=$(wifi_seen)
fact wireless_code "$W_CODE"
fact wifi_hardware_seen "$W_HW"
fact wifi_on "$(settings get global wifi_on 2>/dev/null | clean)"
fact ium_support "$(prop persist.ium.support)"
for x in com.hkmc.software.connectivity.carplay_wireless.xml com.hkmc.software.connectivity.androidauto_wireless.xml com.hkmc.software.wifihotspot.xml android.hardware.wifi.xml; do
    [ -e "$SYS/etc/permissions/$x" ] && fact "perm:$x" present || fact "perm:$x" absent
done
FX=$(prop ro.mobis.targetdir)
if [ -n "$FX" ] && [ -f "$FX/featurexml.cfg" ]; then
    fact featurexml_strip_lines "$(grep -v '^#' "$FX/featurexml.cfg" 2>/dev/null | grep -cE 'carplay_wireless.xml|androidauto_wireless.xml|wifihotspot.xml')"
else
    fact featurexml_strip_lines unknown
fi

PKGS=
if [ -d "$APPS" ]; then
    for d in "$APPS"/*; do
        [ -e "$d" ] || continue
        n=${d##*/}
        case "$n" in *[!a-zA-Z0-9._-]*) n='?';; esac
        PKGS="$PKGS $n"
    done
fi
fact nemesis_packages "${PKGS# }"
OTHER=
for n in $PKGS; do
    case "$n" in gen5w.kr.*) ;; *) OTHER="$OTHER $n";; esac
done
BACKUPS=
for d in "$SYS"/etc/gen5w-kr-backup/*; do [ -e "$d" ] && BACKUPS="$BACKUPS ${d##*/}"; done
fact gen5w_backups "${BACKUPS# }"
TXSTATE=none
[ -f "$TX/state" ] && TXSTATE=$(head -n 1 "$TX/state" | clean)
fact transaction "$TXSTATE"
GUARD=none
if [ -d "$BOOTGUARD" ]; then
    GUARD=present
    [ -f "$BOOTGUARD/armed" ] && GUARD=armed
    [ -e "$BOOTGUARD/recovery-required" ] && GUARD=recovery-required
    fact bootguard_count "$(head -n 1 "$BOOTGUARD/count" 2>/dev/null | clean)"
    fact bootguard_max "$(head -n 1 "$BOOTGUARD/max" 2>/dev/null | clean)"
fi
fact bootguard "$GUARD"
[ -e "$DATA/nemesis/gen5wkr.wireless-disabled" ] && fact wireless_disabled_marker yes || fact wireless_disabled_marker no
[ -e "$DATA/nemesis/gen5wkr.apguard.off" ] && APGUARD_OFF=yes || APGUARD_OFF=no
fact apguard_off $APGUARD_OFF
df "$SYS" "$DATA" /cache 2>/dev/null | while IFS= read -r line; do echo "df=$(echo "$line" | clean)" >> "$FACTS"; done

# --- verdict ---------------------------------------------------------------
BLOCK=; WARN=; WL=
block() { BLOCK="$BLOCK
- $1"; }
warn() { WARN="$WARN
- $1"; }
owned() { [ -e "$SYS/etc/gen5w-kr-backup/$1" ]; }
is_v035() { case "$1" in *-v035) return 0;; esac; return 1; }

for s in "$S_IAP2" "$S_DIPO" "$S_GPM" "$S_SYSUI"; do
    is_v035 "$s" && { block '펌웨어가 V035로 보입니다. 공식 V039로 먼저 업데이트하세요.'; break; }
done
for pair in "Iap2ServerApp:$S_IAP2" "HKMC_DiPO:$S_DIPO" "HKMC_GPM:$S_GPM"; do
    case "${pair#*:}" in
        stock-v039) ;;
        patched-v039) owned bridge || block "${pair%%:*} 파일이 이미 바뀌어 있는데 이 도구의 백업이 없습니다. 공식 V039 업데이트로 순정 복구 후 다시 점검하세요.";;
        *-v035) ;;
        *) if owned bridge; then warn "${pair%%:*} 파일이 이전 버전 패치 상태로 보입니다(${pair#*:}). 설치기가 백업으로 판단합니다."
           else block "${pair%%:*} 파일을 순정 V039로 확인하지 못했습니다(${pair#*:}). 공식 V039 업데이트로 순정 복구 후 다시 점검하세요."; fi;;
    esac
done
# This tool never changes these two; a non-stock copy came from something else.
case "$S_SYSUI" in
    stock-*) ;;
    *) block "SystemUI(시동 동의 화면)가 순정이 아닙니다($S_SYSUI). 다른 도구가 바꾼 상태일 수 있습니다. 공식 V039 업데이트로 순정 복구 후 다시 점검하세요.";;
esac
case "$S_HOTSPOT" in
    stock-*) ;;
    *) block "services.odex(시스템 핵심)가 순정이 아닙니다($S_HOTSPOT). 다른 도구가 바꾼 상태일 수 있습니다. 공식 업데이트로 순정 복구 후 다시 점검하세요.";;
esac
[ "$APGUARD_OFF" = yes ] && warn '핫스팟을 켜는 도중 재부팅이 3번 연속 일어나 무선이 자동으로 꺼져 있습니다(유선은 동작). 다시 설치하면 다시 켜집니다. 재발하면 무선을 쓰지 마세요.'
[ "$GUARD" = recovery-required ] && block '이전 부트가드가 복구 필요 상태입니다. 공식 V039 업데이트를 먼저 하세요.'
case "$TXSTATE" in none|committed|rolled-back) ;;
    *) warn "이전 설치 작업이 끝나지 않은 흔적이 있습니다(state=$TXSTATE). 설치하면 먼저 이 작업을 복구합니다.";; esac
[ -n "$OTHER" ] && warn "다른 NEMESIS 패키지가 있습니다:$OTHER. 이전 Leafia 패키지(wireless.carplay.aa)는 설치 중 백업 후 제거됩니다. 그 외는 그대로 둡니다."
[ -e "$SYS/etc/permissions/android.hardware.wifi.xml" ] && warn 'Wi-Fi 클라이언트 선언(android.hardware.wifi.xml)이 이미 있습니다. 순정에 원래 있던 것인지 확인이 필요합니다. 벽돌 차량에 추가됐던 파일입니다.'

if [ "$W_CODE" != yes ]; then
    WL='무선 안전판을 설치해도 무선은 켜지지 않고 유선 전용으로 설치됩니다(순정 앱에서 무선 코드를 찾지 못함).'
else
    if [ -z "$WL" ]; then
        case "$S_AUDIO" in stock-v039|patched-v039) ;;
            *) warn "libCarPlayAudio.so를 확인하지 못했습니다($S_AUDIO). 무선 오디오 보정은 건너뜁니다.";; esac
        if [ "$W_HW" = yes ]; then
            WL='무선 조건 충족: 무선 코드와 Wi-Fi 장치가 확인됐습니다.'
        else
            WL='무선 코드는 있으나 Wi-Fi 장치가 지금은 꺼져 있어 확인되지 않았습니다. 설치기가 Wi-Fi를 잠깐 켜서 확인하고, 안 되면 유선 전용으로 설치합니다.'
        fi
    fi
fi

if [ -n "$BLOCK" ]; then fact verdict block; else fact verdict install; fi

if [ "$MODE" = verify ]; then
    # Volatile values (Wi-Fi power, free space, boot counter) are not compared.
    stable() { grep -vE '^(wifi_on|wifi_hardware_seen|df|bootguard_count)=' "$1"; }
    SAVED=$OUT/CHECK.txt
    grep -qx 'verdict=install' "$SAVED" || { echo 'REFUSED pre-install check report did not say install'; exit 1; }
    [ -z "$BLOCK" ] || { echo 'REFUSED unit no longer passes the pre-install check'; exit 1; }
    bad=0
    stable "$FACTS" > "$OUT/CHECK-NOW.stable"
    stable "$SAVED" > "$OUT/CHECK-SAVED.stable"
    while IFS= read -r line; do
        grep -qxF "$line" "$OUT/CHECK-SAVED.stable" || { echo "MISMATCH now: $line"; bad=1; }
    done < "$OUT/CHECK-NOW.stable"
    while IFS= read -r line; do
        grep -qxF "$line" "$OUT/CHECK-NOW.stable" || { echo "MISMATCH report: $line"; bad=1; }
    done < "$OUT/CHECK-SAVED.stable"
    rm -f "$OUT/CHECK-NOW.stable" "$OUT/CHECK-SAVED.stable"
    sync
    [ "$bad" = 0 ] || { echo 'REFUSED unit state differs from the pre-install check report: run gen5w-kr-check again'; exit 1; }
    echo 'CHECK verified: unit matches the pre-install check report'
    exit 0
fi

{
    echo '# 설치 전 점검 결과'
    echo
    echo "- 펌웨어: $(prop ro.build.product) / $(prop ro.build.display.id)"
    echo "- 점검 도구 버전: $(head -n 1 BUILD-REVISION 2>/dev/null | cut -c1-7)"
    echo
    if [ -n "$BLOCK" ]; then
        echo '## 판정: 설치하지 마세요'
        echo "$BLOCK"
    else
        echo '## 판정: 설치 가능'
        echo
        echo "- 권장: \`gen5w-kr-safe-wireless.zip\` (동의 화면·services.odex 순정, 무선 유지)"
        echo "- 무선 연결 때 차 일반 핫스팟 이름·암호가 CarPlay용 값으로 바뀝니다."
        echo "- 무선: $WL"
    fi
    if [ -n "$WARN" ]; then
        echo
        echo '## 확인할 점'
        echo "$WARN"
    fi
    echo
    echo '## 파일 상태'
    echo
    echo "| 파일 | 상태 |"
    echo "|---|---|"
    echo "| services.odex (시스템 핵심, 순정 유지) | $S_HOTSPOT |"
    echo "| SystemUI.odex (시동 동의 화면) | $S_SYSUI |"
    echo "| libCarPlayAudio.so (무선 오디오) | $S_AUDIO |"
    echo "| Iap2ServerApp.odex | $S_IAP2 |"
    echo "| HKMC_DiPO.odex | $S_DIPO |"
    echo "| HKMC_GPM.odex | $S_GPM |"
    echo
    echo '이 점검은 차량에 아무것도 쓰지 않았습니다. 세부 값은 CHECK.txt에 있습니다.'
} > "$OUT/CHECK.md"
sync
am broadcast -a com.hkmc.intent.action.TOAST \
    -e com.hkmc.intent.extra.TOAST_MESSAGE "점검 완료: USB의 GEN5W-REPORT/CHECK.md" \
    --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
[ -z "$BLOCK" ]
