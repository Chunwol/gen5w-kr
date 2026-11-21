#!/system/bin/sh
# Which Wi-Fi this install uses: the car's built-in Wi-Fi or a USB Wi-Fi dongle.
#
# detect  Decided once per install (package-post), before any /system change.
#         Prints "backend|reason":
#   builtin  built-in (SDIO Broadcom) Wi-Fi seen, either directly or after
#            turning Wi-Fi on for up to 8 s while it was off (then off again),
#            as the integrated editions' installer and check did.
#   dongle   no built-in Wi-Fi and a USB dongle that can host the stock 5 GHz
#            hotspot is plugged in (2.4 GHz-only dongles report none); or
#            GEN5W-FORCE-DONGLE was on the install USB; or an earlier install
#            already put the dongle stand-in in place (probing would then load
#            the stand-in, not the stock driver).
#   none     neither: installed like builtin; wireless cannot start.
#         Exit 1 (nothing changed) when Wi-Fi could not be turned off again.
# record BACKEND [REASON]  Saves the result for the services and the in-car
#                  screen, and whether a 2.4 GHz-only dongle was the reason.
# get              Prints the saved result, or "unknown".
umask 077
LC_ALL=C; export LC_ALL
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
ROOT=${PORTABLE_TEST_ROOT:-}
ADAPTER=${PORTABLE_TEST_WIFI_ADAPTER:-}
HELPER=${PORTABLE_HELPER:-$BASE/bin/dex-patch}
S=$ROOT/data/local/gen5w-portable
RECORD=$S/wifi-backend
WHY=$S/wifi-backend-why
FORCE=$ROOT/data/nemesis/gen5wkr.force-dongle
RECOVERY_MANIFEST=$S/persistent/recovery/manifest
SYSFS=$ROOT/sys
MODS=$BASE/dongle/modules
FIRMWARE=$BASE/dongle/firmware
STAND_IN=/system/wifi/bcmdhd.ko
fail() { echo "wifi-backend: $*" >&2; exit 1; }
plain() {
    case "$1" in /*) :;; *) return 1;; esac
    case "$1" in *[!a-zA-Z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac
    local part=$1
    while [ "$part" != / ]; do [ ! -L "$part" ] || return 1; part=${part%/*}; [ -n "$part" ] || part=/; done
}
if [ -n "$ROOT" ]; then
    plain "$ROOT" && [ "$ROOT" != / ] && [ -d "$ROOT" ] || fail fixture
else
    [ -z "$ADAPTER" ] || fail fixture
fi
# Android boundaries. Fixtures must supply an adapter; it is never optional.
# V039 settings and svc have no #! line: run them through sh, bounded.
op() {
    if [ -n "$ROOT" ]; then
        [ -n "$ADAPTER" ] && [ -x "$ADAPTER" ] || return 1
        "$ADAPTER" "$@"; return $?
    fi
    case "$1" in
    wifi-on) "$HELPER" supervise 30 /system/bin/true /system/bin/sh /system/bin/settings get global wifi_on;;
    enable) "$HELPER" supervise 30 /system/bin/true /system/bin/sh /system/bin/svc wifi enable;;
    disable) "$HELPER" supervise 30 /system/bin/true /system/bin/sh /system/bin/svc wifi disable;;
    dmesg) dmesg;;
    modules) cat /proc/modules;;
    sleep) sleep 1;;
    *) return 1;;
    esac
}
word() { case "$1" in ''|*[!a-z0-9]*) return 1;; esac; print -r -- "$1"; }
# A loaded USB Wi-Fi driver from our catalog: then a wlan interface may be it.
dongle_driver_loaded() {
    local loaded driver rest
    plain "$MODS/modules.profile" && [ -f "$MODS/modules.profile" ] || return 1
    loaded=$(op modules 2>/dev/null) || return 1
    while IFS='|' read -r driver rest; do
        case "$driver" in ''|*[!a-z0-9_-]*) continue;; esac
        case "$loaded" in *"${driver//-/_} "*|"${driver//-/_} "*) return 0;; esac
    done < "$MODS/modules.profile"
    return 1
}
# Built-in (SDIO Broadcom) Wi-Fi, positive evidence only.
builtin_observed() {
    local e class
    for e in "$SYSFS"/bus/sdio/devices/*/class; do
        [ -f "$e" ] || continue
        IFS= read -r class < "$e" || continue
        [ "$class" = 0x07 ] && return 0
    done
    if ! dongle_driver_loaded; then
        for e in "$SYSFS"/class/net/wlan*; do [ -e "$e" ] && return 0; done
    fi
    op dmesg 2>/dev/null | grep -q 'Firmware up'
}
# A plugged-in USB device that one of our ready driver profiles supports, with
# access-point mode (wireless CarPlay/Android Auto run the head unit as an AP)
# and every module and firmware file of that profile in the package.
profile_ready() {
    local wanted=$1 need=${2:-yes} driver modules firmware bands ap status item
    while IFS='|' read -r driver modules firmware bands ap status; do
        [ "$driver" = "$wanted" ] || continue
        [ "$status" = ready ] && [ "$ap" = "$need" ] || return 1
        for item in $modules; do [ -f "$MODS/$item.ko" ] || return 1; done
        for item in $firmware; do [ -f "$FIRMWARE/$item" ] || return 1; done
        return 0
    done < "$MODS/modules.profile"
    return 1
}
# The kernel's own match keys: each USB interface's modalias, then each
# device's IDs. sysfs prints IDs in lowercase hex; the aliases use uppercase.
usb_modaliases() {
    local f v p
    typeset -u vid pid
    for f in "$SYSFS"/bus/usb/devices/*:*/modalias; do
        [ -r "$f" ] && IFS= read -r v < "$f" && print -r -- "$v"
    done
    for v in "$SYSFS"/bus/usb/devices/*/idVendor; do
        p=${v%idVendor}idProduct
        [ -r "$v" ] && [ -r "$p" ] || continue
        IFS= read -r vid < "$v" && IFS= read -r pid < "$p" || continue
        print -r -- "usb:v${vid}p${pid}d0000dc00dsc00dp00ic00isc00ip00in00"
    done
}
dongle_present() { # catalog AP value: yes (stock 5 GHz hotspot) or 2g
    local need=${1:-yes} list modalias kind pattern module
    plain "$MODS/modules.alias" && [ -f "$MODS/modules.alias" ] && [ -f "$MODS/modules.profile" ] || return 1
    list=$(usb_modaliases)
    while IFS= read -r modalias; do
        [ -n "$modalias" ] || continue
        while read -r kind pattern module; do
            [ "$kind" = alias ] || continue
            case "$modalias" in $pattern) profile_ready "$module" "$need" && return 0;; esac
        done < "$MODS/modules.alias"
    done <<EOF
$list
EOF
    return 1
}
wifi_on() { local v; v=$(op wifi-on 2>/dev/null) || return 1; v=${v%$'\r'}; word "$v"; }
# Up to 8 one-second looks for the built-in interface.
watch_builtin() {
    local n=0
    while [ "$n" -lt 8 ]; do
        builtin_observed && return 0
        op sleep; n=$((n + 1))
    done
    return 1
}
# Wi-Fi was off: turn it on, look, and always turn it off again.
probe() {
    local seen=1 n=0
    op enable >/dev/null 2>&1 && watch_builtin && seen=0
    op disable >/dev/null 2>&1
    while [ "$(wifi_on)" != 0 ]; do
        [ "$n" -lt 8 ] || return 2
        op sleep; n=$((n + 1))
        op disable >/dev/null 2>&1
    done
    return "$seen"
}
detect() {
    local state rc
    if [ -e "$FORCE" ] || [ -L "$FORCE" ]; then
        plain "$FORCE" && [ -f "$FORCE" ] || fail 'unsafe force marker'
        echo 'dongle|forced'; return 0
    fi
    if [ -e "$RECOVERY_MANIFEST" ] || [ -L "$RECOVERY_MANIFEST" ]; then
        plain "$RECOVERY_MANIFEST" && [ -f "$RECOVERY_MANIFEST" ] || fail 'unsafe recovery manifest'
        if grep -q "^$STAND_IN|" "$RECOVERY_MANIFEST"; then echo 'dongle|installed'; return 0; fi
    fi
    if builtin_observed; then echo 'builtin|observed'; return 0; fi
    state=$(wifi_on) || state=unreadable
    case "$state" in
    0)  probe; rc=$?
        [ "$rc" != 2 ] || { echo 'error|wifi-still-on'; return 1; }
        if [ "$rc" = 0 ]; then echo 'builtin|probe'; return 0; fi
        state=probe-none;;
    1)  if watch_builtin; then echo 'builtin|wifi-on'; return 0; fi
        state=wifi-on-no-interface;;
    *)  # Unknown: never swap the Wi-Fi driver without positive evidence.
        echo "none|settings-$state"; return 0;;
    esac
    if dongle_present; then echo "dongle|$state"
    elif dongle_present 2g; then echo "none|$state-2g-only-dongle"
    else echo "none|$state"; fi
}
case "$1" in
detect) detect; exit $?;;
record)
    case "${2:-}" in builtin|dongle|none) :;; *) fail 'usage: wifi-backend.sh record builtin|dongle|none';; esac
    plain "$RECORD" && plain "$RECORD.new" || fail 'unsafe record path'
    mkdir -p "$S" || fail 'state unavailable'
    for f in "$RECORD" "$RECORD.new"; do [ ! -e "$f" ] || [ -f "$f" ] || fail 'unsafe record'; done
    print -r -- "$2" > "$RECORD.new" && chmod 644 "$RECORD.new" && mv "$RECORD.new" "$RECORD" || fail 'record failed'
    plain "$WHY" && [ ! -L "$WHY" ] && { [ ! -e "$WHY" ] || [ -f "$WHY" ]; } || fail 'unsafe reason record'
    case "${3:-}" in
    *-2g-only-dongle) print -r -- 2g-only > "$WHY" && chmod 644 "$WHY" || fail 'reason record failed';;
    *) rm -f "$WHY" || fail 'reason record not cleared';;
    esac
    # The USB override is one-shot: it applies to the install that read it.
    if [ -e "$FORCE" ]; then plain "$FORCE" && [ -f "$FORCE" ] && rm -f "$FORCE" || fail 'force marker not cleared'; fi
    echo "wifi-backend: recorded $2";;
get)
    value=
    plain "$RECORD" && [ -f "$RECORD" ] && IFS= read -r value < "$RECORD"
    case "$value" in builtin|dongle|none) print -r -- "$value";; *) echo unknown;; esac;;
*) fail 'usage: wifi-backend.sh detect | record BACKEND | get';;
esac
