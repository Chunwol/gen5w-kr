#!/system/bin/sh
# Return 77 when the optional V039 relay is not packaged, 0 when complete,
# and 1 when an attempted relay payload is incomplete or unsafe.
PKG=${1:-${0%/*}/..}
MARK=$PKG/app/relay-v039.complete
GATE_DIGEST=${GEN5W_TEST_DIGEST:-md5}

[ ! -L "$PKG" ] && [ -d "$PKG" ] || exit 1
[ ! -L "$PKG/app" ] && [ ! -L "$PKG/bin" ] || exit 1
if [ ! -e "$MARK" ] && [ ! -L "$MARK" ]; then
    for path in "$PKG/app/HKMC_DiPO.relay.lpd" "$PKG/app/HKMC_GPM.guard.lpd" "$PKG/app/relay-v039.md5"; do
        [ ! -e "$path" ] && [ ! -L "$path" ] || exit 1
    done
    exit 77
fi
[ -f "$MARK" ] && [ ! -L "$MARK" ] || exit 1
{
    IFS= read -r value || exit 1
    if IFS= read -r extra; then exit 1; fi
} < "$MARK"
[ "$value" = gen5w.kr.bridge:v039-relay-4 ] || exit 1
for path in \
    "$PKG/app/bridge.dex" \
    "$PKG/app/wireless-host.apk" \
    "$PKG/app/HKMC_DiPO.relay.lpd" \
    "$PKG/app/HKMC_GPM.guard.lpd" \
    "$PKG/app/relay-v039.md5" \
    "$PKG/bin/iap2-bt-patch-v039" \
    "$PKG/bin/dipo-patch-v039" \
    "$PKG/bin/gpm-patch-v039" \
    "$PKG/bin/lpatch"; do
    [ -f "$path" ] && [ ! -L "$path" ] || exit 1
done
gate_digest() {
    set -- $("$GATE_DIGEST" "$1" 2>/dev/null)
    echo "$1"
}
seen=
while read -r sum path extra; do
    [ -n "$sum" ] && [ -n "$path" ] && [ -z "$extra" ] || exit 1
    [ ${#sum} -eq 32 ] || exit 1
    case "$sum" in *[!0123456789abcdefABCDEF]*) exit 1;; esac
    case "$path" in
        app/bridge.dex|app/wireless-host.apk|app/HKMC_DiPO.relay.lpd|app/HKMC_GPM.guard.lpd|bin/iap2-bt-patch-v039|bin/dipo-patch-v039|bin/gpm-patch-v039|bin/lpatch) ;;
        *) exit 1;;
    esac
    case " $seen " in *" $path "*) exit 1;; esac
    seen="$seen $path"
    [ ! -L "$PKG/$path" ] && [ -f "$PKG/$path" ] || exit 1
    [ "$(gate_digest "$PKG/$path")" = "$sum" ] || exit 1
done < "$PKG/app/relay-v039.md5"
for path in app/bridge.dex app/wireless-host.apk app/HKMC_DiPO.relay.lpd app/HKMC_GPM.guard.lpd bin/iap2-bt-patch-v039 bin/dipo-patch-v039 bin/gpm-patch-v039 bin/lpatch; do
    case " $seen " in *" $path "*) ;; *) exit 1;; esac
done
exit 0
