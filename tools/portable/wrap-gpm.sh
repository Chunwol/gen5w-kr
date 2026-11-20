#!/system/bin/sh
# Never fail the app start: any problem, or hooks switched off (marker written
# whenever automatic operation is disabled), runs the stock command unchanged.
BASE=${0%/*}
[ "$#" -gt 0 ] || exit 1
# Report this process to zygote at once. Zygote blocks every other app start until
# a wrapped child sends its pid, and WrapperInit only sends it after a full VM
# start (VM 2026-11-20: post-install boot stalled, stock reboot 5 min). exec
# keeps this pid, so it is already the app's pid; WrapperInit then gets fd 0 and
# skips its own late report. Any problem leaves the command unchanged.
gen5w_fd= gen5w_prev=
for gen5w_a do
    [ "$gen5w_prev" != com.android.internal.os.WrapperInit ] || { gen5w_fd=$gen5w_a; break; }
    gen5w_prev=$gen5w_a
done
case "$gen5w_fd" in ''|0|*[!0-9]*) :;; *)
    gen5w_bytes=
    for gen5w_s in 24 16 8 0; do
        gen5w_b=$(( ($$ >> gen5w_s) & 255 ))
        gen5w_bytes="$gen5w_bytes\0$(( (gen5w_b >> 6) & 7 ))$(( (gen5w_b >> 3) & 7 ))$(( gen5w_b & 7 ))"
    done
    if [ -p "/proc/$$/fd/$gen5w_fd" ] && print -n -- "$gen5w_bytes" 2>/dev/null > "/proc/$$/fd/$gen5w_fd"; then
        # Same arguments, with the reported pipe fd replaced by 0.
        gen5w_prev=
        for gen5w_a do
            shift
            if [ "$gen5w_prev" = com.android.internal.os.WrapperInit ]; then set -- "$@" 0; else set -- "$@" "$gen5w_a"; fi
            gen5w_prev=$gen5w_a
        done
    fi;;
esac
unset gen5w_fd gen5w_prev gen5w_a gen5w_bytes gen5w_s gen5w_b
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
GEN5W_PACKAGE=com.google.android.projection.sink
. "$BASE/wrap-common.sh"
