#!/system/bin/sh
# Explicit validation aid. No app start/stop, mount, or persistent property writes.
umask 077
LC_ALL=C; export LC_ALL
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
BASE=$(CDPATH= cd -- "$BASE" && pwd) || exit 1
HELPER=$BASE/bin/dex-patch
ROOT=${PORTABLE_TEST_ROOT:-}
fail() { echo "check: $*" >&2; exit 1; }
plain() {
    case "$1" in /data/*) :;; *) return 1;; esac
    case "$1" in *[!a-zA-Z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac
    local part=$ROOT$1
    while [ "$part" != / ]; do [ ! -L "$part" ] || return 1; part=${part%/*}; [ -n "$part" ] || part=/; done
}
[ -z "$ROOT" ] || { [ -d "$ROOT" ] && [ "$ROOT" != / ] && [ -x "${PORTABLE_TEST_HELPER:-}" ]; } || fail fixture
[ -z "$ROOT" ] || HELPER=$PORTABLE_TEST_HELPER
op() {
    if [ -n "$ROOT" ]; then "$PORTABLE_TEST_CHECK_ADAPTER" "$@"; return $?; fi
    case "$1" in
    boot) cat /proc/sys/kernel/random/boot_id;;
    prop) getprop "$2";;
    setting)
        # settings needs a running framework; never let it block the check.
        ( /system/bin/settings get global "$2" 2>/dev/null & reader=$!
          ( sleep 20; kill -TERM "$reader" ) >/dev/null 2>&1 & guard=$!
          wait "$reader"; status=$?
          kill "$guard" 2>/dev/null
          exit "$status" );;
    *) return 1;;
    esac
}
regular() { [ -f "$1" ] && [ ! -L "$1" ]; }
# Print the only line of a regular file; fail on zero or several lines.
single() {
    local line count=0 value=''
    regular "$1" || return 1
    while IFS= read -r line || [ -n "$line" ]; do count=$((count+1)); value=$line; done < "$1"
    [ "$count" = 1 ] && echo "$value"
}
# /proc/PID/stat field 22 (start time); PID plus start time name one process.
process_start() {
    local line rest count=0
    case "$1" in ''|*[!0-9]*) return 1;; esac
    IFS= read -r line < "$ROOT/proc/$1/stat" || return 1
    rest=${line##*) }; [ "$rest" != "$line" ] || return 1
    set -- $rest; [ "$#" -ge 20 ] || return 1
    case "$1" in Z|X|x) return 1;; esac
    while [ "$count" -lt 19 ]; do shift; count=$((count+1)); done
    case "$1" in ''|*[!0-9]*) return 1;; esac
    echo "$1"
}
hex() {
    local value=$1 out='' digit
    while :; do
        digit=$((value % 16))
        case "$digit" in 10) digit=a;; 11) digit=b;; 12) digit=c;; 13) digit=d;; 14) digit=e;; 15) digit=f;; esac
        out=$digit$out; value=$((value / 16))
        [ "$value" -gt 0 ] || break
    done
    [ "${#out}" -ge 2 ] || out=0$out
    echo "$out"
}
# stat st_dev (decimal, new_encode_dev) -> the MAJOR:MINOR hex form of /proc/PID/maps.
maps_device() {
    case "$1" in ''|*[!0-9]*) return 1;; esac
    [ "${#1}" -le 9 ] || return 1
    echo "$(hex $(( ($1 >> 8) & 4095 ))):$(hex $(( ($1 & 255) | (($1 >> 12) & 1048320) )))"
}
# Paths overlay.sh may bind; a restored stock boot must not still have one mounted.
overlay_target() {
    case "$1" in
    /system/app/Iap2ServerApp.odex|/system/app/HKMC_DiPO.odex|/system/app/HKMC_GPM.odex|/system/app/HKMC_WifiSettings.odex|/system/lib/libCarPlayAudio.so|/system/lib/libautoreceiver_infobank.so|/system/build.prop|/system/etc/qb_runtime.sh|/system/etc/featurexml.cfg|/system/etc/permissions|/system/*/featurexml.cfg|/system/onebin/*/featurexml.cfg|/system/featurexml/*/featurexml.cfg) return 0;;
    esac
    return 1
}
# wifi_ap_on|normalized|raw. Unset ("null") and 0 both leave the stock AP off.
settings_record() {
    local raw
    raw=$(op setting wifi_ap_on) || return 1
    case "$raw" in null|0) echo "wifi_ap_on|off|$raw";; 1) echo "wifi_ap_on|on|$raw";;
    ''|*[!a-zA-Z0-9_.-]*) return 1;; *) echo "wifi_ap_on|$raw|$raw";; esac
}
# Diagnostic inventory: recorded for review, never a pass/fail input by itself.
diag_net() {
    local item
    for item in "$ROOT"/sys/class/net/*; do
        [ -e "$item" ] || [ -L "$item" ] || continue
        echo "${item##*/}"
    done
}
diag_modules() {
    local name rest
    [ -f "$ROOT/proc/modules" ] || { echo '(no /proc/modules)'; return 0; }
    while read -r name rest; do [ -z "$name" ] || echo "$name"; done < "$ROOT/proc/modules"
}
diag_uptime() { local up idle; read -r up idle < "$ROOT/proc/uptime" && [ -n "$up" ] && echo "$up"; }
diag_softap() {
    if regular "$ROOT/data/misc/wifi/softap.conf"; then "$HELPER" sha256 "$ROOT/data/misc/wifi/softap.conf"
    else echo absent; fi
}
diagnostics() {
    diag_net > "$1/net" && diag_modules > "$1/modules" && cat "$ROOT/proc/mounts" > "$1/mounts" &&
        diag_uptime > "$1/uptime" && diag_softap > "$1/softap"
}
joined() { local line out=''; while IFS= read -r line; do [ -z "$line" ] || out=${out:+$out,}$line; done; echo "$out"; }
# Lines on stdin that are absent from file $1.
added() {
    local line old seen
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        seen=0
        while IFS= read -r old; do [ "$old" != "$line" ] || seen=1; done < "$1"
        [ "$seen" = 1 ] || echo "$line"
    done
}
mkdir_new() {
    plain "$1" && [ ! -e "$ROOT$1" ] || fail 'fresh /data path required'
    mkdir -p "$ROOT${1%/*}" && mkdir "$ROOT$1" || fail 'directory unavailable'
}
inventory() {
    local path file digest property
    for path in /system/app/Iap2ServerApp.odex /system/app/HKMC_DiPO.apk /system/app/HKMC_DiPO.odex /system/app/HKMC_GPM.apk /system/app/HKMC_GPM.odex /system/app/HKMC_WifiSettings.odex /system/lib/libCarPlayAudio.so /system/lib/libautoreceiver_infobank.so /system/build.prop /system/etc/featurexml.cfg; do
        if [ -f "$ROOT$path" ] && [ ! -L "$ROOT$path" ]; then
            digest=$("$HELPER" sha256 "$ROOT$path") || return 1
            echo "$digest|$path"
        fi
    done
    for file in "$ROOT"/system/etc/permissions/*.xml; do
        [ -e "$file" ] || continue
        [ -f "$file" ] && [ ! -L "$file" ] || return 1
        digest=$("$HELPER" sha256 "$file") || return 1
        echo "$digest|${file#"$ROOT"}"
    done
}
properties() {
    local key value
    for key in persist.ium.support wrap.com.daudio.app.dipo wrap.com.google.android.project wrap.com.mnsoft.navi; do
        value=$(op prop "$key") || return 1
        print -r -- "$key|$value"
    done
}
probe_loaded() {
    local marker=$ROOT/data/data/com.daudio.app.dipo/files/gen5w-portable-probe overlay=$ROOT/data/local/gen5w-portable/overlay
    local pid='' boot='' mode='' start='' key value now name row feature src dst hash uid gid perm kind extra
    local journal target recorded source_identity active_identity device inode found=0 library=0 visible=0
    local address perms offset mapdev number file a b c d point rest
    regular "$marker" || fail 'no private library-loaded marker'
    while IFS='=' read -r key value; do
        case "$key" in pid) pid=$value;; boot_id) boot=$value;; mode) mode=$value;; start) start=$value;; esac
    done < "$marker"
    case "$pid" in ''|*[!0-9]*) fail 'invalid marker PID';; esac
    now=$(op boot) || fail 'boot identity unavailable'
    [ "$pid" -gt 1 ] && [ -n "$now" ] && [ "$boot" = "$now" ] && [ "$mode" = no-hooks ] || fail 'probe marker is not from this boot'
    case "$start" in ''|*[!0-9]*) fail 'marker lacks process start identity; rebuild with the current hook library';; esac
    [ "$(process_start "$pid")" = "$start" ] || fail 'marker PID is not the same process (exited or reused)'
    grep -aq '^com[.]daudio[.]app[.]dipo' "$ROOT/proc/$pid/cmdline" || fail 'DiPO process no longer matches marker'
    # The probe is only meaningful while the identical /data copy is actually
    # bound: an absent overlay would map the stock inode on both sides.
    for name in state boot manifest journal; do regular "$overlay/$name" || fail "overlay $name unavailable; probe requires the applied pending overlay"; done
    [ "$(cat "$overlay/state")" = pending ] || fail 'overlay is not pending; probe evidence requires the applied, uncommitted probe overlay'
    [ "$(cat "$overlay/boot")" = "$now" ] || fail 'overlay was not applied in this boot'
    row=$(single "$overlay/manifest") || fail 'overlay manifest must contain exactly the probe row'
    IFS='|' read -r feature src dst hash uid gid perm kind extra <<EOF
$row
EOF
    [ "$dst" = /system/app/HKMC_DiPO.odex ] && [ "$kind" = static ] && [ -z "$extra" ] || fail 'overlay is not the single static DiPO ODEX probe'
    plain "$src" && [ "${src##*/}" = dipo.odex ] && regular "$ROOT$src" || fail 'probe source is not a plain /data copy'
    [ "$(single "$ROOT${src%/*}/manifest" 2>/dev/null)" = "$row" ] || fail 'overlay row differs from the prepare-probe byte-identical manifest'
    [ "$("$HELPER" sha256 "$ROOT$src")" = "$hash" ] || fail 'probe source bytes differ from the prepared stock digest'
    journal=$(single "$overlay/journal") || fail 'not the journaled /data probe copy (journal must hold exactly the probe bind)'
    IFS='|' read -r target recorded extra <<EOF
$journal
EOF
    source_identity=$("$HELPER" identity "$ROOT$src") || fail 'probe source identity unavailable'
    active_identity=$("$HELPER" identity "$ROOT$dst") || fail 'ODEX identity unavailable'
    case "$source_identity" in *[!0-9:]*|:*|*:|*:*:*|'') fail 'probe source identity unavailable';; esac
    [ "$target" = "$dst" ] && [ -z "$extra" ] && [ "$recorded" = "$source_identity" ] && [ "$active_identity" = "$source_identity" ] ||
        fail 'active ODEX is not the journaled /data probe copy (overlay not mounted?)'
    while read -r a b c d point rest; do [ "$point" != "$dst" ] || visible=1; done < "$ROOT/proc/$pid/mountinfo"
    [ "$visible" = 1 ] || fail 'probe bind is not visible in the DiPO mount namespace'
    device=$(maps_device "${source_identity%%:*}") || fail 'probe source device number unsupported'
    inode=${source_identity#*:}
    while read -r address perms offset mapdev number file extra; do
        if [ "$mapdev:$number" = "$device:$inode" ]; then
            [ "$file" != "$dst" ] && [ "$file" != "$src" ] || found=1
        fi
        case "$file" in */libgen5whook.so) library=1;; esac
    done < "$ROOT/proc/$pid/maps"
    [ "$found" = 1 ] || fail "DiPO has not mapped the probe copy $device $inode; inspect cached/other code before continuing"
    [ "$library" = 1 ] || fail 'probe library is not mapped in the marker process'
    # Re-check last: the process read above must still be the marker's process.
    [ "$(process_start "$pid")" = "$start" ] || fail 'marker PID is not the same process (exited or reused)'
    echo "PASS no-hook library loaded in current DiPO $pid; pending journaled identical copy $source_identity mapped as $device $inode"
    cat "$marker"
}
command=${1:-}; shift
case "$command" in
probe-loaded) [ "$#" = 0 ] || fail arguments; probe_loaded;;
snapshot)
    [ "$#" = 1 ] || fail arguments
    # Read the AP restore flag first so an unavailable framework leaves no partial baseline.
    ap=$(settings_record) || fail 'wifi_ap_on unavailable; record the baseline with stock Android running'
    mkdir_new "$1"
    inventory > "$ROOT$1/system.sha256" && [ -s "$ROOT$1/system.sha256" ] && properties > "$ROOT$1/properties" && op boot > "$ROOT$1/boot" &&
        echo "$ap" > "$ROOT$1/settings" && diagnostics "$ROOT$1" || fail snapshot
    IFS='|' read -r key state raw <<EOF
