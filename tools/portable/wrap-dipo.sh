#!/system/bin/sh
# Never fail the app start: any problem, or hooks switched off (marker written
# whenever automatic operation is disabled), runs the stock command unchanged.
BASE=${0%/*}
[ "$#" -gt 0 ] || exit 1
[ ! -e /data/nemesis/gen5w-hooks-off ] || exec "$@"
# Validate before sourcing the authored common wrapper.
case "$BASE" in /data/*) :;; *) exec "$@";; esac
case "$BASE" in *[!a-zA-Z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) exec "$@";; esac
path=$BASE/wrap-common.sh
[ -f "$path" ] || exec "$@"
while [ "$path" != / ]; do
    [ ! -L "$path" ] || exec "$@"
    path=${path%/*}; [ -n "$path" ] || path=/
done
GEN5W_PACKAGE=com.daudio.app.dipo
. "$BASE/wrap-common.sh"
