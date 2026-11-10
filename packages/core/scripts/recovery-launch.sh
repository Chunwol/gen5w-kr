#!/system/bin/sh
# This installed core entry point is the trust anchor, not the recovery bundle.
case "$0" in */*) VERIFY_DIR=${0%/*};; *) exit 1;; esac
. "$VERIFY_DIR/recovery-verify.sh"
RD=${IT_DATA:-/data}/nemesis
bundle=$RD/gen5wkr.recovery/current
token=$1
case "$token" in ''|*[!0-9]*) exit 1;; esac
[ "${#token}" -le 10 ] || exit 1
rv_safe "$RD" || exit 1
valid=yes
rv_safe "$bundle" && rv_manifest "$bundle" || valid=no
for required in recovery.sh recovery-lib.sh recovery-verify.sh common.sh errors.sh report.sh history.sh services.sh; do
    [ "$valid" = yes ] || break
    [ -f "$bundle/$required" ] &&
        grep -qxF "$(rv_hash "$bundle/$required")  $required" "$bundle/RECOVERY.md5" || valid=no
done
if [ "$valid" != yes ]; then
    # One bounded diagnostic, with no unverified code executed. Do not overwrite
    # an active worker's result. A failed request is consumed to prevent loops.
    out=$RD/gen5wkr.recovery-worker.log
    [ ! -L "$out" ] && echo 'REFUSED recovery bundle verification failed' > "$out"
    out=$RD/gen5wkr.recovery-result
    if [ ! -e "$RD/gen5w-kr-integrated/lock" ] && [ ! -L "$RD/gen5w-kr-integrated/lock" ] && [ ! -L "$out" ] && [ ! -L "$out.tmp" ]; then
        { echo "recovery_request=$token"; echo 'recovery_result=failed'; echo 'recovery_reason=runner-unavailable';
            echo "recovery_boot=$(cat /proc/sys/kernel/random/boot_id)"; } > "$out.tmp" && chmod 644 "$out.tmp" && mv "$out.tmp" "$out"
    fi
    exit 1
fi
# These helpers have now been validated by the installed verifier. The pipe and
# bounded, privacy-filtered writer belong to this independent root process,
# not to the collector that recovery can remove.
. "$bundle/errors.sh"
. "$bundle/history.sh"
trap '' HUP
# Identify this independent root launcher so its bounded report-writer sibling
# survives collector quiescence along with the transaction worker.
IFS= read -r launch_stat < /proc/self/stat || exit 1
launch_pid=${launch_stat%% *}; launch_rest=${launch_stat##*) }; launch_n=0
for launch_field in $launch_rest; do
    launch_n=$((launch_n+1))
    [ "$launch_n" != 20 ] || { GEN5W_RECOVERY_ROOT=$launch_pid:$launch_field; break; }
done
[ -n "${GEN5W_RECOVERY_ROOT:-}" ] || exit 1
export GEN5W_RECOVERY_ROOT
if "${IT_SHELL:-/system/bin/sh}" "$bundle/recovery.sh" run "$token" 2>&1 | report_stream "$RD/gen5wkr.recovery-worker.log" single; then
    statuses=("${PIPESTATUS[@]}")
else statuses=("${PIPESTATUS[@]}"); fi
[ "${statuses[1]}" = 0 ] || err_event integrated export recovery-log failed "${statuses[1]}" write-failed
[ "${statuses[0]}" = 0 ] || exit "${statuses[0]}"
exit "${statuses[1]}"
