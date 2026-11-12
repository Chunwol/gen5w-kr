#!/system/bin/sh
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
LOGDIR=$NEMDIR/logs/gen5w.kr.portable
BOOT_ID=$ROOT/proc/sys/kernel/random/boot_id
UPTIME=$ROOT/proc/uptime
MOUNTS=$ROOT/proc/mounts
NETDIR=$ROOT/sys/class/net
USB_MP=/storage/usb0
USB=$ROOT$USB_MP
WIRELESS_OFF=$NEMDIR/gen5wkr.ui-wireless-off
SAVED=$NEMDIR/gen5wkr.ui-portable-saved
REMOVED=$NEMDIR/gen5wkr.ui-portable-removed
RECOVERY=$NEMDIR/gen5wkr.ui-portable-recovery
ADBTOK=$NEMDIR/gen5wkr.ui-portable-adb
RLOCK=$NEMDIR/gen5wkr.ui-portable-restore
WRAP_DIPO='/system/bin/sh /data/local/gen5w-portable/runtime-payload/wrap-dipo.sh'
INTERVAL=${PORTABLE_UI_INTERVAL:-15}; case "$INTERVAL" in ''|*[!0-9]*) INTERVAL=15;; esac
REQ_STEP=2
MAX_REQUEST=256
MAX_LINES=200
MAX_LINE=200
PER_SOURCE=25
MAX_SOURCE_BYTES=131072
# Lines that can carry personal data are dropped (same list as the core collector).
PRIV='([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}|[0-9A-Fa-f]{2}:\*\*|[Ss][Ss][Ii][Dd]|[Pp]assw|PASSW|[Pp]assphrase|[Pp]sk|PSK|[Ss]erial|SERIAL|[Ii]mei|IMEI|[Ii]ccid|ICCID|[Mm]sisdn|MSISDN|VIN[=: ]|vin[=: ]|DEVICE_NAME|[Dd]evice ?[Nn]ame|getName|FRQ:|BND:|ALBUM|TITLE|ARTIST|mArtist'
op() {
    if [ -n "$ROOT" ]; then "$ADAPTER" "$@"; return $?; fi
    case "$1" in
    get) getprop "$2";;
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
    IFS=' ' read -r up rest < "$UPTIME" 2>/dev/null || return 1
    up=${up%%.*}
    case "$up" in ''|*[!0-9]*) return 1;; esac
    [ "${#up}" -le 9 ] || return 1
    print -r -- "$((10#$up))"
}
process_key() {
    local pid=$1 line rest count=0
    case "$pid" in ''|*[!0-9]*) return 1;; esac
    IFS= read -r line < "/proc/$pid/stat" 2>/dev/null || return 1
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
    local f
    for f in status status.tmp log log.tmp filter.tmp notes notes.tmp request.copy diag.tmp diag-latest.txt restore.log restore.log.tmp; do
        [ ! -L "$UI_DIR/$f" ] || return 1
        [ ! -e "$UI_DIR/$f" ] || [ -f "$UI_DIR/$f" ] || return 1
    done
    for f in "$WIRELESS_OFF" "$SAVED" "$SAVED.tmp" "$REMOVED" "$REMOVED.tmp" "$RECOVERY" "$RECOVERY.tmp" "$ADBTOK" "$ADBTOK.tmp" "$RLOCK"; do
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
    if IFS='|' read -r epoch_boot epoch_key < "$PSTATE/session/epoch" 2>/dev/null && ready=$(small "$PSTATE/session/ready") &&
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
    IFS='|' read -r owner_boot owner_key < "$RLOCK/owner" 2>/dev/null || return 0
    [ "$owner_boot" = "$BOOT" ] && [ "$(process_key "${owner_key%%:*}")" = "$owner_key" ]
}
pair() { # "<number>:<result>[:detail]" from a record file, or 0:none
    local n r d
    [ -f "$1" ] && [ ! -L "$1" ] && IFS=' ' read -r n r d < "$1"
    case "$n" in ''|*[!0-9]*) n=0;; esac
    [ "${#n}" -le 10 ] || n=0
    r=$(word "${r:-none}"); d=${d:+$(word "$d")}
    if [ "$r" = working ] && ! restore_live && [ "$1" != "$SAVED" ]; then r=failed; d=interrupted; fi
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
    local ts relay=unknown apguard=on wired=no version= line wlan=missing tmp="$UI_DIR/status.tmp"
    ts=$(uptime_s) || ts=
    read_portable
    host=dead; host_alive && host=alive
    # Wireless relay is truthfully "on" only with the owned DiPO wrapper live this boot.
    if [ "$P_MODE" = static ] || [ "$P_RUNTIME" = disabled ] || [ "$RUNTIME_LIVE" = 0 ]; then relay=off
    elif [ "$P_RUNTIME" = committed ] && [ "$(op get wrap.com.daudio.app.dipo)" = "$WRAP_DIPO" ]; then relay=on; fi
    # The screen cannot start a disabled or runtime-less install: show the switch locked.
    if [ "$P_ENABLED" != 1 ] || [ "$P_MODE" = static ] || ap_blocked; then apguard=off; fi
    [ ! -e "$NEMDIR/gen5wkr.wireless-disabled" ] || wired=yes
    if plain "$BASE/NEMESIS.data" && [ -f "$BASE/NEMESIS.data" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in package-version=*) version=$(word "${line#package-version=}");; esac
        done < "$BASE/NEMESIS.data"
    fi
    [ -d "$NETDIR/wlan0" ] && wlan=present
    {
        print -r -- "ts=$ts"
        print -r -- "boot=$BOOT"
        print -r -- "host=$host"
        print -r -- "relay=$relay"
        print -r -- "backend=builtin"
        print -r -- "version=$version"
        print -r -- "apguard=$apguard"
        print -r -- "wired=$wired"
        if [ -e "$WIRELESS_OFF" ]; then print -r -- "sw_wireless=off"; else print -r -- "sw_wireless=on"; fi
        # Not managed by the portable install: reported as unknown, never as a state.
        print -r -- "sw_timer=unknown"
        print -r -- "sw_bluelink=unknown"
        print -r -- "sw_adb=unknown"
        print -r -- "adb_health=unknown"
        print -r -- "adb_result=$(pair "$ADBTOK")"
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
collect_file() { # file source keep
    local size
    plain "$1" && [ -f "$1" ] || return 0
    [ "$NLOG" -lt "$MAX_LINES" ] || return 0
    size=$(file_size "$1") || return 0
    if [ "$size" -gt "$MAX_SOURCE_BYTES" ]; then
        print -r -- "$2|(log too large, skipped)" >> "$UI_DIR/log.tmp"; NLOG=$((NLOG + 1)); return 0
    fi
    grep -a -v -E "$PRIV" "$1" > "$UI_DIR/filter.tmp" 2>/dev/null
    emit_tail "$2" "$3" "$UI_DIR/filter.tmp"
}
collect_log() {
    local file nl="$NEMDIR/nemesis.log" size
    NLOG=0
    : > "$UI_DIR/log.tmp" || return 1
    print -r -- "boot|enabled=$(word "${P_ENABLED:-0}") phase=$P_PHASE reason=$P_REASON mode=$P_MODE" >> "$UI_DIR/log.tmp"
    print -r -- "boot|overlay=$P_OVERLAY runtime=$P_RUNTIME session=$P_SESSION host=$host" >> "$UI_DIR/log.tmp"
    NLOG=2
    collect_file "$UI_DIR/notes" ui 10
    collect_file "$UI_DIR/restore.log" restore 30
    if plain "$LOGDIR" && [ -d "$LOGDIR" ]; then
        for file in "$LOGDIR"/*.log; do collect_file "$file" portable "$PER_SOURCE"; done
    fi
    if plain "$nl" && [ -f "$nl" ] && size=$(file_size "$nl") && [ "$size" -le 1048576 ] && [ "$NLOG" -lt "$MAX_LINES" ]; then
        grep -a -E 'gen5w\.kr\.portable|boot:|session:|runtime:|overlay:|portable:' "$nl" 2>/dev/null | grep -a -v -E "$PRIV" > "$UI_DIR/filter.tmp"
        emit_tail nemesis 40 "$UI_DIR/filter.tmp"
    fi
    rm -f "$UI_DIR/filter.tmp"
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
    local line key value boot= expires= wireless= timer= bluelink= adb= save= remove= recovery= up count=0
    while IFS= read -r line; do
        key=${line%%=*}; value=${line#*=}
        [ "$key" != "$line" ] || return 0
        case "$key" in
        boot) [ -z "$boot" ] && [ -n "$value" ] || return 0; boot=$value;;
        expires) [ -z "$expires" ] && [ -n "$value" ] || return 0; expires=$value;;
        wireless|timer|bluelink)
            case "$value" in on|off) :;; *) return 0;; esac
            eval "[ -z \"\$$key\" ]" || return 0
            eval "$key=\$value";;
        adb) [ -z "$adb" ] || return 0
            case "$value" in on:*|off:*) :;; *) return 0;; esac
            case "${value#*:}" in ''|*[!0-9]*) return 0;; esac
            [ "${#value}" -le 14 ] || return 0; adb=$value;;
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
    if [ -n "$recovery" ]; then
        [ "$count" = 3 ] || return 0
        start_restore recovery "$recovery"; return 0
    fi
    if [ -n "$remove" ]; then start_restore remove "$remove"; return 0; fi
    [ -z "$save" ] || start_save "$save"
    if [ -n "$wireless" ] && ! restore_live && [ ! -L "$WIRELESS_OFF" ]; then
        if [ "$wireless" = off ]; then [ -f "$WIRELESS_OFF" ] || : > "$WIRELESS_OFF"; else rm -f "$WIRELESS_OFF"; fi
    fi
    [ -z "$timer" ] || note 'UNSUPPORTED timer switch request ignored: the portable install does not manage it'
    [ -z "$bluelink" ] || note 'UNSUPPORTED bluelink switch request ignored: the portable install does not manage it'
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
# ---- diagnosis: status + log only, to a verified FAT/fuse USB mount ----
usb_ok() {
    local src mp fs rest
    plain "$MOUNTS" && [ -f "$MOUNTS" ] || return 1
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
    record "$SAVED" "$n working" || return 0
    do_save "$n" &
}
do_save() {
    local n=$1 result=nousb dest tmp="$UI_DIR/diag.tmp" f
    {
        print -r -- "Gen5W KR portable diagnosis #$n"
        for f in status log; do
            print -r -- "===== $f"
            plain "$UI_DIR/$f" && [ -f "$UI_DIR/$f" ] && grep -a -v -E "$PRIV" "$UI_DIR/$f"
        done
    } > "$tmp" 2>/dev/null || { rm -f "$tmp"; record "$SAVED" "$n fail"; exit 0; }
    chmod 644 "$tmp" && mv "$tmp" "$UI_DIR/diag-latest.txt" || { record "$SAVED" "$n fail"; exit 0; }
    if usb_ok; then
        dest=$USB/gen5w-kr-diag
        if [ ! -L "$dest" ] && mkdir -p "$dest" 2>/dev/null && plain "$dest" &&
           [ ! -e "$dest/diag-$n.txt" ] && [ ! -L "$dest/diag-$n.txt" ] && [ ! -e "$dest/diag-$n.txt.tmp" ] && [ ! -L "$dest/diag-$n.txt.tmp" ] &&
           ( set -C; cat "$UI_DIR/diag-latest.txt" > "$dest/diag-$n.txt.tmp" ) 2>/dev/null &&
           [ ! -L "$dest/diag-$n.txt.tmp" ] && mv "$dest/diag-$n.txt.tmp" "$dest/diag-$n.txt" 2>/dev/null && op sync; then
            result=usb
        else
            [ -L "$dest/diag-$n.txt.tmp" ] || rm -f "$dest/diag-$n.txt.tmp" 2>/dev/null
            result=fail
        fi
    fi
    record "$SAVED" "$n $result"
}
round() {
    prepare || return 0
    read_portable
    collect_status || :
    collect_log || :
}
trap 'exit 0' HUP INT TERM
prepare || :
while :; do
    BOOT=$(boot_id) || BOOT=
    apply_requests
    round
    [ -z "${PORTABLE_UI_ONCE:-}" ] || { wait; round; exit 0; }
    waited=0
    while [ "$waited" -lt "$INTERVAL" ]; do
        sleep "$REQ_STEP"; waited=$((waited + REQ_STEP))
        BOOT=$(boot_id) || BOOT=
        apply_requests
    done
done
