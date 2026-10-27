#!/system/bin/sh
# Optional developer entry; ordinary installation selects recovery automatically.
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
. ./common.sh
acquire || exit 1
case "$(cat "$TX/state" 2>/dev/null)" in applying|removing|recovering|recovery-required)
    report 'REFUSED hotspot repair: finish system recovery first'; exit 1;;
esac
[ ! -e "$NOREBOOT" ] || { report 'REFUSED hotspot repair: unresolved system operation'; exit 1; }
reset_results
auto_hotspot_recovery
