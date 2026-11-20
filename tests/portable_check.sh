#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/gen5w-check.XXXXXX)
trap 'rc=$?; rm -rf "$t"; exit $rc' EXIT
mkdir -p "$t/bundle" "$t/root/system/app" "$t/root/system/etc/permissions" "$t/root/data/misc/wifi" "$t/props" \
    "$t/root/proc" "$t/root/sys/class/net/lo" "$t/root/sys/class/net/eth0"
cp tools/portable/check.sh "$t/bundle/"
echo stock > "$t/root/system/app/HKMC_DiPO.odex"
echo '<permissions/>' > "$t/root/system/etc/permissions/stock.xml"
stock_mounts='rootfs / rootfs ro,relatime 0 0
/dev/block/platform/system /system ext4 ro,relatime 0 0
/dev/block/platform/userdata /data ext4 rw,nosuid,nodev 0 0'
echo "$stock_mounts" > "$t/root/proc/mounts"
echo 'snd_soc_tcc 4096 0 - Live 0x00000000' > "$t/root/proc/modules"
echo '120.50 100.00' > "$t/root/proc/uptime"
echo softap-v1 > "$t/root/data/misc/wifi/softap.conf"
# Safe fixture adapter: no settings binary, getprop or real /proc is consulted.
cat > "$t/adapter" <<'SH'
#!/bin/bash
case "$1" in
boot) cat "$PROPS/boot";;
prop) cat "$PROPS/$2" 2>/dev/null || :;;
setting) [ ! -e "$PROPS/setting-fail" ] || exit 1; cat "$PROPS/setting.$2" 2>/dev/null || echo null;;
*) exit 1;;
esac
SH
chmod +x "$t/adapter"
export PROPS=$t/props PORTABLE_TEST_ROOT=$t/root PORTABLE_TEST_CHECK_ADAPTER=$t/adapter
cat > "$t/helper" <<'PY'
#!/usr/bin/python3
import hashlib,os,stat,sys
command,path=sys.argv[1:3]
if command=='sha256': print(hashlib.sha256(open(path,'rb').read()).hexdigest())
elif command=='identity':
 value=os.stat(path); print(f'{value.st_dev}:{value.st_ino}')
elif command=='metadata':
 value=os.stat(path); print(f'{value.st_uid}|{value.st_gid}|{stat.S_IMODE(value.st_mode):o}')
else: sys.exit(1)
PY
chmod +x "$t/helper"
export PORTABLE_TEST_HELPER=$t/helper
echo boot1 > "$PROPS/boot"
echo usb > "$PROPS/persist.ium.support"
run() { mksh "$t/bundle/check.sh" "$@"; }
# refuse LABEL REASON-PATTERN ARGS...: the command must fail for the stated reason.
refuse() {
    local label=$1 pattern=$2; shift 2
    if run "$@" > "$t/out" 2>&1; then echo "FAIL $label (accepted)"; cat "$t/out"; exit 1; fi
    grep -q -- "$pattern" "$t/out" || { echo "FAIL $label (wrong reason)"; cat "$t/out"; exit 1; }
}
accept() {
    local label=$1; shift
    run "$@" > "$t/out" 2>&1 || { echo "FAIL $label (refused)"; cat "$t/out"; exit 1; }
}

accept 'stock snapshot' snapshot /data/baseline
for file in system.sha256 properties boot settings net modules mounts uptime softap; do
    [ -f "$t/root/data/baseline/$file" ] || { echo "FAIL snapshot lacks $file"; exit 1; }
done
grep -qx 'wifi_ap_on|off|null' "$t/root/data/baseline/settings" || { echo 'FAIL wifi_ap_on not recorded'; exit 1; }
grep -qx eth0 "$t/root/data/baseline/net" && grep -qx snd_soc_tcc "$t/root/data/baseline/modules" &&
    grep -qx 120.50 "$t/root/data/baseline/uptime" || { echo 'FAIL diagnostic inventory missing'; exit 1; }
