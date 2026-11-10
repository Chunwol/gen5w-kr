# shared helpers for the mock tests (bash, run in WSL/Linux; scripts under test run in mksh)
# WSL appends the Windows PATH (/mnt/c/...). Looking up a command the mock unit does not
# have then walks that slow mount for every call; the tests never need those entries.
case "$PATH" in
    */mnt/*) PATH=$(printf '%s\n' "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | paste -sd: -); export PATH ;;
esac
PASS=0; FAIL=0
ok()  { echo "PASS $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL $1"; FAIL=$((FAIL+1)); }
check() {
    local name=$1 t0=$SECONDS; shift
    if "$@"; then ok "$name"; else bad "$name"; fi
    # TEST_TIMING=1 lists the checks that take 2 s or more.
    if [ -n "${TEST_TIMING:-}" ] && [ $((SECONDS - t0)) -ge 2 ]; then echo "SLOW $((SECONDS - t0))s $name"; fi
    return 0
}
# stub bin dir: getprop/setprop read/write files in $W/props, am/nemesis log to $W/calls
stubs() {
    mkdir -p "$W/bin" "$W/props"
    printf '#!/bin/sh\ncat "%s/props/$1" 2>/dev/null\n' "$W" > "$W/bin/getprop"
    printf '#!/bin/sh\necho "$2" > "%s/props/$1"\n' "$W" > "$W/bin/setprop"
    printf '#!/bin/sh\necho "am $*" >> %s/calls\n' "$W" > "$W/bin/am"
    printf '#!/bin/sh\nmd5sum "$1" 2>/dev/null || exit 1\n' > "$W/bin/md5"
    printf '#!/bin/sh\ncase "$1" in version) echo 1.16.3; exit 0;; esac\necho "nemesis $*" >> %s/calls\nexit ${NEMFAIL:-0}\n' "$W" > "$W/nemesis"
    chmod +x "$W/bin/"* "$W/nemesis"; : > "$W/calls"
}
done_tests() {
    unit_shim_report || FAIL=$((FAIL+1))
    unit_shim_cleanup
    echo "== $1: $PASS passed, $FAIL failed"; [ $FAIL = 0 ]
}
# Scripts under test see only the head unit's commands and toolbox options.
. "$(dirname "${BASH_SOURCE[0]}")/unit/shim.sh"
unit_shim_setup || { echo "FAIL could not set up head-unit command wrappers"; exit 1; }
