#!/system/bin/sh
# Durable boot-loop guard state.  This helper is intentionally independent of
# the bridge process so it can run before any patched service is started.
STATE_DIR=${BOOTGUARD_STATE_DIR:-/data/nemesis/gen5wkr.bootguard}
BOOT_ID=${BOOTGUARD_BOOT_ID:-}

fail() { echo "bootguard: $*" >&2; exit 1; }

[ -n "$STATE_DIR" ] || fail 'empty state directory'
[ ! -L "$STATE_DIR" ] || fail 'state directory is a symlink'
[ -d "$STATE_DIR" ] || fail 'state directory is missing'
[ -f "$STATE_DIR/armed" ] && [ ! -L "$STATE_DIR/armed" ] || fail 'guard is not armed'
[ ! -e "$STATE_DIR/recovery-required" ] || fail 'recovery is already required'
[ ! -e "$STATE_DIR/recovered" ] || fail 'guard has already recovered'

atomic_write() {
    _name=$1
    _value=$2
    _tmp="$STATE_DIR/.${_name}.tmp.$$"
    [ ! -e "$_tmp" ] && [ ! -L "$_tmp" ] || rm -f "$_tmp" || return 1
    printf '%s\n' "$_value" > "$_tmp" || { rm -f "$_tmp"; return 1; }
    [ ! -L "$STATE_DIR/$_name" ] || { rm -f "$_tmp"; return 1; }
    mv -f "$_tmp" "$STATE_DIR/$_name" || { rm -f "$_tmp"; return 1; }
    return 0
}

read_uint() {
    _value=$(cat "$1" 2>/dev/null) || return 1
    case "$_value" in
        ''|*[!0-9]*) return 1 ;;
    esac
    printf '%s' "$_value"
}

begin() {
    _count=$(read_uint "$STATE_DIR/count") || fail 'invalid count'
    _max=$(read_uint "$STATE_DIR/max") || fail 'invalid max'
    if [ -n "$BOOT_ID" ]; then
        [ ! -L "$STATE_DIR/boot-id" ] || fail 'boot-id marker is a symlink'
        if [ -f "$STATE_DIR/boot-id" ] && [ "$(cat "$STATE_DIR/boot-id" 2>/dev/null)" = "$BOOT_ID" ]; then
            return 0
        fi
        atomic_write boot-id "$BOOT_ID" || fail 'cannot record boot id'
    fi
    _next=$((_count + 1))
    atomic_write count "$_next" || fail 'cannot persist count'
    atomic_write phase booting || fail 'cannot persist phase'
    sync
    [ "$_next" -le "$_max" ] && return 0
    return 2
}

mark_ok() {
    atomic_write boot-ok boot-ok || fail 'cannot persist boot-ok'
    atomic_write count 0 || fail 'cannot reset count'
    atomic_write phase stable || fail 'cannot persist stable phase'
    sync
    return 0
}

case "$1" in
    begin) begin ;;
    mark-ok) mark_ok ;;
    *) fail 'usage: bootguard-state.sh begin|mark-ok' ;;
esac
