#!/system/bin/sh
# Optional developer entry; ordinary installation selects recovery automatically.
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
. ./common.sh
acquire || exit 1
case "$(cat "$TX/state" 2>/dev/null)" in applying|removing|recovering|recovery-required)
    report 'REFUSED hotspot repair: finish system recovery first'; exit 1;;
esac
[ ! -e "$NOREBOOT" ] || { report 'REFUSED hotspot repair: unresolved system operation'; exit 1; }
# Never turn the hotspot on where wireless is meant to be off.
[ "$VARIANT" != safe ] || { report 'REFUSED hotspot repair: the safe edition is wired-only'; exit 1; }
if [ -e "$WIRELESS_OFF" ] || [ -L "$WIRELESS_OFF" ] || [ -e "$DATA/nemesis/gen5wkr.apguard.off" ] || [ -L "$DATA/nemesis/gen5wkr.apguard.off" ]; then
    report 'REFUSED hotspot repair: wireless is turned off on this unit'; exit 1
fi
reset_results
auto_hotspot_recovery