$ap
EOF
    echo "diag|wifi_ap_on|$state|$raw"
    # A set flag is a legitimate stock state, but stock system_server restores
    # the AP at boot once wireless declarations are mounted: resolve it first.
    [ "$state" = off ] || echo "WARN wifi_ap_on=$raw in the stock baseline; stock boot would restore the AP once wireless features are declared. Resolve before any activation."
    echo 'check: baseline recorded; no activation';;
restored)
    [ "$#" = 1 ] && plain "$1" || fail arguments
    for file in system.sha256 properties boot settings net modules mounts uptime softap; do
        regular "$ROOT$1/$file" || fail 'baseline unavailable (record it with this check.sh snapshot)'
    done
    [ "$(cat "$ROOT$1/boot")" != "$(op boot)" ] || fail 'a different boot is required'
    [ "$(inventory)" = "$(cat "$ROOT$1/system.sha256")" ] && [ "$(properties)" = "$(cat "$ROOT$1/properties")" ] || fail 'stock file/property comparison differs'
    IFS='|' read -r key before raw < "$ROOT$1/settings"
    [ "$key" = wifi_ap_on ] && [ -n "$before" ] || fail 'baseline unavailable (record it with this check.sh snapshot)'
    ap=$(settings_record) || fail 'wifi_ap_on unavailable; check with stock Android running'
    IFS='|' read -r key after raw <<EOF
