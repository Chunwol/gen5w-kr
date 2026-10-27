#!/system/bin/sh
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
. ./common.sh
IT_FORCE_WIRED=1
acquire && install_transaction
