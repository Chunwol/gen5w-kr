#!/system/bin/sh
# Saves the car's own reminder values once, so removal can put them back.
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
[ ! -L "$STATE" ] && [ ! -L "$ORIG" ] || exit 1
mkdir -p "$STATE" && chmod 755 "$STATE" || exit 1
rm -f "$STOPPING"
if [ ! -f "$ORIG" ]; then
    : > "$ORIG.tmp" || exit 1
    if [ -f "$PREFS" ] && [ ! -L "$PREFS" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            # never keep our own far-future time as the "original"
            case "$line" in *"value=\"$FAR\""*) continue;; esac
            if reminder_line "$line"; then print -r -- "$line"; fi
        done < "$PREFS" > "$ORIG.tmp" || exit 1
    fi
    chmod 644 "$ORIG.tmp" && mv "$ORIG.tmp" "$ORIG" || exit 1
fi
log 'INSTALLED bluelink: original reminder values saved; the service hides the reminder after boot'
exit 0
