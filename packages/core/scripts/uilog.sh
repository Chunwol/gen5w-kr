#!/system/bin/sh
# Collects bounded, privacy-filtered copies of every gen5w package log for the in-car screen.
# Runs as root next to the HUD service, separate from the wireless supervisor. The screen
# only reads the two files written here. Every size is capped, and a failure only skips
# one round: the loop keeps going and never touches anything outside UI_DIR.
# UI_DIR is a root-owned folder under /data/nemesis. Root never writes into the app's own
# data folder: the app owns that folder and could swap a path for a link between our check
# and our write.
DATA=${UILOG_TEST_DATA:-/data}
NEMDIR=$DATA/nemesis
UI_DIR=${UILOG_TEST_DIR:-$NEMDIR/gen5wkr.ui}
UI_PARENT=${UI_DIR%/*}
LOGS=$NEMDIR/logs
BRIDGE=$NEMDIR/apps/gen5w.kr.bridge
HOST_READY=${UILOG_TEST_READY:-/data/data/kr.gen5w.wirelesshost/files/bridge-ready}
PROC=${UILOG_TEST_PROC:-/proc}
UPTIME=${UILOG_TEST_UPTIME:-/proc/uptime}
LOGCAT=${UILOG_TEST_LOGCAT:-logcat}
INTERVAL=${UILOG_TEST_INTERVAL:-15}
MAX_SOURCE_BYTES=131072   # a package log above this is not read at all
PER_SOURCE=25             # newest lines kept per package log
MAX_LINES=200             # lines in the whole log file
LOGCAT_LINES=40
MAX_LINE=200              # characters per line
# Lines that can carry personal data are dropped (same list as the USB diagnosis).
PRIV='([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}|[0-9A-Fa-f]{2}:\*\*|[Ss][Ss][Ii][Dd]|[Pp]assw|PASSW|[Pp]assphrase|[Pp]sk|PSK|[Ss]erial|SERIAL|[Ii]mei|IMEI|[Ii]ccid|ICCID|[Mm]sisdn|MSISDN|VIN[=: ]|vin[=: ]|DEVICE_NAME|[Dd]evice ?[Nn]ame|getName|FRQ:|BND:|ALBUM|TITLE|ARTIST|mArtist'

# The parent folder must exist and nothing we write to may be a link. Creates UI_DIR when missing.
prepare() {
    [ -d "$UI_PARENT" ] && [ ! -L "$UI_PARENT" ] || return 1
    [ ! -L "$UI_DIR" ] || return 1
    if [ ! -e "$UI_DIR" ]; then mkdir "$UI_DIR" || return 1; fi
    [ -d "$UI_DIR" ] || return 1
    chmod 755 "$UI_DIR" || return 1
    for _f in status log status.tmp log.tmp filter.tmp; do
        [ ! -L "$UI_DIR/$_f" ] || return 1
    done
    return 0
}

# Byte size from "ls -l": Android toolbox has no link-count column (size is field 4), GNU ls does (field 5).
file_size() {
    _line=$(LC_ALL=C ls -l "$1" 2>/dev/null) || return 1
    set -- $_line
    _size=${5:-}
    case "$_size" in ''|*[!0-9]*) _size=${4:-};; esac
    case "$_size" in ''|*[!0-9]*) return 1;; esac
    print -r -- "$_size"
}

# Appends the last $2 lines of file $3 as "$1|line", never going over MAX_LINES in total.
emit_tail() {
    typeset total=0 skip line
    while IFS= read -r line || [ -n "$line" ]; do total=$((total + 1)); done < "$3"
    skip=$((total - $2))
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$skip" -gt 0 ]; then skip=$((skip - 1)); continue; fi
        [ "$LINES" -lt "$MAX_LINES" ] || return 0
        print -r -- "$1|${line:0:$MAX_LINE}" >> "$UI_DIR/log.tmp"
        LINES=$((LINES + 1))
    done < "$3"
}

# One package log directory: every *.log in it, size checked, filtered, newest lines only.
collect_source() {
    typeset dir=$1 name=${1##*/} file size
    name=${name#gen5w.kr.}
    for file in "$dir"/*.log; do
        [ -f "$file" ] && [ ! -L "$file" ] || continue
        [ "$LINES" -lt "$MAX_LINES" ] || return 0
        size=$(file_size "$file") || continue
        if [ "$size" -gt "$MAX_SOURCE_BYTES" ]; then
            print -r -- "$name|(로그가 너무 커서 건너뜀)" >> "$UI_DIR/log.tmp"
            LINES=$((LINES + 1))
            continue
        fi
        grep -a -v -E "$PRIV" "$file" > "$UI_DIR/filter.tmp" 2>/dev/null
        emit_tail "$name" "$PER_SOURCE" "$UI_DIR/filter.tmp"
    done
}

collect_log() {
    LINES=0
    : > "$UI_DIR/log.tmp" || return 1
    # The wireless bridge first, so a busy package cannot push it out of the line budget.
    [ -d "$LOGS/gen5w.kr.bridge" ] && [ ! -L "$LOGS/gen5w.kr.bridge" ] && collect_source "$LOGS/gen5w.kr.bridge"
    typeset dir
    for dir in "$LOGS"/gen5w.kr.*; do
        [ -d "$dir" ] && [ ! -L "$dir" ] || continue
        [ "${dir##*/}" != gen5w.kr.bridge ] || continue
        [ "$LINES" -lt "$MAX_LINES" ] || break
        collect_source "$dir"
    done
    if [ "$LINES" -lt "$MAX_LINES" ]; then
        $LOGCAT -d -v time 2>/dev/null | grep -a -E 'Gen5w|gen5w|FATAL EXCEPTION' | grep -a -v -E "$PRIV" > "$UI_DIR/filter.tmp"
        typeset keep=$LOGCAT_LINES room=$((MAX_LINES - LINES))
        [ "$keep" -le "$room" ] || keep=$room
        emit_tail logcat "$keep" "$UI_DIR/filter.tmp"
    fi
    chmod 644 "$UI_DIR/log.tmp" && mv "$UI_DIR/log.tmp" "$UI_DIR/log"
}

