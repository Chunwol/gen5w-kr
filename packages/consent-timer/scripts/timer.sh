#!/system/bin/sh
# Closes the stock start-up warning after 3 seconds instead of 10, without
# changing SystemUI. SystemUI logs its own timer decision (Slog, system buffer):
#   "mScreenEnabled : ..."   state line, written each time it (re)arms the timer
#   "ConsentScreenTimeout is not executed ..."   the check failed, timer cancelled
#   "Locale Setting Button pressed ..."          timer cancelled
#   "confirm() : ConsentScreen is going to close"  closed
# We arm only when the state line passes the same check SystemUI uses and no
# failure line follows, cancel on everything that cancels the stock timer, and
# then send the stock close request, which runs the same confirm() as the stock
# timer. If we miss anything, the stock 10 second timer still applies.
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
DELAY=${TIMER_TEST_DELAY:-3}
LOGCAT=${TIMER_TEST_LOGCAT:-logcat}
AM=${TIMER_TEST_AM:-am}
RUN=$PKG/run
GEN=$RUN/generation
stock_systemui || { log 'timer: SystemUI.odex is not a recognised stock file; stock 10 second timer kept'; exit 0; }
[ ! -L "$RUN" ] || exit 1
mkdir -p "$RUN" || exit 1
# Each event takes the next number; a pending close fires only if no event followed it.
bump() {
    gen=$(cat "$GEN" 2>/dev/null)
    case "$gen" in ''|*[!0-9]*) gen=0;; esac
    gen=$((gen + 1)); echo "$gen" > "$GEN"
}
# The same conditions as SystemUI's own check, read from its state line.
passes() {
    local field
    case "$1" in *'mScreenEnabled : true,'*) ;; *) return 1;; esac
    for field in 'mIsEarlyCamOn : false,' 'mIsReverseOn : false,' 'mAccStatus : 0,' \
        'mShowLocaleDialog : false,' 'mIsUpdateCompleteViewOn : false ' 'mIsValet : false,'; do
        case "$1" in *"$field"*) ;; *) return 1;; esac
    done
    case "$1" in
        *'mIsPowerOn : true,'*|*'mIsCalling : true,'*|*'mIsBtCalling : true,'*|\
        *'mIsEmergency : true,'*|*'mIsDipoCalling : true'*) return 0;;
    esac
    return 1
}
arm() {
    bump
    (
        mine=$gen
        sleep "$DELAY"
        [ "$(cat "$GEN" 2>/dev/null)" = "$mine" ] || exit 0
        "$AM" broadcast -a com.hkmc.intent.action.CLOSE_CONSENTSCREEN_FORCE >/dev/null 2>&1
    ) &
}
while :; do
    bump
    "$LOGCAT" -b system -v brief -s ConsentScreen:V 2>/dev/null | while IFS= read -r line; do
        case "$line" in
            *'mScreenEnabled : '*) if passes "$line"; then arm; else bump; fi;;
            *'ConsentScreenTimeout is not executed'*|*'Locale Setting Button pressed'*|\
            *'confirm() : ConsentScreen is going to close'*|*'handleMessage : MSG_CLOSE_CONSENT'*|\
            *'Not auto-close specification'*|*'ConsentScreen is null'*) bump;;
        esac
    done
    [ -z "$TIMER_TEST_ONCE" ] || { wait; exit 0; }
    sleep 5
done
