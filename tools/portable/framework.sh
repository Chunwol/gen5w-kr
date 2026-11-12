#!/system/bin/sh
# Read-only current-framework readiness; sys.boot_completed survives ctl restarts.
identity() {
    local process pid line rest count
    for process in /proc/[0-9]*/cmdline; do
        grep -aq '^system_server' "$process" 2>/dev/null || continue
        pid=${process%/cmdline}; pid=${pid##*/}
        IFS= read -r line < "/proc/$pid/stat" || continue
        rest=${line##*) }; [ "$rest" != "$line" ] || continue
        set -- $rest; [ "$#" -ge 20 ] || continue
        case "$1" in Z|X|x) continue;; esac
        count=0
        while [ "$count" -lt 19 ]; do shift; count=$((count+1)); done
        print -r -- "$pid:$1"
        return 0
    done
    return 1
}
dependencies() {
    local file directive name action rest current=0 found=0 root=${1:-/}
    for file in "$root"/init*.rc; do
        [ -f "$file" ] && [ ! -L "$file" ] || continue
        current=0
        while read -r directive name action rest; do
            case "$directive" in
            service)
                current=0
                if [ "$name" = zygote ]; then current=1; found=$((found+1)); fi;;
            on|import) current=0;;
            onrestart)
                [ "$current:$name" = 1:restart ] || continue
                case "$action" in ''|*[!a-zA-Z0-9_.-]*) return 1;; esac
                [ -z "$rest" ] && [ "${#action}" -le 31 ] || return 1
                print -r -- "$action";;
            esac
        done < "$file"
    done
    [ "$found" = 1 ]
}
case "$1" in
 dependencies) dependencies "${2:-/}";;
identity) identity;;
ready)
    current=$(identity) && [ "$current" != "${2:-}" ] || exit 1
    [ "$(getprop init.svc.zygote)" = running ] || exit 1
    service check package | grep -q ': found$' || exit 1
    service check activity | grep -q ': found$' || exit 1
    # mBooted belongs to the newly registered ActivityManager, unlike the
    # persistent-within-a-kernel sys.boot_completed property.
    dumpsys activity p | grep -q 'mBooted=true' || exit 1
    [ "$(identity)" = "$current" ];;
*) exit 2;;
esac
