#!/system/bin/sh
# Fixed-function emergency restore. All targets are explicitly allowlisted.
set -u

USB=${GEN5W_RECOVERY_USB_ROOT:-${GEN5W_RECOVERY_TEST_USB:-}}
ROOT=${GEN5W_RECOVERY_TEST_ROOT:-}
HELPER=${GEN5W_RECOVERY_TEST_HELPER:-}
if [ -z "$USB" ]; then
    USB=/mnt/media_rw/usb1
fi
if [ -z "$HELPER" ]; then
    HELPER="$USB/bin/dex-patch"
fi
if [ -z "$ROOT" ]; then
    ROOT=
fi
RECOVERY=/data/local/gen5w-portable/persistent/recovery
if [ -n "$ROOT" ]; then
    RECOVERY="$ROOT/data/local/gen5w-portable/persistent/recovery"
fi
MANIFEST="$RECOVERY/manifest"
REPORT="$USB/GEN5W-RECOVERY-RESULT.txt"
DONE="$RECOVERY/restore.done"
TMP="$RECOVERY/.restore.$$"
SYSTEM_RW=0

say() { echo "[recovery] $*"; }
system_is_ro() {
    "$HELPER" is-ro
}
remount_system_ro() {
    "$HELPER" remount-ro || return 1
    system_is_ro
}
fail() {
    reason=$*
    if [ "$SYSTEM_RW" = 1 ]; then
        remount_system_ro >/dev/null 2>&1 && SYSTEM_RW=0
        [ "$SYSTEM_RW" = 0 ] || reason="$reason;system-remount-ro-failed"
    fi
    say "result=failed reason=$reason"
    mkdir -p "$USB" 2>/dev/null || :
    [ ! -L "$REPORT" ] && print -r -- "result=failed
reason=$reason" > "$REPORT" 2>/dev/null || :
    rm -f "$TMP"
    exit 1
}
path_for() {
    case "$1" in
        /system/app/Iap2ServerApp.odex|/system/app/HKMC_DiPO.odex|/system/app/HKMC_GPM.odex|/system/app/HKMC_WifiSettings.odex|/system/lib/libCarPlayAudio.so|/system/build.prop|/system/etc/qb_runtime.sh|/system/etc/featurexml.cfg|/system/onebin/*/featurexml.cfg|/system/featurexml/*/featurexml.cfg|/system/*/featurexml.cfg|/system/etc/permissions/*.xml|/system/etc/permissions/android.hardware.wifi.xml|/system/etc/permissions/com.hkmc.software.connectivity.androidauto_wireless.xml|/system/etc/permissions/com.hkmc.software.connectivity.carplay_wireless.xml|/system/etc/permissions/com.hkmc.software.wifihotspot.xml)
            case "$1" in *..*|*'//'*) return 1;; esac
            case "$1" in /system/etc/permissions/*.xml)
                permission_file=${1##*/}
                case "$permission_file" in ''|*[!a-zA-Z0-9_.+-]*|.*) return 1;; esac
                [ "$1" = "/system/etc/permissions/$permission_file" ] || return 1
                ;;
            esac
            case "$1" in
                /system/onebin/*/featurexml.cfg) region=${1#/system/onebin/}; region=${region%/featurexml.cfg};;
                /system/featurexml/*/featurexml.cfg) region=${1#/system/featurexml/}; region=${region%/featurexml.cfg};;
                /system/*/featurexml.cfg) region=${1#/system/}; region=${region%/featurexml.cfg};;
                *) region=;;
            esac
            case "$region" in ''|*[!a-zA-Z0-9_-]*)
                case "$1" in /system/*/featurexml.cfg|/system/onebin/*/featurexml.cfg|/system/featurexml/*/featurexml.cfg) return 1;; esac;;
            esac
            if [ -n "$ROOT" ]; then print -r -- "$ROOT$1"; else print -r -- "$1"; fi
            ;;
        *) return 1;;
    esac
}
hash_file() {
    if [ -n "$ROOT" ]; then
        GEN5W_RECOVERY_TEST_TMP=$TMP; export GEN5W_RECOVERY_TEST_TMP
    fi
    "$HELPER" sha256 "$1" 2>/dev/null
}
metadata() { "$HELPER" metadata "$1" 2>/dev/null; }
boot_id() {
    if [ -n "$ROOT" ]; then "$HELPER" boot 2>/dev/null
    else cat /proc/sys/kernel/random/boot_id 2>/dev/null
    fi
}
valid_boot_id() {
    case "$1" in ????????-????-????-????-????????????) :;; *) return 1;; esac
    case "$1" in *[!a-f0-9-]*) return 1;; esac
    return 0
}
label_of() {
    "$HELPER" label "$1" 2>/dev/null
}
set_metadata() {
    "$HELPER" setmeta "$1" "$2" "$3" "$4"
}
set_label() {
    # SELinux without a loaded policy refuses the write; accept only when the
    # file already reads back the exact wanted label.
    "$HELPER" setlabel "$1" "$2" || [ "$("$HELPER" label "$1" 2>/dev/null)" = "$2" ]
}
trap 'fail interrupted' HUP INT TERM
is_link() { [ -L "$1" ]; }
no_link_components() {
    component=$1
    while [ -n "$component" ] && [ "$component" != / ]; do
        [ ! -L "$component" ] || return 1
        component=${component%/*}
        [ -n "$component" ] || component=/
    done
}
valid_sha() {
    case "$1" in *[!a-f0-9]*) return 1;; esac
    [ "${#1}" -eq 64 ]
}

[ ! -L "$USB/bin" ] && [ ! -L "$HELPER" ] && [ -x "$HELPER" ] || fail missing-or-linked-helper
[ ! -L "$REPORT" ] || fail linked-report
[ -d "$RECOVERY" ] || fail missing-recovery-data
[ -f "$MANIFEST" ] && no_link_components "$MANIFEST" || fail missing-or-linked-manifest
[ -d "$RECOVERY/originals" ] && no_link_components "$RECOVERY/originals" || fail missing-or-linked-originals
[ ! -L "$DONE" ] || fail linked-completion-marker
[ ! -e "$TMP" ] && [ ! -L "$TMP" ] || fail linked-or-stale-completion-temp

# Validate the entire manifest and every backup/live state before remounting.
mkdir -p "$RECOVERY" || fail recovery-directory
MANIFEST_SHA=$(hash_file "$MANIFEST") || fail unreadable-manifest
valid_sha "$MANIFEST_SHA" || fail invalid-manifest-digest
# Hash helpers and external actors can change the private completion path after
# the initial preflight. Recheck before any mount change, then use noclobber at
# creation so an existing path cannot be followed by shell redirection.
[ ! -e "$TMP" ] && [ ! -L "$TMP" ] || fail linked-or-stale-completion-temp
IFS= read -r manifest_header < "$MANIFEST" || fail invalid-manifest
case "$manifest_header" in
    GEN5W-RECOVERY-MANIFEST\|1) manifest_version=1;;
    GEN5W-RECOVERY-MANIFEST\|2) manifest_version=2;;
    *) fail invalid-manifest;;
esac
seen='|'
while IFS='|' read -r target kind original_sha applied_sha orig_uid orig_gid orig_mode orig_label applied_uid applied_gid applied_mode applied_label prior_applied_sha || [ -n "$target" ]; do
    [ "$target" = 'GEN5W-RECOVERY-MANIFEST' ] && continue
    [ "$target" = '' ] && continue
    case "$seen" in *"|$target|"*) fail duplicate-target;; esac
    seen="$seen$target|"
    live=$(path_for "$target") || fail unknown-target
    no_link_components "$live" || fail symlink-target
    valid_sha "$applied_sha" || fail invalid-applied-digest
    if [ "$manifest_version" = 2 ]; then
        [ "$prior_applied_sha" = - ] || valid_sha "$prior_applied_sha" || fail invalid-prior-applied-digest
    else
        [ -z "$prior_applied_sha" ] || fail invalid-v1-row
    fi
    case "$kind" in
        file)
            valid_sha "$original_sha" || fail invalid-original-digest
            case "$orig_uid:$orig_gid:$orig_mode:$applied_uid:$applied_gid:$applied_mode" in *[!0-9:]*|:*|*:) fail invalid-metadata;; esac
            case "$orig_label:$applied_label" in *'|'*|:|:*) fail invalid-label;; esac
            backup="$RECOVERY/originals${target}"
            [ -f "$backup" ] && no_link_components "$backup" || fail missing-or-linked-backup
            [ "$(hash_file "$backup")" = "$original_sha" ] || fail corrupt-backup
            ;;
        absent)
            [ "$original_sha:$orig_uid:$orig_gid:$orig_mode:$orig_label" = '-:-:-:-:-' ] || fail invalid-absent-record
            case "$applied_uid:$applied_gid:$applied_mode" in *[!0-9:]*|:*|*:) fail invalid-metadata;; esac
            [ -n "$applied_label" ] || fail invalid-label
            ;;
        *) fail invalid-kind;;
    esac
    if [ -e "$live" ]; then
        current=$(hash_file "$live") || fail unreadable-target
        [ "$current" = "$original_sha" ] || [ "$current" = "$applied_sha" ] ||
            { [ "$manifest_version" = 2 ] && [ "$prior_applied_sha" != - ] && [ "$current" = "$prior_applied_sha" ]; } || fail foreign-target-hash
        if [ "$current" = "$original_sha" ]; then
            [ "$(metadata "$live")" = "$orig_uid|$orig_gid|$orig_mode" ] && [ "$(label_of "$live")" = "$orig_label" ] || fail original-metadata-mismatch
        else
            [ "$(metadata "$live")" = "$applied_uid|$applied_gid|$applied_mode" ] && [ "$(label_of "$live")" = "$applied_label" ] || fail applied-metadata-mismatch
        fi
    elif [ "$kind" = file ]; then fail missing-target; fi
done < "$MANIFEST"

# A completion marker is tied to the exact manifest and current restored state.
# It cannot hide a later update or foreign modification.
if [ -f "$DONE" ]; then
    done_magic= done_version= done_sha= done_boot= done_extra=
    IFS='|' read -r done_magic done_version done_sha done_boot done_extra < "$DONE" || :
    [ "$done_magic" = GEN5W-RESTORE-DONE ] && [ "$done_version" = 1 ] &&
        [ "$done_sha" = "$MANIFEST_SHA" ] && [ -z "$done_extra" ] && valid_boot_id "$done_boot" || fail stale-completion-marker
    while IFS='|' read -r target kind original_sha applied_sha orig_uid orig_gid orig_mode orig_label applied_uid applied_gid applied_mode applied_label prior_applied_sha || [ -n "$target" ]; do
        [ "$target" = 'GEN5W-RECOVERY-MANIFEST' ] && continue
        [ "$target" = '' ] && continue
        live=$(path_for "$target") || fail unknown-target
        no_link_components "$live" || fail symlink-target
        if [ "$kind" = absent ]; then
            [ ! -e "$live" ] || fail target-changed-after-restore
        else
            [ -f "$live" ] && [ "$(hash_file "$live")" = "$original_sha" ] || fail target-changed-after-restore
            [ "$(metadata "$live")" = "$orig_uid|$orig_gid|$orig_mode" ] && [ "$(label_of "$live")" = "$orig_label" ] || fail target-metadata-changed-after-restore
        fi
    done < "$MANIFEST"
    if ! system_is_ro; then
        # A prior restore marker does not prove the live mount stayed read-only.
        # Reassert the invariant on every exit while preserving the no-reboot
        # behavior for an already-completed restore.
        SYSTEM_RW=1
        fail system-not-read-only
    fi
    current_boot=$(boot_id) || fail boot-id-unavailable
    valid_boot_id "$current_boot" || fail invalid-boot-id
    if [ "$current_boot" = "$done_boot" ]; then
        fail reboot-not-confirmed
    fi
    print -r -- "result=success
already-restored=1
reboot=confirmed
manifest_sha256=$MANIFEST_SHA" > "$REPORT" || fail report-write
    exit 0
fi

# Treat /system as potentially writable before invoking remount. If the helper
# partially succeeds or a signal arrives after the mount change but before the
# subprocess returns, the EXIT/signal path must still attempt a read-only remount.
SYSTEM_RW=1
if [ -n "$ROOT" ]; then
    "$HELPER" remount-rw || fail remount-rw
else
    "$HELPER" remount-rw || fail remount-rw
fi

mkdir -p "$RECOVERY" || fail recovery-directory
while IFS='|' read -r target kind original_sha applied_sha orig_uid orig_gid orig_mode orig_label applied_uid applied_gid applied_mode applied_label prior_applied_sha || [ -n "$target" ]; do
    [ "$target" = 'GEN5W-RECOVERY-MANIFEST' ] && continue
    [ "$target" = '' ] && continue
    live=$(path_for "$target") || fail unknown-target
    no_link_components "$live" || fail symlink-target-during-restore
    if [ "$kind" = absent ]; then
        if [ -e "$live" ]; then
            current=$(hash_file "$live") || fail unreadable-target-during-restore
            [ "$current" = "$applied_sha" ] ||
                { [ "$manifest_version" = 2 ] && [ "$prior_applied_sha" != - ] && [ "$current" = "$prior_applied_sha" ]; } || fail changed-during-restore
            no_link_components "$live" || fail symlink-target-during-restore
            rm -f "$live" || fail remove-target
        fi
        [ ! -e "$live" ] || fail absent-target-remains
    else
        current=$(hash_file "$live") || fail target-disappeared-during-restore
        if [ "$current" = "$applied_sha" ] ||
                { [ "$manifest_version" = 2 ] && [ "$prior_applied_sha" != - ] && [ "$current" = "$prior_applied_sha" ]; }; then
            backup="$RECOVERY/originals${target}"
            parent=${live%/*}
            mkdir -p "$parent" || fail target-directory
            stage="$parent/.gen5w-restore.$$"
            cp "$backup" "$stage" || fail stage-copy
            set_metadata "$stage" "$orig_uid" "$orig_gid" "$orig_mode" || fail set-metadata
            set_label "$stage" "$orig_label" || fail set-label
            [ "$(hash_file "$stage")" = "$original_sha" ] || fail staged-hash
            no_link_components "$live" || fail symlink-target-during-restore
            mv "$stage" "$live" || fail atomic-replace
        elif [ "$current" != "$original_sha" ]; then
            fail changed-during-restore
        fi
        [ "$(hash_file "$live")" = "$original_sha" ] || fail restored-hash-mismatch
        [ "$(metadata "$live")" = "$orig_uid|$orig_gid|$orig_mode" ] || fail restored-metadata-mismatch
        [ "$(label_of "$live")" = "$orig_label" ] || fail restored-label-mismatch
    fi
done < "$MANIFEST"

"$HELPER" sync || sync
SYSTEM_STATE=ro
if ! remount_system_ro; then
    # Running stock processes still map the replaced inodes, so Linux refuses
    # MS_RDONLY (EBUSY). Every target was verified above; the reboot below
    # mounts /system read-only again.
    "$HELPER" sync || sync
    SYSTEM_STATE=rw-until-reboot
fi
SYSTEM_RW=0
"$HELPER" sync || sync
print -r -- "result=restored
restored=${seen#|}
system=$SYSTEM_STATE" > "$REPORT" || fail report-write
MIGRATION_LOCK="$RECOVERY/migration.lock"
if [ -e "$MIGRATION_LOCK" ] || [ -L "$MIGRATION_LOCK" ]; then
    [ -d "$MIGRATION_LOCK" ] && [ ! -L "$MIGRATION_LOCK" ] && no_link_components "$MIGRATION_LOCK" || fail unsafe-migration-lock
    if [ -e "$MIGRATION_LOCK/owner" ] || [ -L "$MIGRATION_LOCK/owner" ]; then
        [ -f "$MIGRATION_LOCK/owner" ] && [ ! -L "$MIGRATION_LOCK/owner" ] && no_link_components "$MIGRATION_LOCK/owner" || fail unsafe-migration-lock-owner
        rm -f "$MIGRATION_LOCK/owner" || fail migration-lock-cleanup
    fi
    rmdir "$MIGRATION_LOCK" || fail migration-lock-not-empty
fi
rm -f "$RECOVERY/transaction-committed" "$RECOVERY/transaction-needs-recovery" "$RECOVERY/transaction-in-progress" || fail transaction-marker-cleanup
"$HELPER" sync || sync
CURRENT_BOOT=$(boot_id) || fail boot-id-unavailable
valid_boot_id "$CURRENT_BOOT" || fail invalid-boot-id
(set -C; print -r -- "GEN5W-RESTORE-DONE|1|$MANIFEST_SHA|$CURRENT_BOOT" > "$TMP") || fail completion-marker
mv "$TMP" "$DONE" || fail completion-marker
"$HELPER" sync || sync
print -r -- "result=restored
restored=${seen#|}
system=$SYSTEM_STATE
reboot=requested
manifest_sha256=$MANIFEST_SHA" > "$REPORT" || fail report-write
if [ -n "$ROOT" ]; then
    "$HELPER" reboot || fail reboot
else
    reboot || fail reboot
fi
print -r -- "result=restored
restored=${seen#|}
system=$SYSTEM_STATE
reboot=dispatched
manifest_sha256=$MANIFEST_SHA" > "$REPORT" || fail report-write
say 'result=restored reboot=dispatched'
exit 0
