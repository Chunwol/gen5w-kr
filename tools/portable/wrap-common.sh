#!/system/bin/sh
# Sourced only by the two authored app wrappers. No global preload or zygote hook.
# A failed check runs the stock command (no LD_PRELOAD, no engine) instead of exiting.
case "$GEN5W_PACKAGE" in com.daudio.app.dipo|com.google.android.projection.sink|com.mnsoft.navi) :;; *) exec "$@";; esac
case "$BASE" in /data/*) :;; *) exec "$@";; esac
case "$BASE" in *[!a-zA-Z0-9_./-]*|*/../*|*/./*|*//*) exec "$@";; esac
GEN5W_ENGINE_JAR=$BASE/dalvik/engine.jar
GEN5W_ADAPTER_JAR=$BASE/dalvik/adapter.jar
GEN5W_HOOK_LIBRARY=$BASE/dalvik/libgen5whook.so
# App-private optimized DEX for the engine (created by the app uid itself). The
# engine is never added to the bootclasspath: V039 dex cache deps record the
# exact bootclasspath and a mismatch rewrote shared caches under other apps.
GEN5W_ENGINE_CACHE=/data/data/$GEN5W_PACKAGE/app_gen5w-engine
for path in "$GEN5W_ENGINE_JAR" "$GEN5W_ADAPTER_JAR" "$GEN5W_HOOK_LIBRARY"; do
    [ -f "$path" ] || exec "$@"
    while [ "$path" != / ]; do
        [ ! -L "$path" ] || exec "$@"
        path=${path%/*}; [ -n "$path" ] || path=/
    done
done
export GEN5W_PACKAGE GEN5W_ENGINE_JAR GEN5W_ENGINE_CACHE GEN5W_ADAPTER_JAR GEN5W_HOOK_LIBRARY
LD_PRELOAD="$GEN5W_HOOK_LIBRARY${LD_PRELOAD:+:$LD_PRELOAD}"
export LD_PRELOAD
# This is the original app_process command supplied by WrapperInit.
[ "$#" -gt 0 ] || exit 1
exec "$@"
