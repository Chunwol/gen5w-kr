#!/system/bin/sh
# Background work yields the CPU to Android (zygote, system_server, stock apps);
# children inherit it. VM 2026-11-21: polling at normal priority starved a stock
# provider until the system_server watchdog reset the unit.
renice 10 $$ >/dev/null 2>&1
# Explicit debug capture. Own property values are restored when switched off.
umask 077
BASE=$(CDPATH= cd -- "${0%/*}" && pwd) || exit 1
ROOT=${PORTABLE_TEST_ROOT:-}
ADAPTER=${PORTABLE_TEST_DEBUG_ADAPTER:-}
TRUE_BIN=/system/bin/true
[ -z "$ROOT" ] || TRUE_BIN=/bin/true
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
persist.iap2.debug.svc.data|f
debug.gen5wkr.trace|1
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
    if [ -n "$ROOT" ]; then
        exec "$BASE/bin/dex-patch" supervise 180 "$TRUE_BIN" "$BASE/bin/dex-patch" lock-run "$STATE/logcat-writer.lock" "$ADAPTER" capture "$STATE/logcat.log"
    fi
    # High-rate map rendering chatter otherwise rotates away the connection
    # handshake before a failed session can be exported. Keep navigation
    # cluster, projection, audio and Bluetooth tags at their original levels.
    exec "$BASE/bin/dex-patch" supervise 180 "$TRUE_BIN" "$BASE/bin/dex-patch" lock-run "$STATE/logcat-writer.lock" /system/bin/logcat -v time -b main -b system -f "$STATE/logcat.log" -r 4096 -n 3 'CoNA:S' 'ExSL:S' 'ExFW:S' 'NavigationCluster:S' 'ClusterService:S' 'MicomD:S' 'SplitScreenViewHev:S' 'CompassLogRightSideScreen:S' 'TCC317X_WRAPPER:S' 'JNI_Layer:S' 'Java_Layer:S' 'Navi:S' 'GKI_LINUX:S' 'Iap2SendNotiThread:W' '*:V'
}
capture_focus() {
    if [ -n "$ROOT" ]; then
        exec "$BASE/bin/dex-patch" supervise 180 "$TRUE_BIN" "$BASE/bin/dex-patch" lock-run "$STATE/focus-writer.lock" "$ADAPTER" capture "$STATE/focus.log"
    fi
    exec "$BASE/bin/dex-patch" supervise 180 "$TRUE_BIN" "$BASE/bin/dex-patch" lock-run "$STATE/focus-writer.lock" /system/bin/logcat -v time -b main -b system -f "$STATE/focus.log" -r 1024 -n 3 '*:S' 'TccCarPlay:V' 'TccCarPlay_iAP:V' 'CarPlay_:V' 'CarPlayService:V' 'Iap2Service:V' 'iAP2:V' 'IAP2:V' 'Gen5wWireless:V' 'Gen5wDrive:V' 'Gen5wCore:V' 'Gen5wNavi:V' 'Gen5wTrace:V' 'Gen5wDiag:V' 'System.err:W' 'AudioFlinger:V' 'AudioPolicyManager:V' 'audio_a2dp_hw:V' 'audio_hw_primary:V' 'audio_hw_fm1288:V' 'AudioManager:V' 'AudioSystem:V' 'AudioServiceHelper:V' 'MicomAudioManager:V' 'MediaFocusControl:V' 'BTCMStateMachine:V' 'BluetoothRemoteDevices:V' 'SplitScreen:I' 'PhoneProjection:I'
}
case "${1:-run}" in
properties-on) property_transaction on;;
properties-off) property_transaction off;;
on)
    [ ! -e "$FLAG" ] || [ -f "$FLAG" ] || exit 1
    if [ ! -e "$FLAG" ]; then
        plain "$STATE/focus-reset" && { [ ! -e "$STATE/focus-reset" ] || [ -f "$STATE/focus-reset" ]; } && : > "$STATE/focus-reset" || exit 1
    fi
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
    focus_child=
    clear_focus_session() {
        local file
        for file in "$STATE"/focus-first.log* "$STATE"/focus.log*; do
            [ -e "$file" ] || [ -L "$file" ] || continue
            plain "$file" || return 1
            rm -f "$file" || return 1
        done
        return 0
    }
    wait_writer_stopped() {
        local lock=$1
        plain "$lock" || return 1
        "$BASE/bin/dex-patch" lock-wait "$lock" "$SHELL" -c : 9>&- >/dev/null 2>&1
    }
    for capfile in "$STATE/capture" "$STATE/capture-focus"; do
        if plain "$capfile" && [ -f "$capfile" ]; then
            previous=$(cat "$capfile")
            if [ "$(process_key "${previous%%:*}" 2>/dev/null)" = "$previous" ]; then kill "${previous%%:*}" 2>/dev/null; fi
            rm -f "$capfile"
        fi
    done
    wait_writer_stopped "$STATE/logcat-writer.lock" || exit 1
    wait_writer_stopped "$STATE/focus-writer.lock" || exit 1
    if [ -r "$ROOT/proc/sys/kernel/random/boot_id" ] && plain "$STATE/boot-id"; then
        current_boot=$(cat "$ROOT/proc/sys/kernel/random/boot_id" 2>/dev/null)
        previous_boot=
        [ ! -f "$STATE/boot-id" ] || IFS= read -r previous_boot < "$STATE/boot-id" 2>/dev/null
        if [ -n "$current_boot" ] && [ "$current_boot" != "$previous_boot" ]; then
            clear_focus_session || exit 1
            boot_tmp="$STATE/boot-id.tmp.${identity%:*}.${identity#*:}"
            plain "$boot_tmp" && print -r -- "$current_boot" > "$boot_tmp" && mv "$boot_tmp" "$STATE/boot-id" || exit 1
        fi
    fi
    ensure_focus_reset() {
        [ ! -L "$STATE/focus-reset" ] && plain "$STATE/focus-reset" || return 1
        [ -e "$STATE/focus-reset" ] || : > "$STATE/focus-reset"
    }
    stop_captures() {
        if [ -n "$child" ]; then kill "$child" 2>/dev/null; wait "$child" 2>/dev/null; child=; fi
        if [ -n "$focus_child" ]; then kill "$focus_child" 2>/dev/null; wait "$focus_child" 2>/dev/null; focus_child=; fi
        wait_writer_stopped "$STATE/logcat-writer.lock" || return 1
        wait_writer_stopped "$STATE/focus-writer.lock" || return 1
    }
    latch_first_focus() {
        plain "$STATE/focus-first.log" || return 1
        [ ! -e "$STATE/focus-first.log" ] || return 0
        local any=0 part tmp="$STATE/focus-first.log.tmp.${identity%:*}.${identity#*:}"
        plain "$tmp" || return 1
        for part in "$STATE/focus.log.3" "$STATE/focus.log.2" "$STATE/focus.log.1" "$STATE/focus.log"; do
            [ -f "$part" ] && plain "$part" && [ -s "$part" ] && { any=1; break; }
        done
        [ "$any" = 1 ] || return 0
        : > "$tmp" || return 1
        for part in "$STATE/focus.log.3" "$STATE/focus.log.2" "$STATE/focus.log.1" "$STATE/focus.log"; do
            [ -f "$part" ] && plain "$part" && [ -s "$part" ] || continue
            cat "$part" >> "$tmp" 2>/dev/null || :
        done
        dd if="$tmp" of="$STATE/focus-first.log" bs=4096 count=1024 2>/dev/null || :
        rm -f "$tmp"
    }
    cleanup() {
        local rc=0
        stop_captures || rc=$?
        properties off || rc=1
        return "$rc"
    }
    trap cleanup EXIT
    trap 'exit 0' HUP INT TERM
    while :; do
        if plain "$FLAG" && [ -f "$FLAG" ]; then
            properties on || echo 'debug: some requested log levels unavailable' >&2
            if [ -e "$STATE/focus-reset" ] || [ -L "$STATE/focus-reset" ]; then
                plain "$STATE/focus-reset" && [ -f "$STATE/focus-reset" ] || exit 1
                clear_focus_session || exit 1
                rm -f "$STATE/focus-reset" || exit 1
            fi
            for file in "$STATE"/logcat.log* "$STATE"/focus.log* "$STATE"/focus-first.log; do
                [ -e "$file" ] || [ -L "$file" ] || continue
                plain "$file" || exit 1
            done
            # Four files of 4 MiB: full main/system rings; four files of 1 MiB: CarPlay/iAP2/Audio/BT focus.
            capture 9>&- & child=$!
            process_key "$child" > "$STATE/capture.tmp" && mv "$STATE/capture.tmp" "$STATE/capture"
            capture_focus 9>&- & focus_child=$!
            process_key "$focus_child" > "$STATE/capture-focus.tmp" && mv "$STATE/capture-focus.tmp" "$STATE/capture-focus"
            while plain "$FLAG" && [ -f "$FLAG" ] && [ ! -e "$STATE/focus-reset" ] && [ ! -L "$STATE/focus-reset" ] && kill -0 "$child" 2>/dev/null && kill -0 "$focus_child" 2>/dev/null; do
                if [ ! -e "$STATE/focus-first.log" ] && [ -e "$STATE/focus.log.2" ]; then
                    # Stop supervisor and block on focus-writer.lock until rescue kills logcat.
                    if [ -n "$focus_child" ]; then kill "$focus_child" 2>/dev/null; wait "$focus_child" 2>/dev/null; focus_child=; fi
                    if wait_writer_stopped "$STATE/focus-writer.lock"; then
                        latch_first_focus
                    fi
                    break
                fi
                sleep 2 9>&-
            done
            if stop_captures; then
                [ -e "$STATE/focus-reset" ] || [ -L "$STATE/focus-reset" ] || latch_first_focus
            else
                echo 'debug: capture writer failed to stop; halting worker without restart' >&2
                exit 1
            fi
            if ! plain "$FLAG" || [ ! -f "$FLAG" ]; then
                ensure_focus_reset || exit 1
                properties off
                sleep 2 9>&-
            fi
        else
            ensure_focus_reset || exit 1
            sleep 2 9>&-
        fi
    done;;
*) exit 2;;
esac
