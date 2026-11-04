#!/system/bin/sh
# Helpers for the opt-in USB-only structured drive logger.
DL_SEGMENT_BYTES=1048576
DL_SEGMENTS=32
DL_MIN_FREE_KB=65536
if [ "${DL_TESTING:-0}" = 1 ]; then
    DL_SEGMENT_BYTES=${DL_SEGMENT_BYTES_OVERRIDE:-$DL_SEGMENT_BYTES}
    DL_SEGMENTS=${DL_SEGMENTS_OVERRIDE:-$DL_SEGMENTS}
    DL_MIN_FREE_KB=${DL_MIN_FREE_KB_OVERRIDE:-$DL_MIN_FREE_KB}
fi

dl_number() {
    case "$1" in ''|*[!0-9]*) return 1;; esac
    return 0
}

dl_mount_info() {
    _dl_usb=$1 _dl_mounts=$2 _dl_sys=$3
    [ -d "$_dl_usb" ] && [ ! -L "$_dl_usb" ] || return 1
    [ -f "$_dl_mounts" ] && [ ! -L "$_dl_mounts" ] || return 1
    _dl_count=0 _dl_source= _dl_fs= _dl_dev=
    while IFS=' ' read -r _dl_s _dl_m _dl_t _dl_opts _dl_rest; do
        [ "$_dl_m" = "$_dl_usb" ] || continue
        _dl_count=$((_dl_count + 1))
        _dl_source=$_dl_s _dl_fs=$_dl_t
    done < "$_dl_mounts"
    [ "$_dl_count" = 1 ] || return 1
    case "$_dl_fs" in vfat|exfat) ;; *) return 1;; esac
    case "$_dl_source" in /dev/block/vold/*) _dl_dev=${_dl_source##*/};; *) return 1;; esac
    case "$_dl_dev" in *:*) ;; *) return 1;; esac
    _dl_major=${_dl_dev%%:*} _dl_minor=${_dl_dev#*:}
    dl_number "$_dl_major" && dl_number "$_dl_minor" || return 1
    _dl_sysdev=$_dl_sys/dev/block/$_dl_dev
    [ -L "$_dl_sysdev" ] || return 1
    _dl_real=$( (CDPATH= cd -P "$_dl_sysdev" 2>/dev/null && pwd -P) ) || return 1
    case "$_dl_real" in */devices/*/usb[0-9]/*) ;; *) return 1;; esac
    _dl_uevent=$_dl_sysdev/uevent
    [ -f "$_dl_uevent" ] || return 1
    _dl_seen_major= _dl_seen_minor=
    while IFS= read -r _dl_line || [ -n "$_dl_line" ]; do
        case "$_dl_line" in
            MAJOR=*) _dl_seen_major=${_dl_line#MAJOR=};;
            MINOR=*) _dl_seen_minor=${_dl_line#MINOR=};;
        esac
    done < "$_dl_uevent"
    [ "$_dl_seen_major" = "$_dl_major" ] && [ "$_dl_seen_minor" = "$_dl_minor" ] || return 1
    printf '%s|%s|%s\n' "$_dl_source" "$_dl_fs" "$_dl_dev"
}

dl_opt_in() {
    _dl_usb=$1
    [ -d "$_dl_usb" ] && [ ! -L "$_dl_usb" ] || return 1
    [ -f "$_dl_usb/GEN5W-DEBUG-ON" ] && [ ! -L "$_dl_usb/GEN5W-DEBUG-ON" ] || return 1
    [ ! -e "$_dl_usb/GEN5W-DEBUG-OFF" ] && [ ! -L "$_dl_usb/GEN5W-DEBUG-OFF" ] || return 1
    return 0
}

dl_validate_record() {
    _dl_record=$1
    [ "${#_dl_record}" -le 128 ] || return 1
    _dl_old_ifs=$IFS; IFS='|'; set -- $_dl_record; IFS=$_dl_old_ifs
    [ "$#" = 10 ] && [ "$1" = D1 ] || return 1
    case "$3" in 1|2) ;; *) return 1;; esac
    case "$4" in 1|2|20|21|22|24|25|26|27) ;; *) return 1;; esac
    shift
    _dl_pos=2
    for _dl_field in "$@"; do
        case "$_dl_field" in -*) _dl_digits=${_dl_field#-};; *) _dl_digits=$_dl_field;; esac
        if [ "$_dl_pos" = 2 ]; then [ "${#_dl_digits}" -le 13 ] || return 1
        else [ "${#_dl_digits}" -le 10 ] || return 1; fi
        dl_number "$_dl_digits" || return 1
        _dl_pos=$((_dl_pos + 1))
    done
    return 0
}

dl_uptime_ms() {
    _dl_uptime_file=${DL_PROC_UPTIME:-/proc/uptime}
    [ -f "$_dl_uptime_file" ] && [ ! -L "$_dl_uptime_file" ] || return 1
    IFS=' ' read -r _dl_value _dl_rest < "$_dl_uptime_file" || return 1
    case "$_dl_value" in *.*) _dl_seconds=${_dl_value%%.*}; _dl_fraction=${_dl_value#*.};;
        *) _dl_seconds=$_dl_value; _dl_fraction=0;; esac
    dl_number "$_dl_seconds" || return 1
    case "$_dl_fraction" in ''|*[!0-9]*) return 1;; esac
    _dl_fraction=${_dl_fraction}000
    _dl_fraction=${_dl_fraction%${_dl_fraction#???}}
    printf '%s\n' "$((_dl_seconds * 1000 + _dl_fraction))"
}

dl_record_uptime() {
    _dl_old_ifs=$IFS; IFS='|'; set -- $1; IFS=$_dl_old_ifs
    [ "$#" = 10 ] && [ "$1" = D1 ] || return 1
    printf '%s\n' "$2"
}

dl_record_after() {
    _dl_start=$1 _dl_record=$2
    dl_number "$_dl_start" || return 1
    _dl_record_time=$(dl_record_uptime "$_dl_record") || return 1
    dl_number "$_dl_record_time" || return 1
    [ "$_dl_record_time" -ge "$_dl_start" ]
}

dl_read_timeout() {
    dl_number "$1" && dl_number "$2" || return 1
    [ "$2" -ge "$1" ] || return 1
    [ $(( $2 - $1 )) -ge 1000 ]
}

dl_empty_directory() {
    _dl_dir=$1
    for _dl_entry in "$_dl_dir"/* "$_dl_dir"/.[!.]* "$_dl_dir"/..?*; do
        [ -e "$_dl_entry" ] || [ -L "$_dl_entry" ] || continue
        return 1
    done
    return 0
}

dl_prepare_ring() {
    _dl_dir=$1
    [ ! -L "$_dl_dir" ] || return 1
    if [ ! -e "$_dl_dir" ]; then
        mkdir "$_dl_dir" 2>/dev/null || return 1
        printf 'gen5w-drive-log-v1\n' > "$_dl_dir/.owner" || return 1
        printf '0\n' > "$_dl_dir/.cursor" || return 1
        return 0
    fi
    [ -d "$_dl_dir" ] || return 1
    if [ ! -e "$_dl_dir/.owner" ]; then
        dl_empty_directory "$_dl_dir" || return 1
        printf 'gen5w-drive-log-v1\n' > "$_dl_dir/.owner" || return 1
    fi
    [ -f "$_dl_dir/.owner" ] && [ ! -L "$_dl_dir/.owner" ] || return 1
    [ "$(cat "$_dl_dir/.owner" 2>/dev/null)" = gen5w-drive-log-v1 ] || return 1
    if [ ! -e "$_dl_dir/.cursor" ]; then
        printf '0\n' > "$_dl_dir/.cursor" || return 1
    fi
    [ -f "$_dl_dir/.cursor" ] && [ ! -L "$_dl_dir/.cursor" ] || return 1
    _dl_cursor=$(cat "$_dl_dir/.cursor" 2>/dev/null)
    dl_number "$_dl_cursor" || return 1
    [ "$_dl_cursor" -lt "$DL_SEGMENTS" ] || return 1
    # A crash during the cursor rename is ambiguous. Preserve it and stop rather
    # than deleting/truncating state whose ownership may no longer be certain.
    [ ! -e "$_dl_dir/.cursor.tmp" ] && [ ! -L "$_dl_dir/.cursor.tmp" ] || return 1
    return 0
}

dl_write_record() {
    _dl_dir=$1 _dl_record=$2 _dl_free_kb=$3
    dl_validate_record "$_dl_record" || return 1
    dl_number "$_dl_free_kb" && [ "$_dl_free_kb" -ge "$DL_MIN_FREE_KB" ] || return 1
    dl_prepare_ring "$_dl_dir" || return 1
    _dl_cursor=$(cat "$_dl_dir/.cursor" 2>/dev/null) || return 1
    _dl_name=$(printf '%02d' "$_dl_cursor")
    _dl_file=$_dl_dir/segment-$_dl_name.log
    [ ! -L "$_dl_file" ] || return 1
    if [ -e "$_dl_file" ]; then [ -f "$_dl_file" ] || return 1; fi
    _dl_size=0
    if [ -f "$_dl_file" ]; then
        _dl_size=$(wc -c < "$_dl_file" 2>/dev/null) || return 1
        dl_number "$_dl_size" || return 1
    fi
    _dl_record_size=$((${#_dl_record} + 1))
    [ "$_dl_record_size" -le "$DL_SEGMENT_BYTES" ] || return 1
    if [ $((_dl_size + _dl_record_size)) -gt "$DL_SEGMENT_BYTES" ]; then
        _dl_next=$(((_dl_cursor + 1) % DL_SEGMENTS))
        _dl_next_name=$(printf '%02d' "$_dl_next")
        _dl_next_file=$_dl_dir/segment-$_dl_next_name.log
        [ ! -L "$_dl_next_file" ] || return 1
        if [ -e "$_dl_next_file" ]; then [ -f "$_dl_next_file" ] || return 1; fi
        [ ! -e "$_dl_dir/.cursor.tmp" ] && [ ! -L "$_dl_dir/.cursor.tmp" ] || return 1
        printf '%s\n' "$_dl_next" > "$_dl_dir/.cursor.tmp" || return 1
        mv "$_dl_dir/.cursor.tmp" "$_dl_dir/.cursor" || return 1
        : > "$_dl_next_file" || return 1
        _dl_file=$_dl_next_file
    elif [ ! -e "$_dl_file" ]; then
        : > "$_dl_file" || return 1
    fi
    printf '%s\n' "$_dl_record" >> "$_dl_file" || return 1
    return 0
}

dl_free_kb() {
    _dl_usb=$1 _dl_source=$2 _dl_df=${DL_DF:-df}
    _dl_output=$("$_dl_df" -k "$_dl_usb" 2>/dev/null) || return 1
    while IFS= read -r _dl_line; do
        set -- $_dl_line
        [ "$#" -ge 4 ] || continue
        [ "$1" = "$_dl_source" ] || continue
        dl_number "$4" || return 1
        printf '%s\n' "$4"
        return 0
    done <<EOF
$_dl_output
EOF
    return 1
}
