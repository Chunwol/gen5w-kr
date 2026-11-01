#!/bin/bash
# Firmware reinstall: /system goes back to stock (our backups in /system/etc go
# with it) while /data keeps NEMESIS registrations, our runtime copies and persist
# properties. Removal must then clean the leftovers and restore the persist
# properties, and a new install must work again.
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)

# --- wireless-enable ---------------------------------------------------------
setup_wireless() {
 W=$(mktemp -d); stubs; mkdir -p "$W/sys/etc/permissions" "$W/sys/app" "$W/sys/priv-app" "$W/data"
 echo 'carplay_wireless ConnectivitySSID' > "$W/sys/app/HKMC_DiPO.odex"
 echo 'persist.ium.support=stock' > "$W/sys/build.prop"
 echo stock > "$W/props/persist.ium.support"
 echo 1 > "$W/props/persist.wifi.state"
 echo '#!/bin/sh' > "$W/bin/dmesg"; echo 'echo "Firmware up"' >> "$W/bin/dmesg"; chmod +x "$W/bin/dmesg"
 cp -r "$ROOT/packages/wireless-enable" "$W/app"
 echo 'wifi_client_wanted() { return 0; }' >> "$W/app/scripts/common.sh"
 cp -a "$W/sys" "$W/stock"
}
wrun() { (cd "$W/app" && PATH="$W/bin:$PATH" EN_TEST_SYS="$W/sys" EN_TEST_DATA="$W/data" EN_TEST_NEM="$W/nemesis" mksh "scripts/$1" > "$W/out" 2>&1); }
reinstall_system() { rm -rf "$W/sys"; cp -a "$W/stock" "$W/sys"; }
stock_tree() { diff -r "$W/stock" "$W/sys" >/dev/null; }

setup_wireless
check 'wireless install' eval 'wrun pre.sh && wrun post.sh'
check 'wireless runtime properties applied' eval 'test "$(cat "$W/props/persist.ium.support")" = carplay && test "$(cat "$W/props/persist.wifi.state")" = 3'
reinstall_system
check 'wireless removal after system reinstall' wrun preun.sh
check 'wireless removal leaves stock system untouched' stock_tree
check 'wireless removal restores persist.ium.support' test "$(cat "$W/props/persist.ium.support")" = stock
check 'wireless removal restores persist.wifi.state' test "$(cat "$W/props/persist.wifi.state")" = 1
check 'wireless removal clears the data copy' test ! -e "$W/data/nemesis/backup/gen5w.kr.wireless"

setup_wireless
check 'wireless install (2)' eval 'wrun pre.sh && wrun post.sh'
reinstall_system
check 'wireless reinstall after system reinstall' eval 'wrun pre.sh && wrun post.sh'
check 'wireless reinstall records the stock property as original' test "$(cat "$W/sys/etc/gen5w-kr-backup/wireless/runtime.ium")" = stock
check 'wireless removal after reinstall' wrun preun.sh
check 'wireless removal is byte identical' stock_tree
check 'wireless removal restores stock property' test "$(cat "$W/props/persist.ium.support")" = stock

# A wireless change that is still live without its durable journal is not ours
# to discard.
setup_wireless
check 'wireless install (3)' eval 'wrun pre.sh && wrun post.sh'
cp "$W/sys/build.prop" "$W/applied.bp"; reinstall_system; cp "$W/applied.bp" "$W/sys/build.prop"
check 'live change without durable journal is refused' eval '! wrun preun.sh'
check 'refusal keeps the data copy' test -d "$W/data/nemesis/backup/gen5w.kr.wireless"

# Inconclusive Wi-Fi detection after a firmware reinstall: the registration and
# runtime copy are left, but nothing on /system is ours. Skip, never fail.
setup_wireless
check 'wireless install (4)' eval 'wrun pre.sh && wrun post.sh'
reinstall_system
mkdir -p "$W/data/nemesis/apps/gen5w.kr.wireless"
printf '[nemesis]\nid=gen5w.kr.wireless\n' > "$W/data/nemesis/apps/gen5w.kr.wireless/NEMESIS.data"
printf '#!/bin/sh\n' > "$W/bin/dmesg"
check 'inconclusive detection after system reinstall skips' eval 'wrun pre.sh; [ "$?" -eq 77 ]'

done_tests system-reinstall
