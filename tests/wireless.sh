#!/bin/bash
# mock test for packages/wireless-enable
. "$(dirname "$0")/lib.sh"
PKG=$(cd "$(dirname "$0")/../packages/wireless-enable" && pwd)
CP=com.hkmc.software.connectivity.carplay_wireless.xml
HOT=com.hkmc.software.wifihotspot.xml
WIFI=android.hardware.wifi.xml

setup() { # $1 = korean|us|nowifi|nocode ; makes a fake /system
    W=$(mktemp -d); cp -r "$PKG" "$W/app"; stubs
    mkdir -p "$W/hw/class/net" "$W/hw/bus/sdio/devices"
    echo 1 > "$W/props/wifi_on"
    cat > "$W/bin/settings" <<S
#!/bin/sh
[ "\$1:\$2:\$3" = get:global:wifi_on ] && cat "$W/props/wifi_on"
S
    cat > "$W/bin/svc" <<S
#!/bin/sh
echo "\$1 \$2" >> "$W/svc.log"
case "\$1:\$2" in
    wifi:enable) echo 1 > "$W/props/wifi_on"; [ ! -f "$W/probe-creates-interface" ] || mkdir -p "$W/hw/class/net/wlan1";;
    wifi:disable) [ ! -f "$W/restore-fails" ] || exit 1; echo 0 > "$W/props/wifi_on"; rmdir "$W/hw/class/net/wlan1" 2>/dev/null || true;;
    *) exit 1;;
esac
S
    echo '#!/bin/sh' > "$W/bin/sleep"
    chmod +x "$W/bin/settings" "$W/bin/svc" "$W/bin/sleep"
    mkdir -p "$W/sys/etc/permissions" "$W/sys/app" "$W/sys/onebin/oshev_kr" "$W/data" "$W/sys/bin"
    # a stock projection app that knows the wireless features (unless nocode)
    if [ "${1:-korean}" != nocode ]; then
        printf 'x\0carplay_wireless\0ConnectivitySSID\0' > "$W/sys/app/HKMC_DiPO.odex"
    else
        printf 'x\0' > "$W/sys/app/HKMC_DiPO.odex"
    fi
    cat > "$W/sys/build.prop" <<P
ro.build.product=OSHEV.KOR.0000.V039.001.260902
persist.ium.support=
ro.config.x=1
P
    # featurexml that strips the wireless/hotspot features (korean style)
    cat > "$W/sys/onebin/oshev_kr/featurexml.cfg" <<F
# region features
+ /system/etc/permissions/com.hkmc.foo.xml
- /system/etc/permissions/com.hkmc.software.wifihotspot.xml
- /system/etc/permissions/com.hkmc.software.connectivity.carplay_wireless.xml
- /system/etc/permissions/com.hkmc.software.connectivity.androidauto_wireless.xml
F
    echo /system/onebin/oshev_kr > "$W/props/ro.mobis.targetdir.raw"
    # getprop stub must map ro.mobis.targetdir to the fake path under $W/sys
    printf '#!/bin/sh\ncase "$1" in ro.mobis.targetdir) echo %s/sys/onebin/oshev_kr;; *) cat "%s/props/$1" 2>/dev/null || true;; esac\n' "$W" "$W" > "$W/bin/getprop"
    chmod +x "$W/bin/getprop"
    # us firmware already has the feature files present
    if [ "${1:-korean}" = us ]; then
        for f in $CP $HOT com.hkmc.software.connectivity.androidauto_wireless.xml; do echo stock > "$W/sys/etc/permissions/$f"; done
    fi
    printf '#!/bin/sh\n' > "$W/bin/dmesg"
    if [ "${1:-korean}" = nowifi ]; then printf '#!/bin/sh\necho "dhd: failed to power up DHD generic adapter"\n' > "$W/bin/dmesg"; fi
    if [ "${1:-korean}" != nowifi ] && [ "${1:-korean}" != unknownwifi ]; then
        printf '#!/bin/sh\necho "dhd: Firmware up"\n' > "$W/bin/dmesg"
    fi
    chmod +x "$W/bin/dmesg"
    (cd "$W/sys" && find . -type f -exec md5sum {} + | sort -k2) > "$W/before"
}
run() { (cd "$W/app" && GEN5W_TEST_PATH=$W/bin:$PATH EN_TEST_HW_ROOT=$W/hw EN_TEST_SYS=$W/sys EN_TEST_DATA=$W/data EN_TEST_NEM=$W/nemesis PATH=$W/bin:$PATH mksh scripts/$1 >>"$W/out" 2>&1); }
hardware() { (cd "$W/app" && EN_TEST_HW_ROOT=$W/hw EN_TEST_SYS=$W/sys EN_TEST_DATA=$W/data EN_TEST_NEM=$W/nemesis PATH=$W/bin:$PATH mksh -c '. ./scripts/common.sh; wifi_hw'); }
same() { diff <(cd "$W/sys" && find . -type f -exec md5sum {} + | sort -k2) "$W/before" >/dev/null; }
perm() { [ -f "$W/sys/etc/permissions/$1" ]; }

