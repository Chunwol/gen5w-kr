#!/system/bin/sh
# One retry budget per caller; reset only after six consecutive healthy checks.
retry_init() { RETRY_COUNT=0; RETRY_STABLE=0; RETRY_ACTION=; }
retry_action() {
    if [ "$1" = healthy ]; then
        RETRY_STABLE=$((RETRY_STABLE + 1))
        [ "$RETRY_STABLE" -lt 6 ] || RETRY_COUNT=0
        RETRY_ACTION=healthy
    else
        RETRY_STABLE=0
        if [ "$RETRY_COUNT" -ge 3 ]; then RETRY_ACTION=blocked
        else RETRY_COUNT=$((RETRY_COUNT + 1)); RETRY_ACTION=start; fi
    fi
}