host_alive() {
    typeset pid
    [ -f "$HOST_READY" ] && [ ! -L "$HOST_READY" ] || return 1
    IFS= read -r pid < "$HOST_READY"
    case "$pid" in ''|*[!0-9]*) return 1;; esac
    kill -0 "$pid" 2>/dev/null || return 1
    grep -aq 'kr.gen5w.wirelesshost' "$PROC/$pid/cmdline" 2>/dev/null
}

collect_status() {
    typeset up _rest ts host=dead relay=unknown backend apguard=on wired=no version= line
    IFS=' ' read -r up _rest < "$UPTIME" 2>/dev/null
    ts=${up%%.*}
    case "$ts" in ''|*[!0-9]*) ts=;; esac
    host_alive && host=alive
    if [ -d "$BRIDGE" ]; then
        if [ -f "$BRIDGE/app/relay-v039.complete" ]; then relay=on; else relay=off; fi
        if [ -f "$BRIDGE/NEMESIS.data" ]; then
            while IFS= read -r line || [ -n "$line" ]; do
                case "$line" in package-version=*) version=${line#package-version=};; esac
            done < "$BRIDGE/NEMESIS.data"
        fi
    fi
    backend=$(getprop persist.gen5w.wifi.backend 2>/dev/null)
    [ -n "$backend" ] || backend=builtin
    [ -e "$NEMDIR/gen5wkr.apguard.off" ] && apguard=off
    [ -e "$NEMDIR/gen5wkr.wireless-disabled" ] && wired=yes
    {
        print -r -- "ts=$ts"
        print -r -- "host=$host"
        print -r -- "relay=$relay"
        print -r -- "backend=$backend"
        print -r -- "version=$version"
        print -r -- "apguard=$apguard"
        print -r -- "wired=$wired"
    } > "$UI_DIR/status.tmp" || return 1
    chmod 644 "$UI_DIR/status.tmp" && mv "$UI_DIR/status.tmp" "$UI_DIR/status"
}

round() {
    prepare || return 0
    collect_status || :
    collect_log || :
    rm -f "$UI_DIR/filter.tmp" "$UI_DIR/log.tmp" "$UI_DIR/status.tmp"
}

trap 'exit 0' HUP INT TERM
while :; do
    round
    [ -z "$UILOG_TEST_ONCE" ] || exit 0
    sleep "$INTERVAL"
done
