#!/system/bin/sh
# Source-only prototype: transactionally materialize a verified overlay plan
# into /system while retaining exact stock bytes for the separate restore USB.
umask 077
LC_ALL=C; export LC_ALL
PATH=/system/bin:/system/xbin:/sbin:/bin; export PATH

BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
ROOT=${PORTABLE_TEST_ROOT:-}
ADAPTER=${PORTABLE_TEST_MIGRATE_ADAPTER:-}
HELPER=$BASE/bin/dex-patch
if [ -n "$ROOT" ]; then
    [ -x "$ADAPTER" ] || exit 2
    HELPER=$ADAPTER
fi
fail() { echo "persistent-migrate: $*" >&2; exit 1; }
usage() { echo 'usage: persistent-migrate.sh apply VERIFIED-MANIFEST STOCK-ORIGINS' >&2; exit 2; }
OVERLAY_STATE=${PORTABLE_TEST_OVERLAY_STATE:-/data/local/gen5w-portable/overlay}
overlay_cmd() {
    if [ -n "$ROOT" ]; then
        if [ -n "${PORTABLE_TEST_OVERLAY_SHELL:-}" ]; then
            PORTABLE_TEST_ROOT=$ROOT PORTABLE_STATE_DIR=$OVERLAY_STATE_PATH \
                "$PORTABLE_TEST_OVERLAY_SHELL" "$@"
        else
            [ "$1" = status ] || return 1
            "$HELPER" overlay-status
        fi
    else
        PORTABLE_STATE_DIR=$OVERLAY_STATE_PATH /system/bin/sh "$BASE/overlay.sh" "$@"
    fi
}
plain() {
    case "$1" in /*) :;; *) return 1;; esac
    case "$1" in *[!A-Za-z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac
    p=$1
    while [ "$p" != / ]; do [ ! -L "$p" ] || return 1; p=${p%/*}; [ -n "$p" ] || p=/; done
}
allowed_target() {
    case "$1" in
        /system/app/Iap2ServerApp.odex|/system/app/HKMC_DiPO.odex|/system/app/HKMC_GPM.odex|/system/app/HKMC_WifiSettings.odex|/system/lib/libCarPlayAudio.so|/system/build.prop|/system/etc/qb_runtime.sh|/system/wifi/bcmdhd.ko|/system/etc/featurexml.cfg|/system/onebin/*/featurexml.cfg|/system/featurexml/*/featurexml.cfg|/system/*/featurexml.cfg|/system/etc/permissions|/system/etc/permissions|/system/etc/permissions/android.hardware.wifi.xml|/system/etc/permissions/com.hkmc.software.connectivity.androidauto_wireless.xml|/system/etc/permissions/com.hkmc.software.connectivity.carplay_wireless.xml|/system/etc/permissions/com.hkmc.software.wifihotspot.xml|/system/etc/permissions/*.xml)
            case "$1" in *..*|*'//'*) return 1;; esac
            case "$1" in /system/etc/permissions/*.xml) basename=${1##*/}; case "$basename" in ''|*[!A-Za-z0-9_.+-]*|.*) return 1;; esac; [ "$1" = "/system/etc/permissions/$basename" ] || return 1;; esac
            case "$1" in /system/onebin/*/featurexml.cfg) region=${1#/system/onebin/}; region=${region%/featurexml.cfg};; /system/featurexml/*/featurexml.cfg) region=${1#/system/featurexml/}; region=${region%/featurexml.cfg};; /system/*/featurexml.cfg) region=${1#/system/}; region=${region%/featurexml.cfg};; *) return 0;; esac
            case "$region" in ''|*[!A-Za-z0-9_-]*) return 1;; esac
            ;;
        *) return 1;;
    esac
}
no_links() { p=$1; while [ "$p" != / ]; do [ ! -L "$p" ] || return 1; p=${p%/*}; [ -n "$p" ] || p=/; done; }
mapped() { if [ -n "$ROOT" ]; then case "$1" in "$ROOT"/*) print -r -- "$1";; /*) print -r -- "$ROOT$1";; *) print -r -- "$1";; esac; else print -r -- "$1"; fi; }
OVERLAY_STATE_PATH=$(mapped "$OVERLAY_STATE")
# Cost model: each helper call is a process start (about 1 s in the emulator).
# Facts (sha256|uid|gid|mode|label) are fetched for many files per helper run
# and remembered by physical path. Read-only inputs use fact; anything this
# script writes is re-read with facts/fresh after the write.
NL='
'
SLASH=/
mp() { MP=$1; [ -n "$ROOT" ] || return 0; case "$1" in "$ROOT"/*) :;; /*) MP=$ROOT$1;; esac; }
key() { KEY=${1//_/_U}; KEY=${KEY//$SLASH/_S}; KEY=${KEY//./_D}; KEY=${KEY//-/_H}; }
split_fact() {
    local rest=$1 pipes
    FACT_HASH=${rest%%'|'*}; rest=${rest#*'|'}
    FACT_LABEL=${rest##*'|'}; FACT_META=${rest%'|'*}
    case "$FACT_HASH" in *[!a-f0-9]*) return 1;; esac
    [ "${#FACT_HASH}" = 64 ] || return 1
    case "$FACT_META" in *[!0-9\|]*|\|*|*\||*\|\|*) return 1;; esac
    pipes=${FACT_META//[0-9]/}; [ "$pipes" = '||' ] || return 1
    case "$FACT_LABEL" in ''|*[!A-Za-z0-9_:.,+-]*) return 1;; esac
}
facts() {
    local out line path list=''
    [ "$#" -gt 0 ] || return 0
    for path in "$@"; do mp "$path"; case "$MP" in ''|*[!A-Za-z0-9_./-]*) return 1;; esac; list="$list $MP"; done
    set -f; set -- $list; set +f
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
    mp "$1"; key "$MP"; eval "line=\${FACT_$KEY-}"
    if [ -z "$line" ]; then
        facts "$1" || return 1
        mp "$1"; key "$MP"; eval "line=\${FACT_$KEY}"
    fi
    split_fact "$line"
}
fresh() { facts "$1" && fact "$1"; }
# settle_all FILE: apply "path|uid|gid|mode|label" lines in one helper run, then
# re-read every path and require exactly those values.
settle_all() {
    local queue=$1 path uid gid mode wanted list='' paths=''
    [ -s "$queue" ] || return 0
    while IFS='|' read -r path uid gid mode wanted; do
        mp "$path"; list="$list $MP $uid $gid $mode $wanted"; paths="$paths $path"
    done < "$queue"
    set -f; set -- $list; set +f
    "$HELPER" settle "$@" || return 1
    set -f; set -- $paths; set +f
    facts "$@" || return 1
    while IFS='|' read -r path uid gid mode wanted; do
        fact "$path" && [ "$FACT_META" = "$uid|$gid|$mode" ] && [ "$FACT_LABEL" = "$wanted" ] || return 1
    done < "$queue"
}
SIZE_LIST=
count_size() { mp "$1"; SIZE_LIST="$SIZE_LIST $MP"; }
split_row() {
    local rest=$1 n=0
    while :; do
        n=$((n+1))
        case "$rest" in *'|'*) eval "F$n=\${rest%%'|'*}"; rest=${rest#*'|'};; *) eval "F$n=\$rest"; break;; esac
        [ "$n" -lt 20 ] || return 1
    done
    FIELDS=$n
    while [ "$n" -lt 14 ]; do n=$((n+1)); eval "F$n="; done
}
sha() { if [ -n "$ROOT" ]; then "$HELPER" sha "$(mapped "$1")"; else "$HELPER" sha256 "$(mapped "$1")"; fi; }
meta() { if [ -n "$ROOT" ]; then "$HELPER" meta "$(mapped "$1")"; else "$HELPER" metadata "$(mapped "$1")"; fi; }
label() { "$HELPER" label "$(mapped "$1")"; }
set_meta() { "$HELPER" setmeta "$(mapped "$1")" "$2" "$3" "$4"; }
# V039 kernels run SELinux without a loaded policy: every file reads back as
# the same initial label and setxattr(security.selinux) is refused. Accept a
# refused write only when the file already carries exactly the wanted label.
set_label() { "$HELPER" setlabel "$(mapped "$1")" "$2" || [ "$("$HELPER" label "$(mapped "$1")" 2>/dev/null)" = "$2" ]; }
check_sha() { case "$1" in *[!a-f0-9]*) return 1;; esac; [ "${#1}" -eq 64 ]; }
check_meta() {
    local digits mode
    case "$1" in *[!0-9\|]*|\|*|*\||*\|\|*) return 1;; esac
    digits=${1//[0-9]/}; [ "$digits" = '||' ] || return 1
    mode=${1##*'|'}; case "$mode" in *[!0-7]*) return 1;; esac
}
check_label() { case "$1" in ''|*[!A-Za-z0-9_:.,+-]*) return 1;; esac; }
field_count() {
    field_total=1; field_rest=$1
    while case "$field_rest" in *'|'*) :;; *) false;; esac; do
        field_total=$((field_total+1)); field_rest=${field_rest#*'|'}
    done
}
is_ro() { "$HELPER" is-ro; }
target_visible() {
    if [ -n "$ROOT" ]; then
        "$HELPER" visible "$(mapped "$1")"
    else
        [ -r /proc/self/mountinfo ] || return 2
        while IFS=' ' read -r mount_id parent device root mountpoint rest; do
            [ "$mountpoint" = "$1" ] && return 0
        done < /proc/self/mountinfo
        return 1
    fi
}
remount_rw() {
    if [ -n "$ROOT" ]; then
        IFS='|' read -r first_target first_live first_staged first_kind first_original first_extra < "$TX" || return 1
        PORTABLE_TEST_LIVE_TEMP="$first_live.new.$$"; export PORTABLE_TEST_LIVE_TEMP
    fi
    "$HELPER" remount-rw
}
remount_ro() { "$HELPER" remount-ro && is_ro; }
# Linux refuses MS_RDONLY (EBUSY, sb s_remove_count) while a replaced file is
# still mapped by a running stock process. Callers use this only after every
# target was verified; init mounts /system read-only again on the reboot that
# the install (or restore) requires.
RO_DEFERRED=0
remount_ro_or_defer() {
    remount_ro && return 0
    sync_all || return 1
    RO_DEFERRED=1
    echo 'persistent-migrate: /system stays writable until the required reboot (replaced files are still mapped)' >&2
}
sync_all() { if [ -n "$ROOT" ]; then "$HELPER" sync; else sync; fi; }
copy_to_new() {
    copy_source=$1; copy_temp=$2
    [ ! -e "$copy_temp" ] && [ ! -L "$copy_temp" ] || return 1
    (set -C; : > "$copy_temp") 2>/dev/null || return 1
    cp "$copy_source" "$copy_temp" || { rm -f "$copy_temp"; return 1; }
}
publish_copy() {
    copy_source=$1; copy_temp=$2; copy_target=$3
    copy_to_new "$copy_source" "$copy_temp" || return 1
    mv "$copy_temp" "$copy_target"
}
file_bytes() {
    local size_path=$1
    if [ -n "$ROOT" ]; then case "$size_path" in "$ROOT"/*) :;; *) size_path=$(mapped "$size_path");; esac; else size_path=$(mapped "$size_path"); fi
    "$HELPER" size "$size_path"
}
free_bytes() {
    if [ -n "$ROOT" ]; then "$HELPER" free-bytes
    else
        # KitKat toolbox df prints "Filesystem Size Used Free Blksize" with
        # human sizes (e.g. "/data 1.9G 46.5M 1.9G 4096"); there is no -k.
        # Round down one displayed tenth and cap at 1 GiB so 32-bit mksh
        # arithmetic cannot overflow (the plan needs only megabytes).
        local filesystem size used free extra value int frac kib unit
        df /data 2>/dev/null | while IFS=' ' read -r filesystem size used free extra; do
            [ "$filesystem" = /data ] || continue
            value=$free
            case "$value" in *K) unit=1;; *M) unit=1024;; *G) unit=1048576;; *) exit 1;; esac
            value=${value%?}
            case "$value" in *.*) int=${value%%.*}; frac=${value#*.};; *) int=$value; frac=0;; esac
            case "$int:$frac" in :*|*:|*[!0-9:]*) exit 1;; esac
            [ "${#frac}" = 1 ] && [ "${#int}" -le 4 ] || exit 1
            kib=$((int * 10 + frac)); [ "$kib" = 0 ] || kib=$((kib - 1))
            if [ "$unit" = 1048576 ] && [ "$kib" -ge 10 ]; then print -r -- 1073741824; exit 0; fi
            kib=$((kib * unit / 10))
            print -r -- "$((kib * 1024))"
            exit 0
        done
    fi
}

[ "$#" = 3 ] && [ "$1" = apply ] || usage
MANIFEST=$2; ORIGINS=$3
plain "$MANIFEST" && [ -f "$(mapped "$MANIFEST")" ] || fail invalid-manifest-path
plain "$ORIGINS" && [ -d "$(mapped "$ORIGINS")" ] || fail invalid-stock-origin-path
ORIGIN_INDEX="$ORIGINS/index.tsv"
plain "$ORIGIN_INDEX" && [ -f "$(mapped "$ORIGIN_INDEX")" ] || fail missing-stock-origin-index
plain "$HELPER" && [ -x "$(mapped "$HELPER")" ] || fail missing-helper
origin_targets='|'
origin_list=''
while IFS='|' read -r origin_target origin_rest || [ -n "$origin_target" ]; do
    mp "$ORIGINS/${origin_target#/}"
    plain "$ORIGINS/${origin_target#/}" && [ -f "$MP" ] && origin_list="$origin_list $ORIGINS/${origin_target#/}"
done < "$(mapped "$ORIGIN_INDEX")"
set -f; set -- $origin_list; set +f
facts "$@" || :
while IFS='|' read -r origin_target origin_hash origin_uid origin_gid origin_mode origin_label origin_extra || [ -n "$origin_target" ]; do
    [ -n "$origin_target" ] && [ -z "$origin_extra" ] || fail malformed-stock-origin-row
    allowed_target "$origin_target" || fail unsupported-stock-origin-target
    check_sha "$origin_hash" || fail invalid-stock-origin-hash
    check_meta "$origin_uid|$origin_gid|$origin_mode" || fail invalid-stock-origin-metadata
    check_label "$origin_label" || fail invalid-stock-origin-label
    case "$origin_targets" in *"|$origin_target|"*) fail duplicate-stock-origin-target;; esac
    origin_targets="$origin_targets$origin_target|"
    origin_file="$ORIGINS/${origin_target#/}"; mp "$origin_file"
    plain "$origin_file" && [ -f "$MP" ] && fact "$origin_file" && [ "$FACT_HASH" = "$origin_hash" ] || fail stock-origin-file-mismatch
    key "$origin_target"; eval "ORIGINREC_$KEY=\"\$origin_hash|\$origin_uid|\$origin_gid|\$origin_mode|\$origin_label\""
done < "$(mapped "$ORIGIN_INDEX")"
origin_record() {
    local rec origin_file
    key "$1"; eval "rec=\${ORIGINREC_$KEY-}"
    [ -n "$rec" ] || return 1
    split_row "$rec" || return 1
    origin_hash=$F1; origin_uid=$F2; origin_gid=$F3; origin_mode=$F4; origin_selabel=$F5
    origin_meta="$F2|$F3|$F4"
    origin_file="$ORIGINS/${1#/}"
    mp "$origin_file"
    [ -f "$MP" ] && [ ! -L "$MP" ] && fact "$origin_file" && [ "$FACT_HASH" = "$origin_hash" ]
}
is_ro || fail system-not-read-only
RECOVERY=/data/local/gen5w-portable/persistent/recovery
OWNER=/data/local/gen5w-portable/persistent/manifest
R=$(mapped "$RECOVERY"); O=$(mapped "$OWNER")
NEEDS_RECOVERY="$R/transaction-needs-recovery"
COMMITTED_MARKER="$R/transaction-committed"
IN_PROGRESS_MARKER="$R/transaction-in-progress"
[ ! -e "$NEEDS_RECOVERY" ] && [ ! -L "$NEEDS_RECOVERY" ] || fail previous-transaction-needs-recovery
[ ! -e "$COMMITTED_MARKER" ] && [ ! -L "$COMMITTED_MARKER" ] || fail previous-transaction-not-finalized
[ ! -e "$IN_PROGRESS_MARKER" ] && [ ! -L "$IN_PROGRESS_MARKER" ] || fail previous-transaction-incomplete
[ ! -L "$R" ] && [ ! -L "$O" ] || fail linked-persistent-state
no_links "$R" && no_links "${O%/*}" || fail linked-persistent-state
OLD_RECOVERY="$R/manifest"
# old_lookup TARGET: PREV_RECORD is that target's row in the previous manifest.
old_lookup() { key "$1"; eval "PREV_RECORD=\${OLDROW_$KEY-}"; }
parse_previous() {
    split_row "$1"
    prev_target=$F1; prev_kind=$F2; prev_original=$F3; prev_applied=$F4; prev_ou=$F5; prev_og=$F6; prev_om=$F7; prev_ol=$F8
    prev_au=$F9; prev_ag=$F10; prev_am=$F11; prev_al=$F12; prev_prior=$F13
    previous_meta="$prev_au|$prev_ag|$prev_am"
    original_meta="$prev_ou|$prev_og|$prev_om"
    previous_label=$prev_al
    original_label=$prev_ol
}
old_header=''
if [ -e "$OLD_RECOVERY" ]; then
    [ -f "$OLD_RECOVERY" ] && [ ! -L "$OLD_RECOVERY" ] || fail invalid-existing-recovery
    IFS= read -r old_header < "$OLD_RECOVERY" || fail invalid-existing-recovery
    case "$old_header" in GEN5W-RECOVERY-MANIFEST\|1|GEN5W-RECOVERY-MANIFEST\|2) :;; *) fail invalid-existing-recovery;; esac
    old_version=${old_header##*'|'}
    old_targets='|'; old_rows=0; old_line=0
    backup_list=''
    while IFS='|' read -r old_target old_kind old_rest || [ -n "$old_target" ]; do
        [ "$old_kind" = file ] && plain "$R/originals/${old_target#/}" && [ -f "$R/originals/${old_target#/}" ] && backup_list="$backup_list $R/originals/${old_target#/}"
    done < "$OLD_RECOVERY"
    set -f; set -- $backup_list; set +f
    facts "$@" || :
    while IFS= read -r old_record || [ -n "$old_record" ]; do
        old_line=$((old_line+1))
        if [ "$old_line" = 1 ]; then [ "$old_record" = "$old_header" ] || fail invalid-existing-recovery-header; continue; fi
        split_row "$old_record" || fail invalid-existing-recovery-row
        old_target=$F1; old_kind=$F2; old_original=$F3; old_applied=$F4; old_ou=$F5; old_og=$F6; old_om=$F7; old_ol=$F8
        old_au=$F9; old_ag=$F10; old_am=$F11; old_al=$F12; old_prior=$F13; old_extra=$F14
        [ "$FIELDS" -le 14 ] || fail invalid-existing-recovery-row
        [ -n "$old_target" ] || fail invalid-existing-recovery-row
        case "$old_version" in
            1) [ -z "$old_prior$old_extra" ] || fail invalid-existing-recovery-row;;
            2) [ -z "$old_extra" ] || fail invalid-existing-recovery-row;;
        esac
        allowed_target "$old_target" || fail invalid-existing-recovery-target
        case "$old_targets" in *"|$old_target|"*) fail duplicate-existing-recovery-target;; esac
        old_targets="$old_targets$old_target|"
        key "$old_target"; eval "OLDROW_$KEY=\$old_record"
        check_sha "$old_applied" || fail invalid-existing-recovery-applied-hash
        check_meta "$old_au|$old_ag|$old_am" || fail invalid-existing-recovery-applied-metadata
        check_label "$old_al" || fail invalid-existing-recovery-applied-label
        case "$old_version:$old_prior" in
            1:) :;;
            2:-) :;;
            2:*) check_sha "$old_prior" || fail invalid-existing-recovery-prior-hash;;
            *) fail invalid-existing-recovery-prior-hash;;
        esac
        case "$old_kind" in
            file)
                check_sha "$old_original" || fail invalid-existing-recovery-original-hash
                check_meta "$old_ou|$old_og|$old_om" || fail invalid-existing-recovery-original-metadata
                check_label "$old_ol" || fail invalid-existing-recovery-original-label
                old_backup="$R/originals/${old_target#/}"
                plain "$old_backup" && [ -f "$old_backup" ] && [ ! -L "$old_backup" ] && fact "$old_backup" && [ "$FACT_HASH" = "$old_original" ] || fail invalid-existing-recovery-backup
                ;;
            absent)
                [ "$old_original|$old_ou|$old_og|$old_om|$old_ol" = '-|-|-|-|-' ] || fail invalid-existing-recovery-absent-row
                ;;
            *) fail invalid-existing-recovery-kind;;
        esac
        old_rows=$((old_rows+1))
    done < "$OLD_RECOVERY"
    [ "$old_rows" -gt 0 ] || fail invalid-existing-recovery-empty
fi
mkdir -p "$R/originals" "${O%/*}" || fail state-directory
no_links "$R" && no_links "$R/originals" && no_links "${O%/*}" || fail linked-persistent-state
STAGE="$R/.migration.$$"; TX="$R/.transaction.$$"
[ ! -e "$STAGE" ] && [ ! -L "$STAGE" ] && [ ! -e "$TX" ] && [ ! -L "$TX" ] || fail stale-transaction
mkdir -p "$STAGE/originals" || fail stage-directory
rw=0; touched=''; targets='|'; required_bytes=1048576; owner_published=0; recovery_published=0; rollback_complete=1; live_tmp_created=0; overlay_retired=0; overlay_to_finalize=0; system_transaction_committed=0; newrows="$STAGE/recovery-rows"; TXDIR="$STAGE/directory-transaction"; : > "$newrows"; : > "$TX"; : > "$TXDIR"
owner_tmp="$STAGE/owner"; cp "$(mapped "$MANIFEST")" "$owner_tmp" || fail stage-owner-manifest

# An updater may have retired active bind mounts before NEMESIS replaced the
# old package. Adopt that held journal so this transaction either rebinds it on
# a verified rollback or finalizes it after /system commits.
overlay_live=1
overlay_status=$(overlay_cmd status) || fail overlay-status-unavailable
case "$overlay_status" in
    *'state|retired-pending'*) overlay_retired=1; overlay_to_finalize=1;;
    *'state|retiring'*) fail interrupted-overlay-retirement;;
    # Bind mounts never survive a reboot: a journal from an earlier boot (or of
    # an inactive overlay) has nothing live to retire (vehicle 2026-11-19).
    *'state|expired'*|*'state|disabled'*|*'state|prepared'*|*'state|retired'*) overlay_live=0;;
esac

cleanup() {
    rc=$?
    if [ "$rc" -ne 0 ] && [ "$rw" = 1 ]; then
        # Roll back only files that are still either the transaction's new
        # bytes or the exact pre-transaction snapshot. This also preserves an
        # older persistent payload when an update fails.
        oldifs=$IFS; IFS=' '
        for t in $touched; do
            target=${t%%,*}; live=$(mapped "$target")
            txrow=''
            while IFS='|' read -r tx_target tx_live tx_staged tx_kind tx_orig tx_rbkind tx_rbfile tx_rbsha tx_rbu tx_rbg tx_rbm tx_rblabel tx_extra; do
                [ "$tx_target" = "$target" ] || continue
                txrow="$tx_target|$tx_live|$tx_staged|$tx_kind|$tx_orig|$tx_rbkind|$tx_rbfile|$tx_rbsha|$tx_rbu|$tx_rbg|$tx_rbm|$tx_rblabel"
                break
            done < "$TX"
            [ -n "$txrow" ] || { echo "persistent-migrate: rollback snapshot missing for $target" >&2; rollback_complete=0; continue; }
            IFS='|' read -r rt live staged rowkind orig rbkind rbfile rbsha rbu rbg rbm rblabel <<EOF
$txrow
EOF
            IFS=' '
            current=$(sha "$target" 2>/dev/null || :)
            if [ "$rbkind" = absent ]; then
                if [ ! -e "$live" ] && [ ! -L "$live" ]; then :
                elif [ -f "$live" ] && [ ! -L "$live" ] && [ "$current" = "$(sha "$staged" 2>/dev/null)" ]; then rm -f "$live" || rollback_complete=0
                else echo "persistent-migrate: unknown rollback state for $target" >&2; rollback_complete=0; fi
            elif [ "$rbkind" = file ] && [ -f "$(mapped "$rbfile")" ] && [ ! -L "$(mapped "$rbfile")" ] && [ "$(sha "$rbfile")" = "$rbsha" ]; then
                if [ "$current" = "$rbsha" ] && [ "$(meta "$target")" = "$rbu|$rbg|$rbm" ] && [ "$(label "$target")" = "$rblabel" ]; then :
                elif [ "$current" = "$(sha "$staged" 2>/dev/null)" ]; then
                    rollback_tmp="${live%/*}/.gen5w-preupdate-restore.$$"
                    no_links "${live%/*}" && copy_to_new "$rbfile" "$rollback_tmp" || { rollback_complete=0; continue; }
                    set_meta "$rollback_tmp" "$rbu" "$rbg" "$rbm" || { rm -f "$rollback_tmp"; rollback_complete=0; continue; }
                    set_label "$rollback_tmp" "$rblabel" || { rm -f "$rollback_tmp"; rollback_complete=0; continue; }
                    no_links "$live" && mv "$rollback_tmp" "$live" || { rm -f "$rollback_tmp"; rollback_complete=0; continue; }
                    [ "$(sha "$target")" = "$rbsha" ] && [ "$(meta "$target")" = "$rbu|$rbg|$rbm" ] && [ "$(label "$target")" = "$rblabel" ] || rollback_complete=0
                else echo "persistent-migrate: unknown rollback state for $target" >&2; rollback_complete=0; fi
            else
                echo "persistent-migrate: invalid rollback snapshot for $target" >&2; rollback_complete=0
            fi
        done
        IFS=$oldifs
        remount_ro_or_defer || { echo 'persistent-migrate: rollback could not sync /system' >&2; rollback_complete=0; }
        rw=0
    fi
    if [ "$rc" -ne 0 ] && [ "$system_transaction_committed" = 0 ] && [ "$rollback_complete" = 1 ] && [ "$recovery_published" = 1 ]; then
        if [ -f "$STAGE/old-recovery" ]; then publish_copy "$STAGE/old-recovery" "$R/manifest.rollback.$$" "$R/manifest" || :; else rm -f "$R/manifest"; fi
    fi
    if [ "$rc" -ne 0 ] && [ "$system_transaction_committed" = 0 ] && [ "$rollback_complete" = 1 ] && [ "$owner_published" = 1 ]; then
        if [ -f "$STAGE/old-owner" ]; then publish_copy "$STAGE/old-owner" "$O.rollback.$$" "$O" || :; else rm -f "$O"; fi
    fi
    if [ "$rc" -ne 0 ] && [ "$overlay_retired" = 1 ]; then
        if [ "$rollback_complete" = 1 ]; then
            overlay_cmd retire-restore || { echo 'persistent-migrate: owned overlays remain retired; restore plan retained' >&2; rollback_complete=0; }
        else
            echo 'persistent-migrate: persistent rollback is uncertain; owned overlays remain retired for recovery' >&2
        fi
    fi
    if [ "$rc" -ne 0 ] && [ "$rollback_complete" != 1 ]; then
        if no_links "$R" && [ ! -L "$NEEDS_RECOVERY" ] && { [ ! -e "$NEEDS_RECOVERY" ] || [ -f "$NEEDS_RECOVERY" ]; }; then
            (set -C; print -r -- "rollback-incomplete|$(date +%s 2>/dev/null || echo unknown)" > "$NEEDS_RECOVERY") 2>/dev/null ||
                echo 'persistent-migrate: failed to publish recovery-required marker; overlays remain disabled where possible' >&2
            sync
        fi
    fi
    if [ "$rc" -ne 0 ] && [ "$rollback_complete" = 1 ] && [ "$system_transaction_committed" = 0 ]; then
        rm -f "$IN_PROGRESS_MARKER"
        sync
    fi
    if [ "$live_tmp_created" = 1 ] && [ -f "${live_tmp:-}" ] && [ ! -L "${live_tmp:-}" ]; then rm -f "$live_tmp"; fi
    if [ "$rollback_complete" = 1 ] || [ "$rc" = 0 ]; then rm -rf "$STAGE" "$TX"
    else echo "persistent-migrate: preserving uncertain transaction evidence at $STAGE and $TX" >&2; fi
    if [ -d "${LOCK:-}" ] && [ ! -L "$LOCK" ] && [ ! -L "$LOCK/owner" ]; then
        IFS='|' read -r lock_tag lock_pid 2>/dev/null < "$LOCK/owner" || :
        if [ "$lock_tag" = pid ] && [ "$lock_pid" = "$$" ]; then rm -f "$LOCK/owner" && rmdir "$LOCK" 2>/dev/null || :; fi
    fi
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
LOCK="$R/migration.lock"
[ ! -e "$LOCK" ] && [ ! -L "$LOCK" ] && mkdir "$LOCK" || fail migration-busy-or-stale-lock
[ ! -L "$LOCK/owner" ] && (set -C; print -r -- "pid|$$" > "$LOCK/owner") || fail migration-lock-owner
plain "$OVERLAY_STATE_PATH" && [ ! -L "$OVERLAY_STATE_PATH/journal" ] || fail linked-overlay-journal

# Fetch every read-only input in one helper run (an optimisation only: a file
# it cannot read is looked up, and refused, individually below).
prefetch=''
while IFS='|' read -r feature source target digest rest || [ -n "$feature" ]; do
    plain "$source" && plain "$target" || continue
    case "$rest" in
        *'|directory')
            for f in "$(mapped "$source")"/*.xml "$(mapped "$target")"/*.xml; do [ -f "$f" ] && [ ! -L "$f" ] && prefetch="$prefetch $f"; done;;
        *)
            for f in "$(mapped "$source")" "$(mapped "$target")"; do [ -f "$f" ] && [ ! -L "$f" ] && prefetch="$prefetch $f"; done;;
    esac
done < "$(mapped "$MANIFEST")"
set -f; set -- $prefetch; set +f
facts "$@" || :

# Validate all rows and build a complete exact recovery set before /system rw.
while IFS='|' read -r feature source target digest recorded_uid recorded_gid recorded_mode kind extra || [ -n "$feature" ]; do
    recorded_meta="$recorded_uid|$recorded_gid|$recorded_mode"
    [ -z "$feature" ] && continue
    [ -z "$extra" ] || fail malformed-source-row
    case "$feature" in *[!A-Za-z0-9_.-]*|'') fail malformed-feature;; esac
    allowed_target "$target" || fail unsupported-target
    plain "$source" || fail unsafe-source
    case "$kind" in directory) [ -d "$(mapped "$source")" ] || fail unsafe-source;; static|runtime) [ -f "$(mapped "$source")" ] || fail unsafe-source;; *) fail unsupported-kind;; esac
    plain "$target" && no_links "$(mapped "$target")" || fail unsafe-target
    check_sha "$digest" || fail invalid-source-hash
    check_meta "$recorded_meta" || fail invalid-recorded-metadata
    case "$targets" in *"|$target|"*) fail duplicate-target;; esac
    targets="$targets$target|"
    case "$kind" in
      static|runtime)
        fact "$source" && [ "$FACT_HASH" = "$digest" ] || fail source-hash-mismatch
        stock="$ORIGINS/${target#/}"
        plain "$stock" && [ -f "$(mapped "$stock")" ] || fail missing-stock-origin
        origin_record "$target" || fail invalid-stock-origin-record
        stock_sha=$origin_hash; stock_meta=$origin_meta; stock_label=$origin_selabel
        if fact "$target"; then live_sha=$FACT_HASH; live_meta=$FACT_META; live_label=$FACT_LABEL; else live_sha=; live_meta=; live_label=; fi
        count_size "$source"; count_size "$stock"
        if [ -n "$old_header" ]; then
            old_lookup "$target"; previous=$PREV_RECORD
            if [ -n "$previous" ]; then
                parse_previous "$previous"
                previous_applied=$prev_applied; previous_kind=$prev_kind
                [ "$stock_sha" = "$prev_original" ] || fail original-changed-since-install
                if [ "$previous_kind" = file ]; then
                    { [ "$live_sha" = "$previous_applied" ] && [ "$live_meta" = "$previous_meta" ] && [ "$live_label" = "$previous_label" ]; } ||
                    { [ "$live_sha" = "$stock_sha" ] && [ "$live_meta" = "$original_meta" ] && [ "$live_label" = "$original_label" ]; } || fail current-applied-state-mismatch
                elif [ "$previous_kind" = absent ]; then
                    if [ -e "$(mapped "$target")" ]; then [ "$live_sha" = "$previous_applied" ] && [ "$live_meta" = "$previous_meta" ] || fail current-applied-state-mismatch; fi
                else fail malformed-old-kind; fi
            else
            [ "$live_sha" = "$stock_sha" ] && [ "$live_meta" = "$stock_meta" ] && [ "$stock_meta" = "$recorded_meta" ] && [ "$live_label" = "$stock_label" ] || fail new-target-not-stock
            fi
        else
            [ "$stock_sha" = "$live_sha" ] || fail live-stock-mismatch
            [ "$stock_meta" = "$live_meta" ] && [ "$live_meta" = "$recorded_meta" ] && [ "$stock_label" = "$live_label" ] || fail stock-metadata-mismatch
        fi
        ;;
      directory) [ "$target" = /system/etc/permissions ] || fail unsupported-directory-target;;
      *) fail unsupported-kind;;
    esac
done < "$(mapped "$MANIFEST")"

# Directory payload format is source inventory followed by original inventory.
# Expand to per-file allowlisted recovery records; never replace the directory.
while IFS='|' read -r feature source target digest recorded_uid recorded_gid recorded_mode kind extra || [ -n "$feature" ]; do
    recorded_meta="$recorded_uid|$recorded_gid|$recorded_mode"
    [ "$kind" = directory ] || continue
    plain "$source" && [ -d "$(mapped "$source")" ] || fail unsafe-directory-source
    plain "$target" && [ -d "$(mapped "$target")" ] || fail unsafe-directory-target
    case "$target" in /system/etc/permissions) :;; *) fail unsupported-directory-target;; esac
    # Recompute the candidate and stock inventories exactly as prepare.sh does.
    src_inv="$STAGE/source.inventory"; orig_inv="$STAGE/original.inventory"
    ( for f in "$(mapped "$source")"/*.xml; do [ -f "$f" ] || continue; n=${f##*/}; fact "$f" || exit 1; print -r -- "$n|$FACT_HASH|$FACT_META"; done ) > "$src_inv" || fail source-inventory
    if [ -n "$old_header" ]; then
        : > "$orig_inv" || fail original-inventory
        origin_dir="$ORIGINS/${target#/}"
        for origin_file in "$(mapped "$origin_dir")"/*.xml; do
            [ -f "$origin_file" ] || continue
            origin_name=${origin_file##*/}; origin_target="$target/$origin_name"
            old_lookup "$origin_target"; previous=$PREV_RECORD
            [ -n "$previous" ] || :
            if [ -n "$previous" ]; then parse_previous "$previous"; [ "$prev_kind" = absent ] && continue; fi
            if [ -n "$previous" ]; then
                print -r -- "$origin_name|$prev_original|$prev_ou|$prev_og|$prev_om" >> "$orig_inv" || fail original-inventory
            else
                origin_record "$origin_target" || fail original-inventory-origin
                print -r -- "$origin_name|$origin_hash|$origin_uid|$origin_gid|$origin_mode" >> "$orig_inv" || fail original-inventory
            fi
        done
    else
        ( for f in "$(mapped "$target")"/*.xml; do [ -f "$f" ] || continue; n=${f##*/}; fact "$target/$n" || exit 1; print -r -- "$n|$FACT_HASH|$FACT_META"; done ) > "$orig_inv" || fail original-inventory
    fi
    cat "$src_inv" "$orig_inv" > "$STAGE/directory.digest" || fail directory-inventory
    fresh "$STAGE/directory.digest" && [ "$FACT_HASH" = "$digest" ] || fail directory-hash-mismatch
    dir_label=$(label "$target") || fail target-directory-label
    : > "$STAGE/dir-pending" || fail stage-entry
    for f in "$(mapped "$source")"/*.xml; do
        [ -f "$f" ] || continue
        count_size "$f"
        name=${f##*/}; case "$name" in *[!A-Za-z0-9_.-]*|.*) fail unsafe-directory-entry;; esac
        target_file="$target/$name"; allowed_target "$target_file" || fail unsupported-expanded-target
        mp "$target_file"; live=$MP; staged="$STAGE/new-$name"
        origin="$ORIGINS/${target_file#/}"; mp "$origin"; MO=$MP
        case "$targets" in *"|$target_file|"*) fail duplicate-expanded-target;; esac
        targets="$targets$target_file|"
        if [ -n "$old_header" ]; then
            old_lookup "$target_file"; previous=$PREV_RECORD
            if [ -z "$previous" ]; then
                previous_kind=new
            else
            parse_previous "$previous"
            previous_kind=$prev_kind; previous_applied=$prev_applied
            fi
            if [ "$previous_kind" = new ]; then
                if [ -e "$live" ]; then
                    origin="$ORIGINS/${target_file#/}"
                    plain "$origin" && [ -f "$MO" ] || fail new-target-not-stock
                    origin_record "$target_file" || fail original-label
                    original_sha=$origin_hash; original_meta=$origin_meta; original_label=$origin_selabel
                    fact "$live" && [ "$FACT_HASH" = "$original_sha" ] && [ "$FACT_META" = "$original_meta" ] && [ "$FACT_LABEL" = "$original_label" ] || fail new-target-not-stock
                    original_uid=${original_meta%%'|'*}; original_rest=${original_meta#*'|'}; original_gid=${original_rest%%'|'*}; original_mode=${original_rest#*'|'}; kind_row=file
                    staged_original="$STAGE/originals/${target_file#/}"; mkdir -p "${staged_original%/*}" || fail backup-directory
                    cp "$MO" "$staged_original" || fail backup-stage
                else
                    origin="$ORIGINS/${target_file#/}"
                    if [ -e "$MO" ]; then
                        [ -f "$MO" ] && [ "$(file_bytes "$origin")" = 0 ] || fail new-target-missing-from-live
                    fi
                    original_sha=-; original_meta='-:-:-'; original_label=-; original_uid=-; original_gid=-; original_mode=-; kind_row=absent
                fi
            elif [ "$previous_kind" = file ]; then
                origin="$ORIGINS/${target_file#/}"
                plain "$origin" && [ -f "$MO" ] || fail missing-directory-origin
                origin_record "$target_file" || fail original-label
                original_sha=$origin_hash; original_meta=$origin_meta; original_label=$origin_selabel
                parse_previous "$previous"
                [ "$original_sha" = "$prev_original" ] || fail original-changed-since-install
                count_size "$origin"
                original_uid=${original_meta%%'|'*}; original_rest=${original_meta#*'|'}; original_gid=${original_rest%%'|'*}; original_mode=${original_rest#*'|'}
                if [ -e "$live" ]; then
                    [ -f "$live" ] && [ ! -L "$live" ] || fail nonregular-existing-entry
                    fact "$live" || fail current-applied-state-mismatch
                    { [ "$FACT_HASH" = "$previous_applied" ] && [ "$FACT_META" = "$previous_meta" ] && [ "$FACT_LABEL" = "$previous_label" ]; } ||
                    { [ "$FACT_HASH" = "$original_sha" ] && [ "$FACT_META" = "$original_meta" ] && [ "$FACT_LABEL" = "$original_label" ]; } || fail current-applied-state-mismatch
                else fail current-applied-state-mismatch; fi
                staged_original="$STAGE/originals/${target_file#/}"
                mkdir -p "${staged_original%/*}" || fail backup-directory
                cp "$MO" "$staged_original" || fail backup-stage
                kind_row=file
            elif [ "$previous_kind" = absent ]; then
                original_sha=-; original_meta='-:-:-'; original_label=-; original_uid=-; original_gid=-; original_mode=-; kind_row=absent
                if [ -e "$live" ]; then
                    [ -f "$live" ] && [ ! -L "$live" ] && fact "$live" && [ "$FACT_HASH" = "$previous_applied" ] && [ "$FACT_META" = "$previous_meta" ] && [ "$FACT_LABEL" = "$previous_label" ] || fail current-applied-state-mismatch
                fi
            else fail malformed-old-kind; fi
        elif [ -e "$live" ]; then
            [ -f "$live" ] && [ ! -L "$live" ] || fail nonregular-existing-entry
            origin="$ORIGINS/${target_file#/}"
            plain "$origin" && [ -f "$MO" ] || fail missing-directory-origin
            origin_record "$target_file" || fail original-label
            original_sha=$origin_hash; original_meta=$origin_meta; original_label=$origin_selabel
            count_size "$origin"
            fact "$live" && [ "$original_sha" = "$FACT_HASH" ] && [ "$original_meta" = "$FACT_META" ] && [ "$original_label" = "$FACT_LABEL" ] || fail changed-directory-origin
            original_uid=${original_meta%%'|'*}; original_rest=${original_meta#*'|'}; original_gid=${original_rest%%'|'*}; original_mode=${original_rest#*'|'}
            staged_original="$STAGE/originals/${target_file#/}"
            mkdir -p "${staged_original%/*}" || fail backup-directory
            cp "$MO" "$staged_original" || fail backup-stage
            kind_row=file
        else
            origin="$ORIGINS/${target_file#/}"
            if [ -e "$MO" ]; then
                [ -f "$MO" ] && [ "$(file_bytes "$origin")" = 0 ] || fail target-missing-from-stock
            fi
            original_sha=-; original_meta='-:-:-'; original_label=-; original_uid=-; original_gid=-; original_mode=-; kind_row=absent
        fi
        fact "$f" || fail source-entry-hash
        source_sha=$FACT_HASH; source_meta=$FACT_META
        if [ "$kind_row" = file ]; then
            [ "$source_meta" = "$original_meta" ] || fail staged-metadata-mismatch
            source_label=$original_label
        else
            source_label=$dir_label
        fi
        cp "$f" "$staged" || fail stage-entry
        print -r -- "$staged|$source_meta|$source_label" >> "$STAGE/dir-settle" || fail stage-entry
        print -r -- "$staged|$target_file|$kind_row|$original_sha|$original_uid|$original_gid|$original_mode|$original_label|$live" >> "$STAGE/dir-pending" || fail stage-entry
    done
    # Every staged entry gets its metadata and label in one helper run, then
    # its recovery row from the re-read applied state.
    settle_all "$STAGE/dir-settle" || fail stage-entry-metadata
    rm -f "$STAGE/dir-settle"
    while IFS='|' read -r staged target_file kind_row original_sha original_uid original_gid original_mode original_label live; do
        fact "$staged" || fail stage-entry-metadata
        applied_sha=$FACT_HASH; applied_label=$FACT_LABEL; applied_meta=$FACT_META
        applied_uid=${applied_meta%%'|'*}; applied_mode=${applied_meta##*'|'}; applied_gid=${applied_meta#*'|'}; applied_gid=${applied_gid%'|'*}
        print -r -- "$target_file|$kind_row|$original_sha|$applied_sha|$original_uid|$original_gid|$original_mode|$original_label|$applied_uid|$applied_gid|$applied_mode|$applied_label" >> "$newrows" || fail row-write
        key "$target_file"; eval "NEWROW_$KEY=1"
        print -r -- "$target_file|$live|$staged|$kind_row|$original_sha" >> "$TXDIR" || fail transaction-row
    done < "$STAGE/dir-pending"
    rm -f "$STAGE/dir-pending"
done < "$(mapped "$MANIFEST")"

# Publish expanded originals immutably before arming the recovery manifest.
: > "$STAGE/backup-list" || fail backup-inventory
while IFS='|' read -r backup_target backup_kind backup_original backup_applied backup_ou backup_og backup_om backup_ol backup_au backup_ag backup_am backup_al backup_extra; do
    [ "$backup_kind" = file ] || continue
    staged_backup="$STAGE/originals/${backup_target#/}"
    [ -f "$staged_backup" ] && [ ! -L "$staged_backup" ] || continue
    print -r -- "$staged_backup" >> "$STAGE/backup-list" || fail backup-inventory
done < "$newrows"
compare=''
while IFS= read -r staged_backup; do
    rel=${staged_backup#"$STAGE/originals/"}; backup="$R/originals/$rel"
    [ -f "$backup" ] && [ ! -L "$backup" ] && [ -f "$staged_backup" ] && compare="$compare $backup $staged_backup"
done < "$STAGE/backup-list"
set -f; set -- $compare; set +f
facts "$@" || fail immutable-backup-mismatch
while IFS= read -r staged_backup; do
    [ -f "$staged_backup" ] && [ ! -L "$staged_backup" ] || fail unsafe-staged-backup
    rel=${staged_backup#"$STAGE/originals/"}; backup="$R/originals/$rel"
    if [ -e "$backup" ]; then
        [ -f "$backup" ] && [ ! -L "$backup" ] && fact "$staged_backup" && staged_hash=$FACT_HASH && fact "$backup" && [ "$FACT_HASH" = "$staged_hash" ] || fail immutable-backup-mismatch
    else
        mkdir -p "${backup%/*}" || fail backup-directory
        no_links "${backup%/*}" || fail linked-backup-directory
        publish_copy "$staged_backup" "$backup.new.$$" "$backup" || fail backup-publish
    fi
done < "$STAGE/backup-list"

# Static entries and existing recovery backups are staged immutably.
while IFS='|' read -r feature source target digest recorded_uid recorded_gid recorded_mode kind extra || [ -n "$feature" ]; do
    recorded_meta="$recorded_uid|$recorded_gid|$recorded_mode"
    case "$kind" in static|runtime) :;; *) continue;; esac
    mp "$target"; live=$MP; origin="$ORIGINS/${target#/}"
    fact "$source" || fail source-hash-mismatch
    source_sha=$FACT_HASH; source_meta=$FACT_META
    origin_record "$target" || fail original-label
    original_sha=$origin_hash; original_meta=$origin_meta; original_label=$origin_selabel
    [ "$source_meta" = "$recorded_meta" ] && [ "$source_meta" = "$original_meta" ] || fail staged-metadata-mismatch
    source_label=$original_label
    bstage="$STAGE/originals/${target#/}"; mkdir -p "${bstage%/*}" || fail backup-directory
    mp "$origin"; cp "$MP" "$bstage" || fail backup-stage
    backup="$R/originals/${target#/}"
    if [ -e "$backup" ]; then
        [ -f "$backup" ] && [ ! -L "$backup" ] && fact "$backup" && [ "$FACT_HASH" = "$original_sha" ] || fail immutable-backup-mismatch
    else
        mkdir -p "${backup%/*}" || fail backup-directory
        no_links "${backup%/*}" || fail linked-backup-directory
        publish_copy "$bstage" "$backup.new.$$" "$backup" || fail backup-publish
    fi
    original_uid=${original_meta%%'|'*}; original_mode=${original_meta##*'|'}; original_gid=${original_meta#*'|'}; original_gid=${original_gid%'|'*}
    applied_uid=${source_meta%%'|'*}; applied_mode=${source_meta##*'|'}; applied_gid=${source_meta#*'|'}; applied_gid=${applied_gid%'|'*}
    print -r -- "$target|file|$original_sha|$source_sha|$original_uid|$original_gid|$original_mode|$original_label|$applied_uid|$applied_gid|$applied_mode|$source_label" >> "$newrows" || fail row-write
    key "$target"; eval "NEWROW_$KEY=1"
    cp "$(mapped "$source")" "$STAGE/new-${target##*/}" || fail stage-payload
    print -r -- "$STAGE/new-${target##*/}|$applied_uid|$applied_gid|$applied_mode|$source_label" >> "$STAGE/static-settle" || fail stage-payload
    print -r -- "$target|$live|$STAGE/new-${target##*/}|file|$original_sha" >> "$TX" || fail transaction-row
done < "$(mapped "$MANIFEST")"
settle_all "$STAGE/static-settle" || fail stage-payload-metadata
rm -f "$STAGE/static-settle"
cat "$TXDIR" >> "$TX" || fail transaction-order
rm -f "$TXDIR" || fail transaction-order-cleanup

# Snapshot every pre-update target with bytes and metadata before any system
# write. The immutable stock originals remain separately reserved for USB restore.
snapshot_tx="$STAGE/transaction-with-snapshots"
: > "$snapshot_tx" || fail rollback-snapshot-index
while IFS='|' read -r target live staged rowkind orig extra || [ -n "$target" ]; do
    [ -n "$target" ] || continue
    mp "$target"; live_mapped=$MP
    if [ -e "$live_mapped" ] || [ -L "$live_mapped" ]; then
        [ -f "$live_mapped" ] && [ ! -L "$live_mapped" ] || fail nonregular-preupdate-target
        fact "$target" || fail snapshot-hash
        rbsha=$FACT_HASH; rbmeta=$FACT_META; rblabel=$FACT_LABEL
        rbu=${rbmeta%%'|'*}; rbrest=${rbmeta#*'|'}; rbg=${rbrest%%'|'*}; rbm=${rbrest#*'|'}
        rbfile="$STAGE/rollback/${target#/}"
        mkdir -p "${rbfile%/*}" && no_links "${rbfile%/*}" && cp "$live_mapped" "$rbfile" || fail snapshot-copy
        print -r -- "$rbfile|$rbu|$rbg|$rbm|$rblabel" >> "$STAGE/snapshot-settle" || fail snapshot-metadata-copy
        count_size "$rbfile"
        print -r -- "$target|$live|$staged|$rowkind|$orig|file|$rbfile|$rbsha|$rbu|$rbg|$rbm|$rblabel" >> "$snapshot_tx" || fail snapshot-index
    else
        print -r -- "$target|$live|$staged|$rowkind|$orig|absent|-|-|-|-|-|-" >> "$snapshot_tx" || fail snapshot-index
    fi
done < "$TX"
settle_all "$STAGE/snapshot-settle" || fail snapshot-metadata-copy
while IFS='|' read -r target live staged rowkind orig rbkind rbfile rbsha rbu rbg rbm rblabel; do
    [ "$rbkind" = file ] || continue
    fact "$rbfile" && [ "$FACT_HASH" = "$rbsha" ] && [ "$FACT_META" = "$rbu|$rbg|$rbm" ] && [ "$FACT_LABEL" = "$rblabel" ] || fail snapshot-verification
done < "$snapshot_tx"
rm -f "$STAGE/snapshot-settle"
mv "$snapshot_tx" "$TX" || fail snapshot-index-publish
if [ -n "$SIZE_LIST" ]; then
    set -f; set -- $SIZE_LIST; set +f
    counted=$("$HELPER" size-sum "$@") || fail invalid-size
    case "$counted" in ''|*[!0-9]*) fail invalid-size;; esac
    required_bytes=$((required_bytes + counted))
fi

available_bytes=$(free_bytes) || fail storage-query
case "$available_bytes" in ''|*[!0-9]*) fail invalid-storage-size;; esac
[ "$available_bytes" -gt "$required_bytes" ] || fail insufficient-storage

# If an earlier migration is already committed, preserve its stock bytes and
# restore protocol unchanged. A new transaction is permitted only for targets
# that are still in a known patched state; v2 restore tracks the previous hash.
# For updates, retain first stock bytes and require the new plan to account for
# every previously protected target. Publish v2 with the previous apply hash.
recovery_new="$STAGE/recovery-manifest"
if [ -z "$old_header" ]; then
    print -r -- 'GEN5W-RECOVERY-MANIFEST|1' > "$recovery_new" || fail recovery-header
    cat "$newrows" >> "$recovery_new" || fail recovery-rows
else
    recheck=''
    while IFS='|' read -r t k rest || [ -n "$t" ]; do
        [ "$k" = file ] && [ -f "$R/originals/${t#/}" ] && [ ! -L "$R/originals/${t#/}" ] && recheck="$recheck $R/originals/${t#/}"
    done < "$OLD_RECOVERY"
    set -f; set -- $recheck; set +f
    facts "$@" || fail existing-recovery-corrupt
    while IFS='|' read -r t k orig applied ou og om ol au ag am al || [ -n "$t" ]; do
        [ "$t" = GEN5W-RECOVERY-MANIFEST ] && continue; [ -n "$t" ] || continue
        key "$t"; eval "listed=\${NEWROW_$KEY-}"
        [ -n "$listed" ] || { cat "$newrows" >&2; fail "update-target-removed target=$t"; }
        if [ "$k" = file ]; then
            b="$R/originals/${t#/}"; [ -f "$b" ] && [ ! -L "$b" ] && fact "$b" && [ "$FACT_HASH" = "$orig" ] || fail existing-recovery-corrupt
        fi
    done < "$OLD_RECOVERY"
    print -r -- 'GEN5W-RECOVERY-MANIFEST|2' > "$recovery_new" || fail recovery-header
    while IFS='|' read -r t k orig applied ou og om ol au ag am al || [ -n "$t" ]; do
        [ -n "$t" ] || continue
        old_lookup "$t"; previous=$PREV_RECORD; prior=-
        if [ -n "$previous" ]; then
            parse_previous "$previous"
            [ "$prev_original" = "$orig" ] || fail original-changed-since-install
            prior=$prev_applied
        fi
        print -r -- "$t|$k|$orig|$applied|$ou|$og|$om|$ol|$au|$ag|$am|$al|$prior" >> "$recovery_new" || fail recovery-rows
    done < "$newrows"
fi
cp "$owner_tmp" "$STAGE/owner.new" || fail owner-stage
sync_all || fail prewrite-sync
if [ -f "$O" ]; then cp "$O" "$STAGE/old-owner" || fail old-owner-backup; fi
if [ -f "$R/manifest" ]; then cp "$R/manifest" "$STAGE/old-recovery" || fail old-recovery-backup; fi
mv "$STAGE/owner.new" "$O" || fail owner-publish
owner_published=1
mv "$recovery_new" "$R/manifest" || fail recovery-publish
recovery_published=1
sync_all || fail recovery-sync

# Retire only after all source/origin rows, immutable backups, rollback data,
# and the new emergency restore manifest have been fully staged and published.
# The live transaction keeps a durable rebind plan until /system is committed.
if [ "$overlay_retired" = 0 ] && [ "$overlay_live" = 1 ] && [ -s "$OVERLAY_STATE_PATH/journal" ]; then
    overlay_cmd retire-live hold || fail owned-overlay-retirement
    overlay_retired=1; overlay_to_finalize=1
fi

while IFS='|' read -r preflight_target preflight_live preflight_staged preflight_kind preflight_original preflight_extra || [ -n "$preflight_target" ]; do
    [ -n "$preflight_target" ] || continue
    target_visible "$preflight_target"
    visible_rc=$?
    [ "$visible_rc" -eq 1 ] || { [ "$visible_rc" -eq 0 ] && fail target-is-mounted; fail target-mount-state-unknown; }
done < "$TX"
(set -C; print -r -- "system-write-started|$(date +%s 2>/dev/null || echo unknown)" > "$IN_PROGRESS_MARKER") 2>/dev/null || fail write-progress-marker
sync_all || fail progress-marker-sync
rw=1
published=''
remount_rw || fail remount-rw
while IFS='|' read -r target live staged rowkind original_sha || [ -n "$target" ]; do
    [ -n "$target" ] || continue
    no_links "$live" || fail linked-live-target
    parent=${live%/*}; mkdir -p "$parent" && no_links "$parent" || fail target-parent
    if [ "$rowkind" = absent ]; then :; fi
    live_tmp="$live.new.$$"
    [ ! -e "$live_tmp" ] && [ ! -L "$live_tmp" ] || fail unsafe-target-temp
    copy_to_new "$staged" "$live_tmp" || fail unsafe-target-temp
    live_tmp_created=1
    fact "$staged" || fail staged-label
    staged_meta=$FACT_META; staged_label=$FACT_LABEL
    staged_uid=${staged_meta%%'|'*}; staged_mode=${staged_meta##*'|'}; staged_gid=${staged_meta#*'|'}; staged_gid=${staged_gid%'|'*}
    mp "$live_tmp"; "$HELPER" settle "$MP" "$staged_uid" "$staged_gid" "$staged_mode" "$staged_label" || fail live-metadata
    touched="$target,$rowkind $touched"
    no_links "$live" || fail linked-live-target
    mv "$live_tmp" "$live" || fail publish-target
    live_tmp_created=0
    published="$published $target"
done < "$TX"
# Verify every published target against its staged bytes in one helper run;
# a mismatch fails here and the EXIT trap rolls back every touched target.
set -f; set -- $published; set +f
facts "$@" || fail applied-state-mismatch
while IFS='|' read -r target live staged rowkind original_sha || [ -n "$target" ]; do
    [ -n "$target" ] || continue
    fact "$staged" || fail applied-state-mismatch
    expected=$FACT_HASH; staged_meta=$FACT_META; staged_label=$FACT_LABEL
    fact "$target" && [ "$FACT_HASH" = "$expected" ] && [ "$FACT_META" = "$staged_meta" ] && [ "$FACT_LABEL" = "$staged_label" ] || fail applied-state-mismatch
done < "$TX"
sync_all || fail system-sync
remount_ro_or_defer || fail system-remount-ro
rw=0
system_transaction_committed=1
overlay_retired=0
sync_all || fail final-sync
(set -C; print -r -- "persistent-commit|$(date +%s 2>/dev/null || echo unknown)" > "$COMMITTED_MARKER") 2>/dev/null || fail commit-marker
sync_all || fail commit-marker-sync
if [ "$overlay_to_finalize" = 1 ]; then
    # A failure here leaves the installed transaction and its emergency
    # restore manifest intact. Do not rebind over the newly applied payload.
    overlay_to_finalize=0
    overlay_cmd retire-finalize || fail overlay-retirement-finalize
fi
rm -f "$COMMITTED_MARKER" "$IN_PROGRESS_MARKER" || fail commit-marker-clear
sync_all || fail commit-marker-clear-sync
if [ "$RO_DEFERRED" = 1 ]; then echo 'persistent-migrate: applied; /system read-only after the required reboot'
else echo 'persistent-migrate: applied; /system verified read-only; normal reboot is required'; fi
exit 0
