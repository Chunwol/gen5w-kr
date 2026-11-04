#!/system/bin/sh
# Independent, fail-closed reader for the dedicated numeric-only app log tag.
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
USB=${DL_USB:-/storage/usb0}
MOUNTS=${DL_MOUNTS:-/proc/mounts}
SYS=${DL_SYS:-/sys}
GETPROP=${DL_GETPROP:-getprop}
LOGCAT=${DL_LOGCAT:-logcat}
DF=${DL_DF:-df}
until [ "$("$GETPROP" sys.boot_completed 2>/dev/null)" = 1 ]; do sleep 5; done

while :; do
    if ! dl_opt_in "$USB"; then sleep 5; continue; fi
    _dl_identity=$(dl_mount_info "$USB" "$MOUNTS" "$SYS") || { sleep 5; continue; }
    _dl_source=${_dl_identity%%|*}
    (
        # Pin the verified mount as cwd. If it is detached between a check and
        # a write, relative paths still target that filesystem, never the
        # directory exposed underneath /storage/usb0 after unmount.
        cd "$USB" || exit 1
        _dl_after_cd=$(dl_mount_info "$USB" "$MOUNTS" "$SYS") || exit 1
        [ "$_dl_after_cd" = "$_dl_identity" ] && dl_opt_in "$USB" || exit 1
        _dl_start_uptime=$(dl_uptime_ms) || exit 1
        _dl_dir=GEN5W-DRIVELOG
        dl_prepare_ring "$_dl_dir" || exit 1
        # logcat is a pipe only: no buffer or temporary file is created internally.
        "$LOGCAT" -v raw -s Gen5wDrive:I 2>/dev/null | while :; do
            _dl_wait_start=$(dl_uptime_ms) || break
            _dl_record=
            if IFS= read -t 2 -r _dl_record; then
                dl_opt_in "$USB" || break
                _dl_now=$(dl_mount_info "$USB" "$MOUNTS" "$SYS") || break
                [ "$_dl_now" = "$_dl_identity" ] || break
                dl_validate_record "$_dl_record" || continue
                dl_record_after "$_dl_start_uptime" "$_dl_record" || continue
                _dl_free=$(DL_DF="$DF" dl_free_kb "$USB" "$_dl_source") || break
                dl_write_record "$_dl_dir" "$_dl_record" "$_dl_free" || break
            else
                # mksh read -t reports timeout and EOF alike as nonzero. The
                # timeout takes >=1s; EOF returns immediately. Poll the USB at
                # each idle timeout and terminate the pipe immediately on EOF.
                _dl_wait_end=$(dl_uptime_ms) || break
                dl_read_timeout "$_dl_wait_start" "$_dl_wait_end" || break
                dl_opt_in "$USB" || break
                _dl_idle_mount=$(dl_mount_info "$USB" "$MOUNTS" "$SYS") || break
                [ "$_dl_idle_mount" = "$_dl_identity" ] || break
            fi
        done
    )
    # On detach, marker removal, low space, or write failure, stop the pipe and
    # wait before reevaluating. No failed record is redirected to internal storage.
    sleep 5
done
