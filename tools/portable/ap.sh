#!/system/bin/sh
# Match-mode admission and a fail-closed AP restart guard; never starts Wi-Fi.
umask 077
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
ROOT=${PORTABLE_TEST_ROOT:-}
HELPER=${PORTABLE_HELPER:-$BASE/bin/dex-patch}
STATE=$ROOT/data/local/gen5w-portable/ap
NEM=$ROOT/data/nemesis
MATCH=$NEM/gen5wkr.ap-match
GUARD=$NEM/gen5wkr.apguard
HOST=$ROOT/data/data/kr.gen5w.wirelesshost/files
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
    case "$(id)" in uid=0\(*) :;; *) fail 'real root required';; esac
fi
plain "$HELPER" && [ -x "$HELPER" ] && plain "$STATE" && plain "$NEM" && plain "$GUARD" || fail 'unsafe path'
mkdir -p "$STATE" && chmod 700 "$STATE" || fail state
for file in "$STATE/match-owner" "$STATE/match-owner.new" "$MATCH" "$GUARD/attempt" "$GUARD/ok" "$NEM/gen5wkr.apguard.off"; do
    plain "$file" && { [ ! -e "$file" ] || [ -f "$file" ]; } || fail 'unsafe marker'
done
put_owner() { print -r -- "$1" > "$STATE/match-owner.new" && mv "$STATE/match-owner.new" "$STATE/match-owner"; }
check_guard() {
    local marker
    for marker in "$GUARD/attempt" "$HOST/ap-attempt" "$NEM/gen5wkr.apguard.off"; do
        plain "$marker" && { [ ! -e "$marker" ] || [ -f "$marker" ]; } || return 1
        if [ -e "$marker" ]; then
            # Any unfinished AP start observed before this session is unsafe.
            # Even a repeated QuickBoot boot_id must not hide that evidence.
            echo 'ap: previous AP start unfinished or restart guard off; wireless withheld' >&2
            return 77
        fi
    done
}
case "$1" in
prepare)
    [ "$#" = 1 ] || fail arguments
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
    # merely because the package was disabled or uninstalled.
    ;;
status)
    result=0; check_guard || result=$?
    case "$result" in 0) echo 'ap|admitted';; 77) echo 'ap|blocked-unfinished-start';; *) exit 1;; esac
    ;;
*) fail 'usage: ap.sh prepare | check | disable | status';;
esac
