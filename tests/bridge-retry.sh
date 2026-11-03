#!/bin/sh
set -eu
. packages/wireless-bridge/scripts/retry-state.sh
retry_init
retry_action dead; [ "$RETRY_ACTION" = start ]
retry_action dead; [ "$RETRY_ACTION" = start ]
retry_action dead; [ "$RETRY_ACTION" = start ]
retry_action dead; [ "$RETRY_ACTION" = blocked ]
retry_init
retry_action dead; [ "$RETRY_ACTION" = start ]
retry_action healthy; [ "$RETRY_ACTION" = healthy ]
retry_action dead; [ "$RETRY_ACTION" = start ]
retry_action dead; [ "$RETRY_ACTION" = start ]
retry_action dead; [ "$RETRY_ACTION" = blocked ]
retry_init
retry_action dead
for i in 1 2 3 4 5 6; do retry_action healthy; done
retry_action dead; [ "$RETRY_ACTION" = start ]
retry_action dead; [ "$RETRY_ACTION" = start ]
retry_action dead; [ "$RETRY_ACTION" = start ]
retry_action dead; [ "$RETRY_ACTION" = blocked ]
echo 'retry budget: passed'
