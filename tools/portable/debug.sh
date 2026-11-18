#!/system/bin/sh
# Explicit debug capture. Own property values are restored when switched off.
umask 077
BASE=${0%/*}
ROOT=${PORTABLE_TEST_ROOT:-}
ADAPTER=${PORTABLE_TEST_DEBUG_ADAPTER:-}
plain() {
    case "$1" in /*) :;; *) return 1;; esac
    case "$1" in *[!a-zA-Z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac
    local p=$1
    while [ "$p" != / ]; do [ ! -L "$p" ] || return 1; p=${p%/*}; [ -n "$p" ] || p=/; done
}
if [ -n "$ROOT" ]; then
    plain "$ROOT" && [ "$ROOT" != / ] && [ -x "$ADAPTER" ] || exit 1
else
    [ -z "$ADAPTER" ] || exit 1
    case "$(id)" in uid=0\(*) :;; *) exit 1;; esac
fi
STATE=$ROOT/data/local/gen5w-portable/debug
FLAG=$ROOT/data/nemesis/gen5wkr.debug-on
plain "$STATE" && plain "$FLAG" || exit 1
mkdir -p "$STATE" && chmod 700 "$STATE" || exit 1
process_key() {
    local pid=$1 line rest count=0
    case "$pid" in ''|*[!0-9]*) return 1;; esac
    IFS= read -r line < "/proc/$pid/stat" || return 1
    rest=${line##*) }; [ "$rest" != "$line" ] || return 1
    set -- $rest; [ "$#" -ge 20 ] || return 1
    case "$1" in Z|X|x) return 1;; esac
    while [ "$count" -lt 19 ]; do shift; count=$((count+1)); done
    echo "$pid:$1"
}
identity=$(process_key $$) || exit 1
SHELL=/system/bin/sh
[ -z "$ROOT" ] || SHELL=$(command -v mksh)
locked() {
    local name=$1 tries=0 rc; shift
    plain "$STATE/$name.lock" || return 1
    while :; do
        "$BASE/bin/dex-patch" lock-run "$STATE/$name.lock" "$SHELL" "$0" "$@"; rc=$?
        [ "$rc" = 75 ] || return "$rc"
        tries=$((tries+1)); [ "$tries" -lt 8 ] || return 1
        sleep 1
    done
}
op() {
    if [ -n "$ROOT" ]; then "$ADAPTER" "$@"; return $?; fi
    case "$1" in get) getprop "$2";; set) setprop "$2" "$3";; *) return 1;; esac
}
property_transaction() {
    local action=$1 key wanted before saved current result=0
    while IFS='|' read -r key wanted; do
        saved=$STATE/before.$key
        plain "$saved" && { [ ! -e "$saved" ] || [ -f "$saved" ]; } || return 1
        current=$(op get "$key") || { result=1; continue; }
        if [ "$action" = on ]; then
            if [ ! -e "$saved" ]; then
                local staged=$saved.tmp.${identity%:*}.${identity#*:}
                plain "$staged" || return 1
                print -r -- "$current" > "$staged" && sync && mv "$staged" "$saved" && sync || return 1
            fi
            [ "$current" = "$wanted" ] || op set "$key" "$wanted" || result=1
        elif [ -f "$saved" ]; then
            IFS= read -r before < "$saved" || before=
            if [ "$current" = "$wanted" ]; then
                op set "$key" "$before" || { result=1; continue; }
            fi
            # A foreign change wins. Never restore over another owner's value.
            rm -f "$saved" || result=1
        fi
    done <<'PROPERTIES'
persist.iap2.debug.service|t
persist.iap2.debug.svc.data|t
log.tag.CarPlay_|V
log.tag.Iap2Service|V
log.tag.Gen5wCore|V
log.tag.Gen5wNavi|V
log.tag.SplitScreen|V
log.tag.AudioFlinger|V
log.tag.AudioPolicyManager|V
log.tag.BluetoothA2dp|V
PROPERTIES
    return "$result"
}
properties() { locked properties properties-$1; }
capture() {
    if [ -n "$ROOT" ]; then exec "$ADAPTER" capture "$STATE/logcat.log"; fi
    exec "$BASE/bin/dex-patch" supervise 180 /system/bin/true /system/bin/logcat -v time -b main -b system -f "$STATE/logcat.log" -r 4096 -n 3 '*:V'
}
case "${1:-run}" in
properties-on) property_transaction on;;
properties-off) property_transaction off;;
on)
    [ ! -e "$FLAG" ] || [ -f "$FLAG" ] || exit 1
    : > "$FLAG" && chmod 644 "$FLAG" || exit 1
    properties on;;
off)
    [ ! -e "$FLAG" ] || [ -f "$FLAG" ] || exit 1
    rm -f "$FLAG" && properties off;;
run)
    plain "$STATE/worker.lock" || exit 1
    exec "$BASE/bin/dex-patch" lock-wait "$STATE/worker.lock" "$SHELL" "$0" worker;;
worker)
    child=
    if plain "$STATE/capture" && [ -f "$STATE/capture" ]; then
        previous=$(cat "$STATE/capture")
        if [ "$(process_key "${previous%%:*}" 2>/dev/null)" = "$previous" ]; then kill "${previous%%:*}" 2>/dev/null; fi
        rm -f "$STATE/capture"
    fi
    cleanup() {
        if [ -n "$child" ]; then kill "$child" 2>/dev/null; wait "$child" 2>/dev/null; child=; fi
        properties off
    }
    trap cleanup EXIT
    trap 'exit 0' HUP INT TERM
    while :; do
        if plain "$FLAG" && [ -f "$FLAG" ]; then
            properties on || echo 'debug: some requested log levels unavailable' >&2
            for file in "$STATE"/logcat.log*; do
                [ -e "$file" ] || [ -L "$file" ] || continue
                plain "$file" || exit 1
            done
            # Four files of 4 MiB: full main/system rings, including OEM traces.
            capture 9>&- & child=$!
            process_key "$child" > "$STATE/capture.tmp" && mv "$STATE/capture.tmp" "$STATE/capture"
            while plain "$FLAG" && [ -f "$FLAG" ] && kill -0 "$child" 2>/dev/null; do sleep 2 9>&-; done
            cleanup
        fi
        sleep 2 9>&-
    done;;
*) exit 2;;
esac
