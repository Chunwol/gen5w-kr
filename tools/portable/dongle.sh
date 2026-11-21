#!/system/bin/sh
# USB Wi-Fi dongle driver service. Does nothing unless this install chose the
# dongle (wifi-backend.sh) and automatic startup is enabled.
#
# The stock Wi-Fi HAL is unchanged; it loads /system/wifi/bcmdhd.ko, which the
# dongle install replaced with a small stand-in that only waits for a wireless
# interface. This service makes that interface: after boot, when a supported
# dongle is plugged in, it loads the dongle's kernel modules from this package.
# Firmware comes from this package too: the car kernel reads firmware only from
# /lib/firmware (absent on this unit) or firmware_class.path, which is set here
# (it resets every boot). Nothing on /system is written.
#
# Restart guard: a mark is on disk while modules load and for a while after.
# Finding it at start means the last load was cut short (crash, reboot, power
# off), so loading stops until the dongle is unplugged.
renice 10 $$ >/dev/null 2>&1
umask 077
LC_ALL=C; export LC_ALL
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
BASE=$(CDPATH= cd -- "$BASE" && pwd) || exit 1
ROOT=${PORTABLE_TEST_ROOT:-}
ADAPTER=${PORTABLE_TEST_DONGLE_ADAPTER:-}
ROUNDS=${PORTABLE_TEST_DONGLE_ROUNDS:-}
STABLE_SECONDS=${PORTABLE_TEST_DONGLE_STABLE:-60}
S=$ROOT/data/local/gen5w-portable
STATE=$S/dongle
MARK=$STATE/loading
BLOCK=$STATE/blocked
LOGDIR=$ROOT/data/nemesis/logs/gen5w.kr.portable
LOG=$LOGDIR/dongle.log
MODS=$BASE/dongle/modules
FIRMWARE=$BASE/dongle/firmware
FWPATH=$ROOT/sys/module/firmware_class/parameters/path
SYSFS=$ROOT/sys
NET=$SYSFS/class/net
MAX_RETRIES=3
plain() {
    case "$1" in /*) :;; *) return 1;; esac
    case "$1" in *[!a-zA-Z0-9_./:-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac
    local part=$1
    while [ "$part" != / ]; do [ ! -L "$part" ] || return 1; part=${part%/*}; [ -n "$part" ] || part=/; done
}
if [ -n "$ROOT" ]; then
    plain "$ROOT" && [ "$ROOT" != / ] && [ -d "$ROOT" ] && [ -x "$ADAPTER" ] || exit 1
else
    [ -z "$ADAPTER" ] || exit 1
    case "$(id)" in uid=0\(*) :;; *) echo 'dongle: root required' >&2; exit 1;; esac
    case "$BASE" in /data/*) :;; *) exit 1;; esac
fi
op() {
    if [ -n "$ROOT" ]; then "$ADAPTER" "$@"; return $?; fi
    case "$1" in
    boot-completed) getprop sys.boot_completed;;
    modules) cat /proc/modules;;
    insmod) insmod "$2";;
    sleep) sleep "$2";;
    sync) sync;;
    toast) ( /system/bin/am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$2" \
                --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true </dev/null >/dev/null 2>&1 & );;
    *) return 1;;
    esac
}
small() { local v=; [ -f "$1" ] && [ ! -L "$1" ] || return 1; IFS= read -r v < "$1" || [ -n "$v" ] || return 1; print -r -- "$v"; }
log() {
    local up rest line size
    { read -r up rest < "$ROOT/proc/uptime"; } 2>/dev/null || up='?'
    line="$up $*"
    print -r -- "dongle: $*"
    plain "$LOG" && plain "$LOG.1" || return 0
    mkdir -p "$LOGDIR" 2>/dev/null || return 0
    # The unit has no wc; the package helper reports the size (as bootguard.sh).
    if [ -f "$LOG" ]; then
        size=$("$BASE/bin/dex-patch" size "$LOG" 2>/dev/null) || size=0
        case "$size" in ''|*[!0-9]*) size=0;; esac
        [ "$size" -le 32768 ] || mv "$LOG" "$LOG.1" 2>/dev/null || return 0
    fi
    print -r -- "$line" >> "$LOG" 2>/dev/null || :
}
round() { # loop bound for fixtures only
    [ -n "$ROUNDS" ] || return 0
    [ "$ROUNDS" -gt 0 ] || return 1
    ROUNDS=$((ROUNDS - 1))
}

[ "$(small "$S/wifi-backend")" = dongle ] || exit 0
[ "$(small "$S/boot/enabled")" = 1 ] || { echo 'dongle: automatic startup is disabled'; exit 0; }
plain "$MODS/modules.alias" && plain "$MODS/modules.profile" && [ -f "$MODS/modules.alias" ] && [ -f "$MODS/modules.profile" ] || { log 'FAIL driver catalog missing'; exit 1; }
plain "$STATE" && plain "$MARK" && plain "$BLOCK" || exit 1
mkdir -p "$STATE" || exit 1

# Same match keys as wifi-backend.sh: interface modalias, then device IDs.
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
# Sets PROFILE_MODULES/PROFILE_FIRMWARE for a ready AP-capable profile with every file present.
profile() {
    local wanted=$1 driver modules firmware bands ap status item
    while IFS='|' read -r driver modules firmware bands ap status; do
        [ "$driver" = "$wanted" ] || continue
        [ "$status" = ready ] && [ "$ap" = yes ] && [ -n "$modules" ] || return 1
        for item in $modules; do plain "$MODS/$item.ko" && [ -f "$MODS/$item.ko" ] || return 1; done
        for item in $firmware; do plain "$FIRMWARE/$item" && [ -f "$FIRMWARE/$item" ] || return 1; done
        PROFILE_MODULES=$modules; PROFILE_FIRMWARE=$firmware
        return 0
    done < "$MODS/modules.profile"
    return 1
}
# Prints the driver for the first plugged-in supported dongle.
find_driver() {
    local list modalias kind pattern module
    list=$(usb_modaliases)
    while IFS= read -r modalias; do
        [ -n "$modalias" ] || continue
        while read -r kind pattern module; do
            [ "$kind" = alias ] || continue
            case "$modalias" in $pattern) profile "$module" && { print -r -- "$module"; return 0; };; esac
        done < "$MODS/modules.alias"
    done <<EOF
$list
EOF
    return 1
}
have_wlan() { [ -e "$NET/wlan0" ]; }
loaded() { # module file name without .ko; /proc/modules uses _ for -
    local name=${1//-/_}
    case "$NL$(op modules 2>/dev/null)" in *"$NL$name "*) return 0;; esac
    return 1
}
NL='
'
set_firmware_path() {
    local current
    plain "$FIRMWARE" && [ -d "$FIRMWARE" ] || { log 'FAIL firmware folder missing'; return 1; }
    [ -f "$FWPATH" ] || { log 'WARN kernel has no firmware_class.path; dongle firmware cannot load'; return 1; }
    current=$(small "$FWPATH") || current=
    [ "$current" = "$FIRMWARE" ] && return 0
    if [ -n "$current" ]; then log "WARN firmware_class.path already set to $current; left unchanged"; return 1; fi
    # No trailing newline: the 3.18 kernel stores the bytes as written.
    print -rn -- "$FIRMWARE" > "$FWPATH" 2>/dev/null && [ "$(small "$FWPATH")" = "$FIRMWARE" ] ||
        { log 'FAIL could not set firmware_class.path'; return 1; }
    log "firmware_class.path set"
}
load() {
    local driver mod n
    driver=$(find_driver) || return 1
    profile "$driver" || return 1
    # On disk before the first insmod (see the restart guard above).
    print -r -- loading > "$MARK" && op sync || { log 'FAIL restart guard mark not written; not loading'; return 1; }
    stable=0
    log "loading $driver"
    for mod in $PROFILE_MODULES; do
        loaded "$mod" && continue
        op insmod "$MODS/$mod.ko" || { log "FAIL insmod $mod for $driver"; rm -f "$MARK"; return 1; }
    done
    n=0
    while [ "$n" -lt 5 ]; do
        have_wlan && { log "wlan0 ready ($driver)"; return 0; }
        op sleep 1; n=$((n + 1))
    done
    log "FAIL no wlan0 after loading $driver"
    rm -f "$MARK"
    return 1
}

# Policy: the car boots as stock; driver modules load only after boot completed.
while [ "$(op boot-completed)" != 1 ]; do round || exit 0; op sleep 2; done
held=0
if [ -e "$MARK" ] || [ -L "$MARK" ]; then
    rm -f "$BLOCK"
    if print -r -- blocked > "$BLOCK"; then op sync; rm -f "$MARK"; else held=1; fi
    log 'BLOCKED the unit restarted while the dongle driver was loading; unplug the dongle to allow one more try'
    op toast 'USB Wi-Fi 동글 드라이버를 올리던 중 재시작되어 동글 사용을 멈췄습니다. 동글을 뽑았다 다시 꽂으면 한 번 다시 시도합니다.'
fi
set_firmware_path || :
fail_count=0; stable=0
while round; do
    present=0; find_driver >/dev/null && present=1
    # Unplugging the dongle clears the block; the next attachment tries once more.
    if [ "$present" = 0 ]; then
        fail_count=0
        if [ -e "$BLOCK" ] || [ "$held" = 1 ]; then
            [ "$held" = 0 ] || { rm -f "$MARK" && held=0; }
            rm -f "$BLOCK" && log 'dongle unplugged: loading allowed again'
        fi
    fi
    if [ -e "$MARK" ] && have_wlan; then
        stable=$((stable + 2))
        [ "$stable" -lt "$STABLE_SECONDS" ] || { rm -f "$MARK"; stable=0; }
    fi
    if have_wlan; then
        fail_count=0
    elif [ "$present" = 1 ] && [ "$held" = 0 ] && [ ! -e "$BLOCK" ] && [ "$fail_count" -lt "$MAX_RETRIES" ]; then
        if load; then fail_count=0; else fail_count=$((fail_count + 1)); fi
    fi
    op sleep 2
done
