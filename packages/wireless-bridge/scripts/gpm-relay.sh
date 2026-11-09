# Exact-V039 GPM pair lifecycle; sourced by common.sh, no standalone entrypoint.
gpm_relay_enabled() { [ "$VERSION" = v039 ] && [ "$GPM_VERSION" = v039 ] && relay_packaged; }
gpm_relay_hash() {
    typeset sum
    [ -f "$2" ] && [ ! -L "$2" ] && [ -f "$1" ] && [ ! -L "$1" ] || return 1
    sum=$(cat "$2")
    [ ${#sum} -eq 32 ] || return 1
    case "$sum" in *[!0123456789abcdefABCDEF]*) return 1;; esac
    [ "$(digest "$1")" = "$sum" ]
}
gpm_relay_apk_live() { gpm_relay_hash "$GPM_APK" "$STATE/gpmrelay.apk.md5"; }
gpm_relay_odex_live() { gpm_relay_hash "$GPM_TARGET" "$STATE/gpmrelay.odex.md5"; }
gpm_relay_live() { gpm_relay_apk_live && gpm_relay_odex_live; }
gpm_relay_backups() {
    gpm_original "$STATE/gpmoriginal" && [ -f "$STATE/gpmapkoriginal" ] &&
        [ ! -L "$STATE/gpmapkoriginal" ] && "$GPM_TOOL" verify "$STATE/gpmapkoriginal" "$GPM_APK_SHA"
}
gpm_relay_intent() {
    [ -f "$STATE/gpmrelaystaging" ] && [ ! -L "$STATE/gpmrelaystaging" ] &&
        [ "$(cat "$STATE/gpmrelaystaging")" = "$OWNER" ]
}
gpm_relay_known_pair() {
    typeset p
    owned || return 1
    for p in "$STATE/gpmrelaystaging" "$STATE/gpmrelay.apk.md5" "$STATE/gpmrelay.odex.md5"; do
        [ ! -L "$p" ] && { [ ! -e "$p" ] || [ -f "$p" ]; } || return 1
    done
    if [ -e "$STATE/gpmrelaystaging" ]; then gpm_relay_intent || return 1; fi
    gpm_relay_backups || return 1
    { gpm_relay_apk_live || "$GPM_TOOL" verify "$GPM_APK" "$GPM_APK_SHA" ||
      { [ ! -e "$GPM_APK" ] && [ ! -L "$GPM_APK" ] && gpm_relay_intent; }; } &&
    { gpm_relay_odex_live || gpm_original "$GPM_TARGET" || gpm_patched "$GPM_TARGET" ||
      { [ ! -e "$GPM_TARGET" ] && [ ! -L "$GPM_TARGET" ] && gpm_relay_intent; }; }
}
gpm_relay_stage_clear() {
    typeset p
    for p in "$GPM_APK.gen5w-kr-bridge.tmp" "$GPM_TARGET.gen5w-kr-bridge.tmp" "$GPM_TARGET.gen5w-kr-bridge.tmp.opt" \
        "$STATE/gpmrelaystaging" "$STATE/gpmrelay.assembled" "$STATE/gpmrelay.assembled.classes.dex" "$STATE/gpmrelay.log"; do
        [ ! -L "$p" ] || return 1
    done
    if [ -e "$GPM_APK.gen5w-kr-bridge.tmp" ] || [ -e "$GPM_TARGET.gen5w-kr-bridge.tmp.opt" ]; then
        gpm_relay_intent || return 1
    fi
    if gpm_relay_intent; then rm -f "$GPM_TARGET.gen5w-kr-bridge.tmp" || return 1; fi
    rm -f "$GPM_APK.gen5w-kr-bridge.tmp" "$GPM_TARGET.gen5w-kr-bridge.tmp.opt" \
        "$STATE/gpmrelay.assembled" "$STATE/gpmrelay.assembled.classes.dex" "$STATE/gpmrelay.log" || return 1
    # Keep pair intent while a live half is missing or generated.
    if gpm_original "$GPM_TARGET" && "$GPM_TOOL" verify "$GPM_APK" "$GPM_APK_SHA"; then
        rm -f "$STATE/gpmrelaystaging" || return 1
    fi
}
gpm_relay_save_apk() {
    typeset p
    [ "$GPM_VERSION" = v039 ] && relay_packaged || return 0
    for p in "$STATE/gpmapkoriginal" "$STATE/gpmapkoriginal.tmp" "$MARK/gpmapkoriginal" "$MARK/gpmapkoriginal.tmp"; do
        [ ! -L "$p" ] || return 1
    done
    if [ ! -e "$STATE/gpmapkoriginal" ]; then
        "$GPM_TOOL" verify "$GPM_APK" "$GPM_APK_SHA" &&
            cp -p "$GPM_APK" "$STATE/gpmapkoriginal.tmp" &&
            "$GPM_TOOL" verify "$STATE/gpmapkoriginal.tmp" "$GPM_APK_SHA" &&
            mv "$STATE/gpmapkoriginal.tmp" "$STATE/gpmapkoriginal" || return 1
    fi
    gpm_relay_backups || return 1
    cp -p "$STATE/gpmapkoriginal" "$MARK/gpmapkoriginal.tmp" &&
        "$GPM_TOOL" verify "$MARK/gpmapkoriginal.tmp" "$GPM_APK_SHA" &&
        mv "$MARK/gpmapkoriginal.tmp" "$MARK/gpmapkoriginal"
}
gpm_relay_assemble() {
    typeset out=$1 dex=$1.classes.dex lpd=$SCRIPT_DIR/../app/HKMC_GPM.guard.lpd
    [ -f "$lpd" ] && [ ! -L "$lpd" ] && [ ! -L "$out" ] && [ ! -L "$dex" ] || return 1
    gpm_relay_backups && "$LPATCH" delta "$lpd" "$STATE/gpmoriginal" "$dex" &&
        "$LPATCH" zipadd "$STATE/gpmapkoriginal" "$dex" "$out" && [ -s "$out" ]
}
gpm_relay_install() {
    typeset apk=$GPM_APK.gen5w-kr-bridge.tmp odex=$GPM_TARGET.gen5w-kr-bridge.tmp
    typeset opt=$GPM_TARGET.gen5w-kr-bridge.tmp.opt assembled=$STATE/gpmrelay.assembled p rc
    gpm_relay_enabled && gpm_relay_backups && gpm_relay_known_pair || return 1
    gpm_relay_live && return 0
    # A half left by an earlier run would lose its identity once new checksums are
    # recorded: put both stock files back and verify them before generating anything.
    if ! { gpm_original "$GPM_TARGET" && "$GPM_TOOL" verify "$GPM_APK" "$GPM_APK_SHA"; }; then
        gpm_relay_restore || { log 'FAIL bridge GPM: partial state not restored to stock'; return 1; }
    fi
    gpm_relay_stage_clear || return 1
    for p in "$apk" "$odex" "$opt" "$STATE/gpmrelay.apk.md5" "$STATE/gpmrelay.odex.md5" "$STATE/gpmrelay.log"; do
        [ ! -L "$p" ] || return 1
    done
    [ ! -L "$STATE/gpmrelaystaging" ] && echo "$OWNER" > "$STATE/gpmrelaystaging" && sync || return 1
    if ! gpm_relay_assemble "$assembled" > "$STATE/gpmrelay.log" 2>&1; then
        log 'FAIL bridge GPM: delta assembly failed'
        cat "$STATE/gpmrelay.log"
        return 1
    fi
    cp -p "$STATE/gpmapkoriginal" "$apk" && cat "$assembled" > "$apk" &&
        [ "$(digest "$apk")" = "$(digest "$assembled")" ] &&
        cp -p "$STATE/gpmoriginal" "$odex" || return 1
    rm -f "$opt" || return 1
    BOOTCLASSPATH=$(boot_class_path) "$DEXOPT" --preopt "$apk" "$opt" m=y,u=n > "$STATE/gpmrelay.log" 2>&1
    rc=$?
    if [ "$rc" != 0 ] || [ ! -s "$opt" ]; then
        log "FAIL bridge GPM: dexopt rc=$rc"; cat "$STATE/gpmrelay.log"; return 1
    fi
    cat "$opt" > "$odex" && [ -s "$odex" ] &&
        echo "$(digest "$apk")" > "$STATE/gpmrelay.apk.md5" &&
        echo "$(digest "$odex")" > "$STATE/gpmrelay.odex.md5" && sync || return 1
    if [ -z "$BRIDGE_TEST_SYS" ]; then
        /system/bin/am force-stop com.google.android.projection.sink || return 1
    fi
    mv "$apk" "$GPM_APK" && mv "$odex" "$GPM_TARGET" && sync && gpm_relay_live || return 1
    rm -f "$opt" "$assembled" "$assembled.classes.dex" "$STATE/gpmrelay.log" || return 1
    # Retain the intent until removal: it authorizes recovery of a missing live half.
    log 'STEP bridge GPM: assembled, preoptimized and installed'
}
gpm_relay_restore() {
    typeset apk=$GPM_APK.gen5w-kr-bridge.tmp odex=$GPM_TARGET.gen5w-kr-bridge.tmp rc=0
    gpm_relay_known_pair || return 1
    [ ! -L "$apk" ] && [ ! -L "$odex" ] || return 1
    [ ! -L "$STATE/gpmrelaystaging" ] && echo "$OWNER" > "$STATE/gpmrelaystaging" && sync || return 1
    cp -p "$STATE/gpmapkoriginal" "$apk" && cp -p "$STATE/gpmoriginal" "$odex" &&
        "$GPM_TOOL" verify "$apk" "$GPM_APK_SHA" && gpm_original "$odex" || return 1
    mv "$apk" "$GPM_APK" || rc=1
    mv "$odex" "$GPM_TARGET" || rc=1
    sync
    [ "$rc" = 0 ] && "$GPM_TOOL" verify "$GPM_APK" "$GPM_APK_SHA" && gpm_original "$GPM_TARGET" || return 1
    rm -f "$STATE/gpmrelay.apk.md5" "$STATE/gpmrelay.odex.md5" || return 1
    gpm_relay_stage_clear
}
gpm_relay_cleanup() {
    typeset p
    if [ -e "$STATE/gpmapkoriginal" ] || [ -L "$STATE/gpmapkoriginal" ]; then
        gpm_relay_backups && gpm_original "$GPM_TARGET" && "$GPM_TOOL" verify "$GPM_APK" "$GPM_APK_SHA" || return 1
    fi
    for p in gpmapkoriginal gpmapkoriginal.tmp gpmrelay.apk.md5 gpmrelay.odex.md5 gpmrelaystaging gpmrelay.assembled gpmrelay.assembled.classes.dex gpmrelay.log; do
        [ ! -L "$STATE/$p" ] && [ ! -L "$MARK/$p" ] || return 1
    done
    for p in gpmapkoriginal gpmapkoriginal.tmp gpmrelay.apk.md5 gpmrelay.odex.md5 gpmrelaystaging gpmrelay.assembled gpmrelay.assembled.classes.dex gpmrelay.log; do
        rm -f "$STATE/$p" "$MARK/$p" || return 1
    done
}
