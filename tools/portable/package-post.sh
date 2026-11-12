#!/system/bin/sh
BASE=${0%/*}
BOOT=$(cat /proc/sys/kernel/random/boot_id) || exit 1
case "$BOOT" in ''|*[!a-f0-9-]*) exit 1;; esac
PLAN=/data/local/gen5w-portable/plan-$BOOT-$$
# APK installation was completed by NEMESIS before this hook.
/system/bin/sh "$BASE/prepare.sh" "$PLAN" || exit 1
/system/bin/sh "$BASE/boot.sh" arm "$PLAN/manifest" || exit 1
echo "portable install: local plan=$PLAN; automatic activation starts on next boot"
