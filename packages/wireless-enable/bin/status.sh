#!/system/bin/sh
P=/system/etc/permissions
for f in com.hkmc.software.connectivity.carplay_wireless com.hkmc.software.connectivity.androidauto_wireless com.hkmc.software.wifihotspot android.hardware.wifi; do
    [ -f "$P/$f.xml" ] && echo "$f: present" || echo "$f: absent"
done
echo "persist.ium.support=$(getprop persist.ium.support)"
echo "persist.wifi.state=$(getprop persist.wifi.state)"
