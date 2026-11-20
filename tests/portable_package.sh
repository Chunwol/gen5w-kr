#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/g5p-package.XXXXXX)
trap 'rc=$?; rm -rf "$t"; exit $rc' EXIT
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
 state-reset) echo state-reset >> "$ACTIONS/log"; [ ! -f "$ACTIONS/reset-fail" ];;
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
echo none > "$ACTIONS/retirement"; touch "$ACTIONS/reset-fail"
if run >/dev/null 2>&1; then echo 'FAIL replaced portable package without held retirement or verified state reset'; exit 1; fi
rm -f "$ACTIONS/reset-fail"
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
# preinstall. Without a same-boot handoff, earlier state goes through the
# verified staged state-reset.sh, never through the old package's scripts.
rm -f "$t/package/link"; (cd "$t/package"; sha256sum payload package-pre.sh bin/dex-patch > SHA256SUMS)
echo 'gen5w.kr.portable|0.3.72|installed' > "$ACTIONS/packages"; echo none > "$ACTIONS/retirement"; rm -f "$ACTIONS/log"
run; grep -qx state-reset "$ACTIONS/log"
touch "$ACTIONS/reset-fail"
if run >/dev/null 2>&1; then echo 'FAIL installed although earlier state could not be retired'; exit 1; fi
rm -f "$ACTIONS/reset-fail" "$ACTIONS/log"; echo held > "$ACTIONS/retirement"; echo retired-pending > "$ACTIONS/overlay-state"
run; [ ! -f "$ACTIONS/log" ] || ! grep -q state-reset "$ACTIONS/log"
: > "$ACTIONS/packages"
if run >/dev/null 2>&1; then echo 'FAIL accepted a handoff without an installed package'; exit 1; fi
echo none > "$ACTIONS/retirement"; rm -f "$ACTIONS/log"
r=$t/root; stage=$r/data/local/tmp/nemesis/stage/gen5w.kr.portable
mkdir -p "$stage/bin" "$r/data/local/gen5w-portable/boot"
cp tools/portable/package-pre.sh tools/portable/state-reset.sh tools/portable/overlay.sh "$stage/"
cp .build/portable/dex-patch-host "$stage/bin/dex-patch"
(cd "$stage"; sha256sum package-pre.sh state-reset.sh overlay.sh bin/dex-patch > SHA256SUMS)
chmod 644 "$stage"/*.sh "$stage/bin/dex-patch"
cat > "$t/adapter2" <<'SH'
#!/bin/bash
case "$1" in
 version) echo 1.16.7;;
 packages) echo 'gen5w.kr.portable|0.3.72|installed';;
 healthy) :;;
 installed) exit 1;;
 retirement) echo none;;
 state-reset) exit 99;;
 *) exit 1;;
esac
SH
chmod +x "$t/adapter2"; : > "$t/mounts"; echo staged-boot > "$t/boot_id"
run_staged() {
 PORTABLE_TEST_PACKAGE_ADAPTER=$t/adapter2 PORTABLE_TEST_SH=mksh PORTABLE_TEST_MOUNTS=$t/mounts \
 PORTABLE_TEST_ROOT=$r PORTABLE_TEST_BOOT_ID_FILE=$t/boot_id PORTABLE_TEST_GETPROP=true \
 mksh "$stage/package-pre.sh"
}
echo 0 > "$r/data/local/gen5w-portable/boot/enabled"
run_staged || { echo 'FAIL staged state-reset did not retire disabled earlier state'; exit 1; }
[ ! -e "$r/data/local/gen5w-portable/boot" ] && ls -d "$r/data/local/gen5w-portable/retired"/staged-boot-* >/dev/null
mkdir -p "$r/data/local/gen5w-portable/boot"; echo 1 > "$r/data/local/gen5w-portable/boot/enabled"
if run_staged >/dev/null 2>&1; then echo 'FAIL staged state-reset accepted an enabled earlier package'; exit 1; fi
echo 'PASS earlier state: handoff continued, otherwise retired by the verified staged state-reset (enabled refused)'
echo 'PASS package preflight: version floor, healthy Android, app ownership, retired-pending update gate, exact payload and symlink refusal'
