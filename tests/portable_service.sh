#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
command -v mksh >/dev/null 2>&1 || { echo 'mksh not found'; exit 78; }
t=$(mktemp -d)
trap 'rc=$?; rm -rf "$t"; exit $rc' EXIT
pkg=$t/package; root=$t/root; actions=$t/actions
mkdir -p "$pkg" "$root/data/local/gen5w-portable/boot" "$actions"
cp tools/portable/service.sh "$pkg/service.sh"
touch "$pkg/persistent-start.sh" "$pkg/boot.sh"
cat > "$t/adapter" <<'SH'
#!/bin/sh
set -eu
actions=$PORTABLE_TEST_ACTIONS
script=$1; shift
case "${script##*/}:$*" in
    persistent-start.sh:run)
        echo persistent-run >> "$actions/log"
        if [ -e "$PORTABLE_TEST_ROOT/data/local/gen5w-portable/persistent/recovery/manifest" ]; then
            exit "${PORTABLE_TEST_START_RC:-0}"
        fi
        exit 3;;
    boot.sh:run) echo legacy-run >> "$actions/log";;
    *) echo "unexpected dispatch: $script $*" >&2; exit 42;;
esac
SH
chmod +x "$t/adapter"
run() {
    PORTABLE_TEST_ROOT="$root" PORTABLE_TEST_SH="$t/adapter" PORTABLE_TEST_ACTIONS="$actions" \
        PORTABLE_TEST_START_RC="${PORTABLE_TEST_START_RC:-0}" mksh "$pkg/service.sh"
}

# Absence is the sole legacy sentinel.
run
[ "$(cat "$actions/log")" = "$(printf 'persistent-run\nlegacy-run')" ]

# A present recovery manifest selects only the persistent runner, even when it
# fails; never fall back to the zygote-restarting legacy path.
mkdir -p "$root/data/local/gen5w-portable/persistent/recovery"
: > "$root/data/local/gen5w-portable/persistent/recovery/manifest"
: > "$root/data/local/gen5w-portable/boot/enabled"
printf '1\n' > "$root/data/local/gen5w-portable/boot/enabled"
: > "$actions/log"
run
[ "$(cat "$actions/log")" = persistent-run ]
: > "$actions/log"
if PORTABLE_TEST_START_RC=1 run >/dev/null 2>&1; then echo 'FAIL persistent service error was hidden'; exit 1; fi
[ "$(cat "$actions/log")" = persistent-run ]

# A linked manifest is unsafe state and must not select either startup path.
rm "$root/data/local/gen5w-portable/persistent/recovery/manifest"
ln -s "$t/missing-manifest" "$root/data/local/gen5w-portable/persistent/recovery/manifest"
: > "$actions/log"
if run >/dev/null 2>&1; then echo 'FAIL linked persistent manifest was accepted'; exit 1; fi
[ ! -s "$actions/log" ]
echo 'PASS service selects legacy only for absent recovery state and fails closed for persistent state'
