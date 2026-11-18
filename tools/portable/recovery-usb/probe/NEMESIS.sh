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
REPORT=$USB/NEMESIS-PORTABLE-RECOVERY-PROBE.txt
VERSION=$(/system/xbin/nemesis version 2>&1)
{
    echo 'probe=gen5w-portable-recovery-v1'
    echo "script=$0"
    echo "usb=$USB"
    echo "nemesis_version=$VERSION"
    echo "boot_completed=$(getprop sys.boot_completed)"
    echo "zygote=$(getprop init.svc.zygote)"
    echo "init=$(getprop init.svc.bootanim)"
    echo "build=$(getprop ro.build.version.incremental)"
    echo 'android_system_writes=none'
    echo 'reboot=requested-by-no-one'
} > "$REPORT" || exit 4
sync
exit 0
