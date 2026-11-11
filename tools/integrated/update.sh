#!/system/bin/sh
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
. ./common.sh
OP_LABEL=업데이트
acquire && install_transaction
