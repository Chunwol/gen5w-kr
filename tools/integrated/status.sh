#!/system/bin/sh
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
. ./common.sh
if [ -f "$TX/state" ]; then echo "transaction=$(cat "$TX/state")"; else echo 'transaction=none'; fi
for id in $IDS; do
    [ -f "$APPS/$id/NEMESIS.data" ] && echo "$id: installed" || echo "$id: absent"
done
[ ! -f "$TX/report" ] || cat "$TX/report"
write_summary || { echo '결과 문서를 USB에 저장하지 못했습니다.'; exit 1; }
