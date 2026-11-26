#!/system/bin/sh
# Combined field USB: wrapper absence is not proof of a completed restore.
umask 022
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
USB=$(pwd) || exit 1
GUARD=/data/local/gen5w-portable/persistent/bootguard
REC=/data/local/gen5w-portable/persistent/recovery
for key in wrap.com.daudio.app.dipo wrap.com.google.android.project wrap.com.mnsoft.navi; do
    if [ -n "$(getprop "$key")" ]; then
        exec /system/bin/sh "$USB/NEMESIS-recover.sh"
    fi
done
if [ -e "$REC/manifest" ] || [ -L "$REC/manifest" ]; then
    OUT=$USB/GEN5W-PREINSTALL-VERIFY
    [ ! -L "$OUT" ] && mkdir -p "$OUT" || exit 1
    for name in verify.txt GEN5W-RECOVERY-RESULT.txt manifest restore.done; do
        [ ! -L "$OUT/$name" ] || exit 1
    done
    [ -f "$REC/manifest" ] && [ ! -L "$REC/manifest" ] && cp "$REC/manifest" "$OUT/manifest"
    [ ! -f "$REC/restore.done" ] || { [ ! -L "$REC/restore.done" ] && cp "$REC/restore.done" "$OUT/restore.done"; }
    GEN5W_RECOVERY_USB_ROOT=$GUARD GEN5W_RECOVERY_RESTORE_SETTINGS=1 /system/bin/sh "$USB/recovery-restore.sh" --verify-only > "$OUT/verify.txt" 2>&1
    rc=$?
    [ ! -f "$GUARD/GEN5W-RECOVERY-RESULT.txt" ] || { [ ! -L "$GUARD/GEN5W-RECOVERY-RESULT.txt" ] && cp "$GUARD/GEN5W-RECOVERY-RESULT.txt" "$OUT/"; }
    sync
    if [ "$rc" != 0 ]; then
        echo 'field USB: original state incomplete; run recovery, not installation' >&2
        exec /system/bin/sh "$USB/NEMESIS-recover.sh"
    fi
fi
exec /system/bin/sh "$USB/NEMESIS-install.sh"