refuse 'baseline overwritten' 'fresh /data path' snapshot /data/baseline
refuse 'accepted same boot' 'different boot' restored /data/baseline
touch "$PROPS/setting-fail"
refuse 'snapshot without wifi_ap_on' 'wifi_ap_on' snapshot /data/noap
[ ! -e "$t/root/data/noap" ] || { echo 'FAIL partial snapshot left behind'; exit 1; }
rm "$PROPS/setting-fail"
accept 'prepare probe' prepare-probe /data/probe
cmp "$t/root/system/app/HKMC_DiPO.odex" "$t/root/data/probe/dipo.odex"
grep -q '^probe|/data/probe/dipo.odex|' "$t/root/data/probe/manifest"
[ "$(cat "$t/root/data/probe/dipo.odex.stock")" = "$("$t/helper" sha256 "$t/root/system/app/HKMC_DiPO.odex")" ] ||
    { echo 'FAIL prepare-probe lacks the stock origin digest for boot.sh arm'; exit 1; }
echo boot2 > "$PROPS/boot"
accept 'restored' restored /data/baseline
echo 0 > "$PROPS/setting.wifi_ap_on"
accept 'restored with explicit wifi_ap_on=0' restored /data/baseline
grep -q 'diag|wifi_ap_on|baseline=off|now=off' "$t/out" || { echo 'FAIL wifi_ap_on comparison not reported'; cat "$t/out"; exit 1; }
echo 1 > "$PROPS/setting.wifi_ap_on"
refuse 'ignored wifi_ap_on=1 after restore' 'wifi_ap_on' restored /data/baseline
echo 0 > "$PROPS/setting.wifi_ap_on"
echo carplay > "$PROPS/persist.ium.support"
refuse 'ignored persistent property mutation' 'stock file/property' restored /data/baseline
echo usb > "$PROPS/persist.ium.support"
echo changed > "$t/root/system/app/HKMC_DiPO.odex"
refuse 'ignored changed stock' 'stock file/property' restored /data/baseline
echo stock > "$t/root/system/app/HKMC_DiPO.odex"
echo '<added/>' > "$t/root/system/etc/permissions/added.xml"
refuse 'ignored added XML' 'stock file/property' restored /data/baseline
rm "$t/root/system/etc/permissions/added.xml"
printf '%s\n/dev/block/platform/userdata /system/app/HKMC_DiPO.odex ext4 ro,relatime 0 0\n' "$stock_mounts" > "$t/root/proc/mounts"
refuse 'ignored leftover overlay bind' 'overlay target still mounted' restored /data/baseline
printf '%s\ntmpfs /system/etc/permissions tmpfs ro 0 0\n' "$stock_mounts" > "$t/root/proc/mounts"
refuse 'ignored leftover permissions bind' 'overlay target still mounted' restored /data/baseline
echo "$stock_mounts" > "$t/root/proc/mounts"
# Interfaces, modules and the hotspot profile are diagnostics: a stock boot may
# legitimately differ, so they warn instead of rejecting.
mkdir "$t/root/sys/class/net/wlan0"
echo 'dhd 700000 0 - Live 0x00000000' >> "$t/root/proc/modules"
echo softap-v2 > "$t/root/data/misc/wifi/softap.conf"
accept 'diagnostic-only differences' restored /data/baseline
grep -q 'WARN.*wlan0' "$t/out" && grep -q 'WARN.*dhd' "$t/out" && grep -q 'WARN.*softap' "$t/out" &&
    grep -q 'diag|uptime|baseline=120.50|now=' "$t/out" || { echo 'FAIL diagnostic differences not reported'; cat "$t/out"; exit 1; }
