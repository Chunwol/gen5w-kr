#!/system/bin/sh
# Test-only deterministic interleaving of two stale-lock reclaimers.
cd "$RACE_USB" || exit 1
. ./common.sh
kill() {
    if [ "$2" = 99999999 ]; then
        if [ "$RACE_ROLE" = one ]; then
            : > "$RACE_DIR/one-read"
            while [ ! -f "$RACE_DIR/two-read" ] && [ ! -f "$RACE_DIR/two-done" ]; do sleep 0.05; done
        else
            : > "$RACE_DIR/two-read"
            while [ ! -d "$RACE_DIR/critical" ]; do sleep 0.05; done
        fi
        return 1
    fi
    builtin kill "$@"
}
if acquire; then
    if mkdir "$RACE_DIR/critical" 2>/dev/null; then
        : > "$RACE_DIR/$RACE_ROLE-entered"
        sleep 2
        rmdir "$RACE_DIR/critical"
    else : > "$RACE_DIR/overlap"; fi
fi
: > "$RACE_DIR/$RACE_ROLE-done"
