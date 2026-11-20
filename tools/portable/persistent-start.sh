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
wait_android() {
    count=0
    while [ "$(getprop sys.boot_completed 2>/dev/null)" != 1 ] || [ "$(getprop init.svc.zygote 2>/dev/null)" != running ]; do
        count=$((count+1)); [ "$count" -lt 300 ] || return 1
        sleep 1
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
        verify || exit $?
        [ -z "$ROOT" ] || fail fixture-cannot-start-android
        wait_android || fail android-readiness-timeout
        # Second clear path for the pre-zygote boot guard, in case its
        # background child did not survive: Android reached boot_completed.
        GUARD=/data/local/gen5w-portable/persistent/bootguard
        if [ -d "$GUARD" ] && [ ! -L "$GUARD" ] && [ ! -L "$GUARD/count" ] && [ ! -L "$GUARD/count.svc" ] && [ ! -e "$GUARD/tripped" ]; then
            echo 0 > "$GUARD/count.svc" && mv "$GUARD/count.svc" "$GUARD/count" || :
        fi
        "$HELPER" supervise 15 /system/bin/true /system/bin/am startservice -n com.daudio.app.dipo/.service.DipoService || fail dipo-start-request-failed
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
