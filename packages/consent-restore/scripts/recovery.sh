# Private on-unit recovery protocol. No original files leave the head unit.
# Manifest: numeric slot|absolute target|original digest (or absent)|applied digest.
STATE=$SYS/etc/gen5w-kr-backup/consent
state_digest() { file_md5 "$1"; }
state_valid() {
    [ ! -L "$STATE" ] && [ "$(cat "$STATE/owner" 2>/dev/null)" = "gen5w.kr.consent" ] || return 1
    [ -f "$STATE/manifest" ] && [ -f "$STATE/manifest.md5" ] || return 1
    [ "$(file_md5 "$STATE/manifest")" = "$(cat "$STATE/manifest.md5")" ] || return 1
    local n p old new extra prop
    for prop in runtime.ium runtime.wifi; do
        if [ -e "$STATE/$prop" ]; then
            [ ! -L "$STATE/$prop" ] && [ "$(file_md5 "$STATE/$prop")" = "$(cat "$STATE/$prop.md5")" ] || return 1
        fi
    done
    while IFS='|' read -r n p old new extra; do
        case "$n" in ''|*[!0-9]*) return 1;; esac
        case "$p" in "$TARGET") ;; *) return 1;; esac
        case "$p" in */../*|*/./*|*'|'*) return 1;; esac
        [ -z "$extra" ] && [ -n "$new" ] && [ ! -L "$p" ] || return 1
        [ ! -L "$STATE/$n.original" ] && [ ! -L "$STATE/$n.applied" ] || return 1
        [ "$(file_md5 "$STATE/$n.applied")" = "$new" ] || return 1
        if [ "$old" != absent ]; then
            [ "$(file_md5 "$STATE/$n.original")" = "$old" ] || return 1
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
    [ ! -L "$STATE" ] && [ "$(cat "$STATE/owner" 2>/dev/null)" = "gen5w.kr.consent" ] &&
    [ "$(cat "$STATE/phase" 2>/dev/null)" = planning ] &&
    [ ! -e "$STATE/manifest.md5" ] && [ ! -e "$STATE/complete" ]
}
state_discard_plan() {
    state_unsealed || return 1
    rm -rf "$STATE" "$MARK" || return 1
}
state_load() {
    if [ -e "$STATE" ]; then
        # A planning journal cannot have modified targets: applying requires a seal.
        state_unsealed && return 0
        state_check || { log 'FAIL: recovery ownership or live hashes changed'; return 1; }
        mkdir -p "$MARK" || return 1
        cp -R "$STATE/." "$MARK/" || return 1
    elif [ -e "$MARK/saved" ] || [ -e "$MARK/installed" ]; then
        log 'FAIL: legacy backup needs reviewed migration; no durable ownership'
        return 1
    fi
}
state_restore() {
    if state_unsealed; then
        state_discard_plan || return 1
        rmdir "$SYS/etc/gen5w-kr-backup" 2>/dev/null || true
        return 0
    fi
    state_check || return 1
    # All paths are checked before the first mutation. Restoring is resumable.
    rm -f "$STATE/complete"
    local n p old new extra
    while IFS='|' read -r n p old new extra; do
        if [ "$old" = absent ]; then
            rm -f "$p" || return 1
            [ ! -e "$p" ] || return 1
        else
            [ ! -L "$p.gen5wkr.tmp" ] || return 1
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
    rm -rf "$STATE" "$MARK" || return 1
    rmdir "$SYS/etc/gen5w-kr-backup" 2>/dev/null || true
}
