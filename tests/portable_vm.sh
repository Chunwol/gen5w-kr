#!/bin/bash
# PC-only private V039 VM fixtures; never included in a vehicle candidate.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${PORTABLE_VM_RUNNER:?private chroot runner path required}"
: "${PORTABLE_VM_ROOT:?private VM root path required}"
[ "$(id -u)" = 0 ] || { echo 'Run this PC harness as root for its private PID/mount namespace' >&2; exit 1; }
if [ "${PORTABLE_VM_ISOLATED:-}" != 1 ]; then
    exec unshare --mount --pid --fork --mount-proc env PORTABLE_VM_ISOLATED=1 bash "$0"
fi
root=$(realpath "$PORTABLE_VM_ROOT")
[ -d "$root/system" ] && [ -x "$PORTABLE_VM_RUNNER" ] || exit 1
mount -t proc proc "$root/proc"
mkdir "$root/tmp/portable-vm.lock" || { echo 'another private VM test is active' >&2; exit 1; }
trap 'rmdir "$root/tmp/portable-vm.lock"' EXIT
work=$(mktemp -d "$root/tmp/portable-vm.XXXXXX")
guest=${work#"$root"}
build=${PORTABLE_VM_BUILD:-$PWD/.build/portable/dalvik}
for file in engine.jar adapter.jar libgen5whook.so hook-vm-test.jar loader-fixture.jar bootstrap-fixture.jar; do cp "$build/$file" "$work/"; done
mkdir "$work/cache" "$work/application"
# qemu has no ashmem driver; the private runner supplies its PC-only ashmem shim.
# Avoid invoking dexopt subprocesses; Java bytecode verification stays enabled.
export DVM_OPTS='-Xint -Xdexopt:none'
run() { timeout -k 2 30 "$PORTABLE_VM_RUNNER" "$work/hook-vm-test.jar" "$@"; }
run HookVmTest "$guest/libgen5whook.so"
run LoaderVmTest "$guest/loader-fixture.jar" "$guest/cache"
DVM_PRELOAD=$guest/libgen5whook.so DVM_ENV="GEN5W_ENGINE_JAR=$guest/engine.jar GEN5W_HOOK_LIBRARY=$guest/libgen5whook.so GEN5W_ADAPTER_JAR=$guest/bootstrap-fixture.jar GEN5W_PACKAGE=fixture" run BootstrapVmTest "$guest/application"
mkdir -p "$root/data/data/com.daudio.app.dipo/files"
marker=$root/data/data/com.daudio.app.dipo/files/gen5w-portable-probe
[ ! -L "$marker" ] || exit 1
[ ! -e "$marker" ] || mv "$marker" "$work/previous-probe-marker"
DVM_PRELOAD=$guest/libgen5whook.so DVM_ENV='GEN5W_PROBE=1 GEN5W_PACKAGE=com.daudio.app.dipo' run LoaderVmTest "$guest/loader-fixture.jar" "$guest/cache"
grep -qx mode=no-hooks "$marker"
echo 'PASS actual ARM VM no-hook preload marker'
run AdapterDiscoveryVmTest '/system/app/HKMC_DiPO.apk:/system/framework/com.tcc.iap2.jar:/system/framework/com.broadcom.bt.jar:/system/framework/com.telechips.android.tcciap.jar' "$guest/adapter.jar" "$guest/cache"
echo 'PASS private ARM VM suite; no vehicle lifecycle, Binder or display verification claimed'