rmdir "$t/root/sys/class/net/wlan0"
echo 'snd_soc_tcc 4096 0 - Live 0x00000000' > "$t/root/proc/modules"
echo softap-v1 > "$t/root/data/misc/wifi/softap.conf"
accept 'restored again' restored /data/baseline
ln -s "$t/root/data/baseline" "$t/root/data/alias"
refuse 'accepted symlink baseline' 'arguments' restored /data/alias
mkdir "$t/root/data/oldformat"
cp "$t/root/data/baseline/system.sha256" "$t/root/data/baseline/properties" "$t/root/data/baseline/boot" "$t/root/data/oldformat/"
refuse 'accepted baseline without wifi_ap_on' 'baseline unavailable' restored /data/oldformat
# A stock baseline may itself have the AP restore flag set or an OEM mount on a
# target path. Record it with a warning; compare against it rather than reject.
echo 1 > "$PROPS/setting.wifi_ap_on"
printf '%s\n/dev/block/platform/oem /system/etc/permissions ext4 ro 0 0\n' "$stock_mounts" > "$t/root/proc/mounts"
accept 'baseline with AP restore flag' snapshot /data/baseline-on
grep -q 'WARN.*wifi_ap_on' "$t/out" || { echo 'FAIL wifi_ap_on=1 baseline not flagged'; cat "$t/out"; exit 1; }
echo boot3 > "$PROPS/boot"
accept 'restored to a baseline with legitimate states' restored /data/baseline-on
echo 0 > "$PROPS/setting.wifi_ap_on"
refuse 'ignored wifi_ap_on cleared versus baseline' 'wifi_ap_on' restored /data/baseline-on
echo "$stock_mounts" > "$t/root/proc/mounts"
echo 'PASS validation: byte-identical probe, boot identity, stock/property/XML, wifi_ap_on, overlay mounts and diagnostics'

# probe-loaded: a pending overlay whose journaled /data copy is what DiPO maps.
probe=$t/root/data/probe
overlay=$t/root/data/local/gen5w-portable/overlay
files=$t/root/data/data/com.daudio.app.dipo/files
mv "$t/root/system/app/HKMC_DiPO.odex" "$t/stock.odex"
# A hard link stands in for the bind mount: target and source share dev:ino.
ln "$probe/dipo.odex" "$t/root/system/app/HKMC_DiPO.odex"
mapping() { python3 -c 'import os,sys;s=os.stat(sys.argv[1]);print("%02x:%02x %d"%(os.major(s.st_dev),os.minor(s.st_dev),s.st_ino))' "$1"; }
mkdir -p "$overlay" "$files" "$t/root/proc/42"
probe_setup() {
    cp "$probe/manifest" "$overlay/manifest"
    echo pending > "$overlay/state"
    echo boot3 > "$overlay/boot"
    echo "/system/app/HKMC_DiPO.odex|$("$t/helper" identity "$probe/dipo.odex")" > "$overlay/journal"
    printf 'pid=42\nstart=777\nmonotonic=1.000\nmode=no-hooks\nboot_id=boot3\n' > "$files/gen5w-portable-probe"
    printf 'com.daudio.app.dipo\0' > "$t/root/proc/42/cmdline"
    echo '42 (app_process) S 1 42 42 0 -1 4194560 100 0 0 0 1 1 0 0 20 0 10 0 777 123456 100' > "$t/root/proc/42/stat"
    echo '120 20 8:32 /data/probe/dipo.odex /system/app/HKMC_DiPO.odex ro,relatime - ext4 /dev/block/platform/userdata rw' > "$t/root/proc/42/mountinfo"
    {
        echo "40000000-40001000 r--p 00000000 $(mapping "$probe/dipo.odex") /system/app/HKMC_DiPO.odex"
        echo '40100000-40101000 r-xp 00000000 08:20 991 /data/nemesis/apps/gen5w.kr.portable/dalvik/libgen5whook.so'
        echo '40200000-40201000 rw-p 00000000 00:00 0'
    } > "$t/root/proc/42/maps"
}
probe_setup
accept 'probe loaded' probe-loaded
grep -q '^PASS' "$t/out" || { echo 'FAIL no PASS line'; cat "$t/out"; exit 1; }
# Overlay absent: the stock ODEX inode is mapped and identical on both sides.
rm "$t/root/system/app/HKMC_DiPO.odex"; cp "$t/stock.odex" "$t/root/system/app/HKMC_DiPO.odex"
echo "40000000-40001000 r--p 00000000 $(mapping "$t/root/system/app/HKMC_DiPO.odex") /system/app/HKMC_DiPO.odex" > "$t/root/proc/42/maps"
echo '40100000-40101000 r-xp 00000000 08:20 991 /data/nemesis/apps/gen5w.kr.portable/dalvik/libgen5whook.so' >> "$t/root/proc/42/maps"
refuse 'accepted unmounted stock inode' 'not the journaled /data probe copy' probe-loaded
rm "$t/root/system/app/HKMC_DiPO.odex"; ln "$probe/dipo.odex" "$t/root/system/app/HKMC_DiPO.odex"
probe_setup
for state in committed prepared failed; do
    echo "$state" > "$overlay/state"
    refuse "accepted $state overlay" 'not pending' probe-loaded
