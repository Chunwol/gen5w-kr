#!/system/bin/sh
# Portable USB installer. It only copies the verified package ZIP into /data and
# asks NEMESIS to install it; the package's own pre/post hooks perform every
# compatibility, conflict, NEMESIS-version and checksum check. It never removes,
# replaces or changes other packages, /system, or boot images.
umask 077
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
USB=$(pwd) || exit 1
ROOT=${PORTABLE_TEST_ROOT:-}
NEM=${PORTABLE_TEST_NEM:-/system/xbin/nemesis}
SH=${PORTABLE_TEST_SH:-/system/bin/sh}
AM=${PORTABLE_TEST_AM:-/system/bin/am}
SETTINGS=${PORTABLE_TEST_SETTINGS:-/system/bin/settings}
ZIP=gen5w.kr.portable.zip
STAGE=$ROOT/data/gen5w.kr.portable.zip
APP=$ROOT/data/nemesis/apps/gen5w.kr.portable
REPORT=$USB/GEN5W-PORTABLE-REPORT
[ ! -L "$REPORT" ] && mkdir -p "$REPORT" || exit 1
for file in LOG.txt RESULT.txt nemesis-install.txt status.txt baseline.txt status-before.txt nemesis-uninstall.txt nemesis-install-2.txt; do
    [ ! -L "$REPORT/$file" ] || exit 1
done
LOG=$REPORT/LOG.txt
say() { local up rest; read -r up rest < /proc/uptime; print -r -- "${up:-?} $*" >> "$LOG"; }
# On-screen notice, same stock broadcast the integrated installer uses on this car.
alert() {
    say "alert: $1"
    [ -x "$AM" ] || return 0
    "$AM" broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "Gen5W 범용판: $1"         --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1 || :
}
# Restore only the hook we published, including on signals and early failures.
# NEMESIS may replace the entire app or overwrite the hook in place, so compare
# both inode ownership and authored bytes before restoring anything.
transaction=
settle_preun() {
    [ -n "$transaction" ] || return 0
    if [ -f "$transaction/neutral" ] && [ "$preun" -ef "$transaction/neutral" ] &&
            [ "$(digest "$preun")" = "$neutral_digest" ]; then
        if [ -f "$transaction/original" ]; then
            mv "$transaction/original" "$preun" || return 1
        else
            rm "$preun" || return 1
        fi
        say 'original preuninstall restored'
    fi
    rm -f "$transaction/original" "$transaction/neutral" "$transaction/publish" && rmdir "$transaction" || return 1
    transaction=
}
trap 'settle_preun || say "preun restoration failed; recovery files retained at $transaction"' EXIT
trap 'exit 1' HUP INT TERM
finish() {
    # $1 = ok|refused|failed, rest = Korean summary for the driver.
    local state=$1; shift
    if ! settle_preun; then
        state=failed
        set -- "기존 해제 스크립트 복원이 실패했습니다. 보관 경로: $transaction. 재시동하지 말고 보고서를 PC로 가져오세요."
    fi
    { print -r -- "결과: $state"; print -r -- "$*"; } > "$REPORT/RESULT.txt"
    say "result $state: $*"
    sync
    case "$state" in ok) alert '설치 완료. USB를 빼고 시동을 완전히 껐다 켜세요.';;
    *) alert "설치 중단($state): $*";; esac
    [ "$state" = ok ]; exit $?
}
digest() { local line; line=$(md5 "$1" 2>/dev/null) || return 1; set -- $line; print -r -- "$1"; }
say 'portable usb installer start'
alert '설치를 시작합니다. 1~2분 걸립니다. USB를 빼지 마세요.'
[ ! -e GEN5W-PORTABLE-RESCUE ] || finish refused '복구 표식(GEN5W-PORTABLE-RESCUE)이 있는 USB로는 설치하지 않습니다. 표식을 지우고 다시 하세요.'
if [ -z "$ROOT" ]; then
    case "$(id)" in uid=0\(*) :;; *) finish refused 'root 권한이 아니라 설치하지 않았습니다.';; esac
