# Restore-only migration; never creates a notice-disabling feature.
SYS=${SKIP_TEST_SYS:-/system}
DATA=${SKIP_TEST_DATA:-/data}
NEM=${SKIP_TEST_NEM:-/system/xbin/nemesis}
TARGET=$SYS/etc/permissions/com.mobis.feature.remove_consentscreen.xml
MARK=$DATA/nemesis/backup/gen5w.kr.consent
log() { echo "$1"; }
file_md5() {
    local line
    line=$(md5 "$1" 2>/dev/null) || line=$(md5sum "$1" 2>/dev/null) || return 1
    set -- $line
    [ -n "$1" ] || return 1
    echo "$1"
}
. ./scripts/recovery.sh
