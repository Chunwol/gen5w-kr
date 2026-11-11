# Own hash-gated iAP2 capabilities; no OEM executable bytes in this package.
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
SCRIPT_DIR=$(cd "$SCRIPT_DIR" && pwd) || exit 1
. "$SCRIPT_DIR/recipe.sh"
. "$SCRIPT_DIR/errors.sh"
SYS=${BRIDGE_TEST_SYS:-/system}
DATA=${BRIDGE_TEST_DATA:-/data}
NEM=${BRIDGE_TEST_NEM:-/system/xbin/nemesis}
TARGET=$SYS/app/Iap2ServerApp.odex
APK=$SYS/app/Iap2ServerApp.apk
DIPO_TARGET=$SYS/app/HKMC_DiPO.odex
DIPO_APK=$SYS/app/HKMC_DiPO.apk
RELAY_LPD=$SCRIPT_DIR/../app/HKMC_DiPO.relay.lpd
LPATCH=${BRIDGE_TEST_LPATCH:-$SCRIPT_DIR/../bin/lpatch}
RELAY_GATE=$SCRIPT_DIR/relay-gate.sh
DEXOPT=${BRIDGE_TEST_DEXOPT:-/system/bin/dexopt}
INIT_ENV=${BRIDGE_TEST_INITENV:-/init.environ.rc}
# dexopt --preopt reads the boot class path from the environment. A script started by
# NEMESIS may not have it, so take the unit's own value from init, then the V039 list
# recorded in the stock HKMC_DiPO.odex header.
boot_class_path() {
    typeset line value=
    if [ -n "$BOOTCLASSPATH" ]; then echo "$BOOTCLASSPATH"; return 0; fi
    if [ -f "$INIT_ENV" ] && [ ! -L "$INIT_ENV" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                *"export BOOTCLASSPATH "*) value=${line#*export BOOTCLASSPATH }; break;;
            esac
        done < "$INIT_ENV"
    fi
    case "$value" in
        /system/framework/core.jar:*) echo "$value"; return 0;;
    esac
    echo /system/framework/core.jar:/system/framework/conscrypt.jar:/system/framework/okhttp.jar:/system/framework/core-junit.jar:/system/framework/bouncycastle.jar:/system/framework/ext.jar:/system/framework/framework.jar:/system/framework/framework2.jar:/system/framework/telephony-common.jar:/system/framework/voip-common.jar:/system/framework/mms-common.jar:/system/framework/android.policy.jar:/system/framework/services.jar:/system/framework/apache-xml.jar:/system/framework/webviewchromium.jar:/system/framework/automotive.jar
}
DIGEST_TOOL=${BRIDGE_TEST_DIGEST:-md5}
GPM_TARGET=$SYS/app/HKMC_GPM.odex
GPM_APK=$SYS/app/HKMC_GPM.apk
STATE=$SYS/etc/gen5w-kr-backup/bridge
MARK=$DATA/nemesis/backup/gen5w.kr.bridge
STAGE=$TARGET.gen5w-kr-bridge.tmp
NOREBOOT=$DATA/nemesis/gen5wkr.noreboot
STOPPING=$DATA/nemesis/gen5wkr.bridge.stopping
# AP start guard state (service.sh, AndroidWifiAp). Install and uninstall start it fresh.
APG=$DATA/nemesis/gen5wkr.apguard
APG_COUNT=$DATA/nemesis/gen5wkr.apguard.count
APG_OFF=$DATA/nemesis/gen5wkr.apguard.off
# Stock-path records written by the host app itself (StockApGuard).
HOST_APG=${BRIDGE_TEST_HOST_FILES:-$DATA/data/kr.gen5w.wirelesshost/files}
apguard_reset() {
    for _p in "$APG" "$APG_COUNT" "$APG_OFF" "$HOST_APG/ap-attempt" "$HOST_APG/ap-ok"; do [ ! -L "$_p" ] || return 1; done
    rm -f "$APG_COUNT" "$APG_OFF" "$HOST_APG/ap-attempt" "$HOST_APG/ap-ok" || return 1
    [ ! -d "$APG" ] || rm -rf "$APG" || return 1
    [ ! -e "$APG" ] && [ ! -e "$APG_COUNT" ] && [ ! -e "$APG_OFF" ]
}
log() { echo "$1"; }
digest() {
    set -- $("$DIGEST_TOOL" "$1" 2>/dev/null)
    echo "$1"
}
relay_packaged() { [ "$VERSION" = v039 ] && sh "$RELAY_GATE" "$SCRIPT_DIR/.." >/dev/null 2>&1; }
relay_install_ready() {
    typeset rc
    [ "$VERSION" = v039 ] || return 0
    sh "$RELAY_GATE" "$SCRIPT_DIR/.." >/dev/null 2>&1; rc=$?
    [ "$rc" = 0 ] || [ "$rc" = 77 ]
}
relay_live() {
    [ -f "$STATE/diporelay.apk.md5" ] && [ -f "$STATE/diporelay.odex.md5" ] &&
    [ ! -L "$STATE/diporelay.apk.md5" ] && [ ! -L "$STATE/diporelay.odex.md5" ] &&
    [ "$(digest "$DIPO_APK")" = "$(cat "$STATE/diporelay.apk.md5")" ] &&
    [ "$(digest "$DIPO_TARGET")" = "$(cat "$STATE/diporelay.odex.md5")" ]
}
relay_apk_live() {
    [ -f "$STATE/diporelay.apk.md5" ] && [ ! -L "$STATE/diporelay.apk.md5" ] &&
        [ "$(digest "$DIPO_APK")" = "$(cat "$STATE/diporelay.apk.md5")" ]
}
# Rebuild the relay APK from the unit's own stock files: the delta turns the verified stock
# ODEX into classes.dex (lpatch writes nothing unless the source and the result match the
# hashes inside the delta), which is added to the verified stock APK.
relay_assemble() {
    typeset out=$1 dex=$1.classes.dex lplog=$STATE/lpatch.log line rc=0
    [ ! -L "$out" ] && [ ! -L "$dex" ] && [ ! -L "$lplog" ] || return 1
    rm -f "$out" "$dex" "$lplog" || return 1
    [ -f "$RELAY_LPD" ] && [ ! -L "$RELAY_LPD" ] || { log 'FAIL bridge relay: the relay delta file is missing'; return 1; }
    [ -x "$LPATCH" ] || { log 'FAIL bridge relay: lpatch is missing or not executable'; return 1; }
    log "STEP bridge relay: stock DiPO ODEX md5 $(digest "$STATE/dipooriginal"), APK md5 $(digest "$STATE/dipoapkoriginal")"
    if "$LPATCH" delta "$RELAY_LPD" "$STATE/dipooriginal" "$dex" > "$lplog" 2>&1 &&
       "$LPATCH" zipadd "$STATE/dipoapkoriginal" "$dex" "$out" >> "$lplog" 2>&1 &&
       [ -s "$out" ]; then
        rm -f "$dex" "$lplog"
        return 0
    fi
    while IFS= read -r line || [ -n "$line" ]; do log "  lpatch: $line"; done < "$lplog"
    log 'FAIL bridge relay: lpatch could not assemble the relay APK from the stock files'
    rm -f "$out" "$dex" "$lplog"
    return 1
}
relay_odex_live() {
    [ -f "$STATE/diporelay.odex.md5" ] && [ ! -L "$STATE/diporelay.odex.md5" ] &&
        [ "$(digest "$DIPO_TARGET")" = "$(cat "$STATE/diporelay.odex.md5")" ]
}
# Drop any stale optimized copies so the newly written /system ODEX files are the
# ones the next boot loads. A mismatched dalvik-cache entry can fail class load.
DALVIK_ROOTS=${BRIDGE_TEST_DALVIK:-"/data/dalvik-cache /data/dalvik-cache/arm /cache/dalvik-cache"}
wipe_dalvik() {
    local _d _n _f
    for _d in $DALVIK_ROOTS; do
        [ -d "$_d" ] || continue
        [ ! -L "$_d" ] || return 1
        for _n in Iap2ServerApp HKMC_DiPO HKMC_GPM; do
            for _f in "$_d"/*"$_n"*; do
                [ -e "$_f" ] || continue
                rm -f "$_f" || return 1
                [ ! -e "$_f" ] || return 1
            done
        done
    done
    return 0
}
original() { [ -f "$1" ] && [ ! -L "$1" ] && { "$TOOL" original "$1" 2>/dev/null || "$ROUTE_TOOL" original "$1"; }; }
route_patched() { [ -f "$1" ] && [ ! -L "$1" ] && "$ROUTE_TOOL" patched "$1"; }
bt_patched() { [ -f "$1" ] && [ ! -L "$1" ] && [ -n "$BT_TOOL" ] && "$BT_TOOL" patched "$1"; }
legacy_patched() { [ -f "$1" ] && [ ! -L "$1" ] && "$TOOL" patched "$1"; }
patched() { route_patched "$1" || legacy_patched "$1"; }
dipo_original() { [ -f "$1" ] && [ ! -L "$1" ] && "$DIPO_TOOL" original "$1"; }
dipo_patched() { [ -f "$1" ] && [ ! -L "$1" ] && "$DIPO_TOOL" patched "$1"; }
dipo_previous() {
    typeset previous_shas previous_sha
    case "$VERSION" in
        v035) previous_shas=${BRIDGE_DIPO_PREVIOUS_V035_SHAS:-};;
        v039) previous_shas=${BRIDGE_DIPO_PREVIOUS_V039_SHAS:-};;
        *) return 1;;
    esac
    [ -n "$previous_shas" ] && [ -f "$1" ] && [ ! -L "$1" ] || return 1
    for previous_sha in $previous_shas; do
        [ -n "$previous_sha" ] || continue
        "$DIPO_TOOL" verify "$1" "$previous_sha" && return 0
    done
    return 1
}
gpm_original() { [ -f "$1" ] && [ ! -L "$1" ] && [ -n "$GPM_TOOL" ] && "$GPM_TOOL" original "$1"; }
gpm_patched() { [ -f "$1" ] && [ ! -L "$1" ] && [ -n "$GPM_TOOL" ] && "$GPM_TOOL" patched "$1"; }
. "$SCRIPT_DIR/gpm-relay.sh"
owned() { [ -f "$STATE/owner" ] && [ ! -L "$STATE/owner" ] && [ "$(cat "$STATE/owner")" = "$OWNER" ]; }
# /system can stay busy for a moment after a change (EBUSY, also seen on a US
# Ioniq 5). Changes are synced and the install reboots, which mounts /system
# read-only again, so a busy remount is a warning, not a failure.
sys_ro() {
    local n=0
    while [ $n -lt 3 ]; do
        err_mount bridge ro "$NEM" && return 0
        n=$((n + 1)); sleep 1
    done
    echo 'WARN: /system read-only remount failed; reboot required; see ERR cause'
    return 0
}
inspect() {
    [ -x "$NEM" ] || return 1
    for bridge_path in "$SYS/etc/gen5w-kr-backup" "$DATA/nemesis/backup" "$STATE" "$MARK" "$TARGET" "$APK" "$DIPO_TARGET" "$DIPO_APK" "$GPM_TARGET" "$GPM_APK" "$STOPPING"; do
        [ ! -L "$bridge_path" ] || { log 'FAIL bridge: symbolic link at managed path'; return 1; }
    done
    # NEMESIS extracts native files as 0644; only our fixed helper names change mode.
    for bridge_version in v035 v039; do
        for bridge_kind in iap2 iap2-route iap2-bt dipo gpm; do
            bridge_tool=$SCRIPT_DIR/../bin/$bridge_kind-patch-$bridge_version
            if [ -f "$bridge_tool" ] && [ ! -L "$bridge_tool" ]; then chmod 755 "$bridge_tool" || return 1; fi
        done
    done
    # The relay assembler is not named like the patchers above, so it needs its own mode change.
    if [ -f "$LPATCH" ] && [ ! -L "$LPATCH" ]; then chmod 755 "$LPATCH" || return 1; fi
    BRIDGE_OWNED=no
    if [ -e "$STATE" ]; then
        [ -d "$STATE" ] && [ -f "$STATE/owner" ] && [ ! -L "$STATE/owner" ] || return 1
        case "$(cat "$STATE/owner")" in
            gen5w.kr.bridge:v035-1) VERSION=v035;;
            gen5w.kr.bridge:v039-1) VERSION=v039;;
            *) log 'FAIL bridge: foreign recovery ownership'; return 1;;
        esac
        BRIDGE_OWNED=yes
    else
        VERSION=
        for bridge_version in v035 v039; do
            TOOL=$SCRIPT_DIR/../bin/iap2-patch-$bridge_version
            ROUTE_TOOL=$SCRIPT_DIR/../bin/iap2-route-patch-$bridge_version
            if original "$TARGET" || patched "$TARGET"; then VERSION=$bridge_version; break; fi
        done
        [ -n "$VERSION" ] || { log 'SKIP bridge: unknown stock ODEX hash'; return 77; }
    fi
    TOOL=$SCRIPT_DIR/../bin/iap2-patch-$VERSION
    ROUTE_TOOL=$SCRIPT_DIR/../bin/iap2-route-patch-$VERSION
    BT_TOOL=$SCRIPT_DIR/../bin/iap2-bt-patch-$VERSION
    [ -f "$BT_TOOL" ] && [ -x "$BT_TOOL" ] || BT_TOOL=
    DIPO_TOOL=$SCRIPT_DIR/../bin/dipo-patch-$VERSION
    GPM_TOOL=
    GPM_VERSION=
    GPM_APK_SHA=
    OWNER=gen5w.kr.bridge:$VERSION-1
    if original "$TARGET"; then BRIDGE_STATE=stock
    elif bt_patched "$TARGET"; then BRIDGE_STATE=bt-patched
    elif route_patched "$TARGET"; then BRIDGE_STATE=route-patched
    elif legacy_patched "$TARGET"; then BRIDGE_STATE=legacy-patched
    else log 'FAIL bridge: owned target changed'; return 1; fi
    if [ "$BRIDGE_OWNED" = yes ] && { relay_live || relay_apk_live || relay_odex_live; }; then DIPO_STATE=relay
    elif dipo_original "$DIPO_TARGET"; then DIPO_STATE=stock
    elif dipo_patched "$DIPO_TARGET"; then DIPO_STATE=patched
    elif dipo_previous "$DIPO_TARGET"; then DIPO_STATE=previous
    else
        log 'SKIP bridge: unknown or mismatched DiPO ODEX'
        [ "$BRIDGE_OWNED" = no ] && return 77
        return 1
    fi
    GPM_STATE=
    if [ "$BRIDGE_OWNED" = yes ] && [ "$VERSION" = v039 ] &&
       { [ -e "$STATE/gpmrelay.apk.md5" ] || [ -L "$STATE/gpmrelay.apk.md5" ] ||
         [ -e "$STATE/gpmrelay.odex.md5" ] || [ -L "$STATE/gpmrelay.odex.md5" ] ||
         [ -e "$STATE/gpmrelaystaging" ] || [ -L "$STATE/gpmrelaystaging" ]; }; then
        GPM_TOOL=$SCRIPT_DIR/../bin/gpm-patch-v039
        GPM_VERSION=v039; GPM_APK_SHA=$BRIDGE_GPM_APK_V039_SHA
        gpm_relay_known_pair || { log 'FAIL bridge: unknown or damaged GPM relay pair'; return 1; }
        GPM_STATE=relay
    elif [ -f "$GPM_TARGET" ]; then
        for gpm_version in v035 v039; do
            GPM_TOOL=$SCRIPT_DIR/../bin/gpm-patch-$gpm_version
            [ -f "$GPM_TOOL" ] && [ -x "$GPM_TOOL" ] || continue
            case "$gpm_version" in
                v035) GPM_APK_SHA=${BRIDGE_GPM_APK_V035_SHA:-};;
                v039) GPM_APK_SHA=${BRIDGE_GPM_APK_V039_SHA:-};;
            esac
            [ -n "$GPM_APK_SHA" ] && "$GPM_TOOL" verify "$GPM_APK" "$GPM_APK_SHA" || continue
            if gpm_original "$GPM_TARGET"; then GPM_STATE=stock
            elif gpm_patched "$GPM_TARGET"; then GPM_STATE=patched
            else continue; fi
            GPM_VERSION=$gpm_version
            break
        done
        if [ -z "$GPM_VERSION" ]; then
            log 'SKIP bridge: unknown or mismatched GPM APK/ODEX pair'
            [ "$BRIDGE_OWNED" = no ] && return 77
            return 1
        fi
    fi
    case "$VERSION" in
        v035) APK_SHA=$BRIDGE_APK_V035_SHA; DIPO_APK_SHA=$BRIDGE_DIPO_APK_V035_SHA;;
        v039) APK_SHA=$BRIDGE_APK_V039_SHA; DIPO_APK_SHA=$BRIDGE_DIPO_APK_V039_SHA;;
    esac
    if ! "$TOOL" verify "$APK" "$APK_SHA" || { [ "$DIPO_STATE" != relay ] && ! "$DIPO_TOOL" verify "$DIPO_APK" "$DIPO_APK_SHA"; }; then
        log 'SKIP bridge: stock APK and ODEX version do not match'
        [ "$BRIDGE_OWNED" = no ] && return 77
        return 1
    fi
    if [ "$GPM_STATE" != relay ] && [ -n "$GPM_TOOL" ] && [ -f "$GPM_TARGET" ] && [ -n "$GPM_APK_SHA" ]; then
        if ! "$GPM_TOOL" verify "$GPM_APK" "$GPM_APK_SHA"; then
            log 'SKIP bridge: stock GPM APK and ODEX version do not match'
            [ "$BRIDGE_OWNED" = no ] && return 77
            return 1
        fi
    fi
    if [ "$BRIDGE_OWNED" = yes ]; then
        if [ -e "$STATE/gpmapkoriginal" ] || [ -L "$STATE/gpmapkoriginal" ]; then
            gpm_relay_backups || { log 'FAIL bridge: durable GPM pair backup damaged'; return 1; }
        fi
        if [ -e "$STATE/original" ] || [ -L "$STATE/original" ]; then
            original "$STATE/original" || { log 'FAIL bridge: durable backup damaged'; return 1; }
        fi
        if [ -e "$STATE/dipooriginal" ] || [ -L "$STATE/dipooriginal" ]; then
            dipo_original "$STATE/dipooriginal" || { log 'FAIL bridge: durable DiPO backup damaged'; return 1; }
        fi
        if [ -e "$STATE/dipoapkoriginal" ] || [ -L "$STATE/dipoapkoriginal" ]; then
            "$DIPO_TOOL" verify "$STATE/dipoapkoriginal" "$DIPO_APK_SHA" || { log 'FAIL bridge: durable DiPO APK backup damaged'; return 1; }
        fi
        if [ -n "$GPM_TOOL" ] && [ -f "$GPM_TARGET" ]; then
            if [ -e "$STATE/gpmoriginal" ] || [ -L "$STATE/gpmoriginal" ]; then
                gpm_original "$STATE/gpmoriginal" || { log 'FAIL bridge: durable GPM backup damaged'; return 1; }
            fi
        fi
    fi
    if [ "$BRIDGE_STATE" = route-patched ] || [ "$BRIDGE_STATE" = legacy-patched ] || [ "$BRIDGE_STATE" = bt-patched ] ||
       [ "$DIPO_STATE" = patched ] || [ "$DIPO_STATE" = previous ] || [ "$DIPO_STATE" = relay ]; then
        [ "$BRIDGE_OWNED" = yes ] && original "$STATE/original" && dipo_original "$STATE/dipooriginal" || { log 'FAIL bridge: patch lacks owned original pair'; return 1; }
    fi
    if [ "$GPM_STATE" = patched ]; then
        [ "$BRIDGE_OWNED" = yes ] && gpm_original "$STATE/gpmoriginal" || { log 'FAIL bridge: GPM patch lacks owned original'; return 1; }
    fi
    if [ -e "$MARK" ]; then
        [ -d "$MARK" ] && [ ! -L "$MARK/owner" ] && [ "$(cat "$MARK/owner" 2>/dev/null)" = "$OWNER" ] || return 1
        if [ -e "$MARK/original" ] || [ -L "$MARK/original" ]; then original "$MARK/original" || return 1; fi
        if [ -e "$MARK/dipooriginal" ] || [ -L "$MARK/dipooriginal" ]; then dipo_original "$MARK/dipooriginal" || return 1; fi
        if [ -e "$MARK/gpmoriginal" ] || [ -L "$MARK/gpmoriginal" ]; then gpm_original "$MARK/gpmoriginal" || return 1; fi
        if [ -e "$MARK/gpmapkoriginal" ] || [ -L "$MARK/gpmapkoriginal" ]; then
            [ ! -L "$MARK/gpmapkoriginal" ] && "$GPM_TOOL" verify "$MARK/gpmapkoriginal" "$GPM_APK_SHA" || return 1
        fi
    fi
}
save_original() {
    mkdir -p "$STATE" || return 1
    if ! owned; then echo "$OWNER" > "$STATE/owner" && chmod 600 "$STATE/owner" || return 1; fi
    if ! original "$STATE/original"; then
        original "$TARGET" && [ ! -L "$STATE/original.tmp" ] || return 1
        cp -p "$TARGET" "$STATE/original.tmp" && original "$STATE/original.tmp" && mv "$STATE/original.tmp" "$STATE/original" || return 1
    fi
    if ! dipo_original "$STATE/dipooriginal"; then
        dipo_original "$DIPO_TARGET" && [ ! -L "$STATE/dipooriginal.tmp" ] || return 1
        cp -p "$DIPO_TARGET" "$STATE/dipooriginal.tmp" && dipo_original "$STATE/dipooriginal.tmp" && mv "$STATE/dipooriginal.tmp" "$STATE/dipooriginal" || return 1
    fi
    if relay_packaged && [ ! -f "$STATE/dipoapkoriginal" ]; then
        "$DIPO_TOOL" verify "$DIPO_APK" "$DIPO_APK_SHA" && [ ! -L "$STATE/dipoapkoriginal.tmp" ] || return 1
        cp -p "$DIPO_APK" "$STATE/dipoapkoriginal.tmp" &&
            "$DIPO_TOOL" verify "$STATE/dipoapkoriginal.tmp" "$DIPO_APK_SHA" &&
            mv "$STATE/dipoapkoriginal.tmp" "$STATE/dipoapkoriginal" || return 1
    fi
    if [ -n "$GPM_TOOL" ] && [ -f "$GPM_TARGET" ]; then
        if ! gpm_original "$STATE/gpmoriginal"; then
            gpm_original "$GPM_TARGET" && [ ! -L "$STATE/gpmoriginal.tmp" ] || return 1
            cp -p "$GPM_TARGET" "$STATE/gpmoriginal.tmp" && gpm_original "$STATE/gpmoriginal.tmp" && mv "$STATE/gpmoriginal.tmp" "$STATE/gpmoriginal" || return 1
        fi
    fi
    mkdir -p "$MARK" || return 1
    [ ! -L "$MARK/owner" ] && [ ! -L "$MARK/original.tmp" ] && [ ! -L "$MARK/dipooriginal.tmp" ] || return 1
    echo "$OWNER" > "$MARK/owner" || return 1
    cp -p "$STATE/original" "$MARK/original.tmp" && original "$MARK/original.tmp" && mv "$MARK/original.tmp" "$MARK/original" || return 1
    cp -p "$STATE/dipooriginal" "$MARK/dipooriginal.tmp" && dipo_original "$MARK/dipooriginal.tmp" && mv "$MARK/dipooriginal.tmp" "$MARK/dipooriginal" || return 1
    if [ -f "$STATE/dipoapkoriginal" ]; then
        [ ! -L "$MARK/dipoapkoriginal.tmp" ] || return 1
        cp -p "$STATE/dipoapkoriginal" "$MARK/dipoapkoriginal.tmp" &&
            "$DIPO_TOOL" verify "$MARK/dipoapkoriginal.tmp" "$DIPO_APK_SHA" &&
            mv "$MARK/dipoapkoriginal.tmp" "$MARK/dipoapkoriginal" || return 1
    fi
    if [ -n "$GPM_TOOL" ] && [ -f "$GPM_TARGET" ]; then
        [ ! -L "$MARK/gpmoriginal.tmp" ] || return 1
        cp -p "$STATE/gpmoriginal" "$MARK/gpmoriginal.tmp" && gpm_original "$MARK/gpmoriginal.tmp" && mv "$MARK/gpmoriginal.tmp" "$MARK/gpmoriginal" || return 1
    fi
    gpm_relay_save_apk || return 1
    chmod 700 "$STATE" "$MARK" || return 1
    sync
}
stage_clear_one() {
    typeset stage_path=$1 stage_marker=$2 stage_tool=$3
    [ ! -L "$stage_path" ] && [ ! -L "$stage_marker" ] || return 1
    if [ -e "$stage_path" ]; then
        if ! "$stage_tool" original "$stage_path" && ! "$stage_tool" patched "$stage_path"; then
            [ -f "$stage_marker" ] && [ "$(cat "$stage_marker")" = "$OWNER" ] || return 1
        fi
        rm "$stage_path" || return 1
    fi
    rm -f "$stage_marker"
}
stage_clear() {
    gpm_relay_stage_clear || return 1
    stage_clear_one "$STAGE" "$STATE/staging" "$ROUTE_TOOL" &&
        stage_clear_one "$DIPO_TARGET.gen5w-kr-bridge.tmp" "$STATE/dipostaging" "$DIPO_TOOL" &&
        { [ -z "$GPM_TOOL" ] || [ ! -f "$GPM_TARGET" ] || stage_clear_one "$GPM_TARGET.gen5w-kr-bridge.tmp" "$STATE/gpmstaging" "$GPM_TOOL"; } &&
        relay_stage_clear
}
relay_stage_clear() {
    typeset apk_stage=$DIPO_APK.gen5w-kr-bridge.tmp odex_stage=$DIPO_TARGET.gen5w-kr-bridge.tmp marker=$STATE/diporelaystaging
    [ ! -L "$apk_stage" ] && [ ! -L "$odex_stage" ] && [ ! -L "$marker" ] || return 1
    if [ -e "$apk_stage" ] || [ -e "$odex_stage" ]; then
        [ -f "$marker" ] && [ "$(cat "$marker")" = "$OWNER" ] || return 1
        rm -f "$apk_stage" "$odex_stage" "$odex_stage.opt" || return 1
    fi
    rm -f "$marker"
}
replace_plain() {
    typeset source=$1 target=$2 backup=$3 marker=$4 stage=$2.gen5w-kr-bridge.tmp
    [ -f "$source" ] && [ -f "$backup" ] && [ ! -L "$source" ] && [ ! -L "$target" ] &&
        [ ! -L "$stage" ] && [ ! -L "$marker" ] || return 1
    rm -f "$stage" || return 1
    echo "$OWNER" > "$marker" && cp -p "$backup" "$stage" && cat "$source" > "$stage" &&
        [ -s "$stage" ] && sync && mv "$stage" "$target" && [ "$(digest "$target")" = "$(digest "$source")" ] || return 1
    rm -f "$marker"; sync
}
install_relay_dipo() {
    typeset odex_stage=$DIPO_TARGET.gen5w-kr-bridge.tmp apk_stage=$DIPO_APK.gen5w-kr-bridge.tmp
    typeset opt=$DIPO_TARGET.gen5w-kr-bridge.tmp.opt
    typeset assembled=$STATE/diporelay.assembled dexlog=$STATE/dexopt.log bcp line rc out=missing
    relay_packaged || { log 'FAIL bridge relay: relay payload is not complete'; return 1; }
    [ "$DIPO_STATE" = stock ] || { log "FAIL bridge relay: DiPO state is $DIPO_STATE, not stock"; return 1; }
    [ -f "$STATE/dipoapkoriginal" ] || { log 'FAIL bridge relay: no saved stock DiPO APK'; return 1; }
    [ ! -L "$odex_stage" ] && [ ! -L "$apk_stage" ] && [ ! -L "$opt" ] || { log 'FAIL bridge relay: staging path is a symlink'; return 1; }
    relay_stage_clear || { log 'FAIL bridge relay: could not clear earlier staging files'; return 1; }
    rm -f "$opt" "$dexlog" || return 1
    echo "$OWNER" > "$STATE/diporelaystaging" || { log 'FAIL bridge relay: could not write staging marker'; return 1; }
    if ! relay_assemble "$assembled"; then
        :   # relay_assemble has already logged the reason
    elif ! { cp -p "$STATE/dipoapkoriginal" "$apk_stage" && cat "$assembled" > "$apk_stage" &&
             [ "$(digest "$apk_stage")" = "$(digest "$assembled")" ]; }; then
        log 'FAIL bridge relay: could not stage the relay APK'
    elif ! cp -p "$STATE/dipooriginal" "$odex_stage" || ! : > "$odex_stage"; then
        log 'FAIL bridge relay: could not stage the relay ODEX'
    else
        # dexopt creates its output itself and needs the boot class path.
        bcp=$(boot_class_path)
        BOOTCLASSPATH=$bcp "$DEXOPT" --preopt "$apk_stage" "$opt" m=y,u=n > "$dexlog" 2>&1
        rc=$?
        if [ "$rc" != 0 ] || [ ! -s "$opt" ]; then
            [ ! -f "$opt" ] || { [ -s "$opt" ] && out=non-empty || out=empty; }
            log "FAIL bridge relay: dexopt rc=$rc output=$out"
            while IFS= read -r line || [ -n "$line" ]; do log "  dexopt: $line"; done < "$dexlog"
        elif ! { cat "$opt" > "$odex_stage" && rm -f "$opt" && [ -s "$odex_stage" ]; }; then
            log 'FAIL bridge relay: could not write the optimized ODEX'
        elif ! { echo "$(digest "$apk_stage")" > "$STATE/diporelay.apk.md5" &&
                 echo "$(digest "$odex_stage")" > "$STATE/diporelay.odex.md5" && sync; }; then
            log 'FAIL bridge relay: could not record the relay hashes'
        elif ! { mv "$apk_stage" "$DIPO_APK" && mv "$odex_stage" "$DIPO_TARGET" && sync; }; then
            log 'FAIL bridge relay: could not move the relay files into place'
        elif ! relay_live; then
            log 'FAIL bridge relay: installed relay files do not match the recorded hashes'
        else
            rm -f "$STATE/diporelaystaging" "$assembled" "$assembled.classes.dex" "$dexlog"
            log 'STEP bridge relay: assembled, preoptimized and installed'
            return 0
        fi
    fi
    rm -f "$apk_stage" "$odex_stage" "$opt" "$dexlog" "$STATE/diporelaystaging"         "$STATE/diporelay.apk.md5" "$STATE/diporelay.odex.md5" "$assembled" "$assembled.classes.dex"
    return 1
}
replace_target() {
    typeset replace_source=$1 replace_kind=$2 replace_path=$3 replace_tool=$4 replace_backup=$5 replace_marker=$6
    typeset replace_stage=$replace_path.gen5w-kr-bridge.tmp
    # Stage retains original mode, uid and gid; rename is atomic.
    stage_clear_one "$replace_stage" "$replace_marker" "$replace_tool" || return 1
    echo "$OWNER" > "$replace_marker" && sync || return 1
    if cp -p "$replace_backup" "$replace_stage" && cat "$replace_source" > "$replace_stage" &&
       "$replace_tool" "$replace_kind" "$replace_stage" && sync && mv "$replace_stage" "$replace_path" && "$replace_tool" "$replace_kind" "$replace_path"; then
        rm -f "$replace_marker"; sync; return 0
    fi
    stage_clear_one "$replace_stage" "$replace_marker" "$replace_tool" || true
    return 1
}
restore_target() {
    typeset restore_rc=0
    if ! original "$TARGET"; then
        { patched "$TARGET" || bt_patched "$TARGET"; } && original "$STATE/original" &&
            replace_target "$STATE/original" original "$TARGET" "$TOOL" "$STATE/original" "$STATE/staging" || restore_rc=1
    fi
    if [ "$DIPO_STATE" = relay ] || relay_live || relay_apk_live || relay_odex_live; then
        if dipo_original "$STATE/dipooriginal" && "$DIPO_TOOL" verify "$STATE/dipoapkoriginal" "$DIPO_APK_SHA"; then
            cp -p "$STATE/dipoapkoriginal" "$DIPO_APK.gen5w-kr-bridge.tmp" &&
            cp -p "$STATE/dipooriginal" "$DIPO_TARGET.gen5w-kr-bridge.tmp" && sync &&
            mv "$DIPO_APK.gen5w-kr-bridge.tmp" "$DIPO_APK" &&
            mv "$DIPO_TARGET.gen5w-kr-bridge.tmp" "$DIPO_TARGET" && sync || restore_rc=1
        else restore_rc=1; fi
        rm -f "$STATE/diporelay.apk.md5" "$STATE/diporelay.odex.md5"
    elif ! dipo_original "$DIPO_TARGET"; then
        { dipo_patched "$DIPO_TARGET" || dipo_previous "$DIPO_TARGET"; } && dipo_original "$STATE/dipooriginal" &&
            replace_target "$STATE/dipooriginal" original "$DIPO_TARGET" "$DIPO_TOOL" "$STATE/dipooriginal" "$STATE/dipostaging" || restore_rc=1
    fi
    if [ -e "$STATE/gpmapkoriginal" ] || [ -L "$STATE/gpmapkoriginal" ]; then
        gpm_relay_restore || restore_rc=1
    elif [ -n "$GPM_TOOL" ] && [ -f "$GPM_TARGET" ] && ! gpm_original "$GPM_TARGET"; then
        gpm_patched "$GPM_TARGET" && gpm_original "$STATE/gpmoriginal" &&
            replace_target "$STATE/gpmoriginal" original "$GPM_TARGET" "$GPM_TOOL" "$STATE/gpmoriginal" "$STATE/gpmstaging" || restore_rc=1
    fi
    return "$restore_rc"
}
cleanup_owned() {
    owned && gpm_relay_cleanup || return 1
    owned && original "$TARGET" && dipo_original "$DIPO_TARGET" &&
        { [ -z "$GPM_TOOL" ] || [ ! -f "$GPM_TARGET" ] || gpm_original "$GPM_TARGET"; } || return 1
    for bridge_file in original original.tmp dipooriginal dipooriginal.tmp dipoapkoriginal dipoapkoriginal.tmp diporelay.apk.md5 diporelay.odex.md5 diporelaystaging diporelay.assembled diporelay.assembled.classes.dex gpmoriginal gpmoriginal.tmp replacement diporeplacement gpmreplacement staging dipostaging gpmstaging owner; do
        [ ! -L "$STATE/$bridge_file" ] || return 1
    done
    rm -f "$STATE/original" "$STATE/original.tmp" "$STATE/dipooriginal" "$STATE/dipooriginal.tmp" "$STATE/dipoapkoriginal" "$STATE/dipoapkoriginal.tmp" \
         "$STATE/diporelay.apk.md5" "$STATE/diporelay.odex.md5" "$STATE/diporelaystaging" "$STATE/diporelay.assembled" "$STATE/diporelay.assembled.classes.dex" "$STATE/gpmoriginal" "$STATE/gpmoriginal.tmp" \
         "$STATE/replacement" "$STATE/diporeplacement" "$STATE/gpmreplacement" "$STATE/staging" "$STATE/dipostaging" "$STATE/gpmstaging" "$STATE/owner" && rmdir "$STATE" || return 1
    if [ -d "$MARK" ]; then
        [ ! -L "$MARK/owner" ] && [ "$(cat "$MARK/owner")" = "$OWNER" ] && [ ! -L "$MARK/original.tmp" ] && [ ! -L "$MARK/dipooriginal.tmp" ] && [ ! -L "$MARK/dipoapkoriginal.tmp" ] || return 1
        rm -f "$MARK/original" "$MARK/original.tmp" "$MARK/dipooriginal" "$MARK/dipooriginal.tmp" \
            "$MARK/dipoapkoriginal" "$MARK/dipoapkoriginal.tmp" "$MARK/gpmoriginal" "$MARK/gpmoriginal.tmp" "$MARK/owner" && rmdir "$MARK" || return 1
    fi
    rmdir "$SYS/etc/gen5w-kr-backup" 2>/dev/null || true
}
# Runtime copies without a system journal: left by a firmware reinstall. Only
# our own fixed files are removed, and never while a patched file is live.
clear_runtime_copy() {
    [ ! -e "$STATE" ] && [ ! -L "$STATE" ] || return 1
    [ -e "$MARK" ] || [ -L "$MARK" ] || return 0
    [ -d "$MARK" ] && [ ! -L "$MARK" ] || return 1
    case "$(cat "$MARK/owner" 2>/dev/null)" in gen5w.kr.bridge:*) ;; *) return 1;; esac
    if [ -n "$TOOL" ]; then ! patched "$TARGET" || return 1; fi
    if [ -n "$DIPO_TOOL" ]; then ! dipo_patched "$DIPO_TARGET" || return 1; fi
    if [ -n "$GPM_TOOL" ]; then ! gpm_patched "$GPM_TARGET" || return 1; fi
    for bridge_file in original original.tmp dipooriginal dipooriginal.tmp dipoapkoriginal dipoapkoriginal.tmp gpmoriginal gpmoriginal.tmp gpmapkoriginal gpmapkoriginal.tmp owner; do
        [ ! -L "$MARK/$bridge_file" ] || return 1
    done
    rm -f "$MARK/original" "$MARK/original.tmp" "$MARK/dipooriginal" "$MARK/dipooriginal.tmp" \
        "$MARK/dipoapkoriginal" "$MARK/dipoapkoriginal.tmp" "$MARK/gpmoriginal" "$MARK/gpmoriginal.tmp" "$MARK/gpmapkoriginal" "$MARK/gpmapkoriginal.tmp" "$MARK/owner" &&
        rmdir "$MARK" || return 1
    log 'CLEARED bridge: runtime copies left by a system reinstall'
}
