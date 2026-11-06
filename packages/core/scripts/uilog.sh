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
# Switch requests written by the screen (the core app) into its own folder. Root only READS this
# file (never writes into the app's folder) and only accepts the fixed words below; the effect is a
# marker file in the root-owned $NEMDIR, which the packages' own services look at.
REQUEST=${UILOG_TEST_REQUEST:-/data/data/kr.gen5w.core/files/ui-request}
REQ_STEP=${UILOG_TEST_REQ_STEP:-2}
FACT_LINES=60             # lines of unit facts (read-only checks) kept
USB=${UILOG_TEST_USB:-/storage/usb0}
MOUNTS=${UILOG_TEST_MOUNTS:-/proc/mounts}
PM=${UILOG_TEST_PM:-pm}
SAVED=$NEMDIR/gen5wkr.ui-saved   # "<number> <result>" of the last diagnosis save
NEM=${UILOG_TEST_NEM:-/system/xbin/nemesis}
SH=${UILOG_TEST_SH:-/system/bin/sh}
APPS=$NEMDIR/apps
REMOVED=$NEMDIR/gen5wkr.ui-removed    # "<number> <result> [package]" of the last in-car removal
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
    for _f in status log facts status.tmp log.tmp filter.tmp facts.tmp diag.tmp diag-latest.tmp status-save.tmp facts-save.tmp diag-save.tmp diag-latest-save.tmp diag-latest.txt; do
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

# The save runs in the background with its own temp file names, so it never meets the main loop.
collect_status() {
    typeset up _rest ts host=dead relay=unknown backend apguard=on wired=no version= line tmp="$UI_DIR/${1:-status}.tmp"
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
        print -r -- "sw_wireless=$(switch_state wireless)"
        print -r -- "sw_timer=$(switch_state timer)"
        print -r -- "sw_bluelink=$(switch_state bluelink)"
        print -r -- "sw_adb=$(adb_state)"
        print -r -- "saved=$(saved_state)"
        print -r -- "removed=$(removed_state)"
    } > "$tmp" || return 1
    chmod 644 "$tmp" && mv "$tmp" "$UI_DIR/status"
}

# set_marker <name> <on|off>: off = marker present, on = marker absent. Never follows a link.
set_marker() {
    typeset m="$NEMDIR/gen5wkr.ui-$1-off"
    [ -d "$NEMDIR" ] && [ ! -L "$NEMDIR" ] && [ ! -L "$m" ] || return 1
    case "$2" in
        off) [ -f "$m" ] || : > "$m";;
        on) rm -f "$m";;
    esac
}
# Reads at most 8 lines; only "wireless|timer|bluelink=on|off" is accepted, anything else is ignored.
apply_requests() {
    typeset size rpid waited=0
    [ -f "$REQUEST" ] && [ ! -L "$REQUEST" ] && [ -r "$REQUEST" ] || return 0
    # The app owns this file, so it can be swapped after the checks above (for a pipe that never
    # ends, or a huge line). A real request is a few dozen bytes: refuse anything over 256 bytes,
    # and read in a background process that is stopped after 3 seconds, so this service never hangs.
    size=$(file_size "$REQUEST") || return 0
    [ "$size" -le 256 ] || return 0
    read_requests &
    rpid=$!
    while kill -0 "$rpid" 2>/dev/null && [ "$waited" -lt 3 ]; do sleep 1; waited=$((waited + 1)); done
    if kill -0 "$rpid" 2>/dev/null; then kill "$rpid" 2>/dev/null; fi
    wait "$rpid" 2>/dev/null
    return 0
}
read_requests() {
    typeset line n=0
    while IFS= read -r line && [ "$n" -lt 8 ]; do
        n=$((n + 1))
        case "$line" in
            wireless=on|wireless=off|timer=on|timer=off|bluelink=on|bluelink=off)
                # While a removal runs, markers are not put back right after the removal cleared them.
                [ -e "$NEMDIR/gen5wkr.ui-removing" ] || set_marker "${line%%=*}" "${line#*=}" || :;;
            adb=on:*|adb=off:*) handle_adb "${line#adb=}";;
            save=*) handle_save "${line#save=}";;
            remove=*) handle_remove "${line#remove=}";;
        esac
    done < "$REQUEST"
}
# Read-only facts about this unit, for the next version's features (adb, update check, removal).
# Nothing here changes anything. Lines pass the same privacy filter as the log, at most FACT_LINES.
collect_facts() {
    typeset out="$UI_DIR/${1:-facts}.tmp" n=0 line k v
    : > "$out" || return 1
    {
        for k in persist.sys.usb.config sys.usb.config service.adb.tcp.port persist.adb.tcp.port ro.adb.secure ro.product.ota ro.build.version.release; do
            v=$(getprop "$k" 2>/dev/null)
            print -r -- "prop $k=$v"
        done
        print -r -- "-- /data/nemesis (owner, mode)"
        ls -ln "$NEMDIR" 2>/dev/null
        ls -ln "$DATA" 2>/dev/null | grep -a -F " nemesis"
        print -r -- "-- packages matching ota|fota|redbend|nemesis|update"
        "$PM" list packages 2>/dev/null | grep -a -i -E 'ota|redbend|nemesis|update'
        print -r -- "-- usb mount"
        grep -a -F "$USB" "$MOUNTS" 2>/dev/null
    } 2>/dev/null | grep -a -v -E "$PRIV" | while IFS= read -r line; do
        [ "$n" -lt "$FACT_LINES" ] || break
        n=$((n + 1))
        print -r -- "${line:0:$MAX_LINE}"
    done >> "$out"
    chmod 644 "$out" && mv "$out" "$UI_DIR/facts"
}

