#!/system/bin/sh
# Owned report slots and bounded sanitized streams. No recursive deletion.
REPORT_NAMES='EXEC_LOG.txt EXEC_LOG.txt.1 EXEC_LOG.txt.2 EXEC_LOG.txt.3 STARTUP.txt ENTRY_STATUS.txt RESULT.md RESULT.html ISSUE.md DIAG_EXEC_LOG.txt DIAG_EXEC_LOG.txt.1 DIAG_EXEC_LOG.txt.2 DIAG_EXEC_LOG.txt.3 DIAG_STARTUP.txt PROGRESS.txt'
report_stream() {
    typeset out=$1 mode=${2:-rotate} line count=0 long=no n chunk buffer= failed=no full=no nl='
'
    for n in "$out" "$out.1" "$out.2" "$out.3"; do
        [ ! -L "$n" ] && { [ ! -e "$n" ] || [ -f "$n" ]; } || failed=yes
    done
    [ "$failed" = yes ] || : > "$out" || failed=yes
    while :; do
        chunk=
        IFS= read -r -n 1024 chunk || [ -n "$chunk" ] || break
        [ "$failed" = no ] && [ "$full" = no ] || continue
        buffer=$buffer$chunk
        while :; do
            case "$buffer" in *"$nl"*) ;;
                *) break;;
            esac
            line=${buffer%%"$nl"*}
            buffer=${buffer#*"$nl"}
            if [ "$long" = yes ] || [ "${#line}" -ge 1024 ]; then line='[truncated long diagnostic line]';fi
            long=no
            report_write_line "$line" || failed=yes
        done
        if [ "${#buffer}" -ge 1024 ]; then long=yes;buffer=;fi
    done
    if [ "$failed" = no ] && [ "$full" = no ]; then
        if [ "$long" = yes ]; then report_write_line '[truncated long diagnostic line]' || failed=yes
        elif [ -n "$buffer" ];then report_write_line "$buffer" || failed=yes;fi
    fi
    [ "$failed" = no ]
}
report_write_line() {
        typeset line=$1 n bytes
        case "$line" in
            *[Ss][Ss][Ii][Dd]*|*[Pp][Ss][Kk]*|*[Pp]assw*|*[Tt]oken*|*[Ss]erial*|*[Vv][Ii][Nn]=*|*[Ii][Mm][Ee][Ii]*|*[Ii][Cc][Cc][Ii][Dd]*|*[Mm][Ss][Ii][Ss][Dd][Nn]*|*[Dd]evice[Nn]ame*|*[Dd]evice\ [Nn]ame*|*[Pp]hone[Nn]ame*|*[Dd]estination*|*[Aa]rtist*|*[Aa]lbum*|*[Tt]itle=*|*:*:*:*:*:*) line='[redacted diagnostic line]';;
        esac
        # ASCII diagnostics are counted exactly; non-ASCII uses a conservative
        # UTF-8 bound without spawning a tool for every log line.
        case "$line" in *[!\ -~]*) bytes=$((${#line} * 4 + 4));; *) bytes=$((${#line}+1));; esac
        count=$((count + bytes))
        if [ "$count" -gt 61440 ]; then
            if [ "$mode" = single ]; then
                print -r -- '[truncated archived diagnostic]' >> "$out" || return 1
                full=yes
                return 0
            fi
            rm -f "$out.3" || return 1
            for n in 2 1; do [ ! -f "$out.$n" ] || mv "$out.$n" "$out.$((n+1))" || return 1; done
            mv "$out" "$out.1" || return 1
            : > "$out" || return 1
            count=$bytes
        fi
        print -r -- "$line" >> "$out" || return 1
}
report_attempt_end() {
    [ -z "${REPORT_LOCK_DIR:-}" ] || err_unlock "$REPORT_LOCK_DIR" "$REPORT_LOCK_BOOT"
}
report_attempt_begin() {
    typeset action=$1 report=GEN5W-REPORT history=GEN5W-REPORT/HISTORY
    typeset slot=0 next dir name owner= item known
    [ ! -L "$report" ] && [ ! -L "$history" ] || return 1
    mkdir -p "$report" || return 1
    REPORT_LOCK_BOOT=unknown
    [ ! -r /proc/sys/kernel/random/boot_id ] || IFS= read -r REPORT_LOCK_BOOT < /proc/sys/kernel/random/boot_id
    err_lock "$report" "$REPORT_LOCK_BOOT" || return 1
    REPORT_LOCK_DIR=$report
    # Keep the lock through the real operation and current report publication,
    # not only the archive slot counter. A contender must not truncate either.
    trap report_attempt_end EXIT
    if [ -e "$history" ]; then
        [ -d "$history" ] && [ ! -L "$history/.owner" ] && [ -f "$history/.owner" ] || return 1
        IFS= read -r owner < "$history/.owner" || return 1
        [ "$owner" = gen5w-report-history-v1 ] || return 1
    else
        mkdir "$history" || return 1
        print -r -- gen5w-report-history-v1 > "$history/.owner" || return 1
    fi
    [ ! -L "$history/next" ] || return 1
    if [ -f "$history/next" ]; then IFS= read -r slot < "$history/next" || return 1; fi
    case "$slot" in [0-7]) ;; *) return 1;; esac
    dir=$history/$slot
    [ ! -L "$dir" ] || return 1
    if [ -e "$dir" ]; then
        [ -d "$dir" ] && [ ! -L "$dir/.owner" ] && [ -f "$dir/.owner" ] || return 1
        IFS= read -r owner < "$dir/.owner" || return 1
        [ "$owner" = gen5w-report-slot-v1 ] || return 1
        for item in "$dir"/* "$dir"/.[!.]*; do
            [ -e "$item" ] || [ -L "$item" ] || continue
            known=no
            for name in .owner $REPORT_NAMES; do [ "$item" != "$dir/$name" ] || known=yes; done
            [ "$known" = yes ] && [ ! -L "$item" ] && [ -f "$item" ] || return 1
        done
        for name in $REPORT_NAMES; do rm -f "$dir/$name" || return 1; done
    else
        mkdir "$dir" || return 1
        print -r -- gen5w-report-slot-v1 > "$dir/.owner" || return 1
    fi
    for name in $REPORT_NAMES; do
        [ ! -L "$report/$name" ] || return 1
        [ ! -e "$report/$name" ] || [ -f "$report/$name" ] || return 1
        [ ! -f "$report/$name" ] || report_stream "$dir/$name" single < "$report/$name" || return 1
    done
    next=$(((slot + 1) % 8))
    print -r -- "$next" > "$history/next" || return 1
    ERR_SLOT=$slot
    typeset uptime=unknown boot=unknown
    [ ! -r /proc/uptime ] || IFS=' ' read -r uptime name < /proc/uptime
    [ ! -r /proc/sys/kernel/random/boot_id ] || IFS= read -r boot < /proc/sys/kernel/random/boot_id
    ERR_ATTEMPT=${boot:0:8}-${uptime%%.*}-$$-$slot
    ERR_REVISION=unknown
    [ ! -f BUILD-REVISION ] || IFS= read -r ERR_REVISION < BUILD-REVISION
    export ERR_ATTEMPT ERR_SLOT ERR_REVISION
    err_event integrated entry "$action" starting 0 none
}

# Korean on-screen text for the entry's automatic reboot (NEMESIS.sh is ASCII-only).
auto_reboot_text() {
    case "$1" in
        unfinished) echo 'Gen5W 작업이 끝나지 않아 재부팅합니다. 재부팅 후 USB를 다시 꽂으면 순정 복구를 진행합니다.';;
        *) echo 'Gen5W 작업을 시작하지 못해 재부팅합니다. 바뀐 것은 없습니다. 재부팅 후 USB를 다시 꽂으면 다시 시도합니다.';;
    esac
}
