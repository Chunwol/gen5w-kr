#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/g5p-package.XXXXXX)
trap 'rm -rf "$t"' EXIT
mkdir -p "$t/package/bin" "$t/actions"
cp tools/portable/package-pre.sh "$t/package/"
cp .build/portable/dex-patch-host "$t/package/bin/dex-patch"
echo authored > "$t/package/payload"
(cd "$t/package"; sha256sum payload package-pre.sh bin/dex-patch > SHA256SUMS)
cat > "$t/adapter" <<'SH'
#!/bin/bash
case "$1" in
 version) cat "$ACTIONS/version";;
 packages) cat "$ACTIONS/packages";;
 healthy) [ ! -f "$ACTIONS/unhealthy" ];;
 installed) [ -f "$ACTIONS/existing" ];;
 retirement) cat "$ACTIONS/retirement" 2>/dev/null || echo none;;
 overlay-state) cat "$ACTIONS/overlay-state" 2>/dev/null || echo absent;;
 *) exit 1;;
esac
SH
chmod +x "$t/adapter"
export PORTABLE_TEST_PACKAGE_ADAPTER=$t/adapter ACTIONS=$t/actions
run() { mksh "$t/package/package-pre.sh"; }
# Native NEMESIS extracts all regular ZIP members as 0644, ignoring ZIP modes.
chmod 644 "$t/package/bin/dex-patch" "$t/package/package-pre.sh"
: > "$ACTIONS/packages"
echo 1.16.7 > "$ACTIONS/version"; run
[ -x "$t/package/bin/dex-patch" ] && [ -x "$t/package/package-pre.sh" ]
for version in 1.14 1.16.6 unknown 01.16.7 1.16.7.1; do
 echo "$version" > "$ACTIONS/version"
 if run >/dev/null 2>&1; then echo "FAIL accepted NEMESIS $version"; exit 1; fi
done
echo 1.16.10 > "$ACTIONS/version"; run
touch "$ACTIONS/existing"
if run >/dev/null 2>&1; then echo 'FAIL replaced another installation'; exit 1; fi
rm "$ACTIONS/existing"
for package in gen5w.kr.bridge gen5w.kr.core wireless.projection enhanced.projection projection.tbt; do
 echo "$package|existing|0|service" > "$ACTIONS/packages"
 if run >/dev/null 2>&1; then echo "FAIL ignored package conflict $package"; exit 1; fi
done
: > "$ACTIONS/packages"
echo retired-pending > "$ACTIONS/overlay-state"
echo held > "$ACTIONS/retirement"
echo 'gen5w.kr.portable|0.3.72|installed' > "$ACTIONS/packages"
run
echo active > "$ACTIONS/overlay-state"
if run >/dev/null 2>&1; then echo 'FAIL replaced portable package without a held retirement'; exit 1; fi
echo retired-pending > "$ACTIONS/overlay-state"
echo not-held > "$ACTIONS/retirement"
if run >/dev/null 2>&1; then echo 'FAIL replaced portable package without confirmed held retirement'; exit 1; fi
: > "$ACTIONS/packages"
echo absent > "$ACTIONS/overlay-state"
touch "$ACTIONS/unhealthy"
if run >/dev/null 2>&1; then echo 'FAIL installed without healthy Android'; exit 1; fi
rm "$ACTIONS/unhealthy"
echo changed > "$t/package/payload"
if run >/dev/null 2>&1; then echo 'FAIL ignored payload checksum'; exit 1; fi
echo authored > "$t/package/payload"
ln -s payload "$t/package/link"
(cd "$t/package"; sha256sum link > SHA256SUMS)
if run >/dev/null 2>&1; then echo 'FAIL accepted symlink payload'; exit 1; fi
# Vehicle 2026-11-19: NEMESIS --update removes the old app folder before this
# preinstall, so the old package state must be read with the staged scripts.
r=$t/root; stage=$r/data/local/tmp/nemesis/stage/gen5w.kr.portable
mkdir -p "$stage/bin" "$r/data/local/gen5w-portable/boot"
cp tools/portable/package-pre.sh tools/portable/boot.sh tools/portable/runtime.sh tools/portable/overlay.sh "$stage/"
cp .build/portable/dex-patch-host "$stage/bin/dex-patch"
(cd "$stage"; sha256sum package-pre.sh boot.sh runtime.sh overlay.sh bin/dex-patch > SHA256SUMS)
chmod 644 "$stage"/*.sh "$stage/bin/dex-patch"
cat > "$t/adapter2" <<'SH'
#!/bin/bash
case "$1" in
 version) echo 1.16.7;;
 packages) echo 'gen5w.kr.portable|0.3.72|installed';;
 healthy) :;;
 installed) exit 1;;
 retirement) echo none;;
 boot) echo staged-test-boot;;
 old-status|legacy-quiescent|retire-update) exit 99;;
 *) exit 1;;
esac
SH
chmod +x "$t/adapter2"; : > "$t/mounts"
run_staged() {
 PORTABLE_TEST_PACKAGE_ADAPTER=$t/adapter2 PORTABLE_TEST_SH=mksh PORTABLE_TEST_MOUNTS=$t/mounts \
 PORTABLE_TEST_OLD_APP=$r/data/nemesis/apps/gen5w.kr.portable PORTABLE_TEST_ROOT=$r \
 PORTABLE_TEST_BOOT_ADAPTER=$t/adapter2 PORTABLE_TEST_RUNTIME_ADAPTER=$t/adapter2 \
 PORTABLE_TEST_HELPER=$stage/bin/dex-patch PORTABLE_TEST_SUPERVISOR=$stage/bin/dex-patch \
 mksh "$stage/package-pre.sh"
}
echo 0 > "$r/data/local/gen5w-portable/boot/enabled"
run_staged || { echo 'FAIL removed old folder: disabled state not read through staged scripts'; exit 1; }
echo 1 > "$r/data/local/gen5w-portable/boot/enabled"
if run_staged >/dev/null 2>&1; then echo 'FAIL removed old folder: enabled state admitted without owned retirement'; exit 1; fi
echo 0 > "$r/data/local/gen5w-portable/boot/enabled"
echo 'tmpfs /data/local/gen5w-portable/x tmpfs rw 0 0' > "$t/mounts"
if run_staged >/dev/null 2>&1; then echo 'FAIL removed old folder: live mount admitted'; exit 1; fi
: > "$t/mounts"; mkdir -p "$r/data/local/gen5w-portable/runtime"; echo failed > "$r/data/local/gen5w-portable/runtime/phase"
if run_staged >/dev/null 2>&1; then echo 'FAIL removed old folder: failed runtime admitted'; exit 1; fi
echo 'PASS NEMESIS-removed old folder: state read through verified staged scripts; enabled, mounted or failed runtime refused'
echo 'PASS package preflight: version floor, healthy Android, app ownership, retired-pending update gate, exact payload and symlink refusal'
