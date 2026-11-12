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
case "$1" in version) cat "$ACTIONS/version";; packages) cat "$ACTIONS/packages";; healthy) [ ! -f "$ACTIONS/unhealthy" ];; installed) [ -f "$ACTIONS/existing" ];; *) exit 1;; esac
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
touch "$ACTIONS/unhealthy"
if run >/dev/null 2>&1; then echo 'FAIL installed without healthy Android'; exit 1; fi
rm "$ACTIONS/unhealthy"
echo changed > "$t/package/payload"
if run >/dev/null 2>&1; then echo 'FAIL ignored payload checksum'; exit 1; fi
echo authored > "$t/package/payload"
ln -s payload "$t/package/link"
(cd "$t/package"; sha256sum link > SHA256SUMS)
if run >/dev/null 2>&1; then echo 'FAIL accepted symlink payload'; exit 1; fi
echo 'PASS package preflight: version floor, healthy Android, app ownership, exact payload and symlink refusal'
