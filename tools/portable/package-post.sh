#!/system/bin/sh
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
BOOT=$(cat /proc/sys/kernel/random/boot_id) || exit 1
case "$BOOT" in ''|*[!a-f0-9-]*) exit 1;; esac
PLAN=/data/local/gen5w-portable/plan-$BOOT-$$
# APK installation was completed by NEMESIS before this hook.
/system/bin/sh "$BASE/prepare.sh" "$PLAN" || exit 1
# Candidate admission is explicit and radio-off; promote to automatic only
# after the one-visit checklist succeeds.
[ ! -L /data/nemesis/gen5wkr.ui-wireless-off ] || exit 1
: > /data/nemesis/gen5wkr.ui-wireless-off || exit 1
/system/bin/sh "$BASE/boot.sh" arm --trial "$PLAN/manifest" || exit 1
echo "portable install: local plan=$PLAN; one-shot radio-off trial starts on next boot; permanent mode requires post-vehicle re-arm"
