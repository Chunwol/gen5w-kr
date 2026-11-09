#!/bin/bash
# Runs every mock test. The shell-package tests need mksh: used directly when
# present, otherwise run through WSL automatically (Git Bash on Windows has no
# mksh). Python and JVM tests run on the host at the same time.
# TEST_JOBS sets the parallelism (default: CPU count).
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/gen5w-run.XXXXXX") || exit 1

shell_mode=skip
if command -v mksh >/dev/null 2>&1; then
    shell_mode=local
elif command -v wsl.exe >/dev/null 2>&1 && wsl.exe -e sh -c 'command -v mksh' >/dev/null 2>&1; then
    shell_mode=wsl
fi

case $shell_mode in
local) ( bash tests/run-shell.sh >"$out/shell.out" 2>&1; echo $? >"$out/shell.rc" ) & ;;
wsl)
    root=$(pwd -W 2>/dev/null || pwd)
    wslroot=$(printf '%s' "$root" | sed 's#^\([A-Za-z]\):#/mnt/\L\1#')
    ( wsl.exe -e bash -c "cd '$wslroot' && ${TEST_JOBS:+TEST_JOBS=$TEST_JOBS} bash tests/run-shell.sh" 2>&1 | tr -d '\r\0' >"$out/shell.out"
      echo "${PIPESTATUS[0]}" >"$out/shell.rc" ) & ;;
esac

python_tests="tests/unit_commands.py tests/source_revision.py tests/mkpkg_import.py tests/iap2_control.py tests/bt_recipe.py tests/dipo_control.py tests/dipo_relay_structure.py tests/dipo_relay_builder.py tests/v039_bt_adapter.py tests/gpm_control.py tests/fastboot_recovery.py tests/recovery_usb.py"
python_tests="$python_tests tests/hotspot_control.py tests/gpm_guard_builder.py tools/diagnostics/sync.py"
have_jdk=0
command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1 && have_jdk=1
[ "$have_jdk" = 1 ] && python_tests="tests/core_lifecycle.py tests/core_recovery.py tests/dipo_relay_runtime.py tests/gpm_usb_guard_runtime.py $python_tests"

( bash tests/par.sh python3 $python_tests >"$out/py.out" 2>&1; echo $? >"$out/py.rc" ) &
( bash tests/java.sh >"$out/jvm.out" 2>&1; echo $? >"$out/jvm.rc" ) &
wait

rc=0
echo "== shell package tests ($shell_mode)"
if [ "$shell_mode" = skip ]; then
    echo "SKIP (environment): mksh not found locally or in WSL; shell tests did not run"
    rc=1
else
    cat "$out/shell.out"
    [ "$(cat "$out/shell.rc")" = 0 ] || rc=1
fi
echo "== Python tests"
[ "$have_jdk" = 1 ] || echo "SKIP core_lifecycle.py (need both javac and java)"
cat "$out/py.out"
[ "$(cat "$out/py.rc")" = 0 ] || rc=1
echo "== JVM tests (HUD and probe)"
cat "$out/jvm.out"
jvm_rc=$(cat "$out/jvm.rc")
[ "$jvm_rc" = 0 ] || [ "$jvm_rc" = 77 ] || rc=1
rm -rf "$out"

if [ $rc != 0 ]; then echo "SOME TESTS FAILED"
elif [ "$jvm_rc" = 77 ]; then echo "SHELL TESTS PASSED; JVM TESTS SKIPPED (run tests/java.sh with a JDK)"
else echo "ALL TESTS PASSED"
fi
exit $rc
