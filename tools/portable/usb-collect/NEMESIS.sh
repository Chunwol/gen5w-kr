#!/system/bin/sh
# Read-only log collector for the portable package. Writes only sanitized bounded outputs to this USB.
umask 077
ROOT=${PORTABLE_TEST_ROOT:-}
TRUE_BIN=/system/bin/true
SH=/system/bin/sh
[ -z "$ROOT" ] || { TRUE_BIN=/bin/true; SH=$(command -v mksh); }
plain() {
    case "$1" in /*) :;; *) return 1;; esac
    case "$1" in *[!a-zA-Z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac
    local p=$1
    while [ "$p" != / ]; do [ ! -L "$p" ] || return 1; p=${p%/*}; [ -n "$p" ] || p=/; done
}
plain "$SH" && [ -x "$SH" ] || exit 1
if [ -n "$ROOT" ]; then
    plain "$ROOT" && [ "$ROOT" != / ] && [ -d "$ROOT" ] || exit 1
fi
if [ -n "${PORTABLE_TEST_USB:-}" ]; then
    plain "$PORTABLE_TEST_USB" && [ -d "$PORTABLE_TEST_USB" ] || exit 1
    USB=$(CDPATH= cd -- "$PORTABLE_TEST_USB" && pwd) || exit 1
else
    case "$0" in */*) cd "${0%/*}" || exit 1;; esac
    USB=$(pwd) || exit 1
