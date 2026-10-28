#!/system/bin/sh
T=/system/etc/permissions/com.mobis.feature.remove_consentscreen.xml
while :; do
    if [ "$(getprop sys.boot.confirm_screen)" != true ]; then
        setprop sys.boot.enabled_screen true
        setprop sys.boot.confirm_screen true
        while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 1; done
        sleep 3
        am broadcast -a com.hkmc.intent.action.AGREE_USER_LICENSE >/dev/null 2>&1
        echo "agreed $(date 2>/dev/null)"
    fi
    sleep 2
done
