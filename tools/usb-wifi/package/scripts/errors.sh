#!/system/bin/sh
# Canonical standalone copy: regenerate module copies with sync.py.
# No command arguments or arbitrary stderr enter a persistent record.
err_token() {
    case "$1" in ''|*[!a-zA-Z0-9_.:-]*) return 1;; esac
    [ "${#1}" -le 96 ]
}
err_prepare() {
    typeset path=${ERR_DIR:-/data/nemesis/gen5wkr.errors} parent
    case "$path" in /*) ;; *) return 1;; esac
    [ "$path" != / ] || return 1
    parent=$path
    while [ "$parent" != / ] && [ -n "$parent" ]; do
        [ ! -L "$parent" ] || return 1
        [ ! -e "$parent" ] || [ -d "$parent" ] || return 1
        parent=${parent%/*}
    done
    (umask 077; mkdir -p "$path") || return 1
    chmod 700 "$path" || return 1
}
err_size() {
    typeset info
    info=$(ls -ln "$1" 2>/dev/null) || return 1
    set -- $info
    [ $# -ge 5 ] || return 1
    case "$5" in ''|*[!0-9]*) return 1;; esac
    echo "$5"
}
err_event() {
    typeset module=$1 stage=$2 operation=$3 result=$4 code=$5 reason=$6
    typeset dir=${ERR_DIR:-/data/nemesis/gen5wkr.errors} attempt=${ERR_ATTEMPT:-} revision=${ERR_REVISION:-unknown}
    typeset uptime=unknown boot=unknown line old= slot=${ERR_SLOT:-0} n size
    for line in "$module" "$stage" "$operation" "$result" "$code" "$reason"; do
        err_token "$line" || return 0
    done
    case "$code" in *[!0-9]*) return 0;; esac
    [ ! -r /proc/uptime ] || IFS=' ' read -r uptime line < /proc/uptime
    [ ! -r /proc/sys/kernel/random/boot_id ] || IFS= read -r boot < /proc/sys/kernel/random/boot_id
    err_token "$uptime" || uptime=unknown
    err_token "$boot" || boot=unknown
    [ -n "$attempt" ] || attempt=${boot:0:8}-${uptime%%.*}-$$
    err_token "$attempt" && err_token "$revision" || return 0
    case "$slot" in [0-7]) ;; *) slot=0;; esac
    line="ERR attempt=$attempt revision=$revision boot=$boot uptime=$uptime module=$module stage=$stage operation=$operation result=$result rc=$code reason=$reason"
    # Always expose a safe fallback, even when private storage is unavailable.
    print -r -- "$line" >&2
    err_prepare 2>/dev/null || { print -r -- 'ERR persistence=unavailable' >&2; return 0; }
    # Nonblocking lock: concurrent logging must never delay real cleanup.
    mkdir "$dir/write.lock" 2>/dev/null || { print -r -- 'ERR persistence=busy' >&2; return 0; }
    (
        umask 077
        for n in 0 1 2 3; do
            [ ! -L "$dir/errors.$n" ] || exit 1
            [ ! -e "$dir/errors.$n" ] || [ -f "$dir/errors.$n" ] || exit 1
        done
        [ ! -L "$dir/first.$slot" ] || exit 1
        [ ! -e "$dir/first.$slot" ] || [ -f "$dir/first.$slot" ] || exit 1
        if [ -f "$dir/errors.0" ]; then
            size=$(err_size "$dir/errors.0") || exit 1
            if [ "$size" -ge 61440 ]; then
                rm -f "$dir/errors.3" || exit 1
                for n in 2 1 0; do
                    [ ! -f "$dir/errors.$n" ] || mv "$dir/errors.$n" "$dir/errors.$((n+1))" || exit 1
                done
            fi
        fi
        print -r -- "$line" >> "$dir/errors.0" || exit 1
        if [ "$result" = failed ]; then
            [ ! -f "$dir/first.$slot" ] || IFS= read -r old < "$dir/first.$slot"
            case "$old" in "ERR attempt=$attempt "*) ;;
                *) print -r -- "$line" > "$dir/first.$slot" || exit 1;;
            esac
        fi
    ) || print -r -- 'ERR persistence=failed' >&2
    rmdir "$dir/write.lock" 2>/dev/null || :
    return 0
}
err_classify_stream() {
    # Fixed-sized reads bound memory even for a megabyte-long unterminated line.
    # Only known error categories survive; unreviewed raw text is redacted.
    typeset chunk reason=0
    while :; do
        chunk=
        IFS= read -r -n 1024 chunk || [ -n "$chunk" ] || break
        case "$chunk" in
            *'Permission denied'*|*'Operation not permitted'*) reason=10;;
            *'Device or resource busy'*|*'device or resource busy'*|*'EBUSY'*) [ "$reason" != 10 ] || continue; reason=11;;
            *'not found'*|*'No such file or directory'*) [ "$reason" != 0 ] || reason=12;;
            *'No space left on device'*) reason=13;;
            *'Read-only file system'*) reason=14;;
            *'Input/output error'*) reason=15;;
            *'timed out'*|*'Timeout'*) [ "$reason" != 0 ] || reason=16;;
        esac
    done
    return "$reason"
}
err_run() {
    typeset module=$1 stage=$2 operation=$3
    shift 3
    # fd3 preserves command stdout; the pipe consumes stderr without a raw file.
    # mksh PIPESTATUS preserves the operation's rc even if diagnostic storage fails.
    typeset -a statuses
    typeset reason=unknown result=ok rc
    {
        if { "$@" 2>&1 1>&3; } | err_classify_stream; then
            statuses=("${PIPESTATUS[@]}")
        else
            statuses=("${PIPESTATUS[@]}")
        fi
    } 3>&1
    rc=${statuses[0]}
    case "${statuses[1]}" in
        10) reason=permission;; 11) reason=busy;; 12) reason=missing;;
        13) reason=no-space;; 14) reason=read-only;; 15) reason=io;; 16) reason=timeout;;
    esac
    [ "$rc" != 127 ] || reason=missing-command
    [ "$rc" = 0 ] || result=failed
    err_event "$module" "$stage" "$operation" "$result" "$rc" "$reason"
    return "$rc"
}
err_mount() { typeset module=$1 mode=$2 command=$3; err_run "$module" mount "$mode" "$command" remount "$mode"; }