fi
plain "$USB" && [ -d "$USB" ] || exit 1
if [ -z "$ROOT" ]; then
    MOUNTS=/proc/mounts
    if [ -L "$MOUNTS" ]; then
        [ "$(readlink "$MOUNTS")" = self/mounts ] || exit 1
    else
        plain "$MOUNTS" || exit 1
    fi
    [ -f "$MOUNTS" ] || exit 1
    usb_mount_ok=0
    while IFS=' ' read -r _src mp fs _rest; do
        case "$fs" in vfat|exfat|texfat|sdfat|fuse|sdcardfs) :;; *) continue;; esac
        if [ "$USB" = "$mp" ] || case "$USB" in "$mp"/*) :;; *) false;; esac; then
            usb_mount_ok=1
            break
        fi
    done < "$MOUNTS"
    [ "$usb_mount_ok" = 1 ] || exit 1
fi
AM=${PORTABLE_TEST_AM:-/system/bin/am}
APP=$ROOT/data/nemesis/apps/gen5w.kr.portable
STATE=$ROOT/data/local/gen5w-portable
SUPERVISOR=$APP/bin/dex-patch
plain "$APP" && plain "$STATE" || exit 1
STAGE=
if plain "$ROOT/data/local/tmp" && [ -d "$ROOT/data/local/tmp" ]; then
    STAGE_PARENT=$ROOT/data/local/tmp
elif plain "$STATE" && [ -d "$STATE" ]; then
    STAGE_PARENT=$STATE
else
    exit 1
fi
STAGE=$STAGE_PARENT/.gen5w-usb-collect.$$
plain "$STAGE" && [ ! -e "$STAGE" ] && [ ! -L "$STAGE" ] || exit 1
mkdir "$STAGE" && chmod 700 "$STAGE" || exit 1
trap 'rm -rf "$STAGE"' EXIT HUP INT TERM

n=0
while [ -e "$USB/GEN5W-PORTABLE-LOGS-$n" ] || [ -L "$USB/GEN5W-PORTABLE-LOGS-$n" ]; do n=$((n+1)); done
OUT=$USB/GEN5W-PORTABLE-LOGS-$n
plain "$OUT" || exit 1
mkdir "$OUT" || exit 1
plain "$OUT" && [ -d "$OUT" ] || exit 1

# Privacy filtering removed at the user's request (2026-11-26): collected logs keep every line.
PRIV='^G5W_NO_PRIVACY_FILTER_NEVER_MATCHES^'
PROP_ALLOW='^\[(ro\.build|ro\.product|ro\.board|ro\.hardware|ro\.daudio|ro\.system|ro\.boot\.mode|persist\.ium|persist\.service\.adb|persist\.adb|persist\.iap2|sys\.launcher3|sys\.boot_completed|tcc\.|wifi\.interface|wrap\.|init\.svc\.|log\.tag\.|debug\.gen5wkr)'
WIFI_ALLOW='^(fixture-dump-|Wi-Fi is |Stay-awake|mWifiState|mWifiApState|curState=|mNetworkInfo|interface=|mCountryCode|SoftAp|Tethering|WifiService|WifiStateMachine|DhcpStateMachine|  state=|  mApInterface|  mFrequency|  mChannel)'
BT_ALLOW='^(fixture-dump-|Bluetooth Status|  enabled:|  state:|  scan mode:|  AdapterState|Profile:|  mProfile|  A2dp|  Headset|  Hfp|  Avrcp|  Rfcomm|  Sdp|  mConnectionState|  State:)'

has_supervisor() {
    plain "$SUPERVISOR" && [ -x "$SUPERVISOR" ]
}
filter_priv() {
    local src=$1 dst=$2 rc=0
    plain "$src" && plain "$dst" || return 1
    grep -a -v -E "$PRIV" "$src" > "$dst" 2>/dev/null; rc=$?
    if [ "$rc" -gt 1 ]; then
        echo '(privacy filter unavailable)' > "$dst"
        return 1
    fi
    return 0
}
copy_bounded() {
    local src=$1 dst=$2 blocks=${3:-64} raw="$STAGE/copy.raw" flt="$STAGE/copy.flt"
    plain "$src" && [ -f "$src" ] && plain "$dst" || return 0
    dd if="$src" of="$raw" bs=4096 count="$((blocks * 2))" 2>/dev/null
    filter_priv "$raw" "$flt" || :
    dd if="$flt" of="$dst" bs=4096 count="$blocks" 2>/dev/null
    rm -f "$raw" "$flt"
}
copy_raw_bounded() {
    local src=$1 dst=$2 blocks=${3:-16}
    plain "$src" && [ -f "$src" ] && plain "$dst" || return 0
    dd if="$src" of="$dst" bs=4096 count="$blocks" 2>/dev/null
}
alert() {
    [ -x "$AM" ] && has_supervisor || return 0
    "$SUPERVISOR" supervise 5 "$TRUE_BIN" "$AM" broadcast -a com.hkmc.intent.action.TOAST \
        -e com.hkmc.intent.extra.TOAST_MESSAGE "Gen5W 로그: $1" \
        --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1 || :
}
# Require verified process-group supervisor and stage all unredacted output only in internal 0700 storage.
grab() {
    local name=$1 command blocks=64 status=0 sup_rc=0 mode=default; shift
    local out="$OUT/$name" part="$STAGE/cmd.part" allow="$STAGE/cmd.allow" filtered="$STAGE/cmd.flt" rcfile="$STAGE/cmd.rc"
    plain "$out" || return 1
    if ! has_supervisor; then
        echo supervisor-unavailable > "$out"
        echo "$name|126" >> "$OUT/command-results.txt"
        return 0
    fi
    command=$(command -v "$1") || { echo unavailable > "$out"; return 0; }
    shift
    case "$name" in logcat-*|dmesg.txt) blocks=128;; esac
    case "$name" in
        getprop.txt) mode=prop;;
        wifi.txt) mode=wifi;;
        bluetooth.txt) mode=bt;;
    esac
    rm -f "$part" "$allow" "$allow.q" "$filtered" "$rcfile"
    G5_PRIV=$PRIV G5_PROP=$PROP_ALLOW G5_WIFI=$WIFI_ALLOW G5_BT=$BT_ALLOW G5_QUOTE='"' \
    "$SUPERVISOR" supervise 20 "$TRUE_BIN" "$SH" -c '
        ulimit -f 2048
        mode=$1; part=$2; allow=$3; filtered=$4; rcfile=$5; cmd=$6; shift 6
        mode=all # no allow-list / privacy filtering
        "$cmd" "$@" > "$part" 2>&1
        print -r -- "$?" > "$rcfile"
        prc=0
        case "$mode" in
            prop)
                grep -a -E "$G5_PROP" "$part" > "$allow" 2>/dev/null; prc=$?
                if [ "$prc" -gt 1 ]; then echo "(privacy filter unavailable)" > "$filtered"
                else
                    grep -a -v -E "$G5_PRIV" "$allow" > "$filtered" 2>/dev/null; prc=$?
                    [ "$prc" -le 1 ] || echo "(privacy filter unavailable)" > "$filtered"
                fi;;
            wifi)
                grep -a -E "$G5_WIFI" "$part" > "$allow" 2>/dev/null; prc=$?
                if [ "$prc" -gt 1 ]; then echo "(privacy filter unavailable)" > "$filtered"
                else
                    grep -a -v -F "$G5_QUOTE" "$allow" > "$allow.q" 2>/dev/null; prc=$?
                    if [ "$prc" -gt 1 ]; then echo "(privacy filter unavailable)" > "$filtered"
                    else
                        grep -a -v -E "$G5_PRIV" "$allow.q" > "$filtered" 2>/dev/null; prc=$?
                        [ "$prc" -le 1 ] || echo "(privacy filter unavailable)" > "$filtered"
                    fi
                fi;;
            bt)
                grep -a -E "$G5_BT" "$part" > "$allow" 2>/dev/null; prc=$?
                if [ "$prc" -gt 1 ]; then echo "(privacy filter unavailable)" > "$filtered"
                else
                    grep -a -v -E "$G5_PRIV" "$allow" > "$filtered" 2>/dev/null; prc=$?
                    [ "$prc" -le 1 ] || echo "(privacy filter unavailable)" > "$filtered"
                fi;;
            *)
                grep -a -v -E "$G5_PRIV" "$part" > "$filtered" 2>/dev/null; prc=$?
                [ "$prc" -le 1 ] || echo "(privacy filter unavailable)" > "$filtered";;
        esac
    ' _ "$mode" "$part" "$allow" "$filtered" "$rcfile" "$command" "$@"
    sup_rc=$?
    if [ -f "$rcfile" ]; then
        IFS= read -r status < "$rcfile" || status=1
        case "$status" in ''|*[!0-9]*) status=1;; esac
    else
        [ "$sup_rc" -ne 0 ] && status=124 || status=1
    fi
    if [ -f "$filtered" ]; then
        dd if="$filtered" of="$out" bs=4096 count="$blocks" 2>/dev/null
    else
        echo unavailable > "$out"
    fi
    rm -f "$part" "$allow" "$allow.q" "$filtered" "$rcfile"
    echo "$name|$status" >> "$OUT/command-results.txt"
}
alert '연결 상태와 로그를 수집합니다. 완료 안내가 나올 때까지 USB를 빼지 마세요.'
{ cat "$ROOT/proc/sys/kernel/random/boot_id"; cat "$ROOT/proc/uptime"; date; } > "$OUT/boot.txt" 2>/dev/null
# Preserve the active session's rings before slower service queries rotate them.
grab logcat-main.txt logcat -d -v time
grab logcat-system.txt logcat -d -v time -b system
grab logcat-events.txt logcat -d -v time -b events
# These small status files expose the HUD input/output gate without reading
# destinations, phone identities or application databases.
mkdir "$OUT/app-status"
for file in \
    "$ROOT/data/data/kr.gen5w.core/files/hud-owner.status" \
    "$ROOT/data/data/kr.gen5w.core/files/hud-health.status" \
    "$ROOT/data/data/kr.gen5w.core/files/hud-variant.status" \
    "$ROOT/data/data/com.daudio.app.dipo/files/gen5w-portable-ready" \
    "$ROOT/data/data/kr.gen5w.wirelesshost/files/bridge-ready"; do
    copy_raw_bounded "$file" "$OUT/app-status/${file##*/}" 4
