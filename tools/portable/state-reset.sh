#!/system/bin/sh
# Retire the inactive state of earlier portable generations before an install.
#
# Earlier generations (overlay binds, runtime properties, per-boot attempts,
# sessions, plans) each kept their own state machine under one root. Each
# later step refused unexpected residue, so every failed install left new
# residue that blocked the next one (vehicle 2026-11-19). This is now the one
# place that judges that residue. Nothing is deleted: inactive entries are
# moved under retired/. Other scripts never interpret earlier generations.
#
# Kept in place:
#   debug/ and ap/   saved stock property / hotspot values needed for restore
#   retired/         earlier retirements
#   persistent/      when it holds a recovery manifest (an installed
#                    persistent payload; its own update path owns it)
# Refused (exit 1, nothing moved):
#   enabled package, owned mounts, wrap properties, a same-boot live runtime,
#   or a persistent tree without a manifest that has a transaction marker or
#   originals that differ from live /system (use the recovery USB).
umask 077
ROOT=${PORTABLE_TEST_ROOT:-}
S=$ROOT/data/local/gen5w-portable
HELPER=${PORTABLE_HELPER:-${0%/*}/bin/dex-patch}
MOUNTS=${PORTABLE_TEST_MOUNTS:-/proc/mounts}
GETPROP=${PORTABLE_TEST_GETPROP:-getprop}
BOOT_ID_FILE=${PORTABLE_TEST_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}
fail() { echo "state-reset: $*" >&2; exit 1; }
plain() {
    case "$1" in /*) :;; *) return 1;; esac
    case "$1" in *[!a-zA-Z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac
    local part=$1
    while [ "$part" != / ]; do [ ! -L "$part" ] || return 1; part=${part%/*}; [ -n "$part" ] || part=/; done
}
present() { [ -e "$1" ] || [ -L "$1" ]; }
small() { [ -f "$1" ] && [ ! -L "$1" ] && IFS= read -r value < "$1" && print -r -- "$value"; }

present "$S" || { echo 'state-reset: no earlier state'; exit 0; }
plain "$S" && [ -d "$S" ] || fail 'unsafe state root'
boot=$(small "$BOOT_ID_FILE") && [ -n "$boot" ] || fail 'boot id unavailable'

# 1. Nothing of an earlier generation may be live.
[ "$(small "$S/boot/enabled")" != 1 ] || fail 'earlier package is still enabled; disable it first'
[ -r "$MOUNTS" ] || fail 'mount table unavailable'
! grep -q '/data/local/gen5w-portable' "$MOUNTS" || fail 'earlier package still has bind mounts'
for key in wrap.com.daudio.app.dipo wrap.com.google.android.project; do
    [ -z "$("$GETPROP" "$key" 2>/dev/null)" ] || fail "earlier wrapper property is set: $key"
done
case "$(small "$S/runtime/phase")" in pending|committed|enabling)
    [ "$(small "$S/runtime/boot")" != "$boot" ] || fail 'earlier runtime is live in this boot';;
esac

# 2. A persistent tree is kept with its manifest, retired only when provably
#    unused (a migration that failed before any /system write and rolled back).
P=$S/persistent; R=$P/recovery; keep_persistent=0
originals_match() {
    local dir=$1 entry rel a b
    for entry in "$dir"/* "$dir"/.[!.]*; do
        present "$entry" || continue
        [ ! -L "$entry" ] || return 1
        if [ -d "$entry" ]; then originals_match "$entry" || return 1
        elif [ -f "$entry" ]; then
            rel=${entry#"$R/originals"}
            plain "$ROOT$rel" && [ -f "$ROOT$rel" ] || return 1
            a=$("$HELPER" sha256 "$entry") && b=$("$HELPER" sha256 "$ROOT$rel") && [ -n "$a" ] && [ "$a" = "$b" ] || return 1
        else return 1; fi
    done
}
if present "$P"; then
    plain "$P" && [ -d "$P" ] || fail 'unsafe persistent state'
    if present "$R/manifest"; then
        plain "$R/manifest" && [ -f "$R/manifest" ] || fail 'unsafe persistent recovery manifest'
        keep_persistent=1
    else
        for marker in "$P/manifest" "$R/transaction-needs-recovery" "$R/transaction-in-progress" "$R/transaction-committed" "$R/migration.lock"; do
            ! present "$marker" || fail "unfinished persistent transaction (${marker##*/}); use the recovery USB"
        done
        if present "$R/originals"; then
            plain "$R/originals" && [ -d "$R/originals" ] || fail 'unsafe persistent originals'
            originals_match "$R/originals" || fail 'leftover originals differ from live /system; use the recovery USB'
        fi
    fi
fi

# 3. Move every other entry aside, as one dated retirement.
dest=$S/retired/$boot-$$
present "$S/retired" || mkdir "$S/retired" || fail 'cannot create retired directory'
plain "$S/retired" && [ -d "$S/retired" ] && ! present "$dest" && mkdir "$dest" || fail 'cannot create retirement'
moved=
for entry in "$S"/* "$S"/.[!.]*; do
    present "$entry" || continue
    name=${entry##*/}
    case "$name" in debug|ap|retired) continue;; persistent) [ "$keep_persistent" = 0 ] || continue;; esac
    mv "$entry" "$dest/" || fail "cannot retire $name (moved so far:$moved)"
    moved="$moved $name"
done
sync
if [ -z "$moved" ]; then
    rmdir "$dest" 2>/dev/null
    echo 'state-reset: no inactive earlier state'
else
    echo "state-reset: retired inactive earlier state to ${dest#"$ROOT"}:$moved"
fi
