# Private on-unit recovery protocol. No original files leave the head unit.
# Manifest: numeric slot|absolute target|original digest (or absent)|applied digest.
STATE=$SYS/etc/gen5w-kr-backup/wireless
state_digest() { file_md5 "$1"; }
state_valid() {
    [ ! -L "$STATE" ] && [ -f "$STATE/owner" ] && [ ! -L "$STATE/owner" ] &&
    [ "$(cat "$STATE/owner" 2>/dev/null)" = "gen5w.kr.wireless" ] || return 1
    [ -f "$STATE/manifest" ] && [ ! -L "$STATE/manifest" ] && [ -s "$STATE/manifest" ] &&
    [ -f "$STATE/manifest.md5" ] && [ ! -L "$STATE/manifest.md5" ] && [ ! -L "$STATE/owner" ] || return 1
    [ "$(file_md5 "$STATE/manifest")" = "$(cat "$STATE/manifest.md5")" ] || return 1
    local n p old new extra prop parent seen_slots='|' seen_paths='|'
    for prop in runtime.ium runtime.wifi; do
        if [ -e "$STATE/$prop" ] || [ -L "$STATE/$prop" ] || [ -e "$STATE/$prop.md5" ] || [ -L "$STATE/$prop.md5" ]; then
            [ -f "$STATE/$prop" ] && [ ! -L "$STATE/$prop" ] &&
            [ -f "$STATE/$prop.md5" ] && [ ! -L "$STATE/$prop.md5" ] &&
            [ "$(file_md5 "$STATE/$prop")" = "$(cat "$STATE/$prop.md5")" ] || return 1
        fi
    done
    while IFS='|' read -r n p old new extra; do
        case "$n" in ''|*[!0-9]*) return 1;; esac
        case "$p" in "$SYS"/*) ;; *) return 1;; esac
        case "$p" in */../*|*/./*|*'|'*) return 1;; esac
        case "$p" in "$BP"|"$PERM/$CP_XML"|"$PERM/$AA_XML"|"$PERM/$HOTSPOT_XML"|"$PERM/$WIFI_XML"|"$SYS"/*/featurexml.cfg) ;; *) return 1;; esac
        parent=${p%/*}
        while [ "$parent" != "$SYS" ]; do
            [ -d "$parent" ] && [ ! -L "$parent" ] || return 1
            parent=${parent%/*}
        done
        [ ! -L "$SYS" ] || return 1
        case "$seen_slots" in *"|$n|"*) return 1;; esac
        case "$seen_paths" in *"|$p|"*) return 1;; esac
        seen_slots="$seen_slots$n|"; seen_paths="$seen_paths$p|"
        [ -z "$extra" ] && [ -n "$new" ] && [ ! -L "$p" ] || return 1
        [ ! -L "$p.gen5wkr.tmp" ] && { [ ! -e "$p.gen5wkr.tmp" ] || [ -f "$p.gen5wkr.tmp" ]; } || return 1
        [ -f "$STATE/$n.applied" ] && [ ! -L "$STATE/$n.applied" ] && [ ! -L "$STATE/$n.original" ] || return 1
        [ ! -e "$p" ] || [ -f "$p" ] || return 1
        [ "$(file_md5 "$STATE/$n.applied")" = "$new" ] || return 1
        if [ "$old" != absent ]; then
            [ -f "$STATE/$n.original" ] && [ "$(file_md5 "$STATE/$n.original")" = "$old" ] || return 1
        fi
    done < "$STATE/manifest"
}
state_check() {
    state_valid || return 1
    local n p old new actual extra
    while IFS='|' read -r n p old new extra; do
        actual=absent
        [ ! -e "$p" ] || actual=$(file_md5 "$p") || return 1
        if [ "$actual" != "$new" ]; then
            [ ! -f "$STATE/complete" ] && [ "$actual" = "$old" ] || return 1
        fi
    done < "$STATE/manifest"
}
state_unsealed() {
    [ ! -L "$STATE" ] && [ -f "$STATE/owner" ] && [ ! -L "$STATE/owner" ] &&
    [ "$(cat "$STATE/owner" 2>/dev/null)" = "gen5w.kr.wireless" ] &&
    [ "$(cat "$STATE/phase" 2>/dev/null)" = planning ] &&
    [ ! -e "$STATE/manifest.md5" ] && [ ! -e "$STATE/complete" ]
}
state_discard_plan() {
    state_unsealed || return 1
    rm -rf "$STATE" "$MARK" || return 1
}
state_load() {
    STALE=no
    if [ -e "$STATE" ]; then
        # A planning journal cannot have modified targets: applying requires a seal.
        state_unsealed && return 0
        state_check || { log 'FAIL: recovery ownership or live hashes changed'; return 1; }
        mkdir -p "$MARK" || return 1
        cp -R "$STATE/." "$MARK/" || return 1
    elif [ -e "$MARK/saved" ] || [ -e "$MARK/installed" ]; then
        log 'FAIL: legacy backup needs reviewed migration; no durable ownership'
        return 1
    elif [ -e "$MARK" ] || [ -L "$MARK" ]; then
        state_stale || { log 'FAIL: wireless changes are live without their system journal'; return 1; }
        STALE=yes
    fi
}
# Firmware reinstall: /system (with our journal in it) is stock again, but /data
# still holds our runtime copy and the persist properties we set. The copy may be
# discarded only when none of our applied bytes is live. An unsealed copy never
# applied anything.
state_stale() {
    local journal=$STATE n p old new extra actual rc=0
    [ ! -L "$MARK" ] && [ -d "$MARK" ] && [ ! -e "$STATE" ] && [ ! -L "$STATE" ] || return 1
    # Older layouts kept the only backup here; never treat them as leftovers.
    [ ! -e "$MARK/saved" ] && [ ! -L "$MARK/saved" ] && [ ! -e "$MARK/installed" ] && [ ! -L "$MARK/installed" ] || return 1
    [ -e "$MARK/manifest.md5" ] || [ -L "$MARK/manifest.md5" ] || return 0
    STATE=$MARK
    if state_valid; then
        while IFS='|' read -r n p old new extra; do
            actual=absent
            [ ! -e "$p" ] || actual=$(file_md5 "$p") || { rc=1; break; }
            [ "$actual" = "$old" ] || [ "$actual" != "$new" ] || { rc=1; break; }
        done < "$MARK/manifest"
    else
        rc=1
    fi
    STATE=$journal
    return "$rc"
}
# Put back the persist properties recorded before the first install, then drop
# the runtime copy. Only after state_load set STALE=yes.
state_discard_stale() {
    [ "$STALE" = yes ] || return 0
    if [ -f "$MARK/manifest.md5" ]; then
        if [ -f "$MARK/runtime.ium" ]; then
            setprop persist.ium.support "$(cat "$MARK/runtime.ium")" || return 1
            [ "$(getprop persist.ium.support)" = "$(cat "$MARK/runtime.ium")" ] || return 1
        fi
        if [ -f "$MARK/runtime.wifi" ]; then
            setprop persist.wifi.state "$(cat "$MARK/runtime.wifi")" || return 1
            [ "$(getprop persist.wifi.state)" = "$(cat "$MARK/runtime.wifi")" ] || return 1
        fi
    fi
    rm -rf "$MARK" || return 1
    STALE=no
    log 'CLEARED: leftovers of an install whose system files were reinstalled; properties restored'
}
state_begin() {
    [ ! -e "$STATE" ] || return 1
    mkdir -p "$MARK" "$STATE" || return 1
    echo gen5w.kr.wireless > "$STATE/owner" || return 1
    echo planning > "$STATE/phase" || return 1
    : > "$STATE/manifest"
    SLOT=0
}
state_plan() {
    local target=$1 payload=$2 old=absent new
    SLOT=$((SLOT+1))
    if [ -e "$target" ]; then
        [ -f "$target" ] && [ ! -L "$target" ] || return 1
        cp -p "$target" "$STATE/$SLOT.original" || return 1
        old=$(file_md5 "$STATE/$SLOT.original") || return 1
    fi
    new=$(file_md5 "$payload") || return 1
    cp "$payload" "$STATE/$SLOT.applied" || return 1
    echo "$SLOT|$target|$old|$new" >> "$STATE/manifest"
}
state_seal() {
    local prop
    for prop in runtime.ium runtime.wifi; do
        [ ! -f "$STATE/$prop" ] || file_md5 "$STATE/$prop" > "$STATE/$prop.md5" || return 1
    done
    file_md5 "$STATE/manifest" > "$STATE/manifest.md5.tmp" || return 1
    sync
    mv "$STATE/manifest.md5.tmp" "$STATE/manifest.md5" || return 1
    sync
}
state_apply() {
    local n p old new extra
    state_check || return 1
    while IFS='|' read -r n p old new extra; do
        [ "$(file_md5 "$STATE/$n.applied")" = "$new" ] || return 1
        [ ! -L "$p.gen5wkr.tmp" ] || return 1
        [ ! -e "$p.gen5wkr.tmp" ] || rm -f "$p.gen5wkr.tmp" || return 1
        if [ "$old" = absent ]; then
            cp "$STATE/$n.applied" "$p.gen5wkr.tmp" || return 1
            chmod 644 "$p.gen5wkr.tmp" || return 1
            chown 0:0 "$p.gen5wkr.tmp" 2>/dev/null || chown 0.0 "$p.gen5wkr.tmp" 2>/dev/null || { [ -n "$EN_TEST_SYS$SKIP_TEST_SYS" ] || return 1; }
        else
            cp -p "$STATE/$n.original" "$p.gen5wkr.tmp" && cat "$STATE/$n.applied" > "$p.gen5wkr.tmp" || return 1
        fi
        [ "$(file_md5 "$p.gen5wkr.tmp")" = "$new" ] || return 1
        mv "$p.gen5wkr.tmp" "$p" || return 1
        [ ! -x /system/bin/restorecon ] || /system/bin/restorecon "$p" || return 1
        [ "$(file_md5 "$p")" = "$new" ] || return 1
    done < "$STATE/manifest"
    echo 1 > "$STATE/complete" || return 1
    cp -R "$STATE/." "$MARK/" || return 1
    sync
}
state_restore() {
    local retain=${1:-}
    case "$retain" in ''|retain) ;; *) return 1;; esac
    if state_unsealed; then
        [ "$retain" != retain ] || return 1
        state_discard_plan || return 1
        rmdir "$SYS/etc/gen5w-kr-backup" 2>/dev/null || true
        return 0
    fi
    state_check || return 1
    # All paths are checked before the first mutation. Restoring is resumable.
    rm -f "$STATE/complete" || return 1
    # Persist resumable state before any target can become original.
    sync || return 1
    local n p old new extra
    while IFS='|' read -r n p old new extra; do
        if [ "$old" = absent ]; then
            rm -f "$p" || return 1
            [ ! -e "$p" ] || return 1
        else
            [ ! -L "$p.gen5wkr.tmp" ] || return 1
            [ ! -e "$p.gen5wkr.tmp" ] || rm -f "$p.gen5wkr.tmp" || return 1
            cp -p "$STATE/$n.original" "$p.gen5wkr.tmp" && mv "$p.gen5wkr.tmp" "$p" || return 1
            [ "$(file_md5 "$p")" = "$old" ] || return 1
        fi
    done < "$STATE/manifest"
    if [ -f "$STATE/runtime.ium" ]; then
        setprop persist.ium.support "$(cat "$STATE/runtime.ium")" || return 1
        [ "$(getprop persist.ium.support)" = "$(cat "$STATE/runtime.ium")" ] || return 1
    fi
    if [ -f "$STATE/runtime.wifi" ]; then
        setprop persist.wifi.state "$(cat "$STATE/runtime.wifi")" || return 1
        [ "$(getprop persist.wifi.state)" = "$(cat "$STATE/runtime.wifi")" ] || return 1
    fi
    sync
    [ "$retain" != retain ] || return 0
    rm -rf "$STATE" "$MARK" || return 1
    rmdir "$SYS/etc/gen5w-kr-backup" 2>/dev/null || true
}