# The unit uses BSD grep: BRE backslash alternation is not portable.
setup korean
cat > "$W/bin/grep" <<'G'
#!/bin/sh
for arg; do case "$arg" in *'\|'*) exit 1;; esac; done
exec /usr/bin/grep "$@"
G
chmod +x "$W/bin/grep"
check "wireless detection with portable BSD grep expressions" run pre.sh

# Korean unit: full enable + clean uninstall
setup korean
check "install (korean)" eval 'run pre.sh && run post.sh'
check "carplay feature added" perm $CP
check "hotspot feature added" perm $HOT
check "wifi client feature NOT added by default" eval '! perm $WIFI'
check "persist.ium.support set to carplay" grep -qx 'persist.ium.support=carplay' "$W/sys/build.prop"
check "featurexml stripping lines commented" eval 'grep -q "^#- .*carplay_wireless" "$W/sys/onebin/oshev_kr/featurexml.cfg" && grep -q "^#- .*wifihotspot" "$W/sys/onebin/oshev_kr/featurexml.cfg"'
check "featurexml keeps unrelated + lines" grep -q '^+ /system/etc/permissions/com.hkmc.foo.xml' "$W/sys/onebin/oshev_kr/featurexml.cfg"
check "uninstall" run preun.sh
check "uninstall -> /system byte-identical to stock" same

# Reinstall must keep the first install's ownership records for added files.
check "install before reinstall" eval 'run pre.sh && run post.sh'
check "reinstall" eval 'run pre.sh && run post.sh'
check "uninstall after reinstall" run preun.sh
check "reinstall uninstall -> /system byte-identical" same

# Wi-Fi client opt-in
# fake the install-drive flag via a path wifi_client_wanted scans: use a temp override
sed -i "s#/storage/usb0 /storage/usb1 /storage/usb2 /mnt/media_rw/usb0 /mnt/media_rw/usb1#$W/drv#" "$W/app/scripts/common.sh"
mkdir -p "$W/drv"; : > "$W/drv/GEN5W-WIFI-CLIENT"
check "install with wifi client flag" eval 'run pre.sh && run post.sh'
check "wifi feature added when asked" perm $WIFI
check "persist.wifi.state=3 when asked" grep -qx 'persist.wifi.state=3' "$W/sys/build.prop"
check "uninstall after wifi client" run preun.sh
check "wifi client uninstall identical" same

# US unit: feature files already there -> left as stock on uninstall
setup us
check "install (us, features already present)" eval 'run pre.sh && run post.sh'
check "existing feature file untouched kind" grep -qx stock "$W/sys/etc/permissions/$CP"
check "uninstall (us)" run preun.sh
check "us uninstall identical" same

# refuse where there is no wireless code
setup nocode
check "refused without wireless code" eval '! run pre.sh'

# A failed historical driver attempt does not establish physical absence.
setup nowifi
check "failed old driver with no current evidence is unknown" eval '[ "$(hardware)" = unknown ]'
check "unknown wireless feature is skipped" eval '! run pre.sh'

setup nowifi
mkdir -p "$W/hw/class/net/wlan1"
check "current alternate WLAN interface wins over old DHD failure" eval '[ "$(hardware)" = yes ]'
check "active WLAN interface never toggled" eval '[ ! -e "$W/svc.log" ]'