$ap
EOF
    echo "diag|wifi_ap_on|baseline=$before|now=$after"
    [ "$after" = "$before" ] || fail "wifi_ap_on differs from the stock baseline ($before -> $after)"
    # Overlay binds never survive a reboot; a target mount absent from the
    # stock baseline means the package (or someone) still owns that path.
    while read -r device point rest; do
        overlay_target "$point" || continue
        seen=0
        while read -r old_device old_point old_rest; do [ "$old_point" != "$point" ] || seen=1; done < "$ROOT$1/mounts"
        [ "$seen" = 1 ] || fail "overlay target still mounted: $point"
    done < "$ROOT/proc/mounts"
    net=$(diag_net) && modules=$(diag_modules) && up=$(diag_uptime) && softap=$(diag_softap) || fail 'diagnostic inventory unavailable'
    echo "diag|uptime|baseline=$(cat "$ROOT$1/uptime")|now=$up"
    echo "diag|net|baseline=$(joined < "$ROOT$1/net")|now=$(echo "$net" | joined)"
    echo "diag|modules|baseline=$(joined < "$ROOT$1/modules")|now=$(echo "$modules" | joined)"
    # Interfaces, modules and the hotspot profile may differ on a stock boot;
    # report them for review instead of rejecting.
    echo "$net" | added "$ROOT$1/net" | while IFS= read -r item; do echo "WARN network interface $item absent from the baseline"; done
    echo "$modules" | added "$ROOT$1/modules" | while IFS= read -r item; do echo "WARN module $item absent from the baseline"; done
    [ "$softap" = "$(cat "$ROOT$1/softap")" ] || echo 'WARN softap.conf hotspot profile differs from the baseline'
    echo 'PASS selected stock bytes, projection/wrapper properties and wifi_ap_on restored after reboot; no overlay target mounted'
    ;;
