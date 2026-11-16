#!/system/bin/sh
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
BOOT=$(cat /proc/sys/kernel/random/boot_id) || exit 1
case "$BOOT" in ''|*[!a-f0-9-]*) exit 1;; esac
PLAN=/data/local/gen5w-portable/plan-$BOOT-$$
# APK installation was completed by NEMESIS before this hook.
/system/bin/sh "$BASE/prepare.sh" "$PLAN" || exit 1
# The user explicitly selected persistent wireless operation. Clear only the
# authored UI hold; AP reset evidence and other safety inhibits are preserved.
[ ! -L /data/nemesis/gen5wkr.ui-wireless-off ] || exit 1
[ ! -e /data/nemesis/gen5wkr.ui-wireless-off ] || [ -f /data/nemesis/gen5wkr.ui-wireless-off ] || exit 1
rm -f /data/nemesis/gen5wkr.ui-wireless-off || exit 1
/system/bin/sh "$BASE/boot.sh" arm "$PLAN/manifest" || exit 1
echo "portable install: local plan=$PLAN; guarded automatic wireless operation starts on next boot; USB rescue disables it explicitly"