# The USB must be mounted as a FAT-type filesystem (no links possible); prints nothing, returns 0/1.
usb_fs_ok() {
    typeset src mp fs _r
    while IFS=' ' read -r src mp fs _r; do
        [ "$mp" = "$USB" ] || continue
        case "$fs" in vfat|exfat|texfat|sdfat|fuse) return 0;; esac
    done < "$MOUNTS"
    return 1
}

# Diagnosis save: status + log + facts into one text file on the USB stick (when mounted) and
# always a copy in UI_DIR. Needs a real mount (an unmounted /storage/usb0 is a plain folder).
do_save() {
    typeset n=$1 result=nousb dest tmp f
    collect_facts facts-save || :
    tmp="$UI_DIR/diag-save.tmp"
    {
        print -r -- "Gen5W KR diagnosis #$n"
        for f in status facts log; do
            print -r -- "===== $f"
            [ -f "$UI_DIR/$f" ] && [ ! -L "$UI_DIR/$f" ] && cat "$UI_DIR/$f"
        done
    } > "$tmp" 2>/dev/null || { rm -f "$tmp"; set_saved "$n" fail; return; }
    chmod 644 "$tmp"
    cat "$tmp" > "$UI_DIR/diag-latest-save.tmp" && mv "$UI_DIR/diag-latest-save.tmp" "$UI_DIR/diag-latest.txt" || result=fail
    if usb_fs_ok && [ -d "$USB" ] && [ ! -L "$USB" ]; then
        dest=$USB/gen5w-kr-diag
        # FAT-type sticks cannot hold links; the checks and the no-overwrite write also cover a
        # stick that was prepared by someone else. Every path we write is checked right before use.
        if [ ! -L "$dest" ] && mkdir -p "$dest" 2>/dev/null && [ ! -L "$dest" ]             && [ ! -e "$dest/diag-$n.txt.tmp" ] && [ ! -L "$dest/diag-$n.txt" ]             && ( set -C; cat "$tmp" > "$dest/diag-$n.txt.tmp" ) 2>/dev/null             && [ ! -L "$dest/diag-$n.txt.tmp" ] && mv "$dest/diag-$n.txt.tmp" "$dest/diag-$n.txt" 2>/dev/null; then
            result=usb
        else
            [ -L "$dest/diag-$n.txt.tmp" ] || rm -f "$dest/diag-$n.txt.tmp" 2>/dev/null
            result=fail
        fi
    fi
    rm -f "$tmp"
    set_saved "$n" "$result"
}
set_saved() {
    [ ! -L "$SAVED" ] || return 0
    print -r -- "$1 $2" > "$SAVED.tmp" 2>/dev/null && mv "$SAVED.tmp" "$SAVED" 2>/dev/null
}
# A new save number in the request starts one save (the number is digits only, at most 10).
handle_save() {
    typeset n=$1 last _r
    case "$n" in ''|*[!0-9]*) return 0;; esac
    [ "${#n}" -le 10 ] || return 0
    [ -d "$UI_DIR" ] && [ ! -L "$UI_DIR" ] || return 0
    [ ! -L "$SAVED" ] || return 0
    [ -f "$SAVED" ] && IFS=' ' read -r last _r < "$SAVED"
    [ "$last" = "$n" ] && return 0
    set_saved "$n" working
    # In the background: collecting the unit facts can take longer than the request reader's time limit.
    ( do_save "$n"; collect_status status-save || : ) &
}
saved_state() {
    typeset n r
    [ -f "$SAVED" ] && [ ! -L "$SAVED" ] && IFS=' ' read -r n r < "$SAVED"
    print -r -- "${n:-0}:${r:-none}"
}
# adb is a one-time command "on:<number>" / "off:<number>". The last applied number is kept in a root-owned
# file, so the request file left in the app folder from before a reboot cannot switch it on again.
ADBTOK=$NEMDIR/gen5wkr.ui-adb
handle_adb() {
    typeset v=$1 state n last _r
    state=${v%%:*}
    n=${v#*:}
    case "$n" in ''|*[!0-9]*) return 0;; esac
    [ "${#n}" -le 10 ] || return 0
    [ -d "$NEMDIR" ] && [ ! -L "$NEMDIR" ] && [ ! -L "$ADBTOK" ] || return 0
    [ -f "$ADBTOK" ] && IFS=' ' read -r last _r < "$ADBTOK"
    [ "$last" = "$n" ] && return 0
    print -r -- "$n" > "$ADBTOK.tmp" 2>/dev/null && mv "$ADBTOK.tmp" "$ADBTOK" 2>/dev/null || return 0
    set_adb "$state"
}
# adb over the car's Wi-Fi, for this boot only: service.adb.tcp.port is a runtime property and is
# gone after a reboot, and nothing persistent is set. The stock key check (ro.adb.secure) still
# applies. Only restarts adbd when the state really changes.
ADB_PORT=5555
adb_port() {
    typeset p
    p=$(getprop service.adb.tcp.port 2>/dev/null)
    case "$p" in ''|*[!0-9]*) p=0;; esac
    print -r -- "$p"
}
adb_state() { if [ "$(adb_port)" -gt 0 ]; then echo on; else echo off; fi; }
set_adb() {
    if [ "$1" = on ]; then
        [ "$(adb_port)" = "$ADB_PORT" ] && return 0
        setprop service.adb.tcp.port "$ADB_PORT" || return 1
    else
        [ "$(adb_port)" = 0 ] && return 0
        setprop service.adb.tcp.port 0 || return 1
    fi
    stop adbd 2>/dev/null
    start adbd 2>/dev/null
}
# In-car removal of every Gen5W KR package EXCEPT the core app (which runs this service and the
# screen; removing it ends both, so the last step is left to NEMESIS Manager). Same method as the
# USB kit: each package's own preuninstall hook runs first and must succeed (older NEMESIS ignores
# a failing hook), then NEMESIS removes the package. The first failure stops everything and is
# reported; nothing is forced. Runs in the background so the request reader's time limit does not
# cut it off, and a lock marker keeps two removals from overlapping.
REMOVE_IDS='drivelog bluelink timer bridge audio wireless dongle'
set_removed() {
    [ ! -L "$REMOVED" ] || return 0
    print -r -- "$1 $2${3:+ $3}" > "$REMOVED.tmp" 2>/dev/null && mv "$REMOVED.tmp" "$REMOVED" 2>/dev/null
}
hook_path() {
    typeset section= line
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            '['*']') section=$line;;
            preuninstall=*) [ "$section" = '[nemesis]' ] && { print -r -- "${line#*=}"; return 0; };;
        esac
    done < "$1"
    return 1
}
run_hook() {
    typeset tree=$1 helper path
    [ -d "$tree" ] && [ ! -L "$tree" ] && [ -f "$tree/NEMESIS.data" ] || return 1
    for helper in "$tree"/bin/*; do
        [ ! -f "$helper" ] || { [ ! -L "$helper" ] && chmod 755 "$helper"; } || return 1
    done
    path=$(hook_path "$tree/NEMESIS.data") || return 0
    case "$path" in ''|/*|*..*|*[!a-zA-Z0-9_./-]*) return 1;; esac
    [ -f "$tree/$path" ] && [ ! -L "$tree/$path" ] || return 1
    ( cd "$tree" && "$SH" "$path" ) >/dev/null 2>&1
}
do_remove() {
    typeset n=$1 short id lock="$NEMDIR/gen5wkr.ui-removing"
    [ ! -L "$lock" ] && ( set -C; : > "$lock" ) 2>/dev/null || return 0
    set_removed "$n" working
    if [ ! -x "$NEM" ]; then set_removed "$n" failed nemesis; rm -f "$lock"; return 0; fi
    for short in $REMOVE_IDS; do
        id=gen5w.kr.$short
        [ -d "$APPS/$id" ] || continue
        set_removed "$n" working "$id"
        if ! run_hook "$APPS/$id"; then set_removed "$n" failed "$id"; rm -f "$lock"; return 0; fi
        if ! "$NEM" uninstall "$id" >/dev/null 2>&1; then set_removed "$n" failed "$id"; rm -f "$lock"; return 0; fi
        [ ! -e "$APPS/$id" ] || set_removed "$n" failed "$id"
        [ ! -e "$APPS/$id" ] || { rm -f "$lock"; return 0; }
    done
    # Markers that only the removed packages looked at (same ones the USB removal clears).
    for _m in wireless-disabled ap-match ap-hotspot-feature ui-wireless-off ui-timer-off ui-bluelink-off; do
        [ -L "$NEMDIR/gen5wkr.$_m" ] || rm -f "$NEMDIR/gen5wkr.$_m"
    done
    set_removed "$n" done
    rm -f "$lock"
}
handle_remove() {
    typeset n=$1 last _r
    case "$n" in ''|*[!0-9]*) return 0;; esac
    [ "${#n}" -le 10 ] || return 0
    [ -d "$NEMDIR" ] && [ ! -L "$NEMDIR" ] || return 0
    [ ! -L "$REMOVED" ] || return 0
    [ -f "$REMOVED" ] && IFS=' ' read -r last _r < "$REMOVED"
    [ "$last" = "$n" ] && return 0
    do_remove "$n" &
}
removed_state() {
    typeset n r id
    [ -f "$REMOVED" ] && [ ! -L "$REMOVED" ] && IFS=' ' read -r n r id < "$REMOVED"
    print -r -- "${n:-0}:${r:-none}${id:+:$id}"
}
switch_state() { if [ -e "$NEMDIR/gen5wkr.ui-$1-off" ]; then echo off; else echo on; fi; }

round() {
    prepare || return 0
    collect_status || :
    collect_log || :
    # The unit facts do not change while it runs: collected once per start (and again for a save).
    [ -n "$FACTS_DONE" ] || { collect_facts || :; FACTS_DONE=1; }
    rm -f "$UI_DIR/filter.tmp" "$UI_DIR/log.tmp" "$UI_DIR/status.tmp" "$UI_DIR/facts.tmp" "$UI_DIR/diag.tmp" "$UI_DIR/diag-latest.tmp"
}

# A removal that was cut off (ignition off, service restart) leaves its lock and a "working" state
# behind; at start nothing of ours is running yet, so clear the lock and report it as failed.
clear_stale_removal() {
    typeset n r id
    [ -e "$NEMDIR/gen5wkr.ui-removing" ] && [ ! -L "$NEMDIR/gen5wkr.ui-removing" ] || return 0
    rm -f "$NEMDIR/gen5wkr.ui-removing"
    [ -f "$REMOVED" ] && [ ! -L "$REMOVED" ] && IFS=' ' read -r n r id < "$REMOVED"
    [ "$r" = working ] && set_removed "${n:-0}" failed "${id:-interrupted}"
}
trap 'exit 0' HUP INT TERM
clear_stale_removal
while :; do
    apply_requests
    round
    apply_requests   # the first pass may come before the folder exists (needed by a save)
    [ -z "$UILOG_TEST_ONCE" ] || exit 0
    # Requests are looked at every few seconds so a switch takes effect quickly.
    waited=0
    while [ "$waited" -lt "$INTERVAL" ]; do
        sleep "$REQ_STEP"
        waited=$((waited + REQ_STEP))
        apply_requests
    done
done
