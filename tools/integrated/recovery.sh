#!/system/bin/sh
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
. ./recovery-lib.sh
case "$1" in
    prepare) . ./common.sh; acquire && r_prepare;;
    check) r_check;;
    run) r_run "$2";;
    *) recovery_reason=unknown-operation; false;;
esac
rc=$?
echo "$recovery_reason"
exit "$rc"