fi
[ -f "$ZIP" ] && [ ! -L "$ZIP" ] && [ -f "$ZIP.md5" ] || finish refused 'USB에 설치 파일이 없습니다.'
expected=; IFS= read -r expected < "$ZIP.md5" || [ -n "$expected" ]
expected=${expected%%[!0-9a-f]*}
[ "${#expected}" = 32 ] || finish refused '설치 파일 확인값이 손상됐습니다.'
[ "$(digest "$ZIP")" = "$expected" ] || finish refused 'USB의 설치 파일이 손상됐습니다. PC에서 USB를 다시 만드세요.'
packages=$("$NEM" pkg-list 2>/dev/null) || finish refused 'NEMESIS 패키지 목록을 읽지 못했습니다.'
update=0
while IFS='|' read -r package rest; do
    case "$package" in
    gen5w.kr.portable) update=1;;
    gen5w.kr.*|wireless.projection|enhanced.projection|projection.tbt)
        finish refused "기존 패키지($package)가 남아 있습니다. 1단계(통합판 제거)를 먼저 끝내세요.";;
    esac
done <<EOF
$packages
EOF
# Same on-disk evidence the integrated installer uses on this vehicle; does not
# depend on the pkg-list output format.
for meta in "$ROOT"/data/nemesis/apps/*/NEMESIS.data; do
    [ -e "$meta" ] || continue
    package=${meta%/NEMESIS.data}; package=${package##*/}
    case "$package" in
    gen5w.kr.portable) update=1;;
    gen5w.kr.*|wireless.projection|enhanced.projection|projection.tbt)
        finish refused "기존 패키지($package)가 남아 있습니다. 1단계(통합판 제거)를 먼저 끝내세요.";;
    esac
done
if [ "$update" = 1 ]; then
    # Only a portable install whose arming never completed is replaced. An armed
    # or running one must be disabled through its own path first.
    [ -f "$APP/boot.sh" ] || finish refused '범용판 등록은 있지만 설치 폴더가 없습니다. 보고서를 PC로 가져오세요.'
    "$SH" "$APP/boot.sh" status > "$REPORT/status-before.txt" 2>&1 || finish refused '기존 범용판 상태를 읽지 못했습니다. 설치하지 않았습니다.'
    grep -qx 'enabled|1' "$REPORT/status-before.txt" &&
        finish refused '범용판이 이미 설치돼 자동 적용이 켜져 있습니다. 다시 설치하지 않았습니다.'
    # A pending attempt of an earlier boot is the guard's own evidence (it already
    # disabled auto-start); only one still running in this boot blocks replacement.
    this_boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
    [ -n "$this_boot" ] && grep -qx "attempt|$this_boot|pending" "$REPORT/status-before.txt" &&
        finish refused '이번 부팅에서 범용판 적용이 아직 끝나지 않았습니다. 시동을 완전히 껐다 켠 뒤 다시 하세요.'
    say 'portable present but not armed; replacing with --update'
    # The installed (older) package's preuninstall treats records of an earlier
    # boot as live and restarts Android without the V039 reset fix: the unit
    # rebooted mid-install (vehicle 2026-11-13). Nothing is applied in this boot
    # when it is not armed and no portable mount or wrap property exists, so the
    # old hook has nothing to undo. Replace it with a no-op before NEMESIS runs it.
    [ -r "$ROOT/proc/mounts" ] || [ -n "$ROOT" ] || finish refused '마운트 상태를 읽지 못했습니다. 설치하지 않았습니다.'
    if grep -q '/data/local/gen5w-portable' "$ROOT/proc/mounts" 2>/dev/null; then
        finish refused '범용판 마운트가 아직 남아 있습니다. 시동을 완전히 껐다 켠 뒤 다시 하세요.'
    fi
    if [ -z "$ROOT" ]; then
        for key in wrap.com.daudio.app.dipo wrap.com.google.android.project; do
            [ -z "$(getprop "$key")" ] || finish refused "범용판 실행 설정($key)이 남아 있습니다. 시동을 완전히 껐다 켠 뒤 다시 하세요."
        done
    fi
    preun=$APP/package-preun.sh
    [ ! -L "$preun" ] && { [ ! -e "$preun" ] || [ -f "$preun" ]; } || finish refused '기존 범용판 해제 스크립트 경로가 안전하지 않습니다.'
