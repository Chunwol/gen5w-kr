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

# Without a kernel boot id, a NEMESIS restart of service.sh within one boot
# would count as another failed boot. Fall back to an id kept in tmpfs (/dev),
# which is empty again after every real boot. If even that cannot be kept,
# keep the old behaviour: over-counting only restores stock, it never bricks.
RUNTIME_ID=${BOOTGUARD_RUNTIME_ID:-/dev/.gen5wkr-boot-id}
runtime_boot_id() {
    [ ! -L "$RUNTIME_ID" ] || return 1
    _id=$(cat "$RUNTIME_ID" 2>/dev/null)
    case "$_id" in
        local-*[!a-zA-Z0-9-]*) ;;
        local-?*) printf '%s' "$_id"; return 0 ;;
    esac
    _up=$(cat /proc/uptime 2>/dev/null)
    _up=${_up%% *}
    _id="local-$$-${RANDOM:-0}-${_up%%.*}-${_up#*.}"
    case "$_id" in *[!a-zA-Z0-9-]*) _id="local-$$-${RANDOM:-0}";; esac
    _tmp="$RUNTIME_ID.tmp.$$"
    printf '%s
' "$_id" > "$_tmp" 2>/dev/null && mv -f "$_tmp" "$RUNTIME_ID" 2>/dev/null         || { rm -f "$_tmp" 2>/dev/null; return 1; }
    [ "$(cat "$RUNTIME_ID" 2>/dev/null)" = "$_id" ] || return 1
    printf '%s' "$_id"
}
[ -n "$BOOT_ID" ] || BOOT_ID=$(runtime_boot_id) || BOOT_ID=

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
    _attempt_id=
    if [ -e "$STATE_DIR/attempt" ] || [ -L "$STATE_DIR/attempt" ]; then
        [ -f "$STATE_DIR/attempt" ] && [ ! -L "$STATE_DIR/attempt" ] || fail 'invalid attempt journal'
        set -- $(cat "$STATE_DIR/attempt" 2>/dev/null)
        [ "$#" -eq 2 ] || fail 'invalid attempt journal'
        case "$1" in ''|*[!a-zA-Z0-9-]*) fail 'invalid attempt boot id';; esac
        case "$2" in ''|*[!0-9]*) fail 'invalid attempt count';; esac
        _attempt_id=$1
        if [ "$_count" != "$2" ]; then
            atomic_write count "$2" || fail 'cannot recover attempt count'
            _count=$2
        fi
    fi
    if [ -n "$BOOT_ID" ]; then
        case "$BOOT_ID" in *[!a-zA-Z0-9-]*) fail 'invalid boot id';; esac
        [ ! -L "$STATE_DIR/boot-id" ] || fail 'boot-id marker is a symlink'
        if [ "$_attempt_id" = "$BOOT_ID" ] || { [ -z "$_attempt_id" ] && [ -f "$STATE_DIR/boot-id" ] && [ "$(cat "$STATE_DIR/boot-id" 2>/dev/null)" = "$BOOT_ID" ]; }; then
            [ "$_count" -le "$_max" ] && return 0
            return 2
        fi
    fi
    _next=$((_count + 1))
    atomic_write attempt "${BOOT_ID:--} $_next" || fail 'cannot persist attempt journal'
    sync
    atomic_write count "$_next" || fail 'cannot persist count'
    if [ -n "$BOOT_ID" ]; then
        atomic_write boot-id "$BOOT_ID" || fail 'cannot record boot id'
    fi
    atomic_write phase booting || fail 'cannot persist phase'
    sync
    [ "$_next" -le "$_max" ] && return 0
    return 2
}

mark_ok() {
    atomic_write boot-ok boot-ok || fail 'cannot persist boot-ok'
    case "$BOOT_ID" in *[!a-zA-Z0-9-]*) fail 'invalid boot id';; esac
    atomic_write attempt "${BOOT_ID:--} 0" || fail 'cannot persist completed boot'
    sync
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
