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
err_lock() {
    typeset dir=$1 boot=$2 owner_boot= owner_pid= extra=
    if ! mkdir "$dir/write.lock" 2>/dev/null; then
        [ -d "$dir/write.lock" ] && [ ! -L "$dir/write.lock" ] &&
            [ -f "$dir/write.lock/owner" ] && [ ! -L "$dir/write.lock/owner" ] || return 1
        IFS=' ' read -r owner_boot owner_pid extra < "$dir/write.lock/owner" || return 1
        err_token "$owner_boot" || return 1
        case "$owner_pid" in ''|*[!0-9]*) return 1;; esac
        [ -z "$extra" ] || return 1
        if [ "$owner_boot" = "$boot" ] && kill -0 "$owner_pid" 2>/dev/null;then return 1;fi
        # Only the known owner file is removed; foreign lock contents remain.
        rm -f "$dir/write.lock/owner" && rmdir "$dir/write.lock" 2>/dev/null && mkdir "$dir/write.lock" 2>/dev/null || return 1
    fi
    (umask 077; print -r -- "$boot $$" > "$dir/write.lock/owner") || { rmdir "$dir/write.lock" 2>/dev/null;return 1; }
}
err_event() {
    typeset module=$1 stage=$2 operation=$3 result=$4 code=$5 reason=$6
    typeset dir=${ERR_DIR:-/data/nemesis/gen5wkr.errors} attempt=${ERR_ATTEMPT:-} revision=${ERR_REVISION:-unknown}
    typeset uptime=unknown boot=unknown line old= slot=${ERR_SLOT:-0} n size
    case "$module" in integrated|core|wireless|audio|bridge|dongle|hotspot|bootguard|timer|bluelink|drivelog|check|diag|uilog) ;; *) return 0;; esac
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
    [ "${ERR_PERSIST:-yes}" != no ] || return 0
    err_prepare 2>/dev/null || { print -r -- 'ERR persistence=unavailable' >&2; return 0; }
    # Nonblocking lock: concurrent logging must never delay real cleanup.
    err_lock "$dir" "$boot" || { print -r -- 'ERR persistence=busy' >&2; return 0; }
    (
        umask 077
        for n in 0 1 2 3; do
            [ ! -L "$dir/errors.$n" ] || exit 1
            [ ! -e "$dir/errors.$n" ] || [ -f "$dir/errors.$n" ] || exit 1
        done
        [ ! -L "$dir/first.$module.$slot" ] || exit 1
        [ ! -e "$dir/first.$module.$slot" ] || [ -f "$dir/first.$module.$slot" ] || exit 1
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
            [ ! -f "$dir/first.$module.$slot" ] || IFS= read -r old < "$dir/first.$module.$slot" || :
            case "$old" in "ERR attempt=$attempt "*) ;;
                *) print -r -- "$line" > "$dir/first.$module.$slot" || exit 1;;
            esac
        fi
    ) || print -r -- 'ERR persistence=failed' >&2
    rm -f "$dir/write.lock/owner"
    rmdir "$dir/write.lock" 2>/dev/null || :
    return 0
}
err_classify_stream() {
    # Fixed-sized reads bound memory even for a megabyte-long unterminated line.
    # Only known error categories survive; unreviewed raw text is redacted.
    typeset chunk carry= reason=0
    while :; do
        chunk=
        IFS= read -r -n 1024 chunk || [ -n "$chunk" ] || break
        chunk=$carry$chunk
        case "$chunk" in
            *'Permission denied'*|*'Operation not permitted'*) reason=10;;
            *'Device or resource busy'*|*'device or resource busy'*|*'EBUSY'*) [ "$reason" != 10 ] || continue; reason=11;;
            *'not found'*|*'No such file or directory'*) [ "$reason" != 0 ] || reason=12;;
            *'No space left on device'*) reason=13;;
            *'Read-only file system'*) reason=14;;
            *'Input/output error'*) reason=15;;
            *'timed out'*|*'Timeout'*) [ "$reason" != 0 ] || reason=16;;
            *'ClassNotFoundException'*|*'NoClassDefFoundError'*) reason=17;;
            *'LinkageError'*|*'NoSuchMethodError'*|*'UnsatisfiedLinkError'*) reason=18;;
            *'BindException'*|*'Address already in use'*) reason=19;;
            *'SecurityException'*) reason=10;;
        esac
        if [ "${#chunk}" -gt 64 ]; then carry=${chunk:$((${#chunk}-64))};else carry=$chunk;fi
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
    case "$stage" in verify|inspect) ;;
        *) err_event "$module" "$stage" "$operation" started 0 none;;
    esac
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
        17) reason=missing-class;; 18) reason=linkage;; 19) reason=socket-bind;;
    esac
    [ "$rc" != 127 ] || reason=missing-command
    [ "$rc" = 0 ] || result=failed
    if [ "$rc" = 0 ] && [ "${statuses[1]}" = 0 ]; then reason=none;fi
    if [ "$rc" = 77 ] && [ "$stage" = preinstall ]; then result=skipped;reason=unsupported;fi
    # Full acquisition status distinguishes empty output from failed collection;
    # successful checksum probes stay quiet to avoid excessive flash writes.
    if [ "$result" != ok ] || [ "$reason" != none ] || { [ "$stage" != verify ] && [ "$stage" != inspect ]; } || [ "${ERR_LOG_SUCCESS:-no}" = yes ]; then
        err_event "$module" "$stage" "$operation" "$result" "$rc" "$reason"
    fi
    return "$rc"
}
err_mount() { typeset module=$1 mode=$2 command=$3; err_run "$module" mount "$mode" "$command" remount "$mode"; }
err_stderr() {
    typeset code reason=redacted
    if err_classify_stream; then code=0; else code=$?; fi
    case "$code" in
        10) reason=permission;; 11) reason=busy;; 12) reason=missing;;
        13) reason=no-space;; 14) reason=read-only;; 15) reason=io;; 16) reason=timeout;;
        17) reason=missing-class;; 18) reason=linkage;; 19) reason=socket-bind;;
    esac
    err_event "$1" "$2" "$3" observed 0 "$reason"
}
err_export() {
    typeset dir=${ERR_DIR:-/data/nemesis/gen5wkr.errors} name line count size module slot names=
    [ -d "$dir" ] && [ ! -L "$dir" ] || { echo 'ERR export=unavailable'; return 0; }
    for module in integrated core wireless audio bridge dongle hotspot bootguard timer bluelink drivelog check diag uilog; do
        for slot in 0 1 2 3 4 5 6 7; do names="$names first.$module.$slot";done
    done
    for name in $names errors.3 errors.2 errors.1 errors.0; do
        [ -f "$dir/$name" ] && [ ! -L "$dir/$name" ] || continue
        size=$(err_size "$dir/$name") || continue
        [ "$size" -le 65536 ] || { echo 'ERR export=oversize'; continue; }
        count=0
        while IFS= read -r line || [ -n "$line" ]; do
            count=$((count + 1))
            [ "$count" -le 64 ] || { echo 'ERR export=truncated'; break; }
            # Journal records contain only fixed token fields. Drop any other
            # bytes rather than trusting a file solely because of its name.
            [ "${#line}" -le 1024 ] || { echo 'ERR export=redacted'; continue; }
            case "$line" in
                *[!a-zA-Z0-9_.:=\ -]*) echo 'ERR export=redacted';;
                'ERR attempt='*) print -r -- "$line";;
            esac
        done < "$dir/$name"
    done
}
err_context() {
    typeset boot=unknown uptime=unknown extra
    if [ -z "${ERR_ATTEMPT:-}" ]; then
        [ ! -r /proc/uptime ] || IFS=' ' read -r uptime extra < /proc/uptime
        [ ! -r /proc/sys/kernel/random/boot_id ] || IFS= read -r boot < /proc/sys/kernel/random/boot_id
        ERR_ATTEMPT=${boot:0:8}-${uptime%%.*}-$$
        export ERR_ATTEMPT
    fi
    if [ -z "${ERR_REVISION:-}" ];then
        ERR_REVISION=unknown
        for extra in "${SCRIPT_DIR:-.}/../BUILD-REVISION" ./BUILD-REVISION;do
            [ -f "$extra" ] && [ ! -L "$extra" ] || continue
            IFS= read -r ERR_REVISION < "$extra" || ERR_REVISION=unknown
            break
        done
        export ERR_REVISION
    fi
}
err_context
