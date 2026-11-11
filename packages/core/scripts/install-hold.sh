# Canonical startup-only guard. A stale marker from another boot never disables
# the UI/recovery collector. Does not stop an already-running service.
install_hold() {
    typeset base=${IT_DATA:-/data}/nemesis boot= held=
    [ -e "$base/gen5wkr.noreboot" ] && [ ! -L "$base/gen5wkr.install-hold" ] &&
        [ -f "$base/gen5wkr.install-hold" ] || return 1
    IFS= read -r boot < /proc/sys/kernel/random/boot_id || return 1
    IFS= read -r held < "$base/gen5wkr.install-hold" || return 1
    [ "$boot" = "$held" ] || return 1
    # Root-owned same-boot intent remains valid even if the worker crashed.
    # system-UID services must not depend on permission to signal that worker.
    echo 'DEFERRED installation in progress'
}
# For mode=restart services. Exiting while held makes the supervisor relaunch
# the launcher in a loop, so the installer sees a new PID and refuses to go on.
# Wait with the same PID instead; the installer stops it like a running service.
install_hold_wait() {
    install_hold || return 0
    while install_hold >/dev/null; do sleep 2; done
}
