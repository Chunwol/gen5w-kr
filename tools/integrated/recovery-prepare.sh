#!/system/bin/sh
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
"${IT_SHELL:-/system/bin/sh}" ./recovery.sh prepare
