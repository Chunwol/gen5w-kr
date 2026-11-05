#!/system/bin/sh
# Return 77 when the optional V039 relay is not packaged, 0 when complete,
# and 1 when an attempted relay payload is incomplete or unsafe.
PKG=${1:-${0%/*}/..}
MARK=$PKG/app/relay-v039.complete

[ ! -L "$PKG" ] && [ -d "$PKG" ] || exit 1
[ ! -L "$PKG/app" ] && [ ! -L "$PKG/bin" ] || exit 1
if [ ! -e "$MARK" ] && [ ! -L "$MARK" ]; then exit 77; fi
[ -f "$MARK" ] && [ ! -L "$MARK" ] || exit 1
{
    IFS= read -r value || exit 1
    if IFS= read -r extra; then exit 1; fi
} < "$MARK"
[ "$value" = gen5w.kr.bridge:v039-relay-2 ] || exit 1
for path in \
    "$PKG/app/bridge.dex" \
    "$PKG/app/wireless-host.apk" \
    "$PKG/app/HKMC_DiPO.relay.apk" \
    "$PKG/app/relay-v039.md5" \
    "$PKG/bin/iap2-bt-patch-v039" \
    "$PKG/bin/dipo-patch-v039"; do
    [ -f "$path" ] && [ ! -L "$path" ] || exit 1
done
gate_digest() {
    if command -v md5 >/dev/null 2>&1; then set -- $(md5 "$1" 2>/dev/null); echo "$1"
    elif command -v md5sum >/dev/null 2>&1; then set -- $(md5sum "$1" 2>/dev/null); echo "$1"
    else return 1; fi
}
while read -r sum path extra; do
    [ -n "$sum" ] && [ -n "$path" ] && [ -z "$extra" ] || exit 1
    [ ! -L "$PKG/$path" ] && [ -f "$PKG/$path" ] || exit 1
    [ "$(gate_digest "$PKG/$path")" = "$sum" ] || exit 1
done < "$PKG/app/relay-v039.md5"
exit 0
