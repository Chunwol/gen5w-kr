#!/bin/bash
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
setup() {
 W=$(mktemp -d); stubs; mkdir -p "$W/sys/etc/permissions" "$W/sys/app" "$W/sys/priv-app" "$W/data"
 echo 'carplay_wireless ConnectivitySSID' > "$W/sys/app/HKMC_DiPO.odex"
 echo 'persist.ium.support=stock' > "$W/sys/build.prop"
 echo stock > "$W/props/persist.ium.support"
 echo '#!/bin/sh' > "$W/bin/dmesg"; echo 'echo "Firmware up"' >> "$W/bin/dmesg"; chmod +x "$W/bin/dmesg"
 cp -r "$ROOT/packages/$1" "$W/app"
 if [ "$1" = wireless-enable ]; then
  echo 'wifi_client_wanted() { return 0; }' >> "$W/app/scripts/common.sh"
  echo 1 > "$W/props/persist.wifi.state"
 fi
 (cd "$W/sys" && find . -type f -exec md5sum {} + | sort -k2) > "$W/before"
}
run() { (cd "$W/app" && PATH="$W/bin:$PATH" EN_TEST_SYS="$W/sys" EN_TEST_DATA="$W/data" EN_TEST_NEM="$W/nemesis" mksh "scripts/$1" > "$W/out" 2>&1); }
same() { diff "$W/before" <(cd "$W/sys" && find . -type f -exec md5sum {} + | sort -k2) >/dev/null; }
for module in wireless; do
 setup wireless-enable; target="$W/sys/build.prop"
 # A reboot during preparation leaves only our unsealed journal; no target was changed.
 mkdir -p "$W/sys/etc/gen5w-kr-backup/$module"
 echo gen5w.kr.$module > "$W/sys/etc/gen5w-kr-backup/$module/owner"
 echo planning > "$W/sys/etc/gen5w-kr-backup/$module/phase"
 echo partial > "$W/sys/etc/gen5w-kr-backup/$module/manifest"
 check "$module interrupted planning retry" eval 'run pre.sh && run post.sh'
 check "$module durable backup" test -s "$W/sys/etc/gen5w-kr-backup/$module/manifest"
 state="$W/sys/etc/gen5w-kr-backup/$module"
 cp "$state/1.applied" "$W/payload.saved"; echo corrupt >> "$state/1.applied"
 check "$module rejects corrupt recovery payload" eval '! run preun.sh'
 cp "$W/payload.saved" "$state/1.applied"
 if [ "$module" = wireless ]; then
  cp "$state/runtime.ium" "$W/runtime.saved"; echo changed >> "$state/runtime.ium"
  check 'rejects changed runtime recovery value' eval '! run preun.sh'
  cp "$W/runtime.saved" "$state/runtime.ium"
  check 'wifi runtime opt-in applied' test "$(cat "$W/props/persist.wifi.state")" = 3
 fi
 rm -rf "$W/data"; mkdir "$W/data"
 check "$module reset reinstall" eval 'run pre.sh && run post.sh'
 cp "$target" "$W/applied"; echo foreign >> "$target"
 check "$module refuses changed uninstall" eval '! run preun.sh'
 check "$module preserves foreign contents" grep -q foreign "$target"
 cp "$W/applied" "$target"
 check "$module restore after reset" run preun.sh
 check "$module byte identical" same
 if [ "$module" = wireless ]; then
  check 'runtime property restored' test "$(cat "$W/props/persist.ium.support")" = stock
  check 'wifi runtime property restored after reset' test "$(cat "$W/props/persist.wifi.state")" = 1
 fi
done
done_tests recovery
