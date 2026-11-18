#!/system/bin/sh
umask 077
USB=
case "$0" in
    /storage/usb0/*) USB=/storage/usb0;;
    /storage/usb1/*) USB=/storage/usb1;;
    /storage/usb2/*) USB=/storage/usb2;;
    /mnt/media_rw/usb0/*) USB=/mnt/media_rw/usb0;;
    /mnt/media_rw/usb1/*) USB=/mnt/media_rw/usb1;;
    /mnt/media_rw/usb2/*) USB=/mnt/media_rw/usb2;;
    *) exit 2;;
esac
[ -d "$USB" ] && [ -w "$USB" ] || exit 3
[ -f "$USB/NEMESIS.emergency" ] && [ ! -L "$USB/NEMESIS.emergency" ] || exit 4
[ -f "$USB/restore.sh" ] && [ ! -L "$USB/restore.sh" ] &&
    [ ! -L "$USB/bin" ] && [ -f "$USB/bin/dex-patch" ] &&
    [ ! -L "$USB/bin/dex-patch" ] && [ -x "$USB/bin/dex-patch" ] || exit 5
export GEN5W_RECOVERY_USB_ROOT="$USB"
exec /system/bin/sh "$USB/restore.sh"
