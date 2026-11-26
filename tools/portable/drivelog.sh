#!/system/bin/sh
# Portable USB drive log (simple log, on by default).
# While a verified removable USB is mounted at /storage/usb0 this records, on
# that USB only, under GEN5W-DRIVELOG/:
#   drive-NN.log  numeric Gen5wDrive records (HUD, ownership, connection events)
#   wire-NN.log   a short, unfiltered log of the wireless/projection/navigation tags
# Nothing is written to internal storage. A USB with GEN5W-LOG-OFF (or the older
# GEN5W-DEBUG-OFF) in its root is never written. The detailed full log is the
# separate debug switch in the in-car UI (debug.sh).
# Background work yields the CPU to Android (see debug.sh).
renice 10 $$ >/dev/null 2>&1
HOLD_SCRIPT=${0%/*}/install-hold.sh
. "$HOLD_SCRIPT"
install_hold && exit 0
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
USB=${DL_USB:-/storage/usb0}
# /proc/mounts is a symlink on Android 4.4; the table guard refuses symlinks.
MOUNTS=${DL_MOUNTS:-/proc/self/mounts}
SYS=${DL_SYS:-/sys}
GETPROP=${DL_GETPROP:-getprop}
LOGCAT=${DL_LOGCAT:-logcat}
DF=${DL_DF:-df}
AM=${DL_AM:-am}
DL_DIR=GEN5W-DRIVELOG
DL_WIRE_SEGMENTS=16
DL_WIRE_LINE=300
# Free space is read once per this many written lines (df is a process spawn).
DL_FREE_EVERY=200
if [ "${DL_TESTING:-0}" = 1 ]; then
    DL_WIRE_SEGMENTS=${DL_WIRE_SEGMENTS_OVERRIDE:-$DL_WIRE_SEGMENTS}
    DL_FREE_EVERY=${DL_FREE_EVERY_OVERRIDE:-$DL_FREE_EVERY}
fi
# Our tags, the stock wireless/projection tags, crashes. Everything else silent.
# V039 CarPlayLogger.java:8 uses CarPlayService (CarPlay_ does not match).
# Stock tags: SplitScreenManager.java:109; ModeManagerService.java:323,12737-12740;
# MicomAudioService.java:149; PgsService.java:111; CameraEventLogger.java:9;
# Iap2SendNotiThread.java:19; MobisExternalCommunicator.java:158.
# RightScreenHome (split INFO panel) logs as SplitScreen (t/a.java:65-80, t/b.java:55-70)
# and SplitScreenBase (k/r.java:1397).
# Camera / BT delete / BT music (Codex-8 audit): RearCamera CameraPreviewReceiver/Launcher
# (RearCamera-Receiver, RearCamera-App), HKMC_BtSettings BluetoothDeleteDevicesActivity,
# PhoneProjection WirelessPhoneProjectionService (getSimpleName tag).
DL_FILTER='Gen5wDrive:I Gen5wCore:V Gen5wNavi:V Gen5wWireless:V gen5w-wireless:V PhoneProjection:V Iap2Service:V CarPlay_:V CarPlayService:V DipoService:D SplitScreenManager:D SplitScreen:D SplitScreenBase:D ModeManagerService:V MicomAudioService:I PgsService:I CameraEventLogger:I Iap2SendNotiThread:D MobisExternalCommunicator:D DiPOManager:V BTCMService:V BTCMStateMachine:V HfDeviceService:V BluetoothHfDevice:V A2dpStateMachine:V BluetoothA2dp:D BluetoothManagerService:I BluetoothDeleteDevicesActivity:I WirelessPhoneProjectionService:V RearCamera-App:I RearCamera-Receiver:I WifiService:I WifiStateMachine:I SoftapController:V NetworkManagementService:I Tethering:I iAP2:V IAP2:V AndroidRuntime:E System.err:W *:S'

until [ "$("$GETPROP" sys.boot_completed 2>/dev/null)" = 1 ]; do sleep 5; done

_dl_note=
dl_note() {
    [ "$1" != "$_dl_note" ] || return 0
    _dl_note=$1
    print -r -- "drive-log: $1"
}
dl_toast() {
    "$AM" broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "Gen5W KR: $1" --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1 || :
}
# Default on; an explicit marker on the USB turns it off for that USB.
dl_enabled() {
    [ -d "$1" ] && [ ! -L "$1" ] || return 1
    [ ! -e "$1/GEN5W-LOG-OFF" ] && [ ! -L "$1/GEN5W-LOG-OFF" ] || return 1
    [ ! -e "$1/GEN5W-DEBUG-OFF" ] && [ ! -L "$1/GEN5W-DEBUG-OFF" ] || return 1
}
# Drops any line that could carry an identifier or media text. Builtins only:
# an external grep would block-buffer and lose the newest lines on unplug.
dl_seg_name() {
    case "$2" in [0-9]) print -r -- "$DL_DIR/$1-0$2.log";; *) print -r -- "$DL_DIR/$1-$2.log";; esac
}
# Ring state lives in shell variables; the cursor file only survives restarts.
dl_ring_open() { # kind segments -> sets _dl_<kind>_cursor/_size
    typeset kind=$1 segs=$2 cursor=0 file size=0 line
    if [ -f "$DL_DIR/.$kind" ] && [ ! -L "$DL_DIR/.$kind" ]; then
        IFS= read -r cursor < "$DL_DIR/.$kind" || cursor=0
    fi
    dl_number "$cursor" && [ "$cursor" -lt "$segs" ] || cursor=0
    file=$(dl_seg_name "$kind" "$cursor")
    [ ! -L "$file" ] || return 1
    if [ -f "$file" ]; then
        line=$(LC_ALL=C ls -ln "$file" 2>/dev/null) || return 1
        size=$(dl_size_from_ls "$line") || return 1
    elif [ -e "$file" ]; then return 1
    fi
    eval "_dl_${kind}_cursor=\$cursor _dl_${kind}_size=\$size _dl_${kind}_segs=\$segs"
}
dl_ring_write() { # kind text
    typeset kind=$1 text=$2 cursor size segs file len
    eval "cursor=\$_dl_${kind}_cursor size=\$_dl_${kind}_size segs=\$_dl_${kind}_segs"
    len=$((${#text} + 1))
    if [ $((size + len)) -gt "$DL_SEGMENT_BYTES" ]; then
        cursor=$(((cursor + 1) % segs))
        print -r -- "$cursor" > "$DL_DIR/.$kind" || return 1
        file=$(dl_seg_name "$kind" "$cursor")
        [ ! -L "$file" ] || return 1
        : > "$file" || return 1
        size=0
    else
        file=$(dl_seg_name "$kind" "$cursor")
    fi
    print -r -- "$text" >> "$file" || return 1
    size=$((size + len))
    eval "_dl_${kind}_cursor=\$cursor _dl_${kind}_size=\$size"
}
dl_prepare_dir() {
    [ ! -L "$DL_DIR" ] || return 1
    if [ ! -e "$DL_DIR" ]; then
        mkdir "$DL_DIR" 2>/dev/null || return 1
        print -r -- 'gen5w-drive-log-v2' > "$DL_DIR/.owner" || return 1
    fi
    [ -d "$DL_DIR" ] && [ -f "$DL_DIR/.owner" ] && [ ! -L "$DL_DIR/.owner" ] || return 1
    case "$(cat "$DL_DIR/.owner" 2>/dev/null)" in gen5w-drive-log-v1|gen5w-drive-log-v2) ;; *) return 1;; esac
}

_dl_toasted=
dl_note started
while :; do
    if ! dl_enabled "$USB"; then dl_note 'waiting: no USB, or GEN5W-LOG-OFF on it'; sleep 5; continue; fi
    _dl_identity=$(dl_mount_info "$USB" "$MOUNTS" "$SYS")
    case "$_dl_identity" in
        '!'*|'')
            _dl_reason=${_dl_identity#!}
            # No USB plugged in is the normal state; only a USB that is present
            # but cannot be verified is worth a notice.
            case "$_dl_reason" in
                unmounted|no-usb-directory) :;;
                *) [ "$_dl_toasted" = "$_dl_reason" ] || { _dl_toasted=$_dl_reason; dl_toast "USB 로그 대기 - USB 확인 안 됨 ($_dl_reason)"; };;
            esac
            dl_note "waiting: USB not verified reason=$_dl_reason"; sleep 5; continue;;
    esac
    _dl_source=${_dl_identity%%\|*}
    _dl_path=${_dl_identity##*\|}
    (
        # Pin the verified mount as cwd so writes never land under the bare mount point.
        cd "$_dl_path" || exit 2
        _dl_after_cd=$(dl_mount_info "$USB" "$MOUNTS" "$SYS") || exit 5
        [ "$_dl_after_cd" = "$_dl_identity" ] && dl_enabled "$USB" || exit 5
        _dl_start_uptime=$(dl_uptime_ms) || exit 2
        dl_prepare_dir || exit 2
        dl_ring_open drive "$DL_SEGMENTS" || exit 2
        dl_ring_open wire "$DL_WIRE_SEGMENTS" || exit 2
        _dl_free=$(DL_DF="$DF" dl_free_kb "$_dl_path" "$_dl_source") || exit 3
        [ "$_dl_free" -ge "$DL_MIN_FREE_KB" ] || exit 3
        print -r -- 'drive-log: recording'
        dl_toast 'USB에 주행 로그 기록 중 (끄기: USB에 GEN5W-LOG-OFF 파일)'
        _dl_lines=0 _dl_checked=${_dl_start_uptime%???}
        # DL_FILTER is split into arguments; never glob-expand its '*:S'.
        set -f
        # -v time keeps the wall clock on wire lines; Gen5wDrive records carry uptime.
        "$LOGCAT" -v time $DL_FILTER 2>/dev/null | while :; do
            _dl_wait_start=$(dl_uptime_ms) || exit 5
            _dl_line=
            if IFS= read -t 2 -r _dl_line; then
                # Re-verify the mount once per uptime second, not per line.
                _dl_now_ms=$(dl_uptime_ms) || exit 5
                if [ "${_dl_now_ms%???}" != "$_dl_checked" ]; then
                    dl_enabled "$USB" || exit 5
                    _dl_now=$(dl_mount_info "$USB" "$MOUNTS" "$SYS") || exit 5
                    [ "$_dl_now" = "$_dl_identity" ] || exit 5
                    _dl_checked=${_dl_now_ms%???}
                fi
                case "$_dl_line" in
                    *'/Gen5wDrive('*)
                        _dl_record=${_dl_line#*): }
                        dl_validate_record "$_dl_record" || continue
                        dl_record_after "$_dl_start_uptime" "$_dl_record" || continue
                        dl_ring_write drive "$_dl_record" || exit 4;;
                    *)
                        # V039 ModeManagerService.java:6263,7129,12737-12740: mode changes and split status.
                        # Preserve split status and mode transitions before dropping polls.
                        case "$_dl_line" in
                            *'/ModeManagerService('*split_screen_status*|*'/ModeManagerService('*'splitscreen status'*|*'/ModeManagerService('*changeMode*|*'/ModeManagerService('*ChangeMode*|*'/ModeManagerService('*notifyModeChanged*|*'/ModeManagerService('*'mode change'*|*'/ModeManagerService('*setMode*|*'W/ModeManagerService('*|*'E/ModeManagerService('*) ;;
                            *'/ModeManagerService('*getTopPackageName*|*'/ModeManagerService('*getCurrentMode*|*'/ModeManagerService('*getTopActivity*) continue;;
                            *'/ModeManagerService('*) continue;;
                        esac
                        dl_ring_write wire "${_dl_line:0:$DL_WIRE_LINE}" || exit 4;;
                esac
                _dl_lines=$((_dl_lines + 1))
                if [ "$_dl_lines" -ge "$DL_FREE_EVERY" ]; then
                    _dl_lines=0
                    _dl_free=$(DL_DF="$DF" dl_free_kb "$_dl_path" "$_dl_source") || exit 3
                    [ "$_dl_free" -ge "$DL_MIN_FREE_KB" ] || exit 3
                fi
            else
                _dl_wait_end=$(dl_uptime_ms) || exit 5
                dl_read_timeout "$_dl_wait_start" "$_dl_wait_end" || exit 6
                dl_enabled "$USB" || exit 5
                _dl_idle_mount=$(dl_mount_info "$USB" "$MOUNTS" "$SYS") || exit 5
                [ "$_dl_idle_mount" = "$_dl_identity" ] || exit 5
                _dl_checked=${_dl_wait_end%???}
            fi
        done
    )
    _dl_rc=$?
    _dl_note= _dl_toasted=
    case "$_dl_rc" in
        2) dl_note 'stopped: cannot prepare GEN5W-DRIVELOG on the USB';;
        3) dl_note 'stopped: USB free space unknown or below 64 MiB';;
        4) dl_note 'stopped: write to USB failed';;
        5) dl_note 'stopped: USB removed, changed or turned off';;
        6) dl_note 'stopped: log reader ended';;
        *) dl_note "stopped: rc=$_dl_rc";;
    esac
    case "$_dl_rc" in
        2|4) dl_toast 'USB 로그 중단 - USB에 쓸 수 없음';;
        3) dl_toast 'USB 로그 중단 - USB 여유 공간 부족(64MB 미만)';;
        6) dl_toast 'USB 로그 중단 - 로그 읽기 종료';;
    esac
    # A USB that stopped for a fault is retried only after it is re-plugged.
    if [ "$_dl_rc" = 2 ] || [ "$_dl_rc" = 3 ] || [ "$_dl_rc" = 4 ]; then
        while _dl_again=$(dl_mount_info "$USB" "$MOUNTS" "$SYS") && [ "$_dl_again" = "$_dl_identity" ]; do sleep 5; done
    fi
    sleep 5
done
