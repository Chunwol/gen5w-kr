#!/bin/bash
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/data/nemesis/logs" "$W/ui" "$W/bin"
printf '%s\n' '12345678-1234-1234-1234-123456789abc' > "$W/boot"
printf '100 0\n' > "$W/uptime"
printf '#!/bin/sh\nexit 0\n' > "$W/bin/getprop"
cp "$W/bin/getprop" "$W/bin/logcat"; cp "$W/bin/getprop" "$W/bin/pm"
chmod +x "$W/bin/"*
export PATH="$W/bin:$PATH"
run() {
    rm -f "$W/data/nemesis/gen5wkr.ui-wireless-off"
    UILOG_TEST_DATA=$W/data UILOG_TEST_DIR=$W/ui UILOG_TEST_REQUEST=$W/request \
      UILOG_TEST_UPTIME=$W/uptime UILOG_TEST_BOOT_ID=$W/boot UILOG_TEST_ONCE=1 \
      mksh "$ROOT/packages/core/scripts/uilog.sh" > "$W/out" 2>&1
}
printf 'wireless=off\n' > "$W/request"; run
check 'legacy request without boot/deadline is rejected' test ! -e "$W/data/nemesis/gen5wkr.ui-wireless-off"
printf 'boot=old-boot\nexpires=130\nwireless=off\n' > "$W/request"; run
check 'another boot cannot replay its request' test ! -e "$W/data/nemesis/gen5wkr.ui-wireless-off"
printf 'boot=%s\nexpires=99\nwireless=off\n' "$(cat "$W/boot")" > "$W/request"; run
check 'expired request cannot apply' test ! -e "$W/data/nemesis/gen5wkr.ui-wireless-off"
printf 'boot=%s\nexpires=131\nwireless=off\n' "$(cat "$W/boot")" > "$W/request"; run
check 'deadline beyond thirty seconds is rejected' test ! -e "$W/data/nemesis/gen5wkr.ui-wireless-off"
printf 'boot=%s\nexpires=130\nwireless=off\n' "$(cat "$W/boot")" > "$W/request"; run
check 'fresh same-boot request applies' test -e "$W/data/nemesis/gen5wkr.ui-wireless-off"
check 'status exposes current boot identity' grep -qx "boot=$(cat "$W/boot")" "$W/ui/status"
printf 'boot=%s\nboot=%s\nexpires=130\nwireless=off\n' "$(cat "$W/boot")" "$(cat "$W/boot")" > "$W/request"; run
check 'duplicate envelope fields cannot authorize actions' test ! -e "$W/data/nemesis/gen5wkr.ui-wireless-off"
printf 'boot=\nboot=%s\nexpires=130\nwireless=off\n' "$(cat "$W/boot")" > "$W/request"; run
check 'empty duplicate boot cannot bypass envelope validation' test ! -e "$W/data/nemesis/gen5wkr.ui-wireless-off"
printf 'expires=\nboot=%s\nexpires=130\nwireless=off\n' "$(cat "$W/boot")" > "$W/request"; run
check 'empty duplicate deadline cannot bypass envelope validation' test ! -e "$W/data/nemesis/gen5wkr.ui-wireless-off"
printf '23 done\n' > "$W/data/nemesis/gen5wkr.ui-removed"
printf 'boot=%s\nexpires=130\nwireless=off\nremove=23\n' "$(cat "$W/boot")" > "$W/request"; run
check 'completed removal request cannot recreate cleared switch markers' test ! -e "$W/data/nemesis/gen5wkr.ui-wireless-off"
done_tests request-envelope
