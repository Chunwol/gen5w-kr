#!/system/bin/sh
# Background work yields the CPU to Android (zygote, system_server, stock apps);
# children inherit it. VM 2026-11-21: polling at normal priority starved a stock
# provider until the system_server watchdog reset the unit.
renice 10 $$ >/dev/null 2>&1
# In-car screen collector for the portable install (core app MainActivity,
# StatusModel, SwitchRequest). Root only writes the root-owned
# /data/nemesis/gen5wkr.ui (status, log) and root-owned markers in
# /data/nemesis; it only READS the app's request file and never writes into an
# app-owned folder. Portable journals are read without taking their locks, so
# this service can never block boot.sh, overlay.sh or runtime.sh. Restore and
# removal requests run only this package's own boot.sh disable.
umask 022
LC_ALL=C; export LC_ALL
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
BASE=$(CDPATH= cd -- "$BASE" && pwd) || exit 1
ROOT=${PORTABLE_TEST_ROOT:-}
ADAPTER=${PORTABLE_TEST_UI_ADAPTER:-}
HELPER=$BASE/bin/dex-patch
plain() {
    case "$1" in /*) :;; *) return 1;; esac
    case "$1" in *[!a-zA-Z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac
    local part=$1
    while [ "$part" != / ]; do [ ! -L "$part" ] || return 1; part=${part%/*}; [ -n "$part" ] || part=/; done
}
current_uid() { local line; line=$(id) || return 1; line=${line#uid=}; print -r -- "${line%%\(*}"; }
if [ -n "$ROOT" ]; then
    plain "$ROOT" && [ "$ROOT" != / ] && [ -d "$ROOT" ] && [ -x "$ADAPTER" ] || exit 1
    HELPER=${PORTABLE_TEST_HELPER:-$HELPER}
    OWNER_UID=$(current_uid) || exit 1
else
    [ -z "$ADAPTER" ] || exit 1
    case "$(id)" in uid=0\(*) :;; *) echo 'ui: real root shell required' >&2; exit 1;; esac
    case "$BASE" in /data/*) :;; *) exit 1;; esac
    OWNER_UID=0
fi
plain "$BASE" && plain "$HELPER" && [ -x "$HELPER" ] || exit 1
NEMDIR=$ROOT/data/nemesis
UI_DIR=$NEMDIR/gen5wkr.ui
PSTATE=$ROOT/data/local/gen5w-portable
APPDIR=$ROOT/data/data/kr.gen5w.core
REQUEST=$APPDIR/files/ui-request
HOST_READY=$ROOT/data/data/kr.gen5w.wirelesshost/files/bridge-ready
PRIV_STAGE=$PSTATE/.ui-stage
LOGDIR=$NEMDIR/logs/gen5w.kr.portable
BOOT_ID=$ROOT/proc/sys/kernel/random/boot_id
UPTIME=$ROOT/proc/uptime
MOUNTS=$ROOT/proc/mounts
NETDIR=$ROOT/sys/class/net
USB_MP=/storage/usb0
USB=$ROOT$USB_MP
WIRELESS_OFF=$NEMDIR/gen5wkr.ui-wireless-off
# Read by the bundled stock-warning timer and Bluelink reminder services.
TIMER_OFF=$NEMDIR/gen5wkr.ui-timer-off
BLUELINK_OFF=$NEMDIR/gen5wkr.ui-bluelink-off
DEBUG_ON=$NEMDIR/gen5wkr.debug-on
SAVED=$NEMDIR/gen5wkr.ui-portable-saved
REMOVED=$NEMDIR/gen5wkr.ui-portable-removed
RECOVERY=$NEMDIR/gen5wkr.ui-portable-recovery
ADBTOK=$NEMDIR/gen5wkr.ui-portable-adb
PPTOK=$NEMDIR/gen5wkr.ui-portable-pp
RLOCK=$NEMDIR/gen5wkr.ui-portable-restore
PPLOCK=$NEMDIR/gen5wkr.ui-portable-pp-lock
SPLIT_DEFAULT=$PSTATE/split-default-applied
WRAP_DIPO='/system/bin/sh /data/local/gen5w-portable/runtime-payload/wrap-dipo.sh'
WRAP_DIPO_PERSIST='W=/data/nemesis/apps/gen5w.kr.portable/wrap-dipo.sh;[ -f $W ]||W=;exec ${W:+sh $W}'
INTERVAL=${PORTABLE_UI_INTERVAL:-15}; case "$INTERVAL" in ''|*[!0-9]*) INTERVAL=15;; esac
REQ_STEP=2
MAX_REQUEST=256
MAX_LINES=200
MAX_LINE=200
PER_SOURCE=25
MAX_SOURCE_BYTES=131072
ERRORS_AT=-999
ERRORS_BOOT=
ERRORS_STATUS=ok
ERR_FILTER='Gen5w|gen5w|CarPlay|TccCarPlay|Iap2|iAP2|dipo|Dipo|Projection|FATAL EXCEPTION|AndroidRuntime|System\.err|AudioPolicy|AudioFlinger|audio_a2dp_hw|socket underrun'
# Lines that can carry personal data are dropped case-insensitively (aligned with diagnostics/usb-collect).
# Privacy filtering removed at the user's request (2026-11-26): logs keep every line.
PRIV='^G5W_NO_PRIVACY_FILTER_NEVER_MATCHES^'
op() {
    if [ -n "$ROOT" ]; then "$ADAPTER" "$@"; return $?; fi
    case "$1" in
    snapshot) "$HELPER" supervise 60 /system/bin/true /system/bin/sh "$2" active "$3";;
    errors) "$HELPER" supervise 8 /system/bin/true /system/bin/sh -c 'ulimit -f 4096; exec /system/bin/logcat -d -v time -t 250 -b main -b system "*:E" Gen5wCore:W Gen5wNavi:W Gen5wDiag:W Gen5wTrace:W Gen5wWireless:W TccCarPlay:W CarPlayService:W Iap2Service:W DipoService:W AudioFlinger:W AudioPolicyManager:W audio_a2dp_hw:W AndroidRuntime:E System.err:W';;
    get) getprop "$2";;
    settings-get) "$HELPER" supervise 15 /system/bin/true /system/bin/sh /system/bin/settings get system "$2";;
    settings-put) "$HELPER" supervise 15 /system/bin/true /system/bin/sh /system/bin/settings put system "$2" "$3";;
    broadcast-cp-split) "$HELPER" supervise 10 /system/bin/true /system/bin/sh /system/bin/am broadcast -a android.intent.action.daudio.connectivity.carplay.splitscreenview --ei STATE "$2";;
    restart-carplay)
        rcout=$("$HELPER" supervise 16 /system/bin/true /system/bin/sh /system/bin/am broadcast -p com.daudio.app.dipo -a kr.gen5w.dipo.RESTART_CARPLAY 2>&1) || return 1
        # Stock DipoService.java:6616 H(true) queues E()/bP()/nc(); acceptance is not completion.
        # 3 = observed replacement session; 4 = no session (stored setting used next connect).
        # The receiver waits up to 12 s (H(true), then one disconnect fallback if E() did not restart).
        case "$rcout" in *"result=3,"*|*"result=3"|*"result=4,"*|*"result=4") return 0;; *) return 1;; esac;;
    broadcast-pp-status)
        "$HELPER" supervise 10 /system/bin/true /system/bin/sh /system/bin/am broadcast -a "$2" --ez status "$3" &&
        "$HELPER" supervise 10 /system/bin/true /system/bin/sh /system/bin/am broadcast -a com_phoneprojection_status_change;;
    disable) /system/bin/sh "$2" disable;;
    sync) sync;;
    *) return 1;;
    esac
}
# ---- small, link-free reads ----
file_size() {
    local line size
    line=$(ls -l "$1" 2>/dev/null) || return 1
    set -- $line
    size=${5:-}
    case "$size" in ''|*[!0-9]*) size=${4:-};; esac
    case "$size" in ''|*[!0-9]*) return 1;; esac
    print -r -- "$size"
}
small() { # first line of a small regular non-link file
    local line size
    plain "$1" && [ -f "$1" ] || return 1
    size=$(file_size "$1") && [ "$size" -le 4096 ] || return 1
    IFS= read -r line < "$1" || [ -n "$line" ] || return 1
    print -r -- "$line"
}
word() { case "$1" in ''|*[!a-zA-Z0-9_.:-]*) print -r -- invalid;; *) print -r -- "${1:0:40}";; esac; }
uid_of() { local meta; meta=$("$HELPER" metadata "$1") || return 1; print -r -- "${meta%%\|*}"; }
root_dir() { plain "$1" && [ -d "$1" ] && [ "$(uid_of "$1")" = "$OWNER_UID" ]; }
boot_id() {
    local id
    id=$(small "$BOOT_ID") || return 1
    case "$id" in *[!0-9a-f-]*) return 1;; esac
    [ "${#id}" = 36 ] || return 1
    print -r -- "$id"
}
uptime_s() {
    local up rest
    IFS=' ' read -r up rest 2>/dev/null < "$UPTIME" || return 1
    up=${up%%.*}
    case "$up" in ''|*[!0-9]*) return 1;; esac
    [ "${#up}" -le 9 ] || return 1
    print -r -- "$((10#$up))"
}
process_key() {
    local pid=$1 line rest count=0
    case "$pid" in ''|*[!0-9]*) return 1;; esac
    [ -r "/proc/$pid/stat" ] && { IFS= read -r line < "/proc/$pid/stat"; } 2>/dev/null || return 1
    rest=${line##*) }; [ "$rest" != "$line" ] || return 1
    set -- $rest; [ "$#" -ge 20 ] || return 1
    case "$1" in Z|X|x) return 1;; esac
    while [ "$count" -lt 19 ]; do shift; count=$((count+1)); done
    print -r -- "$pid:$1"
}
prepare() {
    root_dir "$NEMDIR" || return 1
    [ ! -L "$UI_DIR" ] || return 1
    [ -e "$UI_DIR" ] || mkdir "$UI_DIR" || return 1
    root_dir "$UI_DIR" && chmod 755 "$UI_DIR" || return 1
    plain "$PRIV_STAGE" || return 1
    [ ! -L "$PRIV_STAGE" ] || return 1
    [ -e "$PRIV_STAGE" ] || mkdir -p "$PRIV_STAGE" || return 1
    root_dir "$PRIV_STAGE" && chmod 700 "$PRIV_STAGE" || return 1
    local f
    for f in status status.tmp log log.tmp notes notes.tmp request.copy diag.tmp diag-latest.txt restore.log restore.log.tmp errors.cache errors.cache.tmp; do
        [ ! -L "$UI_DIR/$f" ] || return 1
        [ ! -e "$UI_DIR/$f" ] || [ -f "$UI_DIR/$f" ] || return 1
    done
    rm -f "$UI_DIR/filter.tmp" "$UI_DIR/tail.tmp" "$UI_DIR/errors.raw" "$UI_DIR/errors.cap" "$UI_DIR/errors.match" 2>/dev/null || :
    for f in "$WIRELESS_OFF" "$SAVED" "$SAVED.tmp" "$REMOVED" "$REMOVED.tmp" "$RECOVERY" "$RECOVERY.tmp" "$ADBTOK" "$ADBTOK.tmp" "$PPTOK" "$PPTOK.tmp" "$RLOCK" "$PPLOCK"; do
        [ ! -L "$f" ] || return 1
    done
}
record() { # file "<number> <result> [detail]" in root-owned /data/nemesis
    [ ! -L "$1" ] && [ ! -L "$1.tmp" ] || return 1
    print -r -- "$2" > "$1.tmp" && mv "$1.tmp" "$1"
}
note() { # bounded own log lines, deduplicated against the newest
    local line last= n=0 keep
    [ ! -L "$UI_DIR/notes" ] && [ ! -L "$UI_DIR/notes.tmp" ] || return 0
    set -A keep
    if [ -f "$UI_DIR/notes" ]; then
        while IFS= read -r line; do keep[${#keep[*]}]=$line; last=$line; done < "$UI_DIR/notes"
    fi
    [ "$last" != "$1" ] || return 0
    keep[${#keep[*]}]=$1
    : > "$UI_DIR/notes.tmp" || return 0
    n=$(( ${#keep[*]} - 10 )); [ "$n" -ge 0 ] || n=0
    while [ "$n" -lt "${#keep[*]}" ]; do print -r -- "${keep[$n]:0:$MAX_LINE}" >> "$UI_DIR/notes.tmp"; n=$((n+1)); done
    chmod 644 "$UI_DIR/notes.tmp" && mv "$UI_DIR/notes.tmp" "$UI_DIR/notes"
}
# ---- portable state, read only ----
read_portable() {
    local previous epoch_boot epoch_key ready
    BOOT=$(boot_id) || BOOT=
    P_ENABLED=$(small "$PSTATE/boot/enabled") || P_ENABLED=
    P_PHASE=unknown
    if previous=$(small "$PSTATE/boot/attempt"); then P_PHASE=$(word "${previous#*\|}"); fi
    P_REASON=$(small "$PSTATE/boot/reason") && P_REASON=$(word "$P_REASON") || P_REASON=none
    P_MODE=$(small "$PSTATE/boot/runtime-mode") && P_MODE=$(word "$P_MODE") || P_MODE=none
    P_OVERLAY=$(small "$PSTATE/overlay/state") && P_OVERLAY=$(word "$P_OVERLAY") || P_OVERLAY=disabled
    P_RUNTIME=$(small "$PSTATE/runtime/phase") && P_RUNTIME=$(word "$P_RUNTIME") || P_RUNTIME=disabled
    OVERLAY_LIVE=0; RUNTIME_LIVE=0
    case "$P_OVERLAY" in applying|pending|committed|failed)
        [ -z "$BOOT" ] || [ "$(small "$PSTATE/overlay/boot")" != "$BOOT" ] || OVERLAY_LIVE=1;; esac
    case "$P_RUNTIME" in enabling|pending|committed|failed)
        [ -z "$BOOT" ] || [ "$(small "$PSTATE/runtime/boot")" != "$BOOT" ] || RUNTIME_LIVE=1;; esac
    P_SESSION=stopped
    if [ -r "$PSTATE/session/epoch" ] && { IFS='|' read -r epoch_boot epoch_key < "$PSTATE/session/epoch"; } 2>/dev/null && ready=$(small "$PSTATE/session/ready") &&
       [ -n "$BOOT" ] && [ "$epoch_boot" = "$BOOT" ] && [ "$ready" = "$epoch_boot|$epoch_key" ] &&
       [ "$(process_key "${epoch_key%%:*}")" = "$epoch_key" ] && plain "$PSTATE/session/epoch"; then P_SESSION=running; fi
}
host_alive() { # HostReadyMarker: pid, boot_id=<this boot>, starttime=<process key>
    local pid boot start extra size
    plain "$HOST_READY" && [ -f "$HOST_READY" ] && size=$(file_size "$HOST_READY") && [ "$size" -le 256 ] || return 1
    { IFS= read -r pid; IFS= read -r boot; IFS= read -r start; IFS= read -r extra && return 1; } < "$HOST_READY"
    [ -n "$BOOT" ] && [ "$boot" = "boot_id=$BOOT" ] || return 1
    start=${start#starttime=}
    case "$pid" in ''|*[!0-9]*) return 1;; esac
    case "$start" in ''|*[!0-9]*) return 1;; esac
    [ "$(process_key "$pid")" = "$pid:$start" ] || return 1
    grep -aq '^kr.gen5w.wirelesshost' "/proc/$pid/cmdline" 2>/dev/null
}
ap_blocked() { # what session.sh/ap.sh would refuse before starting the host
    local marker
    for marker in "$NEMDIR/gen5wkr.apguard.off" "$NEMDIR/gen5wkr.wireless-disabled"; do
        [ ! -e "$marker" ] && [ ! -L "$marker" ] || return 0
    done
    # Unfinished AP start evidence; a live host's own current attempt is not a failure.
    [ "$host" != alive ] || return 1
    for marker in "$NEMDIR/gen5wkr.apguard/attempt" "$ROOT/data/data/kr.gen5w.wirelesshost/files/ap-attempt"; do
        [ ! -e "$marker" ] && [ ! -L "$marker" ] || return 0
    done
    return 1
}
restore_live() { # worker lock: "<boot>|<pid:starttime>"
    local owner_boot owner_key
    [ -d "$RLOCK" ] && [ ! -L "$RLOCK" ] || return 1
    [ -r "$RLOCK/owner" ] && { IFS='|' read -r owner_boot owner_key < "$RLOCK/owner"; } 2>/dev/null || return 0
    [ "$owner_boot" = "$BOOT" ] && [ "$(process_key "${owner_key%%:*}")" = "$owner_key" ]
}
pp_live() { # worker lock: "<boot>|<pid:starttime>"
    local owner_boot owner_key
    [ -d "$PPLOCK" ] && [ ! -L "$PPLOCK" ] && [ -f "$PPLOCK/owner" ] && [ ! -L "$PPLOCK/owner" ] || return 1
    { IFS='|' read -r owner_boot owner_key < "$PPLOCK/owner"; } 2>/dev/null || return 1
    [ -n "$owner_boot" ] && [ -n "$owner_key" ] || return 1
    [ "$owner_boot" = "$BOOT" ] && [ "$(process_key "${owner_key%%:*}")" = "$owner_key" ]
}
pair() { # "<number>:<result>[:detail]" from a record file, or 0:none
    local n r d
    [ -f "$1" ] && [ ! -L "$1" ] && IFS=' ' read -r n r d < "$1"
    case "$n" in ''|*[!0-9]*) n=0;; esac
    [ "${#n}" -le 10 ] || n=0
    r=$(word "${r:-none}"); d=${d:+$(word "$d")}
    if [ "$r" = working ]; then
        if [ "$1" = "$PPTOK" ]; then
            pp_live || { r=failed; d=interrupted; }
        elif ! restore_live && [ "$1" != "$SAVED" ]; then
            r=failed; d=interrupted
        fi
    fi
    print -r -- "$n:$r${d:+:$d}"
}
recovery_status() {
    local state=none available=no reason=unknown token result
    token=$(pair "$RECOVERY"); result=${token#*:}; token=${token%%:*}; result=${result%%:*}
    case "$result" in none|working|restored|failed|interrupted) :;; *) result=failed;; esac
    [ "$result" != failed ] || [ "$(pair "$RECOVERY")" != "$token:failed:interrupted" ] || result=interrupted
    if restore_live; then state=working; reason=busy
    elif [ "$P_ENABLED" != 1 ] && { [ "$OVERLAY_LIVE" = 1 ] || [ "$RUNTIME_LIVE" = 1 ]; }; then
        # Auto-start is off, yet owned overlays or wrappers of this boot remain.
        state=required; reason=runner-unavailable
        if plain "$BASE/boot.sh" && [ -f "$BASE/boot.sh" ]; then available=yes; reason=ready; fi
        [ "$result" != interrupted ] || reason=interrupted
    elif [ "$result" = restored ]; then state=restored
    fi
    echo "recovery_state=$state"
    echo "recovery_available=$available"
    echo "recovery_reason=$reason"
    echo "recovery_stage=unknown"
    echo "recovery_request=$token"
    echo "recovery_result=$result"
}
collect_status() {
    local ts relay=unknown apguard=on wired=no version= line wlan=missing backend dongle why dipo_wrap tmp="$UI_DIR/status.tmp"
    ts=$(uptime_s) || ts=
    read_portable
    host=dead; host_alive && host=alive
    # Wireless relay is truthfully "on" only with the owned DiPO wrapper live this boot.
    dipo_wrap=$(op get wrap.com.daudio.app.dipo)
    if [ "$P_REASON" = persistent-start-ready ] && [ "$dipo_wrap" = "$WRAP_DIPO_PERSIST" ]; then relay=on
    elif [ "$P_MODE" = static ] || [ "$P_RUNTIME" = disabled ] || [ "$RUNTIME_LIVE" = 0 ]; then relay=off
    elif [ "$P_RUNTIME" = committed ] && [ "$dipo_wrap" = "$WRAP_DIPO" ]; then relay=on; fi
    # The screen cannot start a disabled or runtime-less install: show the switch locked.
    if [ "$P_ENABLED" != 1 ] || [ "$P_MODE" = static ] || ap_blocked; then apguard=off; fi
    [ ! -e "$NEMDIR/gen5wkr.wireless-disabled" ] || wired=yes
    if plain "$BASE/NEMESIS.data" && [ -f "$BASE/NEMESIS.data" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in package-version=*) version=$(word "${line#package-version=}");; esac
        done < "$BASE/NEMESIS.data"
    fi
    [ -d "$NETDIR/wlan0" ] && wlan=present
    # Chosen at install (wifi-backend.sh); earlier installs have no record.
    backend=$(small "$PSTATE/wifi-backend") || backend=unknown
    case "$backend" in builtin|dongle|none) :;; *) backend=unknown;; esac
    # The dongle service's state counts only when written during this boot.
    dongle=unknown
    if [ "$backend" = dongle ]; then
        line=$(small "$PSTATE/dongle/status") || line=
        case "$line" in
        "$BOOT|ready"|"$BOOT|waiting"|"$BOOT|loading"|"$BOOT|failed"|"$BOOT|blocked"|"$BOOT|2g") dongle=${line#*'|'};;
        esac
    fi
    why=none
    [ "$(small "$PSTATE/wifi-backend-why")" != 2g-only ] || why=2g-only
    {
        print -r -- "ts=$ts"
        print -r -- "boot=$BOOT"
        print -r -- "host=$host"
        print -r -- "relay=$relay"
        print -r -- "backend=$backend"
        print -r -- "dongle=$dongle"
        print -r -- "wifi_why=$why"
        print -r -- "version=$version"
        if plain "$DEBUG_ON" && [ -f "$DEBUG_ON" ]; then print -r -- 'sw_debug=on'; else print -r -- 'sw_debug=off'; fi
        print -r -- "apguard=$apguard"
        print -r -- "wired=$wired"
        if [ -e "$WIRELESS_OFF" ]; then print -r -- "sw_wireless=off"; else print -r -- "sw_wireless=on"; fi
        if [ -e "$TIMER_OFF" ]; then print -r -- "sw_timer=off"; else print -r -- "sw_timer=on"; fi
        if [ -e "$BLUELINK_OFF" ]; then print -r -- "sw_bluelink=off"; else print -r -- "sw_bluelink=on"; fi
        # Not managed by the portable install: reported as unknown, never as a state.
        print -r -- "sw_adb=unknown"
        print -r -- "adb_health=unknown"
        print -r -- "adb_result=$(pair "$ADBTOK")"
        print -r -- "pp_result=$(pair "$PPTOK")"
        print -r -- "saved=$(pair "$SAVED")"
        print -r -- "removed=$(pair "$REMOVED")"
        print -r -- "wlan=$wlan"
        recovery_status
        print -r -- "portable_enabled=$(word "${P_ENABLED:-0}")"
        print -r -- "portable_phase=$P_PHASE"
        print -r -- "portable_reason=$P_REASON"
        print -r -- "portable_mode=$P_MODE"
        print -r -- "portable_overlay=$P_OVERLAY"
        print -r -- "portable_runtime=$P_RUNTIME"
        print -r -- "portable_session=$P_SESSION"
    } > "$tmp" || return 1
    chmod 644 "$tmp" && mv "$tmp" "$UI_DIR/status"
}
# ---- bounded, privacy-filtered log ----
emit_tail() { # source keep file
    local total=0 skip line
    while IFS= read -r line || [ -n "$line" ]; do total=$((total + 1)); done < "$3"
    skip=$((total - $2))
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$skip" -gt 0 ]; then skip=$((skip - 1)); continue; fi
        [ "$NLOG" -lt "$MAX_LINES" ] || return 0
        print -r -- "$1|${line:0:$MAX_LINE}" >> "$UI_DIR/log.tmp"
        NLOG=$((NLOG + 1))
    done < "$3"
}
drop_unterminated_last() { # reads stdin; drops trailing line lacking '\n'
    local line
    while IFS= read -r line; do
        print -r -- "$line"
    done
}
refresh_errors() {
    local now rc=0 op_rc=0 raw_size=0 skip=0 discard
    now=$(uptime_s) || return 0
    if [ "$ERRORS_BOOT" = "$BOOT" ] && [ -f "$UI_DIR/errors.cache" ] && [ "$now" -ge "$ERRORS_AT" ] && [ "$((now - ERRORS_AT))" -lt 60 ]; then
        return 0
    fi
    plain "$PRIV_STAGE/errors.raw" && plain "$PRIV_STAGE/errors.cap" && plain "$PRIV_STAGE/errors.trim" && plain "$PRIV_STAGE/errors.match" && plain "$UI_DIR/errors.cache.tmp" && plain "$UI_DIR/errors.cache" || return 1
    ( umask 077; op errors > "$PRIV_STAGE/errors.raw" 2>/dev/null ); op_rc=$?
    if [ "$op_rc" -ne 0 ]; then
        rm -f "$PRIV_STAGE/errors.raw"
        ERRORS_STATUS=failed
        return 1
    fi
    raw_size=$(file_size "$PRIV_STAGE/errors.raw") || raw_size=0
    if [ "$raw_size" -gt "$MAX_SOURCE_BYTES" ]; then
        skip=$(( (raw_size - MAX_SOURCE_BYTES + 4095) / 4096 ))
        ( umask 077
          dd if="$PRIV_STAGE/errors.raw" of="$PRIV_STAGE/errors.cap" bs=4096 skip="$skip" count=32 2>/dev/null || :
          { IFS= read -r discard; drop_unterminated_last; } < "$PRIV_STAGE/errors.cap" > "$PRIV_STAGE/errors.trim"
        )
    else
        ( umask 077; drop_unterminated_last < "$PRIV_STAGE/errors.raw" > "$PRIV_STAGE/errors.trim" 2>/dev/null ) || ( umask 077; : > "$PRIV_STAGE/errors.trim" )
    fi
    rm -f "$PRIV_STAGE/errors.raw" "$PRIV_STAGE/errors.cap"
    ( umask 077; grep -a -i -E "$ERR_FILTER" "$PRIV_STAGE/errors.trim" > "$PRIV_STAGE/errors.match" 2>/dev/null ); rc=$?
    rm -f "$PRIV_STAGE/errors.trim"
    if [ "$rc" -le 1 ]; then
        grep -a -i -v -E "$PRIV" "$PRIV_STAGE/errors.match" > "$UI_DIR/errors.cache.tmp" 2>/dev/null; rc=$?
        [ "$rc" -le 1 ] || : > "$UI_DIR/errors.cache.tmp"
    else
        : > "$UI_DIR/errors.cache.tmp"
    fi
    rm -f "$PRIV_STAGE/errors.match"
    chmod 644 "$UI_DIR/errors.cache.tmp" && mv "$UI_DIR/errors.cache.tmp" "$UI_DIR/errors.cache"
    ERRORS_STATUS=ok
    ERRORS_AT=$now
    ERRORS_BOOT=$BOOT
}
collect_file() { # file source keep
    local size skip=0 src=$1 rc=0 discard flt="$PRIV_STAGE/filter.tmp" tail="$PRIV_STAGE/tail.tmp" trim="$PRIV_STAGE/trim.tmp"
    plain "$1" && [ -f "$1" ] && plain "$flt" && plain "$tail" && plain "$trim" || return 0
    [ "$NLOG" -lt "$MAX_LINES" ] || return 0
    size=$(file_size "$1") || return 0
    if [ "$size" -gt "$MAX_SOURCE_BYTES" ]; then
        skip=$(( (size - MAX_SOURCE_BYTES + 4095) / 4096 ))
        ( umask 077
          dd if="$1" of="$tail" bs=4096 skip="$skip" count=32 2>/dev/null || exit 1
          { IFS= read -r discard; drop_unterminated_last; } < "$tail" > "$trim"
        ) || { rm -f "$tail" "$trim"; return 0; }
    else
        ( umask 077; drop_unterminated_last < "$1" > "$trim" 2>/dev/null ) || { rm -f "$trim"; return 0; }
    fi
    src=$trim
    ( umask 077; grep -a -i -v -E "$PRIV" "$src" > "$flt" 2>/dev/null ); rc=$?
    [ "$rc" -le 1 ] || : > "$flt"
    rm -f "$tail" "$trim"
    emit_tail "$2" "$3" "$flt"
    rm -f "$flt"
}
collect_log() {
    local file nl="$NEMDIR/nemesis.log" size rc=0 nem="$PRIV_STAGE/nem.match" ntrim="$PRIV_STAGE/nem.trim" flt="$PRIV_STAGE/filter.tmp"
    NLOG=0
    : > "$UI_DIR/log.tmp" || return 1
    print -r -- "boot|enabled=$(word "${P_ENABLED:-0}") phase=$P_PHASE reason=$P_REASON mode=$P_MODE" >> "$UI_DIR/log.tmp"
    print -r -- "boot|overlay=$P_OVERLAY runtime=$P_RUNTIME session=$P_SESSION host=$host" >> "$UI_DIR/log.tmp"
    NLOG=2
    collect_file "$PSTATE/boot/health-lost" error 5
    refresh_errors || :
    collect_file "$UI_DIR/errors.cache" error 30
    if [ "$ERRORS_STATUS" = failed ] && [ "$NLOG" -lt "$MAX_LINES" ]; then
        print -r -- "ui|FAIL error log collector failed" >> "$UI_DIR/log.tmp"
        NLOG=$((NLOG + 1))
    fi
    collect_file "$UI_DIR/notes" ui 15
    collect_file "$UI_DIR/restore.log" restore 30
    if plain "$LOGDIR" && [ -d "$LOGDIR" ]; then
        for file in "$LOGDIR"/*.log; do collect_file "$file" portable "$PER_SOURCE"; done
    fi
    if plain "$nl" && [ -f "$nl" ] && size=$(file_size "$nl") && [ "$size" -le 1048576 ] && [ "$NLOG" -lt "$MAX_LINES" ]; then
        plain "$nem" && plain "$ntrim" && plain "$flt" || { rm -f "$PRIV_STAGE"/*; return 1; }
        ( umask 077; drop_unterminated_last < "$nl" > "$ntrim" 2>/dev/null ) || ( umask 077; : > "$ntrim" )
        ( umask 077; grep -a -E 'gen5w\.kr\.portable|boot:|session:|runtime:|overlay:|portable:' "$ntrim" > "$nem" 2>/dev/null ); rc=$?
        rm -f "$ntrim"
        if [ "$rc" -le 1 ]; then
            ( umask 077; grep -a -i -v -E "$PRIV" "$nem" > "$flt" 2>/dev/null ); rc=$?
            [ "$rc" -le 1 ] || : > "$flt"
        else
            ( umask 077; : > "$flt" )
        fi
        rm -f "$nem"
        emit_tail nemesis 40 "$flt"
    fi
    rm -f "$PRIV_STAGE"/*
    chmod 644 "$UI_DIR/log.tmp" && mv "$UI_DIR/log.tmp" "$UI_DIR/log"
}
# ---- requests: authenticated envelope, bounded hostile read ----
copy_request() { # background: at most 10 lines, each re-bounded
    local line n=0
    : > "$UI_DIR/request.copy" || exit 1
    while IFS= read -r line; do
        n=$((n + 1)); [ "$n" -le 10 ] || exit 1
        print -r -- "${line:0:$MAX_REQUEST}" >> "$UI_DIR/request.copy"
    done < "$REQUEST"
}
apply_requests() {
    local meta app size before after rpid waited=0 uid mode
    # Nothing to do without a request: skip the checks below on idle polls
    # (helper and chmod calls every 2 s kept a slow unit busy).
    [ -f "$REQUEST" ] || return 0
    # Every root-owned output (UI folder, markers, records) is checked first.
    prepare && plain "$REQUEST" && [ -f "$REQUEST" ] || return 0
    # Only the core app may author it: same owner as its data folder, not root,
    # and no group/other write permission.
    meta=$("$HELPER" metadata "$REQUEST") && app=$(uid_of "$APPDIR") || return 0
    uid=${meta%%\|*}; mode=${meta##*\|}
    [ "$uid" = "$app" ] || return 0
    [ -n "$ROOT" ] || [ "$uid" != 0 ] || return 0
    case "$mode" in *[2367]?|*[2367]) return 0;; esac
    size=$(file_size "$REQUEST") && [ "$size" -le "$MAX_REQUEST" ] || return 0
    before=$("$HELPER" identity "$REQUEST") || return 0
    rm -f "$UI_DIR/request.copy"
    copy_request & rpid=$!
    while kill -0 "$rpid" 2>/dev/null && [ "$waited" -lt 3 ]; do sleep 1; waited=$((waited + 1)); done
    if kill -0 "$rpid" 2>/dev/null; then kill "$rpid" 2>/dev/null; wait "$rpid" 2>/dev/null; rm -f "$UI_DIR/request.copy"; return 0; fi
    wait "$rpid" || { rm -f "$UI_DIR/request.copy"; return 0; }
    after=$("$HELPER" identity "$REQUEST") || { rm -f "$UI_DIR/request.copy"; return 0; }
    [ "$before" = "$after" ] && size=$(file_size "$UI_DIR/request.copy") && [ "$size" -le "$MAX_REQUEST" ] || { rm -f "$UI_DIR/request.copy"; return 0; }
    handle_request
    rm -f "$UI_DIR/request.copy"
}
handle_request() {
    local line key value boot= expires= wireless= timer= bluelink= debug= adb= pp= pptok= pp_rest= save= remove= recovery= up count=0
    while IFS= read -r line; do
        key=${line%%=*}; value=${line#*=}
        [ "$key" != "$line" ] || return 0
        case "$key" in
        boot) [ -z "$boot" ] && [ -n "$value" ] || return 0; boot=$value;;
        expires) [ -z "$expires" ] && [ -n "$value" ] || return 0; expires=$value;;
        wireless|timer|bluelink|debug)
            case "$value" in on|off) :;; *) return 0;; esac
            eval "[ -z \"\$$key\" ]" || return 0
            eval "$key=\$value";;
        adb) [ -z "$adb" ] || return 0
            case "$value" in on:*|off:*) :;; *) return 0;; esac
            case "${value#*:}" in ''|*[!0-9]*) return 0;; esac
            [ "${#value}" -le 14 ] || return 0; adb=$value;;
        pp) [ -z "$pp" ] || return 0
            case "$value" in
            cp_split:on:*|cp_split:off:*|aa_split:on:*|aa_split:off:*|cp_enable:on:*|cp_enable:off:*|aa_enable:on:*|aa_enable:off:*|cp_rhd:on:*|cp_rhd:off:*) :;;
            *) return 0;;
            esac
            pp_rest=${value#*:}
            pptok=${pp_rest#*:}
            case "$pptok" in ''|*[!0-9]*) return 0;; esac
            [ "${#pptok}" -le 10 ] || return 0
            pp=$value;;
        save|remove|recovery)
            case "$value" in ''|*[!0-9]*) return 0;; esac
            [ "${#value}" -le 10 ] || return 0
            eval "[ -z \"\$$key\" ]" || return 0
            eval "$key=\$value";;
        *) return 0;;
        esac
        count=$((count + 1))
    done < "$UI_DIR/request.copy"
    # Same envelope as the core collector: this boot, deadline within 30 s.
    [ -n "$BOOT" ] && [ "$boot" = "$BOOT" ] || return 0
    case "$expires" in ''|*[!0-9]*) return 0;; esac
    [ "${#expires}" -le 9 ] || return 0
    up=$(uptime_s) || return 0
    expires=$((10#$expires))
    [ "$expires" -ge "$up" ] && [ "$expires" -le "$((up + 30))" ] || return 0
    read_portable
    if [ -n "$debug" ]; then
        [ "$count" = 3 ] && plain "$DEBUG_ON" && { [ ! -e "$DEBUG_ON" ] || [ -f "$DEBUG_ON" ]; } || return 0
        if [ "$debug" = on ]; then
            if [ ! -e "$DEBUG_ON" ]; then
                plain "$PSTATE/debug" && mkdir -p "$PSTATE/debug" && plain "$PSTATE/debug/focus-reset" && { [ ! -e "$PSTATE/debug/focus-reset" ] || [ -f "$PSTATE/debug/focus-reset" ]; } && : > "$PSTATE/debug/focus-reset" || return 0
            fi
            : > "$DEBUG_ON" && chmod 644 "$DEBUG_ON"
        else
            rm -f "$DEBUG_ON"
        fi
        return 0
    fi
    if [ -n "$recovery" ]; then
        [ "$count" = 3 ] || return 0
        start_restore recovery "$recovery"; return 0
    fi
    if [ -n "$remove" ]; then start_restore remove "$remove"; return 0; fi
    if [ -n "$pp" ]; then
        [ "$count" = 3 ] || return 0
        if restore_live; then
            local pp_rest=${pp#*:}
            record "$PPTOK" "${pp_rest#*:} failed busy" || :
            return 0
        fi
        start_pp "$pp"; return 0
    fi
    [ -z "$save" ] || start_save "$save"
    if [ -n "$wireless" ] && ! restore_live && [ ! -L "$WIRELESS_OFF" ]; then
        if [ "$wireless" = off ]; then [ -f "$WIRELESS_OFF" ] || : > "$WIRELESS_OFF"; else rm -f "$WIRELESS_OFF"; fi
    fi
    if [ -n "$timer" ] && [ ! -L "$TIMER_OFF" ]; then
        if [ "$timer" = off ]; then [ -f "$TIMER_OFF" ] || : > "$TIMER_OFF"; else rm -f "$TIMER_OFF"; fi
    fi
    if [ -n "$bluelink" ] && [ ! -L "$BLUELINK_OFF" ]; then
        if [ "$bluelink" = off ]; then [ -f "$BLUELINK_OFF" ] || : > "$BLUELINK_OFF"; else rm -f "$BLUELINK_OFF"; fi
    fi
    if [ -n "$adb" ]; then
        local last rest
        [ -f "$ADBTOK" ] && IFS=' ' read -r last rest < "$ADBTOK"
        if [ "$last" != "${adb#*:}" ]; then
            record "$ADBTOK" "${adb#*:} unsupported" || :
            note 'UNSUPPORTED Wi-Fi adb request ignored: adb is not changed by the portable install'
        fi
    fi
}
# ---- own restore: this package's boot.sh disable, never anything else ----
start_restore() { # kind number
    local kind=$1 n=$2 file last rest
    case "$kind" in remove) file=$REMOVED;; recovery) file=$RECOVERY;; *) return 0;; esac
    [ -f "$file" ] && IFS=' ' read -r last rest < "$file"
    [ "$last" != "$n" ] || return 0
    if pp_live; then record "$file" "$n failed busy"; return 0; fi
    if [ "$kind" = recovery ]; then
        # Offered only while auto-start is off with owned changes still live.
        [ "$(recovery_status | grep -x 'recovery_available=yes')" = recovery_available=yes ] || return 0
    fi
    restore_worker "$kind" "$n" "$file" &
}
restore_worker() {
    local kind=$1 n=$2 file=$3 key boot=$BOOT rc=0 self
    # This worker's own pid: the redirect is opened by this process itself (a
    # command substitution would name a short-lived child instead).
    IFS= read -r self < /proc/self/stat || exit 0
    key=$(process_key "${self%% *}") || exit 0
    if ! mkdir "$RLOCK" 2>/dev/null; then
        if restore_live; then record "$file" "$n failed busy"; exit 0; fi
        [ ! -L "$RLOCK" ] && [ -d "$RLOCK" ] || exit 0
        rm -f "$RLOCK/owner"; rmdir "$RLOCK" && mkdir "$RLOCK" || { record "$file" "$n failed busy"; exit 0; }
    fi
    print -r -- "$boot|$key" > "$RLOCK/owner" || { rmdir "$RLOCK"; exit 0; }
    trap 'rm -f "$RLOCK/owner"; rmdir "$RLOCK" 2>/dev/null' EXIT
    if pp_live; then record "$file" "$n failed busy"; exit 0; fi
    record "$file" "$n working gen5w.kr.portable" || exit 0
    if plain "$BASE/boot.sh" && [ -f "$BASE/boot.sh" ]; then
        op disable "$BASE/boot.sh" > "$UI_DIR/restore.log.tmp" 2>&1 || rc=1
        chmod 644 "$UI_DIR/restore.log.tmp" && mv "$UI_DIR/restore.log.tmp" "$UI_DIR/restore.log"
    else rc=1
    fi
    if [ "$rc" = 0 ]; then
        if [ "$kind" = remove ]; then record "$file" "$n done"; else record "$file" "$n restored"; fi
    else record "$file" "$n failed boot-disable"
    fi
}
# ---- projection settings: stock PhoneProjection Settings.System keys ----
put_profiles() {
    local k=$1 v=$2
    op settings-put "$k" "$v" >/dev/null 2>&1 &&
    op settings-put "${k}_dr1" "$v" >/dev/null 2>&1 &&
    op settings-put "${k}_dr2" "$v" >/dev/null 2>&1
}
sync_split_profile() {
    local suf=$1 other_base=$2 shared=$3 other
    if [ "$shared" = 0 ]; then
        other=$(op settings-get "${other_base}${suf}" 2>/dev/null) || return 1
        [ "$other" != 1 ] || shared=1
    fi
    op settings-put "phoneprojection_setting_use_split_screen${suf}" "$shared" >/dev/null 2>&1
}
ensure_default_split() {
    [ ! -e "$SPLIT_DEFAULT" ] && [ ! -L "$SPLIT_DEFAULT" ] && [ ! -L "$SPLIT_DEFAULT.tmp" ] || return 0
    restore_live && return 0
    [ -n "$ROOT" ] || [ "$(getprop sys.boot_completed 2>/dev/null)" = 1 ] || return 0
    if put_profiles carplay_ss_osd 1 &&
       put_profiles androidauto_ss_osd 1 &&
       put_profiles phoneprojection_setting_use_split_screen 1; then
        op broadcast-cp-split 1 >/dev/null 2>&1 || :
        ( umask 022; print -r -- 1 > "$SPLIT_DEFAULT.tmp" && mv "$SPLIT_DEFAULT.tmp" "$SPLIT_DEFAULT" ) 2>/dev/null || rm -f "$SPLIT_DEFAULT.tmp"
    fi
}
start_pp() { # key:state:token
    local key=${1%%:*} rest=${1#*:} state token last unused waited=0
    state=${rest%%:*}; token=${rest#*:}
    [ -f "$PPTOK" ] && IFS=' ' read -r last unused < "$PPTOK"
    [ "$last" != "$token" ] || return 0
    if ! mkdir "$PPLOCK" 2>/dev/null; then
        if pp_live; then record "$PPTOK" "$token failed busy"; return 0; fi
        [ ! -L "$PPLOCK" ] && [ -d "$PPLOCK" ] || return 0
        rm -f "$PPLOCK/owner" "$PPLOCK/owner.tmp"; rmdir "$PPLOCK" && mkdir "$PPLOCK" || { record "$PPTOK" "$token failed busy"; return 0; }
    fi
    record "$PPTOK" "$token working" || { rmdir "$PPLOCK" 2>/dev/null; return 0; }
    pp_worker "$key" "$state" "$token" &
    # Wait briefly until the worker records its owner identity or finishes, avoiding a false interrupted status on round().
    while [ -d "$PPLOCK" ] && [ ! -f "$PPLOCK/owner" ] && [ "$waited" -lt 20 ]; do sleep .05; waited=$((waited + 1)); done
}
# One stock configuration request; supervise bounds the receiver's state observation.
restart_cp() {
    op restart-carplay "$1" >/dev/null 2>&1
}
pp_worker() {
    local key=$1 state=$2 token=$3 boot=$BOOT val=0 bval=false ok=1 self owner_key
    [ "$state" != on ] || { val=1; bval=true; }
    IFS= read -r self < /proc/self/stat || { rmdir "$PPLOCK" 2>/dev/null; exit 0; }
    owner_key=$(process_key "${self%% *}") || { rmdir "$PPLOCK" 2>/dev/null; exit 0; }
    [ ! -L "$PPLOCK/owner.tmp" ] && [ ! -L "$PPLOCK/owner" ] &&
    print -r -- "$boot|$owner_key" > "$PPLOCK/owner.tmp" && mv "$PPLOCK/owner.tmp" "$PPLOCK/owner" || {
        rm -f "$PPLOCK/owner.tmp" 2>/dev/null; rmdir "$PPLOCK" 2>/dev/null; exit 0
    }
    trap 'rm -f "$PPLOCK/owner" "$PPLOCK/owner.tmp"; rmdir "$PPLOCK" 2>/dev/null' EXIT
    if restore_live; then record "$PPTOK" "$token failed busy"; exit 0; fi
    case "$key" in
    cp_split)
        if put_profiles carplay_ss_osd "$val" &&
           sync_split_profile "" androidauto_ss_osd "$val" &&
           sync_split_profile _dr1 androidauto_ss_osd "$val" &&
           sync_split_profile _dr2 androidauto_ss_osd "$val"; then
            # Stock PhoneProjection d.java:318-324 broadcasts the newly stored split value.
            op broadcast-cp-split "$val" >/dev/null 2>&1 || :
            restart_cp "$val" || ok=0
        else ok=0; fi;;
    aa_split)
        if put_profiles androidauto_ss_osd "$val" &&
           sync_split_profile "" carplay_ss_osd "$val" &&
           sync_split_profile _dr1 carplay_ss_osd "$val" &&
           sync_split_profile _dr2 carplay_ss_osd "$val"; then :
        else ok=0; fi;;
    cp_enable)
        if put_profiles carplay_information "$val"; then
            op broadcast-pp-status android.intent.action.daudio.connectivity.carplay.statuschanged "$bval" >/dev/null 2>&1 || :
        else ok=0; fi;;
    aa_enable)
        if put_profiles androidauto_information "$val"; then
            op broadcast-pp-status android.intent.action.daudio.connectivity.androidauto.statuschanged "$bval" >/dev/null 2>&1 || :
        else ok=0; fi;;
    cp_rhd)
        if put_profiles carplya_rhd "$val"; then
            restart_cp "" || ok=0
        else ok=0; fi;;
    *) ok=0;;
    esac
    if [ "$ok" = 1 ]; then
        record "$PPTOK" "$token ok" || :
    else
        record "$PPTOK" "$token failed" || :
        note "FAIL projection setting $key=$state"
    fi
}
# ---- diagnosis: status + log only, to a verified FAT/fuse USB mount ----
usb_ok() {
    local src mp fs rest
    # /proc/mounts -> self/mounts is the kernel's normal trusted alias.
    if [ -L "$MOUNTS" ]; then
        [ "$(readlink "$MOUNTS")" = self/mounts ] || return 1
        [ -z "$ROOT" ] || plain "$ROOT/proc/self/mounts" || return 1
    else plain "$MOUNTS" || return 1; fi
    [ -f "$MOUNTS" ] || return 1
    while IFS=' ' read -r src mp fs rest; do
        [ "$mp" = "$USB_MP" ] || continue
        case "$fs" in vfat|exfat|texfat|sdfat|fuse) plain "$USB" && [ -d "$USB" ]; return $?;; esac
        return 1
    done < "$MOUNTS"
    return 1
}
start_save() {
    local n=$1 last rest
    [ -f "$SAVED" ] && IFS=' ' read -r last rest < "$SAVED"
    [ "$last" != "$n" ] || return 0
    local owner_boot owner_key
    if plain "$UI_DIR/save-worker" && [ -f "$UI_DIR/save-worker" ]; then
        IFS='|' read -r owner_boot owner_key < "$UI_DIR/save-worker"
        if [ "$owner_boot" = "$BOOT" ] && [ "$(process_key "${owner_key%%:*}")" = "$owner_key" ]; then return 0; fi
    fi
    record "$SAVED" "$n working" || return 0
    do_save "$n" &
    local worker=$! key
    key=$(process_key "$worker") && record "$UI_DIR/save-worker" "$BOOT|$key"
}
do_save() {
    local n=$1 result=nousb dest tmp="$UI_DIR/diag.tmp" f
    if plain "$BASE/diagnostics.sh" && [ -f "$BASE/diagnostics.sh" ]; then
        op snapshot "$BASE/diagnostics.sh" "$n" || note 'active diagnosis incomplete; partial files retained'
    fi
    {
        print -r -- "Gen5W KR portable diagnosis #$n"
        for f in status log; do
            print -r -- "===== $f"
            plain "$UI_DIR/$f" && [ -f "$UI_DIR/$f" ] && grep -a -i -v -E "$PRIV" "$UI_DIR/$f"
        done
    } > "$tmp" 2>/dev/null || { rm -f "$tmp"; record "$SAVED" "$n fail"; exit 0; }
    chmod 644 "$tmp" && mv "$tmp" "$UI_DIR/diag-latest.txt" || { record "$SAVED" "$n fail"; exit 0; }
    # Keep the previous save attempts across reboots, bounded to 32 reports.
    local archive="$UI_DIR/diagnostics" archived=0 item
    if plain "$archive" && { [ -d "$archive" ] || mkdir "$archive"; }; then
        for item in "$archive"/diag-*.txt; do [ ! -f "$item" ] || archived=$((archived+1)); done
        if [ "$archived" -lt 32 ]; then
            item="$archive/diag-$(cat "$BOOT_ID")-$n.txt"
            plain "$item" && [ ! -e "$item" ] && ( set -C; cat "$UI_DIR/diag-latest.txt" > "$item" ) 2>/dev/null || :
        fi
    fi
    if usb_ok; then
        dest=$USB/gen5w-kr-diag
        if [ ! -L "$dest" ] && mkdir -p "$dest" 2>/dev/null && plain "$dest" &&
           [ ! -e "$dest/diag-$n.txt" ] && [ ! -L "$dest/diag-$n.txt" ] && [ ! -e "$dest/diag-$n.txt.tmp" ] && [ ! -L "$dest/diag-$n.txt.tmp" ] &&
           ( set -C; cat "$UI_DIR/diag-latest.txt" > "$dest/diag-$n.txt.tmp" ) 2>/dev/null &&
           [ ! -L "$dest/diag-$n.txt.tmp" ] && mv "$dest/diag-$n.txt.tmp" "$dest/diag-$n.txt" 2>/dev/null && op sync; then
            # Include automatically preserved failure evidence on the same USB.
            local evidence target evidence_file staged export_ok=1
            for evidence in "$PSTATE/diagnostics"/failure-* "$PSTATE/diagnostics"/active-*; do
                plain "$evidence" && [ -d "$evidence" ] || continue
                target="$dest/${evidence##*/}"
                plain "$target" || { export_ok=0; continue; }
                if [ -d "$target" ] && [ -f "$target/USB-COMPLETE" ]; then continue; fi
                # Never bless an earlier incomplete directory. A fresh save uses
                # a new staging name and publishes only a complete copy.
                staged=$target.part-$n
                plain "$staged" && [ ! -e "$staged" ] && mkdir "$staged" || { export_ok=0; continue; }
                local copied=1
                for evidence_file in "$evidence"/*; do
                    plain "$evidence_file" && [ -f "$evidence_file" ] || continue
                    case "${evidence_file##*/}" in .*|*.part|*.part.*|*.raw|*.flt|*.rc|*.tmp) continue;; esac
                    ( set -C; cat "$evidence_file" > "$staged/${evidence_file##*/}" ) 2>/dev/null || copied=0
                done
                if [ "$copied" = 1 ] && print -r -- complete > "$staged/USB-COMPLETE" && op sync; then
                    # Retain a preexisting incomplete copy under its old name;
                    # publish this retry with a unique suffix if necessary.
                    [ ! -e "$target" ] || target=$target.retry-$n
                    if [ ! -e "$target" ] && mv "$staged" "$target" && op sync; then
                        print -r -- "$n" > "$evidence/EXPORTED" || export_ok=0
                    else export_ok=0; fi
                else export_ok=0; fi
            done
            if op sync && [ "$export_ok" = 1 ]; then result=usb; else result=fail; fi
        else
            [ -L "$dest/diag-$n.txt.tmp" ] || rm -f "$dest/diag-$n.txt.tmp" 2>/dev/null
            result=fail
        fi
    fi
    record "$SAVED" "$n $result"
}
round() {
    prepare || return 0
    ensure_default_split || :
    read_portable
    collect_status || :
    collect_log || :
}
cleanup_stage() { rm -rf "$PRIV_STAGE" 2>/dev/null || :; }
trap cleanup_stage EXIT
trap 'cleanup_stage; exit 0' HUP INT TERM
# The in-car screen cannot ask anything before Android is up, and this loop's
# helper calls compete with zygote and system_server during boot.
if [ -z "$ROOT" ]; then
    until [ "$(getprop sys.boot_completed 2>/dev/null)" = 1 ]; do sleep 10; done
fi
prepare || :
while :; do
    BOOT=$(boot_id) || BOOT=
    apply_requests
    round
    [ -z "${PORTABLE_UI_ONCE:-}" ] || { wait; round; exit 0; }
    waited=0
    while [ "$waited" -lt "$INTERVAL" ]; do
        sleep "$REQ_STEP"; waited=$((waited + REQ_STEP))
        # The boot id cannot change while this process runs; read it again
        # only if the last read failed.
        [ -n "$BOOT" ] || BOOT=$(boot_id) || BOOT=
        apply_requests
    done
done
