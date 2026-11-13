#!/system/bin/sh
# Match-mode admission and a fail-closed AP restart guard; never starts Wi-Fi.
# classify/rearm: explicit, evidence-preserving release of unfinished-start records.
umask 077
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
ROOT=${PORTABLE_TEST_ROOT:-}
ADAPTER=${PORTABLE_TEST_AP_ADAPTER:-}
HELPER=${PORTABLE_HELPER:-$BASE/bin/dex-patch}
STATE=$ROOT/data/local/gen5w-portable/ap
NEM=$ROOT/data/nemesis
MATCH=$NEM/gen5wkr.ap-match
GUARD=$NEM/gen5wkr.apguard
HOST=$ROOT/data/data/kr.gen5w.wirelesshost/files
SWITCH=$NEM/gen5wkr.apguard.off
ENABLED=$ROOT/data/local/gen5w-portable/boot/enabled
ARCHIVE=$STATE/archive
LOCK=$STATE/rearm.lock
PANIC_DIR=$ROOT/storage/log
DROPBOX=$ROOT/data/system/dropbox
# Evidence bounds: refuse instead of scanning or hashing without limit.
RECORD_MAX=256
PANIC_MAX=8388608
PANIC_COUNT_MAX=16
fail() { echo "ap: $*" >&2; exit 1; }
plain() {
    case "$1" in /*) :;; *) return 1;; esac
    case "$1" in *[!a-zA-Z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac
    local part=$1
    while [ "$part" != / ]; do [ ! -L "$part" ] || return 1; part=${part%/*}; [ -n "$part" ] || part=/; done
}
if [ -n "$ROOT" ]; then
    plain "$ROOT" && [ "$ROOT" != / ] && [ -d "$ROOT" ] || fail fixture
else
    [ -z "$ADAPTER" ] || fail fixture
    case "$(id)" in uid=0\(*) :;; *) fail 'real root required';; esac
fi
plain "$HELPER" && [ -x "$HELPER" ] && plain "$STATE" && plain "$NEM" && plain "$GUARD" || fail 'unsafe path'
mkdir -p "$STATE" && chmod 700 "$STATE" || fail state
for file in "$STATE/match-owner" "$STATE/match-owner.new" "$MATCH" "$GUARD/attempt" "$GUARD/ok" "$SWITCH"; do
    plain "$file" && { [ ! -e "$file" ] || [ -f "$file" ]; } || fail 'unsafe marker'
done
# Android boundaries. Fixtures must supply an adapter; it is never optional.
op() {
    if [ -n "$ROOT" ]; then
        [ -n "$ADAPTER" ] && [ -x "$ADAPTER" ] || return 1
        "$ADAPTER" "$@"; return $?
    fi
    case "$1" in
    wifi-ap-on) "$HELPER" supervise 8 /system/bin/true /system/bin/settings get global wifi_ap_on;;
    boot) cat /proc/sys/kernel/random/boot_id;;
    sync) "$HELPER" supervise 30 /system/bin/true /system/bin/sync;;
    *) return 1;;
    esac
}
put_owner() { print -r -- "$1" > "$STATE/match-owner.new" && mv "$STATE/match-owner.new" "$STATE/match-owner"; }
check_guard() {
    local marker
    for marker in "$GUARD/attempt" "$HOST/ap-attempt" "$SWITCH"; do
        plain "$marker" && { [ ! -e "$marker" ] || [ -f "$marker" ]; } || return 1
        if [ -e "$marker" ]; then
            # Any unfinished AP start observed before this session is unsafe.
            # Even a repeated QuickBoot boot_id must not hide that evidence.
            echo 'ap: previous AP start unfinished or restart guard off; wireless withheld' >&2
            return 77
        fi
    done
}
boot_id() { # print a validated boot id
    case "$1" in ''|*[!0-9a-f-]*) return 1;; esac
    [ "${#1}" -ge 8 ] && [ "${#1}" -le 64 ] && print -r -- "$1"
}
file_size() { # toolbox and GNU ls -l place the size in field 4 or 5
    local line size
    line=$(ls -ln "$1" 2>/dev/null) || line=$(ls -l "$1" 2>/dev/null) || return 1
    set -- $line
    size=${5:-}
    case "$size" in ''|*[!0-9]*) size=${4:-};; esac
    case "$size" in ''|*[!0-9]*) return 1;; esac
    print -r -- "$size"
}
evidence_file() { # regular, unlinked, plainly named, within the size bound
    local name=${1##*/}
    case "$name" in ''|.|..|-*|*[!A-Za-z0-9_.:@+,=-]*) return 1;; esac
    plain "${1%/*}" && [ -f "$1" ] && [ ! -L "$1" ] || return 1
    SIZE=$(file_size "$1") && [ "$SIZE" -le "$2" ] && SHA=$("$HELPER" sha256 "$1") && [ -n "$SHA" ]
}
owner_active() { # same owners as session.sh busy; unreadable state counts as active
    local process
    if [ -e "$ROOT/proc/net/unix" ] || [ -z "$ROOT" ]; then
        [ -r "$ROOT/proc/net/unix" ] || return 0
        grep -q 'gen5wkr.ap.broker.v1' "$ROOT/proc/net/unix" 2>/dev/null && return 0
    fi
    for process in "$ROOT"/proc/[0-9]*/cmdline; do
        [ -f "$process" ] || continue
        if grep -aq '^kr.gen5w.core' "$process" 2>/dev/null || grep -aq '^kr.gen5w.wirelesshost' "$process" 2>/dev/null; then return 0; fi
    done
    return 1
}
# RECORD_LIST holds space-separated "path|archive-name|sha" words (plain paths only).
split_entry() { record=${1%%\|*}; sha=${1##*\|}; name=${1#*\|}; name=${name%\|*}; } # mksh: escape |
# Writes the exact reviewed evidence inventory to $INVENTORY and sets RECORDS,
# PANICS, CLASS, TOKEN and RECORD_LIST (see split_entry). Returns 1 on
# unsafe or unsupported evidence. Panic dumps are hashed and listed, never moved.
inventory() {
    local current record name content valid when panic count=0 newer=0 entry
    RECORDS=0; PANICS=0; RECORD_LIST=; CLASS=clear
    current=$(boot_id "$(op boot)") || { echo 'ap: current boot id unavailable' >&2; return 1; }
    : > "$INVENTORY" || return 1
    print -r -- "ap|current-boot|$current" >> "$INVENTORY"
    for entry in "$GUARD/attempt:guard-attempt" "$HOST/ap-attempt:host-ap-attempt"; do
        record=${entry%:*}; name=${entry##*:}
        plain "$record" || { echo "ap: unsafe record path ${record#$ROOT}" >&2; return 1; }
        [ -e "$record" ] || [ -L "$record" ] || continue
        evidence_file "$record" "$RECORD_MAX" || { echo "ap: unsupported record ${record#$ROOT} (linked, not regular or over $RECORD_MAX bytes)" >&2; return 1; }
        content=; IFS= read -r content < "$record" || : # no trailing newline still yields the line
        valid=$(boot_id "$content") || valid=invalid
        if [ "$valid" = "$current" ]; then when=same-boot; else when=earlier-boot; fi
        print -r -- "ap|record|${record#$ROOT}|$SHA|$SIZE|boot=$valid|$when" >> "$INVENTORY"
        RECORD_LIST="$RECORD_LIST $record|$name|$SHA"
        RECORDS=$((RECORDS + 1))
    done
    if [ -e "$SWITCH" ]; then print -r -- "ap|switch|${SWITCH#$ROOT}|present" >> "$INVENTORY"; fi
    for panic in "$PANIC_DIR"/* "$DROPBOX"/SYSTEM_LAST_KMSG@* "$DROPBOX"/*[Pp][Aa][Nn][Ii][Cc]*; do
        [ -e "$panic" ] || [ -L "$panic" ] || continue
        count=$((count + 1))
        [ "$count" -le "$PANIC_COUNT_MAX" ] || { echo "ap: more than $PANIC_COUNT_MAX panic/log entries; review and preserve them manually" >&2; return 1; }
        evidence_file "$panic" "$PANIC_MAX" || { echo "ap: unsupported panic entry ${panic#$ROOT} (linked, not regular, unusual name or over $PANIC_MAX bytes)" >&2; return 1; }
        when=older
        for entry in $RECORD_LIST; do
            [ ! "$panic" -nt "${entry%%\|*}" ] || when=newer
        done
        [ "$when" = older ] || newer=1
        print -r -- "ap|panic|${panic#$ROOT}|$SHA|$SIZE|mtime-$when-wall-clock-unreliable" >> "$INVENTORY"
        PANICS=$((PANICS + 1))
    done
    if [ "$PANICS" = 0 ]; then print -r -- 'ap|panic-scan|none-found|absence-is-not-proof' >> "$INVENTORY"
    else print -r -- "ap|panic-scan|$PANICS-found|review-each" >> "$INVENTORY"; fi
    # Live logs are named for the reviewer but never hashed (they keep changing).
    if [ -e "$ROOT/proc/last_kmsg" ]; then print -r -- 'ap|kmsg|/proc/last_kmsg|present|not-hashed-review-manually' >> "$INVENTORY"; fi
    if [ -e "$DROPBOX/logcat.txt" ]; then print -r -- 'ap|logcat|/data/system/dropbox/logcat.txt|present|not-hashed-review-manually' >> "$INVENTORY"; fi
    if [ "$RECORDS" -gt 0 ]; then
        if [ "$newer" = 1 ]; then CLASS=reset-evidence-newer; else CLASS=unfinished-start; fi
    elif [ -e "$SWITCH" ]; then CLASS=guard-off; fi
    TOKEN=$("$HELPER" sha256 "$INVENTORY") && [ -n "$TOKEN" ] || return 1
}
case "$1" in
prepare)
    [ "$#" = 1 ] || fail arguments
    # Initial staged admission: stock WifiService restores the AP at boot when
    # wifi_ap_on is set, bypassing every authored guard. Unknown is not "off".
    value=$(op wifi-ap-on) || fail 'wifi_ap_on unreadable (settings unavailable or timed out); confirm the AP is off, run: settings put global wifi_ap_on 0'
    case "$value" in
    0) :;;
    ''|null) fail "wifi_ap_on is unset/unknown ('$value'); confirm the AP is off, run: settings put global wifi_ap_on 0";;
    *[!a-z0-9]*) fail 'wifi_ap_on has an unsupported value; boot-time AP restore possible; withheld';;
    *) fail "wifi_ap_on=$value; stock boot would restore the AP outside the guard; withheld";;
    esac
    mkdir -p "$NEM" || fail parent
    if [ ! -e "$GUARD" ]; then
        mkdir "$GUARD" && chown 1000:1000 "$GUARD" && chmod 700 "$GUARD" || fail 'guard creation failed'
    fi
    [ -d "$GUARD" ] && [ "$("$HELPER" metadata "$GUARD")" = '1000|1000|700' ] || fail 'foreign guard ownership or permissions'
    if [ -e "$MATCH" ]; then
        [ "$(cat "$MATCH")" = match ] || fail 'foreign AP mode retained'
        [ -f "$STATE/match-owner" ] || put_owner foreign || fail ownership
    else
        # Refuse overwrite, including a concurrent existing marker.
        ( set -C; echo match > "$MATCH" ) || fail 'AP mode creation failed'
        chmod 644 "$MATCH" || fail mode
        owner=$("$HELPER" identity "$MATCH") && [ -n "$owner" ] && put_owner "$owner" || fail ownership
    fi
    echo 'ap: stock-service match mode and system-UID restart guard prepared'
    ;;
check) [ "$#" = 1 ] || fail arguments; check_guard;;
disable)
    [ "$#" = 1 ] || fail arguments
    [ -f "$STATE/match-owner" ] || exit 0
    IFS= read -r owner < "$STATE/match-owner" || fail ownership
    [ "$owner" != foreign ] || exit 0
    case "$owner" in ''|*[!0-9:]*|:*|*:|*:*:*) fail ownership;; esac
    if [ -e "$MATCH" ]; then
        [ "$("$HELPER" identity "$MATCH")" = "$owner" ] && [ "$(cat "$MATCH")" = match ] || fail 'foreign AP mode retained'
        rm "$MATCH" || fail restore
    fi
    rm "$STATE/match-owner" || fail ownership
    # Keep unfinished attempts as diagnostic/safety evidence; never erase them
    # merely because the package was disabled or uninstalled. See classify/rearm.
    ;;
status)
    result=0; check_guard || result=$?
    case "$result" in 0) echo 'ap|admitted';; 77) echo 'ap|blocked-unfinished-start';; *) exit 1;; esac
    ;;
classify)
    # Reads evidence only (a scratch inventory in our own state is removed).
    [ "$#" = 1 ] || fail arguments
    INVENTORY=$STATE/classify.$$
    plain "$INVENTORY" || fail 'unsafe path'
    trap 'rm -f "$INVENTORY"' EXIT
    inventory || fail 'evidence unsafe or unsupported; nothing classified'
    cat "$INVENTORY"
    echo "ap|ack|$TOKEN"
    echo "ap|class|$CLASS"
    echo 'ap|note|an absent or older log never proves that no kernel panic or reset happened'
    case "$CLASS" in
    clear) exit 0;;
    unfinished-start)
        if [ "$PANICS" = 0 ]; then echo "ap|next|after review: ap.sh rearm $TOKEN reviewed-no-reset"
        else echo "ap|next|after reviewing every panic entry: ap.sh rearm $TOKEN reviewed-panic-unrelated"; fi;;
    reset-evidence-newer) echo 'ap|next|withheld: panic evidence is newer than the attempt record; rearm refused';;
    guard-off) echo "ap|next|${SWITCH#$ROOT} is an explicit switch; rearm never removes it";;
    esac
    exit 77
    ;;
rearm)
    [ "$#" = 3 ] || fail 'usage: ap.sh rearm <ack-token> reviewed-no-reset|reviewed-panic-unrelated'
    token=$2; ack=$3
    case "$token" in *[!0-9a-f]*) fail 'malformed acknowledgement token';; esac
    [ "${#token}" = 64 ] || fail 'malformed acknowledgement token'
    case "$ack" in reviewed-no-reset|reviewed-panic-unrelated) :;; *) fail 'acknowledgement must be reviewed-no-reset or reviewed-panic-unrelated';; esac
    plain "$LOCK" && plain "$ARCHIVE" && plain "$ENABLED" || fail 'unsafe path'
    mkdir "$LOCK" 2>/dev/null || fail "rearm locked (${LOCK#$ROOT} exists; remove only if no rearm is running)"
    INVENTORY=$LOCK/inventory
    trap 'rm -f "$INVENTORY"; rmdir "$LOCK" 2>/dev/null' EXIT
    [ ! -e "$ENABLED" ] || { [ -f "$ENABLED" ] && [ "$(cat "$ENABLED")" != 1 ]; } || fail 'rearm refused: disable the automatic installation first (boot.sh disable)'
    owner_active && fail 'rearm refused: an AP/host/core owner is active'
    [ ! -e "$SWITCH" ] && [ ! -L "$SWITCH" ] || fail "rearm refused: ${SWITCH#$ROOT} present; it is an explicit switch and is never removed here"
    inventory || fail 'rearm refused: evidence unsafe or unsupported'
    [ "$RECORDS" -gt 0 ] || fail 'rearm refused: no unfinished-start record'
    [ "$CLASS" != reset-evidence-newer ] || fail 'rearm refused: panic evidence is newer than the attempt record'
    [ "$TOKEN" = "$token" ] || fail 'rearm refused: evidence changed since it was classified; run classify and review again'
    if [ "$PANICS" = 0 ]; then
        [ "$ack" = reviewed-no-reset ] || fail 'rearm refused: no panic entry was listed; acknowledgement must be reviewed-no-reset'
    else
        [ "$ack" = reviewed-panic-unrelated ] || fail 'rearm refused: panic entries are listed; acknowledgement must be reviewed-panic-unrelated'
    fi
    current=$(boot_id "$(op boot)") || fail 'rearm refused: boot id unavailable'
    if [ -e "$ARCHIVE" ] || [ -L "$ARCHIVE" ]; then
        [ -d "$ARCHIVE" ] && [ ! -L "$ARCHIVE" ] || fail 'rearm refused: archive is not a plain directory'
    else
        mkdir "$ARCHIVE" || fail 'rearm refused: archive creation failed'
    fi
    chmod 700 "$ARCHIVE" || fail 'rearm refused: archive mode'
    n=1; dir=
    while [ "$n" -le 99 ]; do
        if mkdir "$ARCHIVE/$current-$n" 2>/dev/null; then dir=$ARCHIVE/$current-$n; break; fi
        [ -e "$ARCHIVE/$current-$n" ] || fail 'rearm refused: archive not writable'
        n=$((n + 1))
    done
    [ -n "$dir" ] && plain "$dir" || fail 'rearm refused: no free archive slot'
    {
        echo 'format=gen5wkr-ap-rearm-v1'
        echo "token=$TOKEN"
        echo "ack=$ack"
        echo "uptime=$(cat "$ROOT/proc/uptime" 2>/dev/null || echo unknown)"
        cat "$INVENTORY"
    } > "$dir/MANIFEST.part" || fail 'rearm refused: manifest write failed'
    for entry in $RECORD_LIST; do
        split_entry "$entry"
        cat "$record" > "$dir/$name.part" && [ "$("$HELPER" sha256 "$dir/$name.part")" = "$sha" ] &&
            mv "$dir/$name.part" "$dir/$name" || fail "rearm refused: archive copy of ${record#$ROOT} failed; originals kept"
        echo "archived|${record#$ROOT}|$sha|$name" >> "$dir/MANIFEST.part" || fail 'rearm refused: manifest write failed'
    done
    mv "$dir/MANIFEST.part" "$dir/MANIFEST" || fail 'rearm refused: manifest seal failed'
    op sync || fail 'rearm refused: archive flush failed; originals kept'
    # Last look before release: same owners, same bytes.
    owner_active && fail 'rearm refused: an owner became active; originals kept (archive copy retained)'
    for entry in $RECORD_LIST; do
        split_entry "$entry"
        [ -f "$record" ] && [ ! -L "$record" ] && [ "$("$HELPER" sha256 "$record")" = "$sha" ] ||
            fail "rearm refused: ${record#$ROOT} changed during archiving; nothing released"
    done
    for entry in $RECORD_LIST; do
        split_entry "$entry"
        rm "$record" || fail "rearm incomplete: could not remove ${record#$ROOT} (archived copy in ${dir#$ROOT})"
    done
    op sync || fail "rearm incomplete: removal flush failed; records may reappear after reboot (still fail closed); archive ${dir#$ROOT}"
    echo "ap|rearmed|${dir#$ROOT}"
    ;;
*) fail 'usage: ap.sh prepare | check | disable | status | classify | rearm <ack-token> <ack>';;
esac
