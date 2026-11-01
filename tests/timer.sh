#!/bin/bash
# Consent timer service: follows the stock SystemUI log and closes only when the stock timer would.
set -u
. "$(dirname "$0")/lib.sh" 2>/dev/null || true
ROOT=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
check() { local name=$1; shift; if "$@"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $name"; fi; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
PKG=$W/pkg; mkdir -p "$PKG/bin" "$W/sys/priv-app"
cp -r "$ROOT/packages/consent-timer/scripts" "$ROOT/packages/consent-timer/NEMESIS.data" "$PKG/"
printf '#!/bin/sh\n[ "$1" = original ] && grep -qx stock "$2"\n' > "$PKG/bin/notice-patch-v039"
echo stock > "$W/sys/priv-app/SystemUI.odex"
cat > "$W/am" <<'A'
#!/bin/sh
echo "$*" >> "$TIMER_AM_LOG"
A
chmod 755 "$W/am"
OK='D/ConsentScreen(  1): mScreenEnabled : true, mIsEarlyCamOn : false, mIsReverseOn : false, mIsPowerOn : true, mIsCalling : false, mIsBtCalling : false, mAccStatus : 0, mShowLocaleDialog : false, mIsUpdateCompleteViewOn : false mIsValet : false, mIsEmergency : false, mInitDriverIdx : 0, mIsDipoCalling : false'
# Feed lines with gaps; $1.. are "line|seconds-before-next".
feed() {
    printf '#!/bin/bash\n' > "$W/logcat"
    for item in "$@"; do printf 'echo %q; sleep %s\n' "${item%|*}" "${item##*|}" >> "$W/logcat"; done
    chmod 755 "$W/logcat"
}
run() {
    rm -rf "$PKG/run"; : > "$W/am.log"
    TIMER_TEST_SYS=$W/sys TIMER_TEST_DELAY=1 TIMER_TEST_LOGCAT=$W/logcat TIMER_TEST_AM=$W/am \
    TIMER_TEST_ONCE=1 TIMER_AM_LOG=$W/am.log mksh "$PKG/scripts/timer.sh" >/dev/null 2>&1
}
closed() { grep -q CLOSE_CONSENTSCREEN_FORCE "$W/am.log"; }

feed "$OK|2"; run
check 'passing stock check closes after the short delay' closed
feed "$OK|0" 'D/ConsentScreen(  1): ConsentScreenTimeout is not executed because it shouldn'"'"'t be closed yet|2'; run
check 'stock failure line cancels' eval '! closed'
feed "${OK/mIsReverseOn : false/mIsReverseOn : true}|2"; run
check 'reverse gear never arms' eval '! closed'
feed "${OK/mAccStatus : 0,/mAccStatus : 10,}|2"; run
check 'non-zero ACC status never arms' eval '! closed'
feed "${OK/mIsPowerOn : true/mIsPowerOn : false}|2"; run
check 'power off without call never arms' eval '! closed'
DIPO=${OK/mIsPowerOn : true/mIsPowerOn : false}; feed "${DIPO/mIsDipoCalling : false/mIsDipoCalling : true}|2"; run
check 'CarPlay call with power off arms like stock' closed
feed "$OK|0.3" 'D/ConsentScreen(  1): Locale Setting Button pressed or refresh dialog|2'; run
check 'language button cancels' eval '! closed'
feed "${OK/mInitDriverIdx : 0,/mInitDriverIdx : -1,}|2"; run
check 'no driver profile chosen never arms' eval '! closed'
feed "$OK|0.3" 'D/ConsentScreen(  1): confirm() : ConsentScreen is going to close|2'; run
check 'user agree before the delay sends nothing' eval '! closed'
feed "$OK|0.6" "$OK|0.6" "$OK|2"; run
check 're-armed state lines close once' test "$(grep -c CLOSE "$W/am.log")" = 1
feed 'D/ConsentScreen(  1): mScreenEnabled : true, garbled|2'; run
check 'unknown log format keeps the stock timer' eval '! closed'
echo patched > "$W/sys/priv-app/SystemUI.odex"; feed "$OK|2"; run
check 'non-stock SystemUI keeps the stock timer' eval '! closed'
check 'preinstall refuses non-stock SystemUI' eval '! TIMER_TEST_SYS=$W/sys mksh "$PKG/scripts/pre.sh" >/dev/null'
echo stock > "$W/sys/priv-app/SystemUI.odex"
check 'preinstall accepts stock SystemUI' eval 'TIMER_TEST_SYS=$W/sys mksh "$PKG/scripts/pre.sh" >/dev/null'
check 'no system file changed' grep -qx stock "$W/sys/priv-app/SystemUI.odex"
# Default: close right when the button activates (no added wait).
feed "$OK|0"; rm -rf "$PKG/run"; : > "$W/am.log"
TIMER_TEST_SYS=$W/sys TIMER_TEST_LOGCAT=$W/logcat TIMER_TEST_AM=$W/am TIMER_TEST_ONCE=1 TIMER_AM_LOG=$W/am.log mksh "$PKG/scripts/timer.sh" >/dev/null 2>&1
check 'default closes immediately on a passing state line' closed
feed "${OK/mIsReverseOn : false/mIsReverseOn : true}|0"; rm -rf "$PKG/run"; : > "$W/am.log"
TIMER_TEST_SYS=$W/sys TIMER_TEST_LOGCAT=$W/logcat TIMER_TEST_AM=$W/am TIMER_TEST_ONCE=1 TIMER_AM_LOG=$W/am.log mksh "$PKG/scripts/timer.sh" >/dev/null 2>&1
check 'default never closes while reversing' eval '! closed'
echo "== timer: $pass passed, $fail failed"
[ "$fail" = 0 ]
