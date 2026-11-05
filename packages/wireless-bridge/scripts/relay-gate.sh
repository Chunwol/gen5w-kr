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
[ "$value" = gen5w.kr.bridge:v039-relay-1 ] || exit 1
for path in \
    "$PKG/app/bridge.dex" \
    "$PKG/app/wireless-host.apk" \
    "$PKG/bin/iap2-bt-patch-v039" \
    "$PKG/bin/dipo-patch-v039" \
    "$PKG/bin/relay-v039-structural-check"; do
    [ -f "$path" ] && [ ! -L "$path" ] || exit 1
done
[ -x "$PKG/bin/iap2-bt-patch-v039" ] && [ -x "$PKG/bin/dipo-patch-v039" ] &&
    [ -x "$PKG/bin/relay-v039-structural-check" ] || exit 1
"$PKG/bin/relay-v039-structural-check" "$PKG/app/bridge.dex" \
    "$PKG/bin/iap2-bt-patch-v039" "$PKG/bin/dipo-patch-v039" || exit 1
exit 0
