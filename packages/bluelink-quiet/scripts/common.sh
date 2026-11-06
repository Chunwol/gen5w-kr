# Shared by the Bluelink reminder scripts. mksh + Android toolbox only.
# Writes no system file: only the two reminder values in the Bluelink
# service's own settings file.
#
# The stock Bluelink setup app (HKMC_TAppVRM) shows "서비스 가입 안내" to
# cars without a subscription. Its "30 일간 보지 않기" button saves the time
# it was pressed (extra_remind_time) in this settings file, and the app shows
# the screen again once 29 days have passed since that time. That time is
# read only for this decision (checked in the stock V039 apps below), so a
# time far in the future keeps the screen hidden. Subscribing works as usual:
# a subscribed car never reaches this check, and signing up runs from
# [블루링크 설정] > [서비스 설정] > [가입].
DATA=${BL_TEST_DATA:-/data}
SYS=${BL_TEST_SYS:-/system}
PREFS_DIR=$DATA/data/com.hkmc.telematics.service/shared_prefs
PREFS=$PREFS_DIR/shard_service_activation_start_setting.xml
TMP=$PREFS_DIR/.gen5w-bluelink.tmp
STATE=$DATA/nemesis/gen5wkr.bluelink
ORIG=$STATE/orig-lines
STOPPING=$STATE/stopping
# Set from the in-car screen: the original reminder values are put back and kept.
UI_OFF=$DATA/nemesis/gen5wkr.ui-bluelink-off
# 2100-01-01 00:00 UTC in milliseconds
FAR=4102444800000
# md5 of the stock V039 odex files, taken from the official V039 system image (system.ext4).
VRM_V039=${BL_TEST_VRM_MD5:-5689fb31a761a5696eb2bbe0801a0f77}
SERVICE_V039=${BL_TEST_SERVICE_MD5:-0778d4b95ee51a97a555aec4fdcc6c3f}
log() { echo "$1"; }
file_md5() { local _l; _l=$(md5 "$1" 2>/dev/null) || return 1; set -- $_l; echo "$1"; }
# The reminder logic above was read from these exact stock builds only.
stock_apps() {
    [ "$(file_md5 "$SYS/app/HKMC_TAppVRM.odex")" = "$VRM_V039" ] &&
    [ "$(file_md5 "$SYS/app/HKMC_TAppService.odex")" = "$SERVICE_V039" ]
}
reminder_line() { case "$1" in *'name="extra_remind_time"'*|*'name="extra_remind_value"'*) return 0;; esac; return 1; }
hidden() {
    [ -f "$PREFS" ] &&
    grep -q "name=\"extra_remind_time\" value=\"$FAR\"" "$PREFS" &&
    grep -q 'name="extra_remind_value" value="true"' "$PREFS"
}
# write_prefs hide | write_prefs restore <file with the original lines>
# Rewrites the settings file keeping every other line; owner stays system.
write_prefs() {
    local line
    [ -d "$PREFS_DIR" ] && [ ! -L "$PREFS_DIR" ] && [ ! -L "$PREFS" ] && [ ! -L "$TMP" ] || return 1
    if [ -e "$PREFS" ]; then
        # Only an Android settings map; anything else is left alone.
        [ -f "$PREFS" ] && grep -q '<map' "$PREFS" || return 1
    fi
    rm -f "$TMP"
    {
        if [ -f "$PREFS" ]; then
            while IFS= read -r line || [ -n "$line" ]; do
                reminder_line "$line" && continue
                case "$line" in
                    *'</map>'*) ;;
                    *'<map />'*|*'<map/>'*) print -r -- '<map>';;
                    *) print -r -- "$line";;
                esac
            done < "$PREFS"
        else
            print -r -- "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>"
            print -r -- '<map>'
        fi
        if [ "$1" = hide ]; then
            print -r -- "    <long name=\"extra_remind_time\" value=\"$FAR\" />"
            print -r -- '    <boolean name="extra_remind_value" value="true" />'
        else
            while IFS= read -r line || [ -n "$line" ]; do
                if reminder_line "$line"; then print -r -- "$line"; fi
            done < "$2"
        fi
        print -r -- '</map>'
    } > "$TMP" || { rm -f "$TMP"; return 1; }
    chmod 660 "$TMP" &&
    { chown 1000:1000 "$TMP" 2>/dev/null || chown 1000.1000 "$TMP" 2>/dev/null; } &&
    mv "$TMP" "$PREFS" || { rm -f "$TMP"; return 1; }
}
