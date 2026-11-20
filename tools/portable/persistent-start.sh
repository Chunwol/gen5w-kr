#!/system/bin/sh
# Start authored services over an already materialized /system installation.
# Exit 3 is reserved for a genuinely absent recovery manifest; every malformed,
# partial, or unknown persistent state fails closed and must never fall back to
# the legacy zygote-restarting boot path.
umask 077
LC_ALL=C; export LC_ALL
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
BASE=$(CDPATH= cd -- "$BASE" && pwd) || exit 1
ROOT=${PORTABLE_TEST_ROOT:-}
HELPER=$BASE/bin/dex-patch
SYSTEM=$ROOT
DATA=$ROOT/data
RECOVERY=$DATA/local/gen5w-portable/persistent/recovery
MANIFEST=$RECOVERY/manifest
ORIGINALS=$RECOVERY/originals
OWNER=$DATA/local/gen5w-portable/persistent/manifest
fail() { echo "persistent-start: $*" >&2; exit 1; }
plain() {
    case "$1" in /*) :;; *) return 1;; esac
    case "$1" in *[!A-Za-z0-9_./+-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac
    local p=$1
    while [ "$p" != / ]; do [ ! -L "$p" ] || return 1; p=${p%/*}; [ -n "$p" ] || p=/; done
}
mapped() { if [ -n "$ROOT" ]; then case "$1" in "$ROOT"/*) print -r -- "$1";; /*) print -r -- "$ROOT$1";; *) print -r -- "$1";; esac; else print -r -- "$1"; fi; }
sha() { "$HELPER" sha256 "$(mapped "$1")"; }
meta() { "$HELPER" metadata "$(mapped "$1")"; }
label() { "$HELPER" label "$(mapped "$1")"; }
allowed_target() {
    case "$1" in
        /system/app/Iap2ServerApp.odex|/system/app/HKMC_DiPO.odex|/system/app/HKMC_GPM.odex|/system/app/HKMC_WifiSettings.odex|/system/lib/libCarPlayAudio.so|/system/build.prop|/system/etc/qb_runtime.sh|/system/etc/featurexml.cfg|/system/onebin/*/featurexml.cfg|/system/featurexml/*/featurexml.cfg|/system/*/featurexml.cfg|/system/etc/permissions/*.xml)
            case "$1" in *..*|*'//'*) return 1;; esac
            case "$1" in /system/etc/permissions/*.xml) n=${1##*/}; case "$n" in ''|*[!A-Za-z0-9_.+-]*|.*) return 1;; esac; [ "$1" = "/system/etc/permissions/$n" ] || return 1;; esac
            ;;
        *) return 1;;
    esac
}
valid_sha() { case "$1" in ''|*[!a-f0-9]*) return 1;; esac; [ "${#1}" = 64 ]; }
valid_meta() {
    local digits
    case "$1" in *[!0-9\|]*|\|*|*\||*\|\|*) return 1;; esac
    digits=${1//[0-9]/}; [ "$digits" = '||' ]
}
# One helper process reports sha256|uid|gid|mode|label for every checked file
# (a process start costs about 1 s in the emulator); results are kept by path.
NL='
'
SLASH=/
key() { KEY=${1//_/_U}; KEY=${KEY//$SLASH/_S}; KEY=${KEY//./_D}; KEY=${KEY//-/_H}; }
split_fact() {
    local rest=$1
    FACT_HASH=${rest%%'|'*}; rest=${rest#*'|'}
    FACT_LABEL=${rest##*'|'}; FACT_META=${rest%'|'*}
    valid_sha "$FACT_HASH" && valid_meta "$FACT_META" && valid_label "$FACT_LABEL"
}
facts() {
    local out line path
    [ "$#" -gt 0 ] || return 0
    for path in "$@"; do case "$path" in ''|*[!A-Za-z0-9_./-]*) return 1;; esac; done
    out=$("$HELPER" ident "$@") || return 1
    out="$out$NL"
    for path in "$@"; do
        case "$out" in *"$NL"*) :;; *) return 1;; esac
        line=${out%%"$NL"*}; out=${out#*"$NL"}
        split_fact "$line" || return 1
        key "$path"; eval "FACT_$KEY=\$line"
    done
    [ -z "$out" ]
}
fact() {
    local line
    key "$1"; eval "line=\${FACT_$KEY-}"
    if [ -z "$line" ]; then
        facts "$1" || return 1
        key "$1"; eval "line=\${FACT_$KEY}"
    fi
    split_fact "$line"
}
valid_label() { case "$1" in ''|*[!A-Za-z0-9_:.,+-]*) return 1;; esac; }
verify() {
    local saved_ifs=$IFS
    if [ ! -e "$MANIFEST" ] && [ ! -L "$MANIFEST" ]; then return 3; fi
    plain "$MANIFEST" && [ -f "$MANIFEST" ] || fail unsafe-recovery-manifest
    plain "$ORIGINALS" && [ -d "$ORIGINALS" ] || fail unsafe-recovery-originals
    plain "$OWNER" && [ -f "$OWNER" ] || fail missing-persistent-owner-manifest
    plain "$HELPER" && [ -x "$HELPER" ] || fail missing-helper
    header=; IFS= read -r header < "$MANIFEST" || fail empty-recovery-manifest
    case "$header" in 'GEN5W-RECOVERY-MANIFEST|1') version=1;; 'GEN5W-RECOVERY-MANIFEST|2') version=2;; *) fail unsupported-recovery-manifest;; esac
    seen='|'; rows=0; line_number=0
    list=''
    while IFS='|' read -r target kind rest || [ -n "$target" ]; do
        allowed_target "$target" || continue
        [ -f "$SYSTEM$target" ] && list="$list $SYSTEM$target"
        [ "$kind" = file ] && [ -f "$ORIGINALS$target" ] && list="$list $ORIGINALS$target"
    done < "$MANIFEST"
    set -f; set -- $list; set +f
    facts "$@" || :
    while IFS= read -r line || [ -n "$line" ]; do
        line_number=$((line_number+1))
        [ "$line_number" != 1 ] || { [ "$line" = "$header" ] || fail recovery-header-changed; continue; }
        [ -n "$line" ] || fail empty-recovery-row
        IFS='|'; set -f; set -- $line; set +f; IFS=$saved_ifs
        target=$1 kind=$2 original=$3 applied=$4 uid=$5 gid=$6 mode=$7 original_label=$8 applied_uid=$9 applied_gid=${10} applied_mode=${11} applied_label=${12} prior=${13} extra=${14}
        [ "$#" -le 14 ] || extra=overflow
        if [ "$version" = 1 ]; then
            [ -z "$prior$extra" ] || fail malformed-recovery-row
        else
            [ -n "$prior" ] && [ -z "$extra" ] || fail malformed-recovery-row
        fi
        allowed_target "$target" || fail unsupported-recovery-target
        case "$seen" in *"|$target|"*) fail duplicate-recovery-target;; esac
        seen="$seen$target|"; rows=$((rows+1))
        valid_sha "$applied" && valid_meta "$applied_uid|$applied_gid|$applied_mode" && valid_label "$applied_label" || fail malformed-applied-state
        if [ "$version" = 2 ]; then case "$prior" in -) :;; *) valid_sha "$prior" || fail malformed-prior-state;; esac; fi
        live="$SYSTEM$target"
        plain "$live" || fail unsafe-live-target
        [ -f "$live" ] && [ ! -L "$live" ] || fail missing-applied-target
        fact "$live" && [ "$FACT_HASH" = "$applied" ] && [ "$FACT_META" = "$applied_uid|$applied_gid|$applied_mode" ] && [ "$FACT_LABEL" = "$applied_label" ] || fail unapplied-or-unknown-target
        case "$kind" in
            file)
                valid_sha "$original" && valid_meta "$uid|$gid|$mode" && valid_label "$original_label" || fail malformed-original-state
                backup="$ORIGINALS${target}"
                plain "$backup" && [ -f "$backup" ] && [ ! -L "$backup" ] && fact "$backup" && [ "$FACT_HASH" = "$original" ] || fail missing-or-corrupt-original-backup
                ;;
            absent)
                [ "$original|$uid|$gid|$mode|$original_label" = '-|-|-|-|-' ] || fail malformed-absent-state
                ;;
            *) fail malformed-recovery-kind;;
        esac
    done < "$MANIFEST"
    [ "$rows" -gt 0 ] || fail empty-recovery-manifest
    echo "persistent-start: verified $rows applied target(s) and immutable restore originals"
    return 0
}
# Boot-time polling and hashing compete with zygote and system_server. On the
# V039 VM (2026-11-20) all services together kept boot from ever completing;
# with them idle it completed in stock time. Poll every 5 s for up to 15 min.
# Right after boot_completed every stock app is still starting (BOOT_COMPLETED
# receivers). Starting our VMs and apps on top of that storm saturated a 1-CPU
# VM until zygote stalled with the AMS lock held and the watchdog reset Android
# (VM 2026-11-21: reset ~2-4 min after our start; none while we stayed idle).
# Wait until the 1-minute load is below 2 per CPU, at most 3 minutes.
settle_android() {
    local n=0 line l1 rest waited=0
    while IFS= read -r line; do case "$line" in processor*) n=$((n+1));; esac; done < /proc/cpuinfo 2>/dev/null
    [ "$n" -gt 0 ] || n=1
    while [ "$waited" -lt 180 ]; do
        IFS=' ' read -r l1 rest < /proc/loadavg 2>/dev/null || break
        l1=${l1%%.*}
        case "$l1" in ''|*[!0-9]*) break;; esac
        [ "$l1" -ge $((n * 2)) ] || break
        sleep 5; waited=$((waited + 5))
    done
    echo "persistent-start: settled after ${waited}s (load ${l1:-?}, cpus $n)"
}
normal_priority() { # this (sub)shell: /proc/self is opened by the builtin read
    local me rest
    IFS=' ' read -r me rest < /proc/self/stat 2>/dev/null && renice 0 "$me" >/dev/null 2>&1
    return 0
}
wait_android() {
    count=0
    while [ "$(getprop sys.boot_completed 2>/dev/null)" != 1 ] || [ "$(getprop init.svc.zygote 2>/dev/null)" != running ]; do
        count=$((count+1)); [ "$count" -lt 180 ] || return 1
        sleep 5
    done
}
case "${1:-}" in
    verify) [ "$#" = 1 ] || exit 2; verify; exit $?;;
    detect)
        [ "$#" = 1 ] || exit 2
        if [ ! -e "$(mapped "$MANIFEST")" ] && [ ! -L "$(mapped "$MANIFEST")" ]; then exit 3; fi
        verify; exit $?;;
    run)
        [ "$#" = 1 ] || exit 2
        # No manifest: hand over to the stock-first path at once (exit 3).
        if [ ! -e "$MANIFEST" ] && [ ! -L "$MANIFEST" ]; then exit 3; fi
        [ -z "$ROOT" ] || { verify || exit $?; fail fixture-cannot-start-android; }
        # Hash the 97 targets only after Android is up; nothing starts before
        # this check passes, as before.
        wait_android || fail android-readiness-timeout
        settle_android
        verify || exit $?
        # Second clear path for the pre-zygote boot guard, in case its
        # background child did not survive: Android reached boot_completed.
        GUARD=/data/local/gen5w-portable/persistent/bootguard
        if [ -d "$GUARD" ] && [ ! -L "$GUARD" ] && [ ! -L "$GUARD/count" ] && [ ! -L "$GUARD/count.svc" ] && [ ! -e "$GUARD/tripped" ]; then
            echo 0 > "$GUARD/count.svc" && mv "$GUARD/count.svc" "$GUARD/count" || :
        fi
        # `am` boots a Dalvik VM; right after boot on a slow unit that alone can
        # take over 15 s (VM 2026-11-21: every start request timed out, so no
        # feature ever started). Run it at normal priority, allow 30 s, and
        # retry; startservice is idempotent. Bounded to 4 attempts.
        # Only when DiPO is not already running with the hook: Android starts it at
        # boot, and a redundant onStartCommand on its busy main thread ran past the
        # service timeout, so Android killed and restarted it (VM 2026-11-21).
        count=0
        /system/bin/sh "$BASE/session.sh" adapter-ready ||
        until ( normal_priority; exec "$HELPER" supervise 30 /system/bin/true /system/bin/am startservice -n com.daudio.app.dipo/.service.DipoService ); do
            count=$((count+1)); [ "$count" -lt 4 ] || fail dipo-start-request-failed
            sleep 5
        done
        count=0
        until /system/bin/sh "$BASE/session.sh" adapter-ready; do
            count=$((count+1)); [ "$count" -lt 180 ] || fail dipo-adapter-not-ready
            sleep 1
        done
        export GEN5W_PERSISTENT=1
        exec /system/bin/sh "$BASE/session.sh" run
        ;;
    *) echo 'usage: persistent-start.sh verify|detect|run' >&2; exit 2;;
esac
