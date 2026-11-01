# shared helpers for the mock tests (bash, run in WSL/Linux; scripts under test run in mksh)
PASS=0; FAIL=0
ok()  { echo "PASS $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL $1"; FAIL=$((FAIL+1)); }
check() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
# stub bin dir: getprop/setprop read/write files in $W/props, am/nemesis log to $W/calls
stubs() {
    mkdir -p "$W/bin" "$W/props"
    printf '#!/bin/sh\ncat "%s/props/$1" 2>/dev/null\n' "$W" > "$W/bin/getprop"
    printf '#!/bin/sh\necho "$2" > "%s/props/$1"\n' "$W" > "$W/bin/setprop"
    printf '#!/bin/sh\necho "am $*" >> %s/calls\n' "$W" > "$W/bin/am"
    printf '#!/bin/sh\nmd5sum "$1" 2>/dev/null || exit 1\n' > "$W/bin/md5"
    printf '#!/bin/sh\necho "nemesis $*" >> %s/calls\nexit ${NEMFAIL:-0}\n' "$W" > "$W/nemesis"
    chmod +x "$W/bin/"* "$W/nemesis"; : > "$W/calls"
}
done_tests() { echo "== $1: $PASS passed, $FAIL failed"; [ $FAIL = 0 ]; }
