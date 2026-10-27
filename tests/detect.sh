#!/bin/bash
# mock test for tools/usb-detect (read-only report)
. "$(dirname "$0")/lib.sh"
S=$(cd "$(dirname "$0")/../tools/usb-detect" && pwd)
W=$(mktemp -d); stubs; R=$W/root
mkdir -p $R/storage/usb0 $R/system/etc/permissions $R/system/priv-app $R/system/framework $R/system/app $R/system/lib $R/system/xbin $R/sys/class/net/wlan0
printf 'x\0com.mobis.feature.remove_consentscreen\0sys.boot.confirm_screen\0AGREE_USER_LICENSE\0' > $R/system/priv-app/SystemUI.odex
touch $R/system/framework/com.tcc.iap2.jar $R/system/app/Iap2ServerApp.apk $R/system/etc/permissions/com.hkmc.software.wifi.module.xml $R/system/etc/permissions/other.xml
echo lib > $R/system/lib/libCarPlayAudio.so; : > $R/system/xbin/nemesis; chmod +x $R/system/xbin/nemesis
echo OSHEV.KOR.0000.V039.001.260902 > $W/props/ro.build.product
printf '#!/bin/sh\necho "1 cluster: [com.hkmc.micom.IClusterService]"\n' > $W/bin/service; printf '#!/bin/sh\n' > $W/bin/dmesg; chmod +x $W/bin/*
(cd $W && GEN5W_TEST_PATH=$W/bin:$PATH DETECT_TEST_ROOT=$R mksh "$S/NEMESIS.sh")
O=$R/storage/usb0/GEN5WKR_DETECT.txt
check "report written" [ -s $O ]
for want in firmware=OSHEV.KOR.0000.V039.001.260902 wifi_hardware=yes consent_switch=yes iap2_library=yes iap2_server=yes cluster_service=yes feature_file=com.hkmc.software.wifi.module.xml nemesis=yes "lib_carplay_audio=$(md5sum $R/system/lib/libCarPlayAudio.so | cut -c1-32)" lib_carplay_core=missing; do
    check "report has $want" grep -qx "$want" $O
done
check "other permission files not listed" eval '! grep -q other.xml $O'
rm -r $R/sys/class/net/wlan0; printf '#!/bin/sh\necho "dhd: failed to power up DHD generic adapter"\n' > $W/bin/dmesg
: > $R/system/priv-app/SystemUI.odex
(cd $W && GEN5W_TEST_PATH=$W/bin:$PATH DETECT_TEST_ROOT=$R mksh "$S/NEMESIS.sh")
check "old power failure does not prove absent chip" grep -qx wifi_hardware=unknown $O
check "no consent switch detected" grep -qx consent_switch=no $O
done_tests detect
