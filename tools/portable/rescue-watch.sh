#!/system/bin/sh
# Root NEMESIS service: fixed USB disable token, independent of Android/Manager.
# Never executes USB code, installs packages, or starts wireless.
umask 077
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
BASE=$(CDPATH= cd -- "$BASE" && pwd) || exit 1
ROOT=${PORTABLE_TEST_ROOT:-}
ADAPTER=${PORTABLE_TEST_RESCUE_ADAPTER:-}
STATE=$ROOT/data/local/gen5w-portable/boot
plain() {
    case "$1" in /*) :;; *) return 1;; esac
    case "$1" in *[!a-zA-Z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac
    local part=$1
    while [ "$part" != / ]; do [ ! -L "$part" ] || return 1; part=${part%/*}; [ -n "$part" ] || part=/; done
}
if [ -n "$ROOT" ]; then
    plain "$ROOT" && [ "$ROOT" != / ] && [ -d "$ROOT" ] || exit 1
    [ "${1:-watch}" = check ] || [ -x "$ADAPTER" ] || exit 1
else
    [ -z "$ADAPTER" ] || exit 1
    case "$(id)" in uid=0\(*) :;; *) exit 1;; esac
    case "$BASE" in /data/*) :;; *) exit 1;; esac
fi
requested() {
    local root file line size token extra
    for root in /storage/usb0 /mnt/media_rw/usb0 /storage/usb1 /mnt/media_rw/usb1 /storage/usb2 /mnt/media_rw/usb2; do
        file=$ROOT$root/GEN5W-PORTABLE-RESCUE
        plain "$file" && [ -f "$file" ] || continue
        line=$(ls -ln "$file" 2>/dev/null) || continue
        set -- $line; size=${5:-}
        case "$size" in ''|*[!0-9]*) size=${4:-};; esac
        # 19 bytes bare, 20 with LF, 21 with CRLF (Windows Notepad).
        case "$size" in 19|20|21) :;; *) continue;; esac
        # FAT32 CRLF is accepted, but additional lines are never instructions.
        token=; extra=
        { IFS= read -r token || [ -n "$token" ]; IFS= read -r extra && continue; [ -z "$extra" ] || continue; } < "$file"
        token=${token%$(print -- '\r')}
        [ "$token" = disable-portable-v1 ] && return 0
    done
    return 1
}
put() {
    plain "$STATE" && [ -d "$STATE" ] || return 1
    plain "$STATE/$1" && plain "$STATE/$1.new" || return 1
    for item in "$STATE/$1" "$STATE/$1.new"; do [ ! -e "$item" ] || [ -f "$item" ] || return 1; done
    print -r -- "$2" > "$STATE/$1.new" && mv "$STATE/$1.new" "$STATE/$1"
}
disable() {
    # No Android call or lock precedes this durable interlock. The controller
    # also checks rescue-request, so an in-flight arm cannot overrule the USB.
    put rescue-request usb-disable && put enabled 0 && sync || return 1
    put rescue-result restore-required || return 1
    if [ -n "$ROOT" ]; then "$ADAPTER" disable
    else /system/bin/sh "$BASE/boot.sh" disable; fi
    local result=$?
    [ "$result" = 0 ] || return "$result"
    put rescue-result restored && sync
}
case "${1:-watch}" in
check) requested;;
disable) disable;;
watch)
    while :; do
        if requested; then
            # Retry restoration after a failed/blocked maintenance window, but
            # retain a successful result while the same rescue USB is present.
            if [ ! -f "$STATE/rescue-result" ] || [ "$(cat "$STATE/rescue-result")" != restored ] || [ "$(cat "$STATE/enabled" 2>/dev/null)" != 0 ]; then
                disable || echo 'rescue: automatic operation disabled; restoration still required' >&2
            fi
        fi
        sleep 2
    done;;
*) exit 2;;
esac
