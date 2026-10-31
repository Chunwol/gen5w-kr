#!/bin/bash
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
DATA="$W"
export DATA
. "$ROOT/tools/integrated/report.sh"
check 'missing HUD setting stays unknown' test "$(hud_variant)" = '확인되지 않음'
mkdir -p "$DATA/data/kr.gen5w.core/files"
status="$DATA/data/kr.gen5w.core/files/hud-variant.status"
echo CONFIG_ON > "$status"
check 'HUD on is a last observed setting not a physical claim' test "$(hud_variant)" = '마지막 확인: 차량 설정에서 켜짐 · 실제 표시 미확인'
echo CONFIG_OFF > "$status"
check 'HUD off is a last observed setting not a physical claim' test "$(hud_variant)" = '마지막 확인: 차량 설정에서 꺼짐 · 실제 장착 미확인'
echo PRIVATE_UNTRUSTED_VALUE > "$status"
check 'unexpected status is not copied into report' test "$(hud_variant)" = '확인되지 않음'
rm "$status"
ln -s /dev/null "$status"
check 'linked status is not read' test "$(hud_variant)" = '확인되지 않음'
owner="$DATA/data/kr.gen5w.core/files/hud-owner.status"
echo CARPLAY > "$owner"
check 'stored owner is presented as last observed' test "$(hud_owner)" = '마지막 확인: CarPlay 안내 출력 허용'
echo AA > "$owner"
check 'auxiliary AA ownership is presented correctly' test "$(hud_owner)" = '마지막 확인: 보조 Android Auto 안내 출력 중'
done_tests hud-variant-report