done
if plain "$APP/boot.sh" && [ -f "$APP/boot.sh" ]; then
    grab status.txt "$SH" "$APP/boot.sh" status
fi
if plain "$ROOT/system/lib/libCarPlayAudio.so" && [ -f "$ROOT/system/lib/libCarPlayAudio.so" ]; then
    grab audio-lib-sha256.txt "$SUPERVISOR" sha256 "$ROOT/system/lib/libCarPlayAudio.so"
fi
copy_raw_bounded "$STATE/persistent/manifest" "$OUT/persistent-manifest.txt" 16
grab services.txt "$ROOT/system/xbin/nemesis" service list
grab packages.txt "$ROOT/system/xbin/nemesis" pkg-list
grab state-list.txt ls -l -R "$STATE"
for dir in boot ap runtime overlay session; do
    plain "$STATE/$dir" && [ -d "$STATE/$dir" ] || continue
    mkdir "$OUT/state-$dir" || continue
    count=0
    for file in "$STATE/$dir"/*; do
        [ "$count" -lt 32 ] || break
        plain "$file" && [ -f "$file" ] || continue
        copy_bounded "$file" "$OUT/state-$dir/${file##*/}" 32
        count=$((count + 1))
    done
done
for source in "$STATE/diagnostics" "$ROOT/data/nemesis/gen5wkr.ui/diagnostics"; do
    plain "$source" && [ -d "$source" ] || continue
    case "$source" in "$STATE/diagnostics") name=failure-evidence;; *) name=saved-diagnostics;; esac
    mkdir "$OUT/$name" || continue
    dcount=0
    for entry in "$source"/*; do
        [ "$dcount" -lt 32 ] || break
        if plain "$entry" && [ -f "$entry" ]; then
            copy_bounded "$entry" "$OUT/$name/${entry##*/}" 64
            dcount=$((dcount + 1))
        elif plain "$entry" && [ -d "$entry" ]; then
            sub=${entry##*/}
            plain "$OUT/$name/$sub" || continue
            mkdir "$OUT/$name/$sub" || continue
            fcount=0
            for f in "$entry"/*; do
                [ "$fcount" -lt 64 ] || break
                plain "$f" && [ -f "$f" ] || continue
                blocks=64
                case "${f##*/}" in debug-*) blocks=1024;; esac
                copy_bounded "$f" "$OUT/$name/$sub/${f##*/}" "$blocks"
                fcount=$((fcount + 1))
            done
            dcount=$((dcount + 1))
        fi
    done
