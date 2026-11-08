# Fixed allowlist only. No raw logs, phone identifiers or hotspot credentials.
result() {
    case "$1" in gen5w.kr.localhotspot|gen5w.kr.dongle|gen5w.kr.wireless|gen5w.kr.audio|gen5w.kr.bridge|gen5w.kr.core|gen5w.kr.timer|gen5w.kr.bluelink|gen5w.kr.drivelog)
        echo "$2" > "$TX/result.$1";;
    esac
}
reset_results() { rm -f "$TX"/result.* "$TX/failure" "$TX/recovery-mode"; }
feature_name() {
    case "$1" in
        gen5w.kr.dongle) echo 'USB Wi-Fi 동글 드라이버';;
        gen5w.kr.wireless) echo '무선 연결·핫스팟 설정';;
        gen5w.kr.audio) echo '무선 음악·안내 음성';;
        gen5w.kr.bridge) echo 'Bluetooth 자동 연결·유선 HUD 기반';;
        gen5w.kr.core) echo 'CarPlay 계기판·HUD 길안내';;
        gen5w.kr.timer) echo '시동 주의 안내 즉시 자동 전환';;
        gen5w.kr.bluelink) echo '블루링크 월간 가입 안내 숨기기';;
        gen5w.kr.drivelog) echo 'USB 주행 진단 로그';;
        gen5w.kr.localhotspot) echo '순정 핫스팟 로컬 스위치';;
    esac
}
result_label() {
    case "$1" in
        applied) echo '적용 완료';;
        preserved) echo '기존 설정 유지 · 무선 장치 확인 필요';;
        wired-only) echo '유선 HUD 기반 적용 · 무선 자동 연결 끔';;
        failed) echo '실패';;
        failed-restored) echo '실패 후 이전 상태로 원복';;
        restored) echo '이전 상태로 원복';;
        skipped) echo '이번 설치에서 제외';;
        removed) echo '제거 완료';;
        disabled) echo '이전 설정 해제 · 순정 안내 표시';;
        recovery-required) echo '복구 필요';;
        *) echo '미적용';;
    esac
}
safe_prop() {
    local value
    local cr=$'\r' nl=$'\n'
    value=$(getprop "$1" 2>/dev/null)
    value=${value//"$cr"/}; value=${value//"$nl"/}; value=${value:0:128}
    case "$value" in ''|*[!a-zA-Z0-9_.:/\ -]*) echo '확인 불가';; *) echo "$value";; esac
}
# Shell builtins only: the head unit has no sed.
html_escape() {
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line//\&/\&amp;}; line=${line//</\&lt;}; line=${line//>/\&gt;}; line=${line//\"/\&quot;}
        print -r -- "$line"
    done
}
wifi_support() {
    local entry class messages root=${IT_SYSFS:-/sys}
    for entry in "$root"/class/net/wlan*; do [ -e "$entry" ] && { echo 'Wi-Fi 인터페이스 확인'; return; }; done
    for entry in "$root"/bus/sdio/devices/*/class; do
        [ -r "$entry" ] || continue
        IFS= read -r class < "$entry"
        [ "$class" = 0x07 ] && { echo 'Wi-Fi 하드웨어 확인'; return; }
    done
    [ -n "${IT_SYSFS:-}" ] || messages=$(dmesg 2>/dev/null)
    case "$messages" in
        *'Firmware up'*) echo 'Wi-Fi 펌웨어 응답 확인';;
        *) echo 'Wi-Fi 하드웨어 확인 필요';;
    esac
}
# Which download fits this car, from this run's own results. One line or nothing.
edition_advice() {
    local hint=$DATA/nemesis/gen5wkr.edition-hint value
    if [ -f "$hint" ] && [ ! -L "$hint" ]; then
        value=$(cat "$hint" 2>/dev/null)
        if [ "$value" = standard ]; then
            echo '내장 Wi-Fi가 확인돼 동글형 설치를 멈췄습니다(차는 바뀌지 않았습니다). 기본형 gen5w-kr-standard.zip을 설치하세요. 내장 대신 동글을 꼭 쓰려면 USB 맨 바깥에 빈 파일 GEN5W-FORCE-DONGLE을 두고 다시 실행하세요.'
            return
        fi
    fi
    # Only when the stock apps know wireless projection; a dongle cannot add it.
    for value in "$SYS/app/HKMC_DiPO.odex" "$SYS/app/PhoneProjection.odex" "$SYS/app/Iap2ServerApp.odex" ''; do
        [ -n "$value" ] || return 0
        [ -f "$value" ] && grep -aqE 'carplay_wireless|androidauto_wireless|ConnectivitySSID' "$value" 2>/dev/null && break
    done
    if [ "$VARIANT" != dongle ] && [ "$(cat "$TX/result.gen5w.kr.wireless" 2>/dev/null)" = skipped ] &&
        [ "$(wifi_support)" = 'Wi-Fi 하드웨어 확인 필요' ]; then
        echo '내장 Wi-Fi를 찾지 못해 무선 연결은 빼고 설치했습니다. 내장 Wi-Fi가 없는 차라면 지원 USB Wi-Fi 동글(AR9271/AR7010)을 꽂고 동글형 gen5w-kr-dongle.zip으로 업데이트하세요.'
    fi
}
# "nemesis version" exists from 1.16; 1.15 has no such command.
nemesis_version() {
    local v
    v=$("$NEM" version 2>/dev/null)
    case "$v" in ''|*[!0-9.]*) echo '확인 불가(1.15 이하일 수 있음)';; *) echo "$v";; esac
}
hud_owner() {
    local file=$DATA/data/kr.gen5w.core/files/hud-owner.status value
    [ ! -L "$file" ] && [ -f "$file" ] || { echo '아직 확인되지 않음'; return; }
    value=$(cat "$file" 2>/dev/null)
    case "$value" in
        CARPLAY) echo '마지막 확인: CarPlay 안내 출력 허용';;
        AA) echo '마지막 확인: 보조 Android Auto 안내 출력 중';;
        STOCK) echo '마지막 확인: 순정 내비 안내 우선 · CarPlay HUD 대기';;
        UNKNOWN) echo '마지막 확인: 순정 안내 상태 확인 불가 · CarPlay HUD 대기';;
        *) echo '아직 확인되지 않음';;
    esac
}
hud_variant() {
    local file=$DATA/data/kr.gen5w.core/files/hud-variant.status value
    [ ! -L "$file" ] && [ -f "$file" ] || { echo '확인되지 않음'; return; }
    value=$(cat "$file" 2>/dev/null)
    case "$value" in
        CONFIG_ON) echo '마지막 확인: 차량 설정에서 켜짐 · 실제 표시 미확인';;
        CONFIG_OFF) echo '마지막 확인: 차량 설정에서 꺼짐 · 실제 장착 미확인';;
        *) echo '확인되지 않음';;
    esac
}
native_warning() {
    local file=$DATA/data/kr.gen5w.core/files/hud-native-warning.status value
    [ ! -L "$file" ] && [ -f "$file" ] || { echo '아직 확인되지 않음'; return; }
    value=$(cat "$file" 2>/dev/null)
    case "$value" in
        APIS_PRESENT_SOURCE_UNOBSERVED) echo '순정 경고 API 확인 · CarPlay 중 표시 미확인';;
        APIS_INCOMPLETE_SOURCE_UNOBSERVED) echo '순정 경고 API 일부 확인 · CarPlay 중 표시 미확인';;
        APIS_UNAVAILABLE_SOURCE_UNOBSERVED) echo '순정 경고 API 확인 불가 · 표시 미확인';;
        *) echo '아직 확인되지 않음';;
    esac
}
write_summary() {
    local destination="$(pwd)/GEN5W-REPORT" file id value label installed state revision rows= name report_ids="$ALL_IDS" advice
    case " $report_ids " in
        *" gen5w.kr.dongle "*) ;;
        *)
            if [ -f "$TX/result.gen5w.kr.dongle" ] || [ -f "$APPS/gen5w.kr.dongle/NEMESIS.data" ]; then
                report_ids="gen5w.kr.dongle $report_ids"
            fi
            ;;
    esac
    # Refuse linked report paths even though the device command runs as root.
    [ ! -L "$destination" ] || return 1
    mkdir -p "$destination" || return 1
    for file in RESULT.md ISSUE.md RESULT.html; do
        [ ! -L "$destination/$file" ] && [ ! -L "$destination/$file.tmp" ] || return 1
        [ ! -e "$destination/$file" ] || [ -f "$destination/$file" ] || return 1
    done
    advice=$(edition_advice)
    rm -f "$DATA/nemesis/gen5wkr.edition-hint" 2>/dev/null
    state=$(cat "$TX/state" 2>/dev/null)
    case "$state" in committed|rolled-back|capturing|applying|removing|recovering|recovery-required) ;; *) state=none;; esac
    revision=$(cat BUILD-REVISION 2>/dev/null)
    case "$revision" in ''|*[!a-f0-9]*) revision=unknown;; esac
    {
        echo '# Gen5W KR 적용 결과'
        echo
        if [ -f "$TX/recovery-mode" ]; then echo '**핫스팟 복구 경로로 진행했습니다. 전체 설치 완료가 아닙니다.**'; echo; fi
        if [ -n "$advice" ]; then echo "**받을 버전 안내:** $advice"; echo; fi
        if [ "$VARIANT" = dongle ]; then echo '- 동글형(USB Wi-Fi)'; else echo '- 기본형(내장 Wi-Fi)'; fi
        echo '- 순정 주의 안내 버튼 활성화 즉시 자동 전환 (지원 조건에 한함)'
        echo
        echo "- HUD 설정: $(hud_variant)"
        echo '- 계기판 길안내 지원 여부: 확인되지 않음'
        echo "- 길안내 출력 우선순위: $(hud_owner)"
        echo "- 순정 과속·카메라 경고: $(native_warning)"
        echo
        echo '| 기능 | 적용 결과 | 설치 여부 |'
        echo '|---|---|---|'
        for id in $report_ids; do
            name=$(feature_name "$id")
            value=$(cat "$TX/result.$id" 2>/dev/null); label=$(result_label "$value")
            installed=없음
            [ ! -f "$APPS/$id/NEMESIS.data" ] || installed=있음
            echo "| $name | $label | $installed |"
        done
        echo
        echo '적용 완료는 설정·파일 설치 결과입니다. 실제 휴대폰 연결·소리·HUD 동작 성공을 뜻하지 않습니다.'
        echo '이전 상태로 원복된 기능은 새 적용이 유지되지 않습니다. 복구 필요라면 백업을 삭제하지 마세요.'
    } > "$destination/RESULT.md.tmp" || return 1
    {
        cat "$destination/RESULT.md.tmp"
        echo
        echo '## 진단 로그'
        echo
        echo "- 코드 버전: $revision"
        echo "- NEMESIS 버전: $(nemesis_version)"
        echo "- 명령 종료 코드: ${1:-0}"
        echo "- 트랜잭션 상태: $state"
        echo "- 모델 식별명: $(safe_prop ro.product.model)"
        echo "- 차량 모델 코드: $(safe_prop ro.product.vcrm.model)"
        echo "- 제품 코드: $(safe_prop ro.build.product)"
        echo "- 지역·차종 설정 경로: $(safe_prop ro.mobis.targetdir)"
        echo "- 하드웨어 플랫폼: $(safe_prop ro.hardware)"
        echo "- 소프트웨어 표시 버전: $(safe_prop ro.build.display.id)"
        echo "- 빌드 버전: $(safe_prop ro.build.version.incremental)"
        echo "- Android: $(safe_prop ro.build.version.release) / API $(safe_prop ro.build.version.sdk)"
        echo "- Wi-Fi: $(wifi_support)"
        echo '- 내장 Wi-Fi 모듈이 없으면 동글형 배포 후 시도해 주세요. 동글·드라이버 호환 확인이 필요합니다.'
        echo
        echo '## 기존 설치와 원본 식별'
        echo
        if [ -f "$APPS/wireless.carplay.aa/NEMESIS.data" ]; then
            echo '- 기존 무선 패키지 등록 파일: 있음'
        elif [ -e "$APPS/wireless.carplay.aa" ]; then
            echo '- 기존 무선 패키지: 불완전한 설치 흔적 있음'
        else echo '- 기존 무선 패키지 등록 파일: 없음 (다른 방식의 설치 여부는 판정하지 않음)'; fi
        for file in app/Iap2ServerApp.apk app/Iap2ServerApp.odex app/HKMC_DiPO.apk app/HKMC_DiPO.odex lib/libCarPlayAudio.so lib/libCarPlayCore.so lib/libCarPlayUtils.so lib/libopus.so; do
            value='없음 또는 읽기 불가'
            if [ -f "$SYS/$file" ] && [ ! -L "$SYS/$file" ]; then
                value=$(digest "$SYS/$file")
                case "$value" in ''|*[!a-fA-F0-9]*) value='확인 불가';; esac
            fi
            echo "- $file MD5: $value"
        done
        echo
        echo '## 순정 기능 선언'
        echo
        for name in com.hkmc.software.connectivity.carplay_wireless com.hkmc.software.connectivity.androidauto_wireless com.hkmc.software.wifihotspot; do
            value='확인 불가'
            if command -v pm >/dev/null 2>&1; then
                value=없음
                pm list features 2>/dev/null | grep -qx "feature:$name" && value=있음
            fi
            echo "- $name: $value"
        done
        if [ -f "$TX/failure" ]; then
            echo
            echo '## 설치기 오류 코드'
            # Only messages authored by this installer, not subprocess logs.
            cat "$TX/failure"
        fi
        echo
        echo '## 최초 실패와 복구 진단'
        echo "- 시도: ${ERR_ATTEMPT:-unknown}"
        err_export
        echo
        echo '## 사용자가 작성할 내용'
        echo
        echo '- 차량 모델/연식/지역:'
        echo '- 재현 순서:'
        echo '- 기대한 동작과 실제 동작:'
        echo
        echo '오류가 있으면 이 로그를 확인한 뒤 지원 요청에 첨부해 주세요. 한국 내수용 현대·기아·제네시스 Gen5W만 지원합니다.'
        echo 'https://github.com/Chunwol/gen5w-kr/issues/new/choose'
        echo
        echo 'VIN·일련번호·전화번호·MAC·SSID·비밀번호·인증서·키·토큰·원시 로그·제조사 파일은 수집하지 않았습니다.'
        echo '첨부 전 내용을 확인하고 필요한 경우 모델/버전도 지운 뒤 이슈에 첨부하세요. 자동으로 전송하지 않습니다.'
    } > "$destination/ISSUE.md.tmp" || return 1
    {
        echo '<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
        echo '<title>Gen5W KR 적용 결과</title><style>body{font:16px/1.6 sans-serif;max-width:960px;margin:32px auto;padding:0 16px;color:#17212b}table{border-collapse:collapse;width:100%}th,td{padding:12px;border:1px solid #ccd4dc;text-align:left}.applied,.wired-only{background:#e4f7eb}.failed,.recovery-required{background:#ffe5e5}.failed-restored,.restored,.skipped{background:#fff2cd}pre{white-space:pre-wrap;overflow-wrap:anywhere}a{color:#145ac4}</style>'
        echo '<h1>Gen5W KR 적용 결과</h1><p>설정·파일 적용 결과이며 실제 연결 성공과는 구분합니다.</p>'
        [ ! -f "$TX/recovery-mode" ] || echo '<p><strong>핫스팟 복구 경로입니다. 전체 설치 완료가 아닙니다.</strong></p>'
        if [ -n "$advice" ]; then
            echo '<p style="background:#fff2cd;padding:12px"><strong>받을 버전 안내:</strong> '
            echo "$advice" | html_escape
            echo '</p>'
        fi
        echo '<table><thead><tr><th>기능</th><th>적용 결과</th><th>설치 등록</th></tr></thead><tbody>'
        for id in $report_ids; do
            name=$(feature_name "$id"); value=$(cat "$TX/result.$id" 2>/dev/null)
            case "$value" in applied|wired-only|failed|failed-restored|restored|skipped|removed|disabled|recovery-required) ;; *) value=not-run;; esac
            label=$(result_label "$value"); installed=없음
            [ ! -f "$APPS/$id/NEMESIS.data" ] || installed=있음
            echo "<tr class=\"$value\"><td>$name</td><td>$label</td><td>$installed</td></tr>"
        done
        echo '</tbody></table><h2>실행 정보</h2><pre>'
        cat "$destination/RESULT.md.tmp" | html_escape
        echo '</pre><p><a href="ISSUE.md">이슈 첨부용 문서</a> · <a href="https://github.com/Chunwol/gen5w-kr/issues/new/choose">문제 신고</a></p></html>'
    } > "$destination/RESULT.html.tmp" || return 1
    for file in RESULT.md ISSUE.md RESULT.html; do mv "$destination/$file.tmp" "$destination/$file" || return 1; done
    cat "$destination/RESULT.md"
    echo 'USB의 GEN5W-REPORT/RESULT.html에서 한눈에 확인하고, ISSUE.md를 검토 후 이슈에 첨부하세요.'
    if [ -x /system/bin/am ]; then
        value='Gen5W KR 작업 결과: USB의 GEN5W-REPORT에서 기능별 결과를 확인하세요.'
        [ -z "$advice" ] || value="$value 맞는 버전 안내가 있습니다."
        /system/bin/am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$value" --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1 || true
    fi
    return 0
}
transaction_exit() {
    local status=$1
    write_summary "$status" || echo 'USB 결과 저장 실패: Manager 로그를 확인하세요.'
    rm -f "$TX/lock/pid"; rmdir "$TX/lock" 2>/dev/null
    return "$status"
}
