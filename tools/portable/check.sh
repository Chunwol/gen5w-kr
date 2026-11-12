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
    case "$1" in boot) cat /proc/sys/kernel/random/boot_id;; prop) getprop "$2";; *) return 1;; esac
}
mkdir_new() {
    plain "$1" && [ ! -e "$ROOT$1" ] || fail 'fresh /data path required'
    mkdir -p "$ROOT${1%/*}" && mkdir "$ROOT$1" || fail 'directory unavailable'
}
inventory() {
    local path file digest property
    for path in /system/app/Iap2ServerApp.odex /system/app/HKMC_DiPO.apk /system/app/HKMC_DiPO.odex /system/app/HKMC_GPM.apk /system/app/HKMC_GPM.odex /system/app/HKMC_WifiSettings.odex /system/lib/libCarPlayAudio.so /system/build.prop /system/etc/featurexml.cfg; do
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
    for key in persist.ium.support wrap.com.daudio.app.dipo wrap.com.google.android.project; do
        value=$(op prop "$key") || return 1
        print -r -- "$key|$value"
    done
}
probe_loaded() {
    local marker=$ROOT/data/data/com.daudio.app.dipo/files/gen5w-portable-probe pid='' boot='' mode='' key value line identity inode found=0 address perms offset device number file extra
    [ -f "$marker" ] && [ ! -L "$marker" ] || fail 'no private library-loaded marker'
    while IFS='=' read -r key value; do
        case "$key" in pid) pid=$value;; boot_id) boot=$value;; mode) mode=$value;; esac
    done < "$marker"
    case "$pid" in ''|*[!0-9]*) fail 'invalid marker PID';; esac
    [ "$pid" -gt 1 ] && [ "$boot" = "$(op boot)" ] && [ "$mode" = no-hooks ] || fail 'probe marker is not from this boot'
    grep -aq '^com[.]daudio[.]app[.]dipo' "$ROOT/proc/$pid/cmdline" || fail 'DiPO process no longer matches marker'
    identity=$("$HELPER" identity "$ROOT/system/app/HKMC_DiPO.odex") || fail 'ODEX identity unavailable'
    inode=${identity#*:}
    while read -r address perms offset device number file extra; do
        [ "$file:$number" != "/system/app/HKMC_DiPO.odex:$inode" ] || found=1
    done < "$ROOT/proc/$pid/maps"
    [ "$found" = 1 ] || fail 'DiPO has not mapped the active ODEX inode; inspect cached/other code before continuing'
    echo 'PASS no-hook library loaded in current DiPO and active ODEX inode mapped'
    cat "$marker"
}
command=${1:-}; shift
case "$command" in
probe-loaded) [ "$#" = 0 ] || fail arguments; probe_loaded;;
snapshot)
    [ "$#" = 1 ] || fail arguments
    mkdir_new "$1"
    inventory > "$ROOT$1/system.sha256" && [ -s "$ROOT$1/system.sha256" ] && properties > "$ROOT$1/properties" && op boot > "$ROOT$1/boot" || fail snapshot
    echo 'check: baseline recorded; no activation';;
restored)
    [ "$#" = 1 ] && plain "$1" || fail arguments
    for file in system.sha256 properties boot; do [ -f "$ROOT$1/$file" ] && [ ! -L "$ROOT$1/$file" ] || fail 'baseline unavailable'; done
    [ "$(cat "$ROOT$1/boot")" != "$(op boot)" ] || fail 'a different boot is required'
    [ "$(inventory)" = "$(cat "$ROOT$1/system.sha256")" ] && [ "$(properties)" = "$(cat "$ROOT$1/properties")" ] || fail 'stock file/property comparison differs'
    echo 'PASS selected stock bytes and projection/wrapper properties restored after reboot';;
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
    echo "probe|$1/dipo.odex|/system/app/HKMC_DiPO.odex|$digest|$meta|static" > "$ROOT$1/manifest" || fail manifest
    echo 'check: byte-identical DiPO overlay manifest prepared; nothing mounted';;
*) fail 'usage: check.sh snapshot NEW-DIR | prepare-probe NEW-DIR | probe-loaded | restored BASELINE-DIR';;
esac
