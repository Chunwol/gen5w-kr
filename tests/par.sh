#!/bin/bash
# Runs independent tests in parallel and prints one timing table.
# Usage: par.sh <interpreter> <test>...   (TEST_JOBS sets the parallelism, default: CPU count)
# Exit 0 when every test passes or skips (exit 77), 1 otherwise. A failing
# test's log is printed after the table. List slow tests first.
interp=$1; shift
JOBS=${TEST_JOBS:-$(nproc 2>/dev/null || echo 8)}
dir=$(mktemp -d "${TMPDIR:-/tmp}/gen5w-par.XXXXXX") || exit 1
export PAR_DIR=$dir PAR_INTERP=$interp
one() {
    # "tests/x.sh#2" runs tests/x.sh with IT_PART=2 (one slice of a long test).
    local item=$1 t=${1%%#*} a r log
    log="$PAR_DIR/$(basename "${item//#/_}").log"
    a=$(date +%s)
    if [ "$item" != "$t" ]; then IT_PART=${item#*#} $PAR_INTERP "$t" >"$log" 2>&1
    else $PAR_INTERP "$t" >"$log" 2>&1; fi
    r=$?
    echo "$r $(( $(date +%s) - a )) $item" >> "$PAR_DIR/_res"
}
export -f one
: > "$dir/_res"
printf '%s\n' "$@" | xargs -P "$JOBS" -I{} bash -c 'one {}'
rc=0
sort -k2,2nr "$dir/_res" | while read -r r secs t; do
    case $r in 0) s=PASS ;; 77) s=SKIP ;; *) s=FAIL ;; esac
    printf '%-4s %4ss  %s\n' "$s" "$secs" "$t"
done
while read -r r secs t; do
    [ "$r" = 0 ] || [ "$r" = 77 ] && continue
    rc=1
    echo "---- $t (exit $r) ----"
    tail -n 60 "$dir/$(basename "${t//#/_}").log"
done < "$dir/_res"
[ "$(grep -cv '^\(0\|77\) ' "$dir/_res")" = 0 ] || rc=1
rm -rf "$dir"
exit $rc