fi
say 'zip verified; no conflicting package'
# Stock boot restores the hotspot when wifi_ap_on is set, outside every guard;
# the package refuses anything but 0. Check before any change. V039 settings has
# no #! line, so it is run through sh, bounded like check.sh.
ap=$( ( "$SH" "$SETTINGS" get global wifi_ap_on 2>/dev/null & reader=$!
        ( sleep 30; kill -TERM "$reader" ) >/dev/null 2>&1 & guard=$!
        wait "$reader"; status=$?
        kill "$guard" 2>/dev/null
        exit "$status" ) ) || ap='(읽기 실패)'
ap=${ap%$'\r'}
say "wifi_ap_on=$ap"
[ "$ap" = 0 ] || finish refused "순정 핫스팟 설정(wifi_ap_on)이 0이 아닙니다: $ap. 설치하지 않았고 바뀐 것은 없습니다. 보고서를 PC로 가져오세요."
# Stage under the fixed name the package documentation uses.
if [ -e "$STAGE" ] || [ -L "$STAGE" ]; then
    [ -f "$STAGE" ] && [ ! -L "$STAGE" ] || finish failed '/data의 임시 파일 경로가 안전하지 않아 중단했습니다.'
    rm -f "$STAGE" || finish failed '/data 임시 파일을 지우지 못했습니다.'
fi
cp "$ZIP" "$STAGE" && chmod 600 "$STAGE" && sync || { rm -f "$STAGE"; finish failed '/data로 복사하지 못했습니다(공간 부족 가능).'; }
[ "$(digest "$STAGE")" = "$expected" ] || { rm -f "$STAGE"; finish failed '/data에 복사된 파일이 USB와 다릅니다.'; }
# Only after every read-only admission and staged-ZIP check may the old package
# be touched. Hard links preserve its original inode, metadata and bytes. A
# second link identifies only our temporary hook; a new NEMESIS hook is retained.
if [ "$update" = 1 ]; then
    claim=$ROOT/data/gen5w-portable-usb-preun.$$
    [ ! -e "$claim" ] && [ ! -L "$claim" ] && mkdir "$claim" || finish failed '기존 해제 스크립트 보관 폴더를 만들지 못했습니다.'
    transaction=$claim
    if [ -e "$preun" ]; then
        ln "$preun" "$transaction/original" || finish failed '기존 해제 스크립트를 보관하지 못했습니다.'
    fi
    { print -r -- '#!/system/bin/sh'; print -r -- "echo 'preun: never armed in this boot; nothing to undo (USB installer)'"; } > "$transaction/neutral" || finish failed '임시 해제 스크립트를 만들지 못했습니다.'
    neutral_digest=$(digest "$transaction/neutral") || finish failed '임시 해제 스크립트를 확인하지 못했습니다.'
    ln "$transaction/neutral" "$transaction/publish" && mv "$transaction/publish" "$preun" && sync || finish failed '임시 해제 스크립트를 적용하지 못했습니다. 보고서를 PC로 가져오세요.'
    # The old package's preuninstall (boot.sh disable) refuses while our own apps
    # run, and NEMESIS 1.16.7 then aborts the update (vehicle 2026-11-13, rc=5:
    # kr.gen5w.core had started on its own in the stock boot). Not armed, so
    # nothing depends on them; stop both explicitly first.
    if [ -x "$AM" ]; then
        for app in kr.gen5w.core kr.gen5w.wirelesshost; do
            "$AM" force-stop "$app" >/dev/null 2>&1 || say "force-stop $app failed"
        done
    fi
    say 'own apps stopped before update'
    say 'old preuninstall temporarily neutralized (not armed, no mounts/wrap)'
