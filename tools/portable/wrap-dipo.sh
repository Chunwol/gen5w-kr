#!/system/bin/sh
BASE=${0%/*}
# Validate before sourcing the authored common wrapper.
case "$BASE" in /data/*) :;; *) exit 1;; esac
case "$BASE" in *[!a-zA-Z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) exit 1;; esac
path=$BASE/wrap-common.sh
[ -f "$path" ] || exit 1
while [ "$path" != / ]; do
    [ ! -L "$path" ] || exit 1
    path=${path%/*}; [ -n "$path" ] || path=/
done
GEN5W_PACKAGE=com.daudio.app.dipo
. "$BASE/wrap-common.sh"
