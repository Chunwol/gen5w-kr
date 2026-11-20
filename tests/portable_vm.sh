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
trap 'rc=$?; rmdir "$root/tmp/portable-vm.lock"; exit $rc' EXIT
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
# The hooked VM must not rewrite dex caches made by stock VMs: V039 records the
# exact bootclasspath as cache deps, and an in-place rewrite under other mapped
# processes was the vehicle's mass SIGBUS (2026-11-13).
# Every cache file is compared (inode, size, mtime, content), not only the
# test's own; the test jar cache made by the stock VM above must exist.
[ -f "$root/data/dalvik-cache/tmp@run.jar@classes.dex" ] || { echo 'stock dex cache missing' >&2; exit 1; }
snapshot() { (cd "$root/data/dalvik-cache" && for f in *; do printf '%s %s ' "$f" "$(stat -c '%i %s %Y' "$f")"; md5sum < "$f"; done); }
before=$(snapshot)
run LoaderVmTest "$guest/loader-fixture.jar" "$guest/cache"
DVM_PRELOAD=$guest/libgen5whook.so DVM_ENV="GEN5W_ENGINE_JAR=$guest/engine.jar GEN5W_ENGINE_CACHE=$guest/application/app_gen5w-engine GEN5W_HOOK_LIBRARY=$guest/libgen5whook.so GEN5W_ADAPTER_JAR=$guest/bootstrap-fixture.jar GEN5W_PACKAGE=fixture" run BootstrapVmTest "$guest/application"
after=$(snapshot)
[ "$before" = "$after" ] || { echo 'hooked VM changed /data/dalvik-cache:' >&2; diff <(echo "$before") <(echo "$after") >&2; exit 1; }
ls "$work/application/app_gen5w-engine/" | grep -q . || { echo 'engine optimized DEX not app-private' >&2; exit 1; }
echo 'PASS hooked VM leaves every /data/dalvik-cache file untouched; engine DEX app-private (dexopt runs with -Xdexopt:none here)'
# -Xdexopt:none hides the cache rewrite itself, so check its cause directly: the
# hooked VM's live bootclasspath must equal BOOTCLASSPATH, also after opening a
# shared framework jar (2026-11-19 vehicle: a stale hook build made it 17).
DVM_PRELOAD=$guest/libgen5whook.so DVM_ENV="GEN5W_ENGINE_JAR=$guest/engine.jar GEN5W_ENGINE_CACHE=$guest/application/app_gen5w-engine GEN5W_HOOK_LIBRARY=$guest/libgen5whook.so GEN5W_ADAPTER_JAR=$guest/bootstrap-fixture.jar GEN5W_PACKAGE=fixture" \
    run BootPathVmTest /system/framework/com.tcc.iap2.jar com.tcc.iap2.IIap2Service > "$work/bootpath.out" 2>&1 || :
grep -q '^PASS bootclasspath unchanged' "$work/bootpath.out" || { echo 'hooked VM changed the bootclasspath:' >&2; cat "$work/bootpath.out" >&2; exit 1; }
echo 'PASS hooked VM keeps the stock bootclasspath and opens a shared framework jar'
mkdir -p "$root/data/data/com.daudio.app.dipo/files"
marker=$root/data/data/com.daudio.app.dipo/files/gen5w-portable-probe
[ ! -L "$marker" ] || exit 1
[ ! -e "$marker" ] || mv "$marker" "$work/previous-probe-marker"
DVM_PRELOAD=$guest/libgen5whook.so DVM_ENV='GEN5W_PROBE=1 GEN5W_PACKAGE=com.daudio.app.dipo' run LoaderVmTest "$guest/loader-fixture.jar" "$guest/cache"
grep -qx mode=no-hooks "$marker"
echo 'PASS actual ARM VM no-hook preload marker'
run AdapterDiscoveryVmTest '/system/app/HKMC_DiPO.apk:/system/framework/com.tcc.iap2.jar:/system/framework/com.broadcom.bt.jar:/system/framework/com.telechips.android.tcciap.jar' "$guest/adapter.jar" "$guest/cache"
echo 'PASS private ARM VM suite; no vehicle lifecycle, Binder or display verification claimed'
