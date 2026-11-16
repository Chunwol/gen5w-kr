#!/system/bin/sh
# Opt-in only. No boot hook, system writes, service restart, or remount.
# Manifest: feature|/data/source|/system/target|sha256|uid|gid|mode|static-or-directory
set -f
umask 077
ROOT=${PORTABLE_TEST_ROOT:-}
STATE=${PORTABLE_STATE_DIR:-/data/local/gen5w-portable/overlay}
ADAPTER=${PORTABLE_TEST_ADAPTER:-}
HELPER=${PORTABLE_HELPER:-${0%/*}/dex-patch}
err() { echo "overlay: $*" >&2; return 1; }
safe() { case "$1" in ''|*[!a-zA-Z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac; }
plain() {
    safe "$1" || return 1
    p=$1
    while [ "$p" != / ] && [ -n "$p" ]; do
        [ ! -L "$p" ] || return 1
        p=${p%/*}; [ -n "$p" ] || p=/
    done
}
if [ -n "$ROOT" ]; then
    safe "$ROOT" && [ "$ROOT" != / ] && [ -d "$ROOT" ] && [ -x "$ADAPTER" ] || exit 1
    case "$STATE" in "$ROOT"/*) :;; *) exit 1;; esac
else
    [ -z "$ADAPTER" ] || exit 1
    case "$STATE" in /data/*) :;; *) exit 1;; esac
fi
plain "$STATE" || exit 1
op() {
    if [ -n "$ROOT" ]; then "$ADAPTER" "$@"; return $?; fi
    case "$1" in
    boot) cat /proc/sys/kernel/random/boot_id;;
    healthy) /system/bin/sh "${0%/*}/framework.sh" ready;;
    ready) [ "$(getprop init.svc.zygote)" = stopped ];;
    identity) "$HELPER" identity "$2";;
    namespace) [ "$(readlink /proc/self/ns/mnt)" = "$(readlink /proc/1/ns/mnt)" ] && [ -n "$(readlink /proc/self/ns/mnt)" ];;
    sha) "$HELPER" sha256 "$2";;
    meta) "$HELPER" metadata "$2";;
    visible) while read a b c d target rest; do [ "$target" != "$2" ] || return 0; done < /proc/self/mountinfo; return 1;;
    bound) identity=$("$HELPER" identity "$2") && [ -n "$identity" ] && [ "$identity" = "$("$HELPER" identity "$3")" ];;
    bind) "$HELPER" bind "$2" "$3";;
    unmount) umount "$2";;
    sync) sync;;
    *) return 1;;
    esac
}
mkdir -p "$STATE" || exit 1
chmod 700 "$STATE" || exit 1
# Refuse persisted symlinks before any journal/state write.
for name in state state.new boot prepareboot journal manifest manifest.new targets.tmp tree.tmp tree.actual; do
    [ ! -L "$STATE/$name" ] || exit 1
    if [ -e "$STATE/$name" ] && [ ! -f "$STATE/$name" ]; then exit 1; fi
done
# Publish complete owner records atomically; reclaimers remain anchored to
# the stale directory so they can never delete a newly published owner.
process_key() {
    local pid=$1 line rest count=0
    case "$pid" in ''|*[!0-9]*) return 1;; esac
    IFS= read -r line < "/proc/$pid/stat" || return 1
    rest=${line##*) }; [ "$rest" != "$line" ] || return 1
    set -- $rest; [ "$#" -ge 20 ] || return 1
    case "$1" in Z|X|x) return 1;; esac
    while [ "$count" -lt 19 ]; do shift; count=$((count+1)); done
    echo "$pid:$1"
}
lock_boot=$(op boot) || exit 1
case "$lock_boot" in ''|*[!a-zA-Z0-9_-]*) exit 1;; esac
lock_process=$(process_key $$) || exit 1
lock_owner="$lock_boot|$lock_process"
lock_claim="$STATE/lock.claim.${lock_process%:*}.${lock_process#*:}"
lock_release() {
    [ "${lock_held:-0}" = 1 ] || return 0
    ( cd "$STATE/lock" && [ ! -L owner ] && [ "$(cat owner 2>/dev/null)" = "$lock_owner" ] &&
      rm owner && rmdir "$STATE/lock" ) 2>/dev/null
    lock_held=0
}
lock_stale_record() {
    [ ! -L owner ] || return 1
    [ -e owner ] || return 0
    [ -f owner ] || return 1
    [ -s owner ] || return 0
    local oldboot oldkey extra
    IFS='|' read -r oldboot oldkey extra < owner
    [ -z "$extra" ] || return 1
    if [ -z "$oldkey" ]; then
        case "$oldboot" in ''|*[!0-9]*) return 1;; esac
        process_key "$oldboot" >/dev/null 2>&1 && return 1
    else
        case "$oldboot" in ''|*[!a-zA-Z0-9_-]*) return 1;; esac
        case "$oldkey" in *[!0-9:]*|:*|*:|*:*:*) return 1;; esac
        case "$oldkey" in *:*) :;; *) return 1;; esac
        if [ "$oldboot" = "$lock_boot" ] &&
           [ "$(process_key "${oldkey%%:*}" 2>/dev/null)" = "$oldkey" ]; then return 1; fi
    fi
    return 0
}
lock_reclaim() (
    [ -d "$STATE/lock" ] && [ ! -L "$STATE/lock" ] || exit 1
    cd "$STATE/lock" || exit 1
    lock_stale_record && [ ! -L recover ] || exit 1
    # A contender killed after mv nested its staged claim must not wedge recovery.
    set +f
    for claim in lock.claim.*; do
        [ -e "$claim" ] || { [ ! -L "$claim" ] || exit 1; continue; }
        [ -d "$claim" ] && [ ! -L "$claim" ] || exit 1
        ( cd "$claim" && lock_stale_record && { [ ! -e owner ] || rm owner; } ) || exit 1
        rmdir "$claim" || exit 1
    done
    [ ! -e owner ] || rm owner || exit 1
    if [ -e recover ]; then [ -d recover ] && rmdir recover || exit 1; fi
    # A newly published lock is nonempty; an anchored old reclaimer cannot remove it.
    rmdir "$STATE/lock"
)
lock_acquire() {
    local count=0 nested=${lock_claim##*/}
    while [ "$count" -lt 4 ]; do
        count=$((count+1))
        [ ! -L "$STATE/lock" ] && { [ ! -e "$STATE/lock" ] || [ -d "$STATE/lock" ]; } || return 1
        mkdir "$lock_claim" || return 1
        echo "$lock_owner" > "$lock_claim/owner" || return 1
        # mv nests the staged directory if lock already exists; that claim
        # withdraws. An absent-destination rename alone publishes ownership.
        if ! mv "$lock_claim" "$STATE/lock" 2>/dev/null; then
            rm -f "$lock_claim/owner"; rmdir "$lock_claim" 2>/dev/null
            return 1
        fi
        if [ -d "$STATE/lock/$nested" ] && [ ! -L "$STATE/lock/$nested" ]; then
            rm "$STATE/lock/$nested/owner" && rmdir "$STATE/lock/$nested" || return 1
            lock_reclaim 2>/dev/null || return 1
        elif [ ! -L "$STATE/lock/owner" ] && [ "$(cat "$STATE/lock/owner" 2>/dev/null)" = "$lock_owner" ]; then
            lock_held=1
            return 0
        else return 1; fi
    done
    return 1
}
lock_acquire_bounded() {
    local up rest until
    IFS=' ' read -r up rest < /proc/uptime || return 1
    until=$((${up%%.*}+10))
    while ! lock_acquire; do
        IFS=' ' read -r up rest < /proc/uptime || return 1
        [ "${up%%.*}" -lt "$until" ] || return 1
        sleep 1
    done
}
lock_acquire_bounded || { echo 'portable: locked or unsafe lock' >&2; exit 1; }
trap lock_release EXIT
trap 'exit 1' HUP INT TERM
write_state() { echo "$1" > "$STATE/state.new" && mv "$STATE/state.new" "$STATE/state" && op sync; }
current() { if [ -f "$STATE/state" ]; then cat "$STATE/state"; else echo disabled; fi; }
# Canonical inventory is lexical filename order under C locale, one row per XML.
# No hidden files, symlinks, directories, or unspecified entries are admitted.
verify_tree() (
    directory=$1; inventory=$2
    plain "$directory" && plain "$inventory" && [ -d "$directory" ] && [ -f "$inventory" ] || exit 1
    set +f
    LC_ALL=C; export LC_ALL
    : > "$STATE/tree.actual"
    for item in "$directory"/* "$directory"/.[!.]* "$directory"/..?*; do
        [ -e "$item" ] || { [ ! -L "$item" ] || exit 1; continue; }
        basename=${item##*/}
        case "$basename" in .*) exit 1;; *.xml) :;; *) exit 1;; esac
        safe "$basename" && [ -f "$item" ] && [ ! -L "$item" ] || exit 1
        digest=$(op sha "$item") || exit 1
        metadata=$(op meta "$item") || exit 1
        echo "$basename|$digest|$metadata" >> "$STATE/tree.actual" || exit 1
    done
    [ -s "$STATE/tree.actual" ] || exit 1
    [ "$(op sha "$STATE/tree.actual")" = "$(op sha "$inventory")" ]
)
validate_row() {
    case "$feature" in ''|*[!a-zA-Z0-9_-]*) return 1;; esac
    safe "$src" && safe "$dst" || return 1
    case "$src" in /data/*) :;; *) return 1;; esac
    case "$dst" in
    /system/app/Iap2ServerApp.odex|/system/app/HKMC_DiPO.odex|/system/app/HKMC_GPM.odex|/system/app/HKMC_WifiSettings.odex|/system/lib/libCarPlayAudio.so|/system/build.prop|/system/etc/featurexml.cfg|/system/etc/permissions) :;;
    /system/onebin/*/featurexml.cfg)
        region=${dst#/system/onebin/}; region=${region%/featurexml.cfg}
        case "$region" in ''|*[!a-zA-Z0-9_-]*) return 1;; esac;;
    /system/featurexml/*/featurexml.cfg)
        region=${dst#/system/featurexml/}; region=${region%/featurexml.cfg}
        case "$region" in ''|*[!a-zA-Z0-9_-]*) return 1;; esac;;
    /system/*/featurexml.cfg)
        region=${dst#/system/}; region=${region%/featurexml.cfg}
        case "$region" in ''|*[!a-zA-Z0-9_-]*) return 1;; esac;;
    *) return 1;; esac
    [ -z "$extra" ] || return 1
    case "$hash" in *[!a-f0-9]*|'') return 1;; esac
    [ ${#hash} -eq 64 ] || return 1
    case "$uid:$gid" in *[!0-9:]*|:*|*:) return 1;; esac
    case "$mode" in 644|444|640|600|755|555) :;; *) return 1;; esac
    plain "$ROOT$src" && plain "$ROOT$dst" || return 1
    case "$kind" in
    static) [ -f "$ROOT$src" ] && [ -f "$ROOT$dst" ] && [ "$(op sha "$ROOT$src")" = "$hash" ] || return 1;;
    directory)
        [ "$dst" = /system/etc/permissions ] || return 1
        verify_tree "$ROOT$src" "$ROOT$src.inventory" || return 1
        verify_tree "$ROOT$dst" "$ROOT$src.stock-inventory" || return 1
        while IFS= read -r stockrow; do
            retained=0
            while IFS= read -r sourcerow; do [ "$stockrow" != "$sourcerow" ] || retained=1; done < "$ROOT$src.inventory"
            [ "$retained" = 1 ] || return 1
        done < "$ROOT$src.stock-inventory"
        cat "$ROOT$src.inventory" "$ROOT$src.stock-inventory" > "$STATE/tree.tmp" || return 1
        [ "$(op sha "$STATE/tree.tmp")" = "$hash" ] || return 1;;
    *) return 1;;
    esac
    [ "$(op meta "$ROOT$src")" = "$uid|$gid|$mode" ] || return 1
    [ "$(op meta "$ROOT$dst")" = "$uid|$gid|$mode" ] || return 1
}
validate_file() {
    [ -s "$1" ] || return 1
    : > "$STATE/targets.tmp"
    while IFS='|' read -r feature src dst hash uid gid mode kind extra || [ -n "$feature" ]; do
        validate_row || return 1
        while IFS= read -r existing; do [ "$existing" != "$dst" ] || return 1; done < "$STATE/targets.tmp"
        echo "$dst" >> "$STATE/targets.tmp" || return 1
    done < "$1"
}
active_check() {
    op namespace || return 1
    while IFS='|' read -r feature src dst hash uid gid mode kind extra; do
        op visible "$ROOT$dst" && op bound "$ROOT$src" "$ROOT$dst" || return 1
        if [ "$kind" = directory ]; then
            verify_tree "$ROOT$src" "$ROOT$src.inventory" && verify_tree "$ROOT$dst" "$ROOT$src.inventory" || return 1
            cat "$ROOT$src.inventory" "$ROOT$src.stock-inventory" > "$STATE/tree.tmp" || return 1
            [ "$(op sha "$STATE/tree.tmp")" = "$hash" ] || return 1
            [ "$(op meta "$ROOT$src")" = "$uid|$gid|$mode" ] || return 1
        else
            validate_row || return 1
        fi
    done < "$STATE/manifest"
}
rollback() {
    # A status query or healthy prepare must never unmount code being used by
    # an application. Only maintenance may remove a currently visible bind.
    if [ -f "$STATE/journal" ]; then
        while IFS='|' read -r rollback_target rollback_identity; do
            if op visible "$ROOT$rollback_target"; then
                op ready || { err 'stop Android before removing visible overlays'; return 1; }
            fi
        done < "$STATE/journal"
    fi
    failed=0
    if [ -f "$STATE/journal" ]; then
        # File and directory targets are disjoint; journal precedes each mount.
        while IFS='|' read -r target owner_identity; do
            safe "$target" || { failed=1; continue; }
            if op visible "$ROOT$target"; then
                actual_identity=$(op identity "$ROOT$target")
                if [ -n "$owner_identity" ] && [ "$actual_identity" = "$owner_identity" ]; then
                    op unmount "$ROOT$target" || failed=1
                else failed=1
                fi
            fi
        done < "$STATE/journal"
    fi
    [ "$failed" = 0 ] || { write_state failed; return 1; }
    : > "$STATE/journal"
    op sync
}
recover() {
    s=$(current)
    if [ "$s" = applying ] || { [ "$s" = pending ] && [ "$(cat "$STATE/boot" 2>/dev/null)" != "$(op boot)" ]; }; then
        rollback; write_state failed; return 1
    fi
    # Even a committed overlay must never automatically reapply after reboot.
    if [ "$s" = committed ] && [ "$(cat "$STATE/boot" 2>/dev/null)" != "$(op boot)" ]; then
        rollback || return 1
        write_state disabled
    fi
}
command=${1:-}; [ $# -eq 0 ] || shift
case "$command" in
prepare|prepare-boot)
    [ $# -ge 1 ] || exit 1
    manifest=$1; shift
    if [ "$command" = prepare-boot ]; then op ready || exit 1;
    else op healthy || { err 'prepare requires healthy running zygote'; exit 1; }; fi
    [ -f "$manifest" ] && [ ! -L "$manifest" ] || exit 1
    recover || :
    rollback || exit 1
    : > "$STATE/manifest.new"
    while IFS='|' read -r feature src dst hash uid gid mode kind extra || [ -n "$feature" ]; do
        selected=0; [ $# -ne 0 ] || selected=1
        for requested in "$@"; do [ "$requested" != "$feature" ] || selected=1; done
        [ "$selected" = 1 ] || continue
        echo "$feature|$src|$dst|$hash|$uid|$gid|$mode|$kind${extra:+|$extra}" >> "$STATE/manifest.new"
    done < "$manifest"
    # validate_file checks every selected row and the duplicate-target rule in
    # one pass. Revalidating each row above doubled the stopped-framework
    # window, especially for the permissions directory inventory.
    validate_file "$STATE/manifest.new" || { rm -f "$STATE/manifest.new"; write_state failed; err 'invalid manifest or source'; exit 1; }
    for requested in "$@"; do
        found=0
        while IFS='|' read -r feature rest; do [ "$feature" != "$requested" ] || found=1; done < "$STATE/manifest.new"
        [ "$found" = 1 ] || { write_state failed; exit 1; }
    done
    mv "$STATE/manifest.new" "$STATE/manifest" || exit 1
    op boot > "$STATE/prepareboot" && [ -s "$STATE/prepareboot" ] || exit 1
    write_state prepared || exit 1
    ;;
apply)
    [ $# = 0 ] || exit 1
    recover || exit 1
    [ "$(current)" = prepared ] || { err 'prepare required'; exit 1; }
    [ "$(cat "$STATE/prepareboot" 2>/dev/null)" = "$(op boot)" ] && op ready && op namespace && validate_file "$STATE/manifest" || { write_state failed; err 'health, namespace, or identity rejected'; exit 1; }
    # Refuse pre-existing mounts: rollback must never remove someone else's bind.
    while IFS='|' read -r feature src dst rest; do
        if op visible "$ROOT$dst"; then write_state failed; exit 1; fi
    done < "$STATE/manifest"
    op boot > "$STATE/boot" || exit 1
    [ -s "$STATE/boot" ] || exit 1
    : > "$STATE/journal"
    write_state applying || exit 1
    while IFS='|' read -r feature src dst hash uid gid mode kind extra; do
        # The complete manifest was validated immediately before mutation while
        # this transaction held the overlay lock. Keep the durable per-target
        # journal and identity checks below; a second full hash/tree pass here
        # only lengthens the Android-off interval.
        owner_identity=$(op identity "$ROOT$src")
        [ -n "$owner_identity" ] || { rollback; write_state failed; exit 1; }
        echo "$dst|$owner_identity" >> "$STATE/journal" && op sync || { rollback; write_state failed; exit 1; }
        if ! op bind "$ROOT$src" "$ROOT$dst" || ! op visible "$ROOT$dst" || ! op bound "$ROOT$src" "$ROOT$dst" || ! op namespace; then
            rollback; write_state failed; exit 1
        fi
    done < "$STATE/manifest"
    write_state pending || exit 1
    ;;
commit)
    [ $# = 0 ] || exit 1
    recover && [ "$(current)" = pending ] && op healthy && op namespace || exit 1
    active_check || { rollback; write_state failed; exit 1; }
    write_state committed || exit 1
    ;;
disable)
    [ $# = 0 ] || exit 1
    rollback && write_state disabled || exit 1
    ;;
status)
    [ $# = 0 ] || exit 1
    s=$(current)
    case "$s" in applying|pending|committed)
        # Bind mounts never survive a kernel reboot: any record of an earlier
        # boot is stale. Treating it as failed made disable restart Android.
        if [ "$(cat "$STATE/boot" 2>/dev/null)" != "$(op boot)" ]; then s=expired
        elif [ "$s" = applying ]; then s=failed
        elif ! active_check; then s=failed; fi;;
    esac
    echo "state|$s"
    if [ -f "$STATE/manifest" ]; then
        while IFS='|' read -r feature src dst rest; do
            flag=stock
            case "$s" in pending|committed) op visible "$ROOT$dst" && flag=active;; prepared) flag=prepared;; failed) flag=failed;; esac
            echo "$feature|$flag"
        done < "$STATE/manifest"
    fi
    ;;
*) err 'usage: overlay.sh prepare MANIFEST [FEATURE ...] | apply | status | commit | disable'; exit 1;;
esac