setup nowifi
mkdir -p "$W/hw/bus/sdio/devices/mmc1:0001:1"
echo 0x07 > "$W/hw/bus/sdio/devices/mmc1:0001:1/class"
check "SDIO WLAN function proves hardware despite old failure" eval '[ "$(hardware)" = yes ]'
echo 0x00 > "$W/hw/bus/sdio/devices/mmc1:0001:1/class"
echo '#!/bin/sh' > "$W/bin/dmesg"
echo 'echo "new high speed SDIO card"' >> "$W/bin/dmesg"
check "generic SDIO card does not prove WLAN" eval '[ "$(hardware)" = unknown ]'

setup nowifi
echo 'echo "dhd: Firmware up"' >> "$W/bin/dmesg"
check "firmware success wins over historical failure" eval '[ "$(hardware)" = yes ]'

setup unknownwifi
check "already-enabled client without evidence stays unknown" eval '[ "$(hardware)" = unknown ] && [ ! -e "$W/svc.log" ]'
echo 0 > "$W/props/wifi_on"
: > "$W/probe-creates-interface"
check "disabled client may be probed and detected" eval '[ "$(hardware)" = yes ]'
check "temporary probe restores client disabled" eval '[ "$(cat "$W/props/wifi_on")" = 0 ] && [ ! -e "$W/hw/class/net/wlan1" ] && [ "$(wc -l < "$W/svc.log")" -eq 2 ]'

setup unknownwifi
echo 0 > "$W/props/wifi_on"
check "unsuccessful bounded probe remains unknown" eval '[ "$(hardware)" = unknown ] && [ "$(cat "$W/props/wifi_on")" = 0 ]'

setup unknownwifi
echo 0 > "$W/props/wifi_on"
: > "$W/probe-creates-interface"; : > "$W/restore-fails"
check "probe restoration failure is a true error" eval '! hardware'
check "preinstall reports restoration error rather than hardware absence" eval 'echo 0 > "$W/props/wifi_on"; rmdir "$W/hw/class/net/wlan1"; run pre.sh; [ "$?" -eq 1 ]'

setup unknownwifi
check "refused when wifi hardware is unknown" eval '! run pre.sh'
mkdir -p "$W/data/nemesis/backup/gen5w.kr.wireless"
echo legacy > "$W/data/nemesis/backup/gen5w.kr.wireless/saved"
check "unknown wifi refuses orphaned legacy backup" eval 'run pre.sh; [ "$?" -eq 1 ]'

# An inconclusive probe after a verified installation is not evidence that the
# previous working configuration should be removed.
setup korean
check "install before inconclusive recheck" eval 'run pre.sh && run post.sh'
mkdir -p "$W/data/nemesis/apps/gen5w.kr.wireless"
printf '[nemesis]\nid=gen5w.kr.wireless\n' > "$W/data/nemesis/apps/gen5w.kr.wireless/NEMESIS.data"
printf '#!/bin/sh\n' > "$W/bin/dmesg"
check "unknown hardware preserves verified existing wireless" eval 'run pre.sh; [ "$?" -eq 78 ]'
mv "$W/sys/app/HKMC_DiPO.odex" "$W/original-dipo"
check "unreadable projection capability preserves verified existing wireless" eval 'run pre.sh; [ "$?" -eq 78 ]'
echo changed >> "$W/sys/build.prop"
check "damaged existing wireless state is not preserved as verified even when code is unreadable" eval 'run pre.sh; [ "$?" -eq 1 ]'

# Another model's file must never be selected when this model has no config.
setup korean
mkdir -p "$W/sys/onebin/other_model"
mv "$W/sys/onebin/oshev_kr/featurexml.cfg" "$W/sys/onebin/other_model/featurexml.cfg"
cp "$W/sys/onebin/other_model/featurexml.cfg" "$W/other.before"
check "install without current-model featurexml" eval 'run pre.sh && run post.sh'
check "other-model featurexml untouched" cmp -s "$W/other.before" "$W/sys/onebin/other_model/featurexml.cfg"
check "uninstall without current-model featurexml" run preun.sh

done_tests wireless