done
probe_setup; rm "$overlay/state"
refuse 'accepted missing overlay state' 'overlay state unavailable' probe-loaded
probe_setup; echo boot2 > "$overlay/boot"
refuse 'accepted overlay from another boot' 'overlay was not applied in this boot' probe-loaded
probe_setup; echo '/system/app/HKMC_DiPO.odex|1:2' > "$overlay/journal"
refuse 'accepted wrong journal identity' 'not the journaled /data probe copy' probe-loaded
probe_setup; echo '/system/app/HKMC_GPM.odex|'"$("$t/helper" identity "$probe/dipo.odex")" > "$overlay/journal"
refuse 'accepted wrong journal target' 'not the journaled /data probe copy' probe-loaded
probe_setup; sed 's/|static$/|static/; s/^probe|\([^|]*\)|\([^|]*\)|[0-9a-f]*|/probe|\1|\2|'"$(printf 'a%.0s' $(seq 64))"'|/' "$probe/manifest" > "$overlay/manifest"
refuse 'accepted non-prepared digest' 'prepare-probe' probe-loaded
probe_setup; { cat "$probe/manifest"; cat "$probe/manifest"; } > "$overlay/manifest"
refuse 'accepted multi-row overlay' 'exactly the probe row' probe-loaded
probe_setup; cp "$probe/dipo.odex" "$t/saved.odex"; echo patched >> "$probe/dipo.odex"
refuse 'accepted non-identical copy' 'differ from the prepared stock digest' probe-loaded
cat "$t/saved.odex" > "$probe/dipo.odex"
probe_setup; sed -i 's/^\(40000000-40001000 r--p 00000000 \)[0-9a-f]*:[0-9a-f]*/\1ff:ff/' "$t/root/proc/42/maps"
refuse 'accepted inode on another device' 'has not mapped' probe-loaded
probe_setup; sed -i '/libgen5whook/d' "$t/root/proc/42/maps"
refuse 'accepted unloaded probe library' 'library' probe-loaded
probe_setup; : > "$t/root/proc/42/mountinfo"
refuse 'accepted bind outside DiPO namespace' 'mount namespace' probe-loaded
probe_setup; sed -i 's/ 777 / 778 /' "$t/root/proc/42/stat"
refuse 'accepted reused PID' 'same process' probe-loaded
probe_setup; printf 'pid=42\nmonotonic=1.000\nmode=no-hooks\nboot_id=boot3\n' > "$files/gen5w-portable-probe"
refuse 'accepted marker without process identity' 'start identity' probe-loaded
probe_setup; printf 'app_process\0' > "$t/root/proc/42/cmdline"
refuse 'accepted non-DiPO process' 'DiPO process' probe-loaded
probe_setup; : > "$t/root/proc/42/maps"
refuse 'accepted unmapped ODEX' 'has not mapped' probe-loaded
probe_setup; echo boot4 > "$PROPS/boot"
refuse 'accepted stale probe marker' 'not from this boot' probe-loaded
echo 'PASS real-loader checks: pending journaled byte-identical overlay, dev:ino mapping, library, namespace, PID identity and stale/missing refusal'
