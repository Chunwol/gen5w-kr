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
case "$1" in /data/*) WORK=$1;; *) fail 'usage: prepare.sh /data/NEW-DIRECTORY [route|bt|dipo|gpm|hotspot|audio|projection ...]';; esac
shift
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
REPORT=$ROOT$WORK/features.txt
MANIFEST=$ROOT$WORK/manifest
: > "$REPORT"; : > "$MANIFEST"
status() { echo "$1|$2|$3" >> "$REPORT" || fail 'cannot record feature result'; }
digest() { "$HELPER" sha256 "$1"; }
metadata() { "$HELPER" metadata "$1"; }
match_meta() {
    local meta uid gid mode
    meta=$(metadata "$1") || return 1
    IFS='|' read -r uid gid mode <<EOF
$meta
EOF
    case "$uid:$gid:$mode" in *[!0-9:]*|:*|*:) return 1;; esac
    chown "$uid:$gid" "$2" && chmod "$mode" "$2" && [ "$(metadata "$2")" = "$meta" ]
}
row() {
    local feature=$1 source=$2 target=$3 kind=${4:-static} hash meta
    hash=$(digest "$ROOT$source") || return 1
    meta=$(metadata "$ROOT$target") || return 1
    if [ "$kind" = static ]; then
        digest "$ROOT$target" > "$ROOT$source.stock" || return 1
    fi
    echo "$feature|$source|$target|$hash|$meta|$kind" >> "$MANIFEST"
}
patch() {
    local feature=$1 target=$2 source=$WORK/files/$1.odex original_hash
    if ! plain "$ROOT$target" || [ ! -f "$ROOT$target" ]; then status "$feature" skipped missing-stock; return 0; fi
    original_hash=$(digest "$ROOT$target") || fail 'cannot identify stock'
    if "$HELPER" "$feature" "$ROOT$target" "$ROOT$source"; then
        plain "$ROOT$source" && [ -f "$ROOT$source" ] && [ "$(digest "$ROOT$target")" = "$original_hash" ] || fail 'stock changed or unsafe patch output'
        match_meta "$ROOT$target" "$ROOT$source" && row "$feature" "$source" "$target" || fail 'patch metadata/manifest failure'
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
projection() {
    local dir=$ROOT/system/etc/permissions source=$WORK/files/permissions file name hash meta fx target
    if ! plain "$dir" || [ ! -d "$dir" ]; then status projection skipped missing-permissions; return; fi
    inventory "$dir" > "$ROOT$source.stock-inventory" || { status projection skipped unsupported-permissions-tree; return; }
    [ -s "$ROOT$source.stock-inventory" ] || { status projection skipped empty-permissions-tree; return; }
    mkdir "$ROOT$source" || fail 'permissions staging failed'
    for file in "$dir"/*.xml; do
        name=${file##*/}; cp -p "$file" "$ROOT$source/$name" || fail 'permissions copy failed'
        match_meta "$file" "$ROOT$source/$name" || fail 'permissions metadata failed'
    done
    inventory "$dir" > "$ROOT$WORK/stock-recheck" || fail 'stock permissions changed'
    [ "$(digest "$ROOT$WORK/stock-recheck")" = "$(digest "$ROOT$source.stock-inventory")" ] || fail 'stock permissions changed'
    inventory "$ROOT$source" > "$ROOT$WORK/copy-recheck" || fail 'permissions copy changed'
    [ "$(digest "$ROOT$WORK/copy-recheck")" = "$(digest "$ROOT$source.stock-inventory")" ] || fail 'permissions copy identity differs'
    for name in com.hkmc.software.connectivity.carplay_wireless.xml com.hkmc.software.connectivity.androidauto_wireless.xml com.hkmc.software.wifihotspot.xml; do
        if [ ! -e "$ROOT$source/$name" ]; then
            plain "$BASE/permissions/$name" && [ -f "$BASE/permissions/$name" ] || fail 'unsafe authored declaration'
            cp "$BASE/permissions/$name" "$ROOT$source/$name" && chown 0:0 "$ROOT$source/$name" && chmod 644 "$ROOT$source/$name" || fail 'feature declaration failed'
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
        while IFS= read -r file || [ -n "$file" ]; do
            case "$file" in \#*) literal "$file";; *carplay_wireless.xml*|*androidauto_wireless.xml*|*wifihotspot.xml*) literal "#$file";; *) literal "$file";; esac
        done < "$ROOT$fx" > "$ROOT$source" || fail 'featurexml staging failed'
        match_meta "$ROOT$fx" "$ROOT$source" && row projection "$source" "$fx" || fail 'featurexml metadata failed'
    fi
    status projection prepared configuration-only
}
audio() (
    local suffix tool target=/system/lib/libCarPlayAudio.so source=$WORK/files/libCarPlayAudio.so
    plain "$ROOT$target" && [ -f "$ROOT$target" ] || { status audio skipped missing-stock; exit 0; }
    for suffix in '' -v035; do
        tool=$BASE/bin/audio-patch$suffix
        plain "$tool" && plain "$BASE/audio/recipe$suffix.sh" && [ -x "$tool" ] && [ -f "$BASE/audio/recipe$suffix.sh" ] || continue
        for dependency in libCarPlayCore.so libCarPlayUtils.so libopus.so; do
            plain "$ROOT/system/lib/$dependency" && [ -f "$ROOT/system/lib/$dependency" ] || { status audio skipped missing-or-unsafe-dependency; exit 0; }
        done
        "$tool" original "$ROOT$target" || continue
        # These are authored, fixed bundle resources, never vehicle/import data.
        . "$BASE/audio/recipe$suffix.sh"
        "$tool" verify "$ROOT/system/lib/libCarPlayCore.so" "$AUDIO_CORE_SHA" &&
        "$tool" verify "$ROOT/system/lib/libCarPlayUtils.so" "$AUDIO_UTILS_SHA" &&
        "$tool" verify "$ROOT/system/lib/libopus.so" "$AUDIO_OPUS_SHA" || continue
        "$tool" apply "$ROOT$target" "$ROOT$source" && match_meta "$ROOT$target" "$ROOT$source" && row audio "$source" "$target" || fail 'audio staging failed'
        status audio prepared exact-native-abi
        exit 0
    done
    status audio skipped unsupported-native-abi
)
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
echo 'carplay-relay|not-active|requires-explicit-runtime-hooks' >> "$REPORT"
sync
cat "$REPORT"
[ -s "$MANIFEST" ] || exit 77
echo "prepare: ready manifest=$WORK/manifest; no mounts or services changed"
