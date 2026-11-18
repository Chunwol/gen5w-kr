#!/system/bin/sh
# Build private replacements on the unit. Nothing is mounted or started here.
umask 077
LC_ALL=C; export LC_ALL
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
BASE=$(CDPATH= cd -- "$BASE" && pwd) || exit 1
ROOT=${PORTABLE_TEST_ROOT:-}
HELPER=$BASE/bin/dex-patch
fail() { echo "prepare: $*" >&2; exit 1; }
# The target mksh print builtin preserves literal stock text.
literal() { print -r -- "$1"; }
safe() { case "$1" in ''|*[!a-zA-Z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac; }
plain() {
    safe "$1" || return 1
    case "$1" in /*) :;; *) return 1;; esac
    local part=$1
    while [ "$part" != / ] && [ -n "$part" ]; do
        [ ! -L "$part" ] || return 1
        part=${part%/*}; [ -n "$part" ] || part=/
    done
}
if [ -n "$ROOT" ]; then
    plain "$ROOT" && [ "$ROOT" != / ] && [ -d "$ROOT" ] || fail 'invalid fixture'
    [ -n "$PORTABLE_TEST_HELPER" ] && HELPER=$PORTABLE_TEST_HELPER
fi
plain "$HELPER" && [ -x "$HELPER" ] || fail 'native helper missing'
case "$1" in /data/*) WORK=$1;; *) fail 'usage: prepare.sh /data/NEW-DIRECTORY [--stock-origins] [route|bt|dipo|gpm|hotspot|audio|projection ...]';; esac
shift
ORIGIN_MODE=off
case "${1:-}" in --stock-origins) ORIGIN_MODE=on; shift;; esac
RECOVERY=$ROOT/data/local/gen5w-portable/persistent/recovery
OLD_RECOVERY=$RECOVERY/manifest
PERSISTENT=$ROOT/data/local/gen5w-portable/persistent
UPDATE_MODE=0
if [ "$ORIGIN_MODE" = on ] && { [ -e "$OLD_RECOVERY" ] || [ -L "$OLD_RECOVERY" ]; }; then
    plain "$OLD_RECOVERY" && [ -f "$OLD_RECOVERY" ] || fail 'unsafe persistent recovery manifest'
    UPDATE_MODE=1
elif [ "$ORIGIN_MODE" = on ]; then
    # A missing manifest is not evidence of a fresh install. Leftover originals,
    # a partial recovery directory, or the persistent owner manifest means a
    # prior migration may have happened; never recapture its applied /system
    # bytes as the new stock origin.
    OWNER=$ROOT/data/local/gen5w-portable/persistent/manifest
    plain "$PERSISTENT" && plain "$RECOVERY" && plain "$OWNER" || fail 'unsafe persistent recovery state'
    if [ -e "$PERSISTENT" ] || [ -L "$PERSISTENT" ] || [ -e "$RECOVERY" ] || [ -L "$RECOVERY" ] || [ -e "$OWNER" ] || [ -L "$OWNER" ]; then
        fail 'persistent recovery manifest missing; refusing to recapture live system files'
    fi
fi
plain "$ROOT$WORK" || fail 'unsafe work directory'
[ ! -e "$ROOT$WORK" ] || fail 'work directory already exists; use a fresh path'
[ "$#" -gt 0 ] || set -- bt dipo gpm hotspot audio projection
features=" $* "
seen=' '
for feature in "$@"; do
    case "$feature" in route|bt|dipo|gpm|hotspot|audio|projection) :;; *) fail 'unknown feature';; esac
    case "$seen" in *" $feature "*) fail 'duplicate feature';; esac
    seen="$seen$feature "
done
case "$features" in *' route '*) case "$features" in *' bt '*) fail 'bt and route share one target; select one';; esac;; esac
mkdir -p "$ROOT${WORK%/*}" || fail 'cannot create parent'
mkdir "$ROOT$WORK" && mkdir "$ROOT$WORK/files" || fail 'cannot create work directory'
if [ "$ORIGIN_MODE" = on ]; then mkdir "$ROOT$WORK/stock-origins" || fail 'cannot create stock origins'; : > "$ROOT$WORK/stock-origins/index.tsv" || fail 'cannot create stock origin index'; fi
REPORT=$ROOT$WORK/features.txt
MANIFEST=$ROOT$WORK/manifest
: > "$REPORT"; : > "$MANIFEST"
status() { echo "$1|$2|$3" >> "$REPORT" || fail 'cannot record feature result'; }
digest() { "$HELPER" sha256 "$1"; }
metadata() { "$HELPER" metadata "$1"; }
selabel() { "$HELPER" label "$1"; }
field_count() {
    field_total=1; field_rest=$1
    while case "$field_rest" in *'|'*) :;; *) false;; esac; do
        field_total=$((field_total+1)); field_rest=${field_rest#*'|'}
    done
}
find_row() {
    local file=$1 requested=$2 record first rest found=0
    FOUND_ROW=
    while IFS= read -r record || [ -n "$record" ]; do
        IFS='|' read -r first rest <<EOF
$record
EOF
        [ "$first" = "$requested" ] || continue
        found=$((found+1)); FOUND_ROW=$record
    done < "$file"
    [ "$found" -le 1 ]
}
has_feature() {
    local wanted=$1 feature rest
    while IFS='|' read -r feature rest; do [ "$feature" = "$wanted" ] && return 0; done < "$MANIFEST"
    return 1
}
load_stock_origin() {
    local target=$1 row header version fields extra current current_meta current_label
    STOCK_PATH=$ROOT$target; STOCK_HASH=; STOCK_META=; STOCK_LABEL=; STOCK_KIND=file
    if [ "$UPDATE_MODE" = 1 ]; then
        IFS= read -r header < "$OLD_RECOVERY" || return 1
        case "$header" in GEN5W-RECOVERY-MANIFEST\|1) version=1;; GEN5W-RECOVERY-MANIFEST\|2) version=2;; *) return 1;; esac
        find_row "$OLD_RECOVERY" "$target" || return 1
        row=$FOUND_ROW
        if [ -n "$row" ]; then
            IFS='|' read -r old_target old_kind original_sha applied_sha orig_uid orig_gid orig_mode orig_label applied_uid applied_gid applied_mode applied_label prior_sha extra <<EOF
$row
EOF
            [ "$old_target" = "$target" ] && [ -z "$extra" ] || return 1
            field_count "$row"
            if [ "$version" = 1 ]; then [ "$field_total" = 12 ] || return 1; else [ "$field_total" = 13 ] || return 1; fi
            case "$applied_sha" in *[!a-f0-9]*) return 1;; esac
            [ "${#applied_sha}" = 64 ] || return 1
            case "$applied_uid:$applied_gid:$applied_mode" in *[!0-9:]*|:*|*:) return 1;; esac
            case "$applied_label" in ''|*[!A-Za-z0-9_:.,+-]*) return 1;; esac
            case "$version:$prior_sha" in
                1:) :;;
                2:-) :;;
                2:*) case "$prior_sha" in *[!a-f0-9]*) return 1;; esac; [ "${#prior_sha}" = 64 ] || return 1;;
                *) return 1;;
            esac
            case "$old_kind" in
                file)
                    case "$original_sha" in *[!a-f0-9]*) return 1;; esac
                    [ "${#original_sha}" = 64 ] || return 1
                    case "$orig_uid:$orig_gid:$orig_mode" in *[!0-9:]*|:*|*:) return 1;; esac
                    case "$orig_label" in ''|*[!A-Za-z0-9_:.,+-]*) return 1;; esac
                    STOCK_PATH=$RECOVERY/originals$target
                    plain "$STOCK_PATH" && [ -f "$STOCK_PATH" ] && [ ! -L "$STOCK_PATH" ] || return 1
                    STOCK_HASH=$("$HELPER" sha256 "$STOCK_PATH") || return 1
                    [ "$STOCK_HASH" = "$original_sha" ] || return 1
                    STOCK_META="$orig_uid|$orig_gid|$orig_mode"; STOCK_LABEL=$orig_label
                    ;;
                absent)
                    [ "$original_sha:$orig_uid:$orig_gid:$orig_mode:$orig_label" = '-:-:-:-:-' ] || return 1
                    STOCK_KIND=absent
                    ;;
                *) return 1;;
            esac
            if [ -e "$ROOT$target" ]; then
                [ -f "$ROOT$target" ] && [ ! -L "$ROOT$target" ] || return 1
                current=$(digest "$ROOT$target") && current_meta=$(metadata "$ROOT$target") && current_label=$(selabel "$ROOT$target") || return 1
                case "$old_kind" in
                    file)
                        if [ "$current" = "$original_sha" ]; then
                            [ "$current_meta" = "$STOCK_META" ] && [ "$current_label" = "$STOCK_LABEL" ] || return 1
                        elif [ "$current" = "$applied_sha" ] || { [ "$version" = 2 ] && [ "$prior_sha" != - ] && [ "$current" = "$prior_sha" ]; }; then
                            [ "$current_meta" = "$applied_uid|$applied_gid|$applied_mode" ] && [ "$current_label" = "$applied_label" ] || return 1
                        else return 1; fi
                        ;;
                    absent)
                        [ "$current" = "$applied_sha" ] && [ "$current_meta" = "$applied_uid|$applied_gid|$applied_mode" ] && [ "$current_label" = "$applied_label" ] || return 1
                        ;;
                esac
            elif [ "$old_kind" = file ]; then return 1; fi
            return 0
        fi
    fi
    plain "$ROOT$target" && [ -f "$ROOT$target" ] && [ ! -L "$ROOT$target" ] || return 1
    STOCK_HASH=$(digest "$ROOT$target") && STOCK_META=$(metadata "$ROOT$target") && STOCK_LABEL=$(selabel "$ROOT$target") || return 1
    return 0
}
capture_origin() {
    local target=$1 origin="$ROOT$WORK/stock-origins/${1#/}" hash meta label uid gid mode
    [ "$ORIGIN_MODE" = on ] || return 0
    load_stock_origin "$target" || return $?
    [ "$STOCK_KIND" = file ] || return 0
    hash=$STOCK_HASH; meta=$STOCK_META; label=$STOCK_LABEL
    find_row "$ROOT$WORK/stock-origins/index.tsv" "$target" || return 1
    if [ -n "$FOUND_ROW" ]; then
        local existing etarget ehash euid egid emode elabel eextra
        existing=$FOUND_ROW
        IFS='|' read -r etarget ehash euid egid emode elabel eextra <<EOF
$existing
EOF
        [ "$etarget" = "$target" ] && [ -z "$eextra" ] &&
            [ "$hash" = "$ehash" ] && [ "$meta" = "$euid|$egid|$emode" ] && [ "$label" = "$elabel" ] &&
            [ -f "$origin" ] && [ ! -L "$origin" ] && [ "$(digest "$origin")" = "$ehash" ]
        return $?
    fi
    IFS='|' read -r uid gid mode <<EOF
$meta
EOF
    case "$uid:$gid:$mode" in *[!0-9:]*|:*|*:) return 1;; esac
    case "$label" in ''|*[!A-Za-z0-9_:.,+-]*) return 1;; esac
    mkdir -p "${origin%/*}" || return 1
    plain "$origin" || return 1
    cp "$STOCK_PATH" "$origin" || return 1
    [ "$(digest "$origin")" = "$hash" ] || return 1
    echo "$target|$hash|$uid|$gid|$mode|$label" >> "$ROOT$WORK/stock-origins/index.tsv"
}
match_meta() {
    local meta uid gid mode
    if [ "$#" -gt 2 ]; then meta=$3; else meta=$(metadata "$1") || return 1; fi
    IFS='|' read -r uid gid mode <<EOF
$meta
EOF
    case "$uid:$gid:$mode" in *[!0-9:]*|:*|*:) return 1;; esac
    "$HELPER" setmeta "$2" "$uid" "$gid" "$mode" && [ "$(metadata "$2")" = "$meta" ]
}
row() {
    local feature=$1 source=$2 target=$3 kind=${4:-static} hash meta
    hash=$(digest "$ROOT$source") || return 1
    meta=$(metadata "$ROOT$target") || return 1
    if [ "$kind" = static ]; then
        capture_origin "$target" || return 1
        if [ "$ORIGIN_MODE" = on ]; then
            load_stock_origin "$target" || return 1
            digest "$STOCK_PATH" > "$ROOT$source.stock" || return 1
        else digest "$ROOT$target" > "$ROOT$source.stock" || return 1; fi
    fi
    echo "$feature|$source|$target|$hash|$meta|$kind" >> "$MANIFEST"
}
patch() {
    local feature=$1 target=$2 source=$WORK/files/$1.odex original_hash base
    if ! plain "$ROOT$target" || [ ! -f "$ROOT$target" ]; then status "$feature" skipped missing-stock; return 0; fi
    base=$ROOT$target
    if [ "$ORIGIN_MODE" = on ]; then load_stock_origin "$target" || fail 'cannot validate stock origin'; [ "$STOCK_KIND" = file ] || fail 'structural target has no stock file origin'; base=$STOCK_PATH; fi
    original_hash=$(digest "$base") || fail 'cannot identify stock'
    if "$HELPER" "$feature" "$base" "$ROOT$source"; then
        plain "$ROOT$source" && [ -f "$ROOT$source" ] && [ "$(digest "$base")" = "$original_hash" ] || fail 'stock changed or unsafe patch output'
        if [ "$ORIGIN_MODE" = on ]; then
            match_meta "$base" "$ROOT$source" "$STOCK_META" || fail 'patch metadata/manifest failure'
        else
            match_meta "$base" "$ROOT$source" || fail 'patch metadata/manifest failure'
        fi
        row "$feature" "$source" "$target" || fail 'patch metadata/manifest failure'
        status "$feature" prepared structural
    else
        [ ! -e "$ROOT$source" ] || fail 'patch tool left a partial output'
        status "$feature" skipped unsupported-structure
    fi
}
inventory() (
    local path=$1 file name hash meta
    for file in "$path"/* "$path"/.[!.]* "$path"/..?*; do
        [ -e "$file" ] || { [ ! -L "$file" ] || exit 1; continue; }
        name=${file##*/}
        case "$name" in .*) exit 1;; *.xml) :;; *) exit 1;; esac
        safe "$name" && plain "$file" && [ -f "$file" ] || exit 1
        hash=$(digest "$file") && meta=$(metadata "$file") || exit 1
        echo "$name|$hash|$meta" || exit 1
    done
)
stock_inventory() (
    local target=$1 file name
    for file in "$ROOT$target"/*.xml; do
        [ -f "$file" ] || continue
        name=${file##*/}; safe "$name" || exit 1
        load_stock_origin "$target/$name" || exit 1
        [ "$STOCK_KIND" = file ] || continue
        print -r -- "$name|$STOCK_HASH|$STOCK_META" || exit 1
    done
)
projection() {
    local dir=$ROOT/system/etc/permissions source=$WORK/files/permissions file name hash meta fx target
    if ! plain "$dir" || [ ! -d "$dir" ]; then status projection skipped missing-permissions; return; fi
    stock_inventory /system/etc/permissions > "$ROOT$source.stock-inventory" || { status projection skipped unsupported-permissions-tree; return; }
    [ -s "$ROOT$source.stock-inventory" ] || { status projection skipped empty-permissions-tree; return; }
    mkdir "$ROOT$source" || fail 'permissions staging failed'
    for file in "$dir"/*.xml; do
        [ -f "$file" ] || continue
        name=${file##*/}; target="/system/etc/permissions/$name"
        load_stock_origin "$target" || fail 'permissions original lookup failed'
        [ "$STOCK_KIND" = file ] || continue
        capture_origin "$target" || fail 'permissions original capture failed'
        cp -p "$STOCK_PATH" "$ROOT$source/$name" || fail 'permissions copy failed'
        match_meta "$STOCK_PATH" "$ROOT$source/$name" "$STOCK_META" || fail 'permissions metadata failed'
    done
    stock_inventory /system/etc/permissions > "$ROOT$WORK/stock-recheck" || fail 'stock permissions changed'
    [ "$(digest "$ROOT$WORK/stock-recheck")" = "$(digest "$ROOT$source.stock-inventory")" ] || fail 'stock permissions changed'
    inventory "$ROOT$source" > "$ROOT$WORK/copy-recheck" || fail 'permissions copy changed'
    [ "$(digest "$ROOT$WORK/copy-recheck")" = "$(digest "$ROOT$source.stock-inventory")" ] || fail 'permissions copy identity differs'
    for name in com.hkmc.software.connectivity.carplay_wireless.xml com.hkmc.software.connectivity.androidauto_wireless.xml com.hkmc.software.wifihotspot.xml; do
        if [ ! -e "$ROOT$source/$name" ]; then
            plain "$BASE/permissions/$name" && [ -f "$BASE/permissions/$name" ] || fail 'unsafe authored declaration'
            cp "$BASE/permissions/$name" "$ROOT$source/$name" && "$HELPER" setmeta "$ROOT$source/$name" 0 0 644 || fail 'feature declaration failed'
        fi
    done
    match_meta "$dir" "$ROOT$source" || fail 'permissions directory metadata failed'
    inventory "$ROOT$source" > "$ROOT$source.inventory" || fail 'permissions inventory failed'
    cat "$ROOT$source.inventory" "$ROOT$source.stock-inventory" > "$ROOT$WORK/permissions.digest" || fail 'permissions digest failed'
    hash=$(digest "$ROOT$WORK/permissions.digest") && meta=$(metadata "$dir") || fail 'permissions identity failed'
    # The stock PhoneProjection application owns its persistent UI selection.
    # This candidate never writes persist.ium.support.
    echo "projection|$source|/system/etc/permissions|$hash|$meta|directory" >> "$MANIFEST" || fail 'manifest failed'
    fx=${PORTABLE_TEST_FEATUREXML:-}
    [ -n "$fx" ] || fx=$(getprop ro.mobis.targetdir 2>/dev/null)/featurexml.cfg
    if [ "$fx" = /featurexml.cfg ] || [ ! -f "$ROOT$fx" ]; then fx=/system/etc/featurexml.cfg; fi
    if plain "$ROOT$fx" && [ -f "$ROOT$fx" ]; then
        case "$fx" in
        /system/onebin/*/featurexml.cfg) target=${fx#/system/onebin/}; target=${target%/featurexml.cfg};;
        /system/featurexml/*/featurexml.cfg) target=${fx#/system/featurexml/}; target=${target%/featurexml.cfg};;
        /system/*/featurexml.cfg) target=${fx#/system/}; target=${target%/featurexml.cfg};;
        *) fail 'featurexml outside reviewed locations';;
        esac
        case "$target" in ''|*[!a-zA-Z0-9_-]*) fail 'unsupported featurexml region';; esac
        source=$WORK/files/featurexml.cfg
        load_stock_origin "$fx" || fail 'featurexml original lookup failed'
        [ "$STOCK_KIND" = file ] || fail 'featurexml original is absent'
        fx_stock=$STOCK_PATH
        while IFS= read -r file || [ -n "$file" ]; do
            case "$file" in \#*) literal "$file";; *carplay_wireless.xml*|*androidauto_wireless.xml*|*wifihotspot.xml*) literal "#$file";; *) literal "$file";; esac
        done < "$fx_stock" > "$ROOT$source" || fail 'featurexml staging failed'
        match_meta "$fx_stock" "$ROOT$source" "$STOCK_META" && row projection "$source" "$fx" || fail 'featurexml metadata failed'
    fi
    status projection prepared configuration-only
}
audio() (
    local suffix tool target=/system/lib/libCarPlayAudio.so source=$WORK/files/libCarPlayAudio.so
    plain "$ROOT$target" && [ -f "$ROOT$target" ] || { status audio skipped missing-stock; exit 0; }
    local base=$ROOT$target
    if [ "$ORIGIN_MODE" = on ]; then load_stock_origin "$target" || fail 'cannot validate audio origin'; [ "$STOCK_KIND" = file ] || fail 'audio target has no stock file origin'; base=$STOCK_PATH; fi
    # The regional helper checks loader/constant/patch regions and decoder ABI
    # regions. Unrelated target code and nonloaded metadata need not match a
    # model-specific whole-file digest. Legacy profiles remain independent.
    tool=$BASE/bin/audio-region-patch
    if plain "$tool" && [ -x "$tool" ] && "$tool" original "$base"; then
        compatible=1
        for pair in 'libCarPlayCore.so core' 'libCarPlayUtils.so utils' 'libopus.so opus'; do
            set -- $pair
            plain "$ROOT/system/lib/$1" && [ -f "$ROOT/system/lib/$1" ] &&
                "$tool" verify "$ROOT/system/lib/$1" "$2" || compatible=0
        done
        if [ "$compatible" = 1 ]; then
            "$tool" apply "$base" "$ROOT$source" && {
                if [ "$ORIGIN_MODE" = on ]; then match_meta "$base" "$ROOT$source" "$STOCK_META"; else match_meta "$base" "$ROOT$source"; fi
            } && row audio "$source" "$target" || fail 'regional audio staging failed'
            status audio prepared reviewed-native-regions
            exit 0
        fi
    fi
    for suffix in '' -v035; do
        tool=$BASE/bin/audio-patch$suffix
        plain "$tool" && plain "$BASE/audio/recipe$suffix.sh" && [ -x "$tool" ] && [ -f "$BASE/audio/recipe$suffix.sh" ] || continue
        for dependency in libCarPlayCore.so libCarPlayUtils.so libopus.so; do
            plain "$ROOT/system/lib/$dependency" && [ -f "$ROOT/system/lib/$dependency" ] || { status audio skipped missing-or-unsafe-dependency; exit 0; }
        done
        "$tool" original "$base" || continue
        # These are authored, fixed bundle resources, never vehicle/import data.
        . "$BASE/audio/recipe$suffix.sh"
        "$tool" verify "$ROOT/system/lib/libCarPlayCore.so" "$AUDIO_CORE_SHA" &&
        "$tool" verify "$ROOT/system/lib/libCarPlayUtils.so" "$AUDIO_UTILS_SHA" &&
        "$tool" verify "$ROOT/system/lib/libopus.so" "$AUDIO_OPUS_SHA" || continue
        "$tool" apply "$base" "$ROOT$source" && {
            if [ "$ORIGIN_MODE" = on ]; then match_meta "$base" "$ROOT$source" "$STOCK_META"; else match_meta "$base" "$ROOT$source"; fi
        } && row audio "$source" "$target" || fail 'audio staging failed'
        status audio prepared exact-native-abi
        exit 0
    done
    status audio skipped unsupported-native-abi
)
add_wrapper_property() {
    local key=$1 value=$2 target=/system/build.prop source=$WORK/files/build.prop temp=$WORK/files/build.prop.next
    local line artifact
    [ ${#key} -le 31 ] && [ ${#value} -le 91 ] || fail 'persistent wrapper property exceeds KitKat limits'
    for artifact in wrap-common.sh dalvik/engine.jar dalvik/adapter.jar dalvik/libgen5whook.so; do
        plain "$BASE/$artifact" && [ -f "$BASE/$artifact" ] || fail "persistent wrapper artifact missing: $artifact"
    done
    case "$key" in
        wrap.com.daudio.app.dipo) artifact=wrap-dipo.sh;;
        wrap.com.google.android.project) artifact=wrap-gpm.sh;;
        *) fail 'unsupported persistent wrapper key';;
    esac
    plain "$BASE/$artifact" && [ -f "$BASE/$artifact" ] || fail "persistent wrapper artifact missing: $artifact"
    plain "$ROOT$target" && [ -f "$ROOT$target" ] || fail 'persistent wrappers require a regular system build.prop'
    capture_origin "$target" || fail 'cannot capture immutable build.prop origin'
    load_stock_origin "$target" && [ "$STOCK_KIND" = file ] || fail 'persistent wrappers require a file origin'
    if [ ! -f "$ROOT$source" ]; then
        plain "$ROOT$source" && [ ! -e "$ROOT$source" ] && [ ! -L "$ROOT$source" ] || fail 'unsafe staged build.prop path'
        cp -p "$STOCK_PATH" "$ROOT$source" || fail 'cannot stage build.prop'
    fi
    plain "$ROOT$source" && [ -f "$ROOT$source" ] && [ ! -L "$ROOT$source" ] || fail 'unsafe staged build.prop'
    plain "$ROOT$temp" && [ ! -e "$ROOT$temp" ] && [ ! -L "$ROOT$temp" ] || fail 'unsafe build.prop temporary path'
    : > "$ROOT$temp" || fail 'cannot stage wrapper property update'
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "$key="*)
                [ "${line#*=}" = "$value" ] || fail "foreign $key property retained"
                ;;
            *) print -r -- "$line" >> "$ROOT$temp" || fail 'build.prop copy failed';;
        esac
    done < "$ROOT$source"
    print -r -- "$key=$value" >> "$ROOT$temp" || fail 'wrapper property write failed'
    mv "$ROOT$temp" "$ROOT$source" || fail 'wrapper property publish failed'
    match_meta "$ROOT$target" "$ROOT$source" "$STOCK_META" || fail 'build.prop metadata mismatch'
}
# Pre-zygote boot guard: one background line in the stock qb_runtime.sh, which
# V039 init runs as root at post-fs-data (service qb_uid_check). Init does not
# wait for it. The stock script must be recognized exactly; otherwise skip.
BOOTGUARD_LINE='[ "$1" != check_fixed_uid ] || [ ! -f /data/local/gen5w-portable/persistent/bootguard/guard.sh ] || ( trap "" HUP; exec /system/bin/sh /data/local/gen5w-portable/persistent/bootguard/guard.sh ) </dev/null >/dev/null 2>&1 &'
add_boot_guard() {
    local target=/system/etc/qb_runtime.sh source=$WORK/files/qb_runtime.sh line first=1 shebang=0 dispatch=0
    plain "$ROOT$target" && [ -f "$ROOT$target" ] || { status bootguard skipped missing-stock; return 0; }
    capture_origin "$target" || fail 'cannot capture immutable qb_runtime.sh origin'
    load_stock_origin "$target" && [ "$STOCK_KIND" = file ] || fail 'boot guard requires a file origin'
    plain "$ROOT$source" && [ ! -e "$ROOT$source" ] && [ ! -L "$ROOT$source" ] || fail 'unsafe staged qb_runtime.sh path'
    : > "$ROOT$source" || fail 'cannot stage qb_runtime.sh'
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in *gen5w-portable*) fail 'qb_runtime.sh origin already carries a portable hook';; esac
        case "$line" in *'"check_fixed_uid" ]'*) dispatch=1;; esac
        if [ "$first" = 1 ]; then
            first=0
            [ "$line" = '#!/system/bin/sh' ] || break
            shebang=1
        fi
    done < "$STOCK_PATH"
    if [ "$shebang" != 1 ] || [ "$dispatch" != 1 ]; then
        rm -f "$ROOT$source"
        status bootguard skipped unrecognized-qb-runtime
        return 0
    fi
    # Copy the remainder as bytes, including an unterminated final stock line.
    {
        IFS= read -r line
        print -r -- "$line"
        print -r -- "$BOOTGUARD_LINE"
        cat
    } < "$STOCK_PATH" > "$ROOT$source" || fail 'boot guard staging copy failed'
    match_meta "$STOCK_PATH" "$ROOT$source" "$STOCK_META" && row bootguard "$source" "$target" || fail 'boot guard staging failed'
    status bootguard prepared prezygote-qb-runtime
}
for feature in "$@"; do
    case "$feature" in
    bt|route) patch "$feature" /system/app/Iap2ServerApp.odex;;
    dipo) patch dipo /system/app/HKMC_DiPO.odex;;
    gpm) patch gpm /system/app/HKMC_GPM.odex;;
    hotspot) patch hotspot /system/app/HKMC_WifiSettings.odex;;
    projection) projection;;
    audio) audio || fail 'audio preparation failed';;
    esac
done
if [ "$ORIGIN_MODE" = on ]; then
    wrapper_properties=0
    if has_feature dipo; then
        add_wrapper_property wrap.com.daudio.app.dipo '/system/bin/sh /data/nemesis/apps/gen5w.kr.portable/wrap-dipo.sh'
        wrapper_properties=1
    fi
    if has_feature gpm; then
        add_wrapper_property wrap.com.google.android.project '/system/bin/sh /data/nemesis/apps/gen5w.kr.portable/wrap-gpm.sh'
        wrapper_properties=1
    fi
    [ "$wrapper_properties" = 0 ] || row runtime "$WORK/files/build.prop" /system/build.prop || fail 'wrapper property manifest failure'
    [ "$wrapper_properties" = 0 ] || add_boot_guard
fi
echo 'carplay-relay|not-active|requires-explicit-runtime-hooks' >> "$REPORT"
sync
cat "$REPORT"
[ -s "$MANIFEST" ] || exit 77
echo "prepare: ready manifest=$WORK/manifest; no mounts or services changed"