prepare-probe)
    [ "$#" = 1 ] || fail arguments
    mkdir_new "$1"
    original=$ROOT/system/app/HKMC_DiPO.odex
    [ -f "$original" ] && [ ! -L "$original" ] || fail 'stock DiPO missing'
    cp "$original" "$ROOT$1/dipo.odex" || fail copy
    meta=$("$HELPER" metadata "$original") || fail metadata
    IFS='|' read -r uid gid mode <<EOF
$meta
EOF
    chown "$uid:$gid" "$ROOT$1/dipo.odex" && chmod "$mode" "$ROOT$1/dipo.odex" || fail ownership
    digest=$("$HELPER" sha256 "$ROOT$1/dipo.odex") || fail digest
    [ "$digest" = "$("$HELPER" sha256 "$original")" ] || fail 'copy differs'
    # boot.sh arm validates origins against SOURCE.stock (the stock target digest).
    echo "$digest" > "$ROOT$1/dipo.odex.stock" || fail 'stock digest'
    echo "probe|$1/dipo.odex|/system/app/HKMC_DiPO.odex|$digest|$meta|static" > "$ROOT$1/manifest" || fail manifest
    echo 'check: byte-identical DiPO overlay manifest prepared; nothing mounted';;
*) fail 'usage: check.sh snapshot NEW-DIR | prepare-probe NEW-DIR | probe-loaded | restored BASELINE-DIR';;
esac
