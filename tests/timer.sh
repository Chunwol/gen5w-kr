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
printf '#!/bin/sh\n[ "$1" = verify ] && grep -qx stock "$2" && [ "$3" = 97e7e258df34d76ed61a714f83de4bf0fbc3d6b6188055c941ad2689f72595af ]\n' > "$PKG/bin/sha256-check"
echo stock > "$W/sys/priv-app/SystemUI.odex"
cat > "$W/am" <<'A'
#!/bin/sh
echo "$*" >> "$TIMER_AM_LOG"
A
chmod 755 "$W/am"
# Boot state: $W/booted holds sys.boot_completed (1 unless a test changes it).
echo 1 > "$W/booted"
printf '#!/bin/sh
cat "%s/booted"
' "$W" > "$W/getprop"; chmod 755 "$W/getprop"
export TIMER_TEST_GETPROP=$W/getprop TIMER_BOOT_WAIT=3
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
    TIMER_TEST_ONCE=1 TIMER_AM_LOG=$W/am.log mksh "$PKG/scripts/timer.sh" > "$W/timer.log" 2>&1
}
closed() { grep -q CLOSE_CONSENTSCREEN_FORCE "$W/am.log"; }

feed "$OK|2"; run
check 'passing stock check closes after the short delay' closed
check 'timer logs startup and accepted state' eval 'grep -q "timer: started" "$W/timer.log" && grep -q "timer: state accepted" "$W/timer.log"'
check 'timer logs close request' grep -q 'timer: sending delayed close request' "$W/timer.log"
feed "$OK|0" 'D/ConsentScreen(  1): ConsentScreenTimeout is not executed because it shouldn'"'"'t be closed yet|2'; run
check 'stock failure line cancels' eval '! closed'
feed "${OK/mIsReverseOn : false/mIsReverseOn : true}|2"; run
check 'reverse gear never arms' eval '! closed'
check 'unsafe state is logged without the state contents' eval 'grep -q "timer: state rejected reason=reverse" "$W/timer.log" && ! grep -q "mIsReverseOn" "$W/timer.log"'
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
feed "${OK/mInitDriverIdx : 0, /}|2"; run
check 'missing driver profile never arms' eval '! closed'
feed "${OK/mIsReverseOn : false/mIsReverseOn : true}|0.2" "$OK|2"; run
check 'safe state after reverse arms again' closed
feed "${OK/mIsValet : false/mIsValet : true}|0.2" "$OK|2"; run
check 'safe state after valet arms again' closed
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
# A restarted logcat replays its buffer: an old passing line must not close again.
cat > "$W/logcat" <<'L'
#!/bin/bash
n=$(cat "$TIMER_CALLS" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$TIMER_CALLS"
echo "01-01 00:00:01.000 $OK"
[ "$n" = 1 ] || echo "01-01 00:00:09.000 ${OK/mIsReverseOn : false/mIsReverseOn : true}"
L
chmod 755 "$W/logcat"; rm -rf "$PKG/run"; : > "$W/am.log"; rm -f "$W/calls"
OK=$OK TIMER_CALLS=$W/calls TIMER_TEST_SYS=$W/sys TIMER_TEST_LOGCAT=$W/logcat TIMER_TEST_AM=$W/am TIMER_TEST_ONCE=2 TIMER_TEST_PAUSE=0 TIMER_AM_LOG=$W/am.log mksh "$PKG/scripts/timer.sh" >/dev/null 2>&1
check 'restarted logcat does not replay an old close' test "$(grep -c CLOSE "$W/am.log")" = 1
check 'restarted logcat ran twice' test "$(cat "$W/calls")" = 2
# Cold start: the screen can come up before Android allows broadcasts.
echo 0 > "$W/booted"; feed "$OK|4"; ( sleep 1; echo 1 > "$W/booted" ) & run; wait
check 'early screen closes once boot completes' closed
echo 0 > "$W/booted"; feed "$OK|5"; run
check 'boot never completing sends nothing' eval '! closed'
echo 0 > "$W/booted"; feed "$OK|0.5" 'D/ConsentScreen(  1): Locale Setting Button pressed or refresh dialog|4'; ( sleep 1.5; echo 1 > "$W/booted" ) & run; wait
check 'event while waiting for boot cancels' eval '! closed'
echo 1 > "$W/booted"
echo "== timer: $pass passed, $fail failed"
[ "$fail" = 0 ]