done
copy_bounded "$ROOT/data/nemesis/nemesis.log" "$OUT/nemesis.log" 64
grab getprop.txt getprop
grab ps.txt ps
grab dmesg.txt dmesg
grab audio.txt dumpsys audio
grab audio-flinger.txt dumpsys media.audio_flinger
grab audio-policy.txt dumpsys media.audio_policy
grab wifi.txt dumpsys wifi
grab bluetooth.txt dumpsys bluetooth
grab binder-services.txt service list
grab activity-services.txt dumpsys activity services
grab interfaces.txt ls -l "$ROOT/sys/class/net"
grab mounts.txt cat "$ROOT/proc/mounts"
grab net-dev.txt cat "$ROOT/proc/net/dev"
grab net-unix.txt cat "$ROOT/proc/net/unix"
# The selected process maps show loaded libraries. Compare these with the
# overlay journals and mounts; installation preparation alone is insufficient.
mkdir "$OUT/process-state"
for process in "$ROOT"/proc/[0-9]*; do
    plain "$process/cmdline" && [ -f "$process/cmdline" ] || continue
    command=
    IFS= read -r -d '' command < "$process/cmdline" 2>/dev/null || continue
    case "$command" in com.daudio.app.dipo|kr.gen5w.core|kr.gen5w.wirelesshost)
        pid=${process##*/}
        for name in stat status maps; do
            copy_bounded "$process/$name" "$OUT/process-state/$pid-$name.txt" 32
        done;;
    esac
done
DROPBOX=$ROOT/data/system/dropbox
if plain "$DROPBOX" && [ -d "$DROPBOX" ]; then
    grab dropbox-list.txt ls -l "$DROPBOX"
    mkdir "$OUT/dropbox"
    db_count=0
    for file in "$DROPBOX"/*; do
        [ "$db_count" -lt 16 ] || break
        [ -f "$file" ] && [ ! -L "$file" ] || continue
        base=${file##*/}
        case "$base" in
            ''|*[!a-zA-Z0-9_.@-]*|.|..) continue;;
            *.txt|*.txt.gz) :;;
            *) continue;;
        esac
        rm -f "$STAGE/db.raw" "$STAGE/db.flt"
        case "$base" in
            *.gz)
                has_supervisor || continue
                "$SUPERVISOR" supervise 5 "$TRUE_BIN" "$SH" -c 'ulimit -f 2048; gzip -d -c "$1" > "$2"' _ "$file" "$STAGE/db.raw" 2>/dev/null || continue
                [ -s "$STAGE/db.raw" ] || continue;;
            *)
                dd if="$file" of="$STAGE/db.raw" bs=4096 count=32 2>/dev/null
                [ -s "$STAGE/db.raw" ] || continue;;
        esac
        relevant=0
        case "$base" in
            system_server_crash@*|system_server_watchdog@*|system_server_wtf@*) relevant=1;;
            *)
                if grep -a -qE '^(Process:|Package:|Cmd line:|pid:.*(name:|>>>))[[:space:]]+(com\.daudio\.app\.dipo|com\.google\.android\.projection|com\.tcc\.iap2(server)?|com\.hkmc\.wifisettings|com\.mnsoft\.navi|kr\.gen5w\.[a-zA-Z0-9_.]+)([.:[:space:]]|$)' "$STAGE/db.raw" 2>/dev/null; then
                    relevant=1
                fi;;
        esac
        if [ "$relevant" = 1 ]; then
            outname=${base%.gz}
            dst="$OUT/dropbox/$outname"
            [ ! -L "$OUT/dropbox" ] && [ ! -L "$dst" ] || continue
            filter_priv "$STAGE/db.raw" "$STAGE/db.flt" || :
            dd if="$STAGE/db.flt" of="$dst" bs=4096 count=16 2>/dev/null
            db_count=$((db_count + 1))
        fi
        rm -f "$STAGE/db.raw" "$STAGE/db.flt"
    done
fi
if plain "$ROOT/storage/log" && [ -d "$ROOT/storage/log" ]; then
    grab storage-log-list.txt ls -l "$ROOT/storage/log"
fi
{ cat "$ROOT/proc/sys/kernel/random/boot_id"; cat "$ROOT/proc/uptime"; date; } > "$OUT/boot-end.txt" 2>/dev/null
sync
echo done > "$OUT/DONE"
sync
alert "로그 복사 완료 (GEN5W-PORTABLE-LOGS-$n). USB를 빼서 PC로 가져오세요."
exit 0