fi
say 'staged; nemesis install begins'
# NEMESIS extracts the package with the caller's umask. Under 077 the APKs end
# up 0600 in a 0700 directory and pm (uid system) cannot read them (vehicle,
# 2026-11-13). Use the same 022 as ADB and the integrated installer.
alert '패키지를 설치하는 중입니다. 1분 정도 걸립니다. USB를 빼지 마세요.'
if [ "$update" = 1 ]; then
    (umask 022; exec "$NEM" install "$STAGE" --update) > "$REPORT/nemesis-install.txt" 2>&1; rc=$?
else
    (umask 022; exec "$NEM" install "$STAGE") > "$REPORT/nemesis-install.txt" 2>&1; rc=$?
fi
say "nemesis install rc=$rc"
if [ "$rc" = 5 ] && [ "$update" = 1 ] && grep -q 'old version could not be removed' "$REPORT/nemesis-install.txt"; then
    # Never armed in this or a later boot (checked above): remove it plainly and
    # install fresh. Uninstall does not depend on the old hook succeeding.
    alert '이전 범용판을 지우고 다시 설치합니다. USB를 빼지 마세요.'
    (umask 022; exec "$NEM" uninstall gen5w.kr.portable) > "$REPORT/nemesis-uninstall.txt" 2>&1; urc=$?
    say "nemesis uninstall rc=$urc"
    if [ "$urc" = 0 ] && [ ! -e "$APP" ]; then
        (umask 022; exec "$NEM" install "$STAGE") > "$REPORT/nemesis-install-2.txt" 2>&1; rc=$?
        say "nemesis fresh install rc=$rc"
    fi
fi
rm -f "$STAGE"; sync
if [ "$rc" != 0 ]; then
    # NEMESIS keeps the package registered when only its postinstall hook fails.
    if [ -f "$APP/NEMESIS.data" ]; then
        "$SH" "$APP/boot.sh" status > "$REPORT/status.txt" 2>&1 ||
            finish failed "NEMESIS 설치가 실패했고(rc=$rc) 현재 자동 적용 상태를 읽지 못했습니다. 재시동하지 말고 보고서를 PC로 가져오세요."
        grep -qx 'enabled|1' "$REPORT/status.txt" &&
            finish failed "설치 마무리가 실패했는데(rc=$rc) 자동 적용이 켜져 있습니다. 재시동하지 말고 보고서를 PC로 가져오세요."
        finish failed "범용판 등록이 남아 있지만 자동 적용은 켜지지 않았습니다(rc=$rc). 설치 상태를 확인해야 합니다. 보고서를 PC로 가져오세요."
    fi
    finish failed "NEMESIS 설치가 거부/실패했습니다(rc=$rc). 설치 상태를 확인해야 합니다. 보고서를 PC로 가져오세요."
fi
"$SH" "$APP/boot.sh" status > "$REPORT/status.txt" 2>&1
grep -qx 'enabled|1' "$REPORT/status.txt" && grep -qx 'mode|auto' "$REPORT/status.txt" ||
    finish failed '설치는 됐지만 자동 적용 준비 상태가 확인되지 않습니다. 재시동하지 말고 보고서를 PC로 가져오세요.'
# Read-only stock baseline for a later restore comparison (never overwritten).
if [ ! -e "$ROOT/data/g5p-before" ]; then
    "$SH" "$APP/check.sh" snapshot /data/g5p-before > "$REPORT/baseline.txt" 2>&1 || say 'baseline snapshot failed (non-fatal)'
fi
finish ok '설치 완료. 지금 이 부팅에는 아직 적용되지 않았습니다. USB를 빼고 시동을 완전히 끈 뒤(콜드 재시작) 다시 켜면 무선 CarPlay 자동 적용이 시작됩니다.'
