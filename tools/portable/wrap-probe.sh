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
# Keep the original process and VM options; do not load any Java adapter.
unset GEN5W_ENGINE_JAR GEN5W_ADAPTER_JAR GEN5W_HOOK_LIBRARY
GEN5W_PROBE=1
LD_PRELOAD=$BASE/dalvik/libgen5whook.so
[ -f "$LD_PRELOAD" ] && [ ! -L "$LD_PRELOAD" ] || exit 1
export GEN5W_PROBE LD_PRELOAD GEN5W_PACKAGE
[ "$#" -gt 0 ] || exit 1
exec "$@"
