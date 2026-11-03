#!/system/bin/sh
# Closes the stock start-up warning as soon as its confirm button becomes
# active (instead of the stock 10 seconds), without changing SystemUI.
# SystemUI enables the screen and button in enableScreen(), which ends by
# running its timer check; that check writes the state line below. SystemUI logs its own timer decision (Slog, system buffer):
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
DELAY=${TIMER_TEST_DELAY:-0}
LOGCAT=${TIMER_TEST_LOGCAT:-logcat}
AM=${TIMER_TEST_AM:-am}
GETPROP=${TIMER_TEST_GETPROP:-getprop}
RUN=$PKG/run
GEN=$RUN/generation
stock_systemui || { log 'timer: SystemUI.odex is not a recognised stock file; stock 10 second timer kept'; exit 0; }
[ ! -L "$RUN" ] || exit 1
mkdir -p "$RUN" || exit 1
log 'timer: started, listening for ConsentScreen state'
# Each event takes the next number; a pending close fires only if no event followed it.
bump() {
    gen=$(cat "$GEN" 2>/dev/null)
    case "$gen" in ''|*[!0-9]*) gen=0;; esac
    gen=$((gen + 1)); echo "$gen" > "$GEN"
}
# The same conditions as SystemUI's own check, read from its state line.
passes() {
    local field profile
    case "$1" in *'mScreenEnabled : true,'*) ;; *) return 1;; esac
    for field in 'mIsEarlyCamOn : false,' 'mIsReverseOn : false,' 'mAccStatus : 0,' \
        'mShowLocaleDialog : false,' 'mIsUpdateCompleteViewOn : false ' 'mIsValet : false,'; do
        case "$1" in *"$field"*) ;; *) return 1;; esac
    done
    case "$1" in
        *'mIsPowerOn : true,'*|*'mIsCalling : true,'*|*'mIsBtCalling : true,'*|\
        *'mIsEmergency : true,'*|*'mIsDipoCalling : true'*) ;;
        *) return 1;;
    esac
    # SystemUI also refuses while no driver profile is chosen (index -1) on units
    # with user profiles. Its failure line comes after the state line, too late
    # for an immediate close, so refuse here on -1 regardless.
    case "$1" in *'mInitDriverIdx : '*) ;; *) return 1;; esac
    profile=${1#*'mInitDriverIdx : '}
    case "$profile" in *,*) profile=${profile%%,*};; *) return 1;; esac
    case "$profile" in ''|*[!0-9]*) return 1;; esac
    return 0
}
# Fixed reason labels only; do not retain the SystemUI state line.
reject_reason() {
    case "$1" in *'mScreenEnabled : true,'*) ;; *) echo screen; return;; esac
    case "$1" in *'mIsEarlyCamOn : false,'*) ;; *) echo camera; return;; esac
    case "$1" in *'mIsReverseOn : false,'*) ;; *) echo reverse; return;; esac
    case "$1" in *'mAccStatus : 0,'*) ;; *) echo accessory; return;; esac
    case "$1" in *'mShowLocaleDialog : false,'*) ;; *) echo locale; return;; esac
    case "$1" in *'mIsUpdateCompleteViewOn : false '*) ;; *) echo update; return;; esac
    case "$1" in *'mIsValet : false,'*) ;; *) echo valet; return;; esac
    case "$1" in *'mIsPowerOn : true,'*|*'mIsCalling : true,'*|*'mIsBtCalling : true,'*|*'mIsEmergency : true,'*|*'mIsDipoCalling : true'*) ;; *) echo power; return;; esac
    echo profile
}
# Android refuses broadcasts before boot completes ("Cannot broadcast before
# boot completed"), and a cold start can show the screen that early. Wait up
# to 30 s for boot, then send only if no event came in meanwhile.
booted() { [ "$("$GETPROP" sys.boot_completed 2>/dev/null)" = 1 ]; }
arm() {
    bump
    if ! booted; then
        (
            mine=$gen; n=0
            while ! booted; do
                n=$((n + 1)); [ "$n" -le "${TIMER_BOOT_WAIT:-30}" ] || exit 0
                sleep 1
            done
            sleep "$DELAY"
            [ "$(cat "$GEN" 2>/dev/null)" = "$mine" ] || exit 0
            log 'timer: sending close request after boot'
            "$AM" broadcast -a com.hkmc.intent.action.CLOSE_CONSENTSCREEN_FORCE >/dev/null 2>&1
        ) &
        return
    fi
    if [ "$DELAY" = 0 ]; then
        log 'timer: sending close request'
        "$AM" broadcast -a com.hkmc.intent.action.CLOSE_CONSENTSCREEN_FORCE >/dev/null 2>&1
        return
    fi
    (
        mine=$gen
        sleep "$DELAY"
        [ "$(cat "$GEN" 2>/dev/null)" = "$mine" ] || exit 0
        log 'timer: sending delayed close request'
        "$AM" broadcast -a com.hkmc.intent.action.CLOSE_CONSENTSCREEN_FORCE >/dev/null 2>&1
    ) &
}
# logcat has no -T on this unit, so a restarted logcat replays the whole buffer.
# Lines carry their time (-v time: "MM-DD HH:MM:SS.mmm ..."); after a restart we
# skip every line not newer than the last one already handled, so an old state
# line can never close a screen that the current state would keep open. If the
# clock moves back we only miss an early close; the stock timer still applies.
LAST=$RUN/last
passes=0
rm -f "$LAST"
newer() {
    local d t rest last
    case "$1" in [0-9][0-9]-[0-9][0-9]' '[0-9][0-9]:*) ;; *) return 0;; esac
    d=${1%% *}; rest=${1#* }; t=${rest%% *}
    last=$(cat "$LAST" 2>/dev/null)
    [ -z "$last" ] || [[ "$d $t" > "$last" ]] || return 1
    echo "$d $t" > "$LAST"
}
while :; do
    bump
    "$LOGCAT" -b system -v time -s ConsentScreen:V 2>/dev/null | { last_decision=; while IFS= read -r line; do
        newer "$line" || continue
        case "$line" in
            *'mScreenEnabled : '*)
                if passes "$line"; then
                    [ "$last_decision" = accepted ] || log 'timer: state accepted'
                    last_decision=accepted; arm
                else
                    reason=$(reject_reason "$line")
                    [ "$last_decision" = "rejected:$reason" ] || log "timer: state rejected reason=$reason"
                    last_decision="rejected:$reason"; bump
                fi;;
            *'ConsentScreenTimeout is not executed'*|*'Locale Setting Button pressed'*|\
            *'confirm() : ConsentScreen is going to close'*|*'handleMessage : MSG_CLOSE_CONSENT'*|\
            *'Not auto-close specification'*|*'ConsentScreen is null'*) bump;;
        esac
    done; }
    passes=$((passes + 1))
    [ -z "$TIMER_TEST_ONCE" ] || [ "$passes" -lt "$TIMER_TEST_ONCE" ] || { wait; exit 0; }
    sleep "${TIMER_TEST_PAUSE:-5}"
done
