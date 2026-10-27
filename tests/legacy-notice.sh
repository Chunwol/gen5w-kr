#!/bin/bash
# Restore only synthetic prior ownership; never build or install a skip feature.
cd "$(dirname "$0")/.."
. tests/lib.sh
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
stubs
printf '#!/bin/sh\nexit 0\n' > "$W/bin/sync"; chmod +x "$W/bin/sync"
mkdir -p "$W/sys/etc/permissions" "$W/data/nemesis/backup" "$W/pkg"
cp -R packages/consent-restore/. "$W/pkg/"
STATE=$W/sys/etc/gen5w-kr-backup/consent
TARGET=$W/sys/etc/permissions/com.mobis.feature.remove_consentscreen.xml
fixture() {
    mkdir -p "$STATE"
    echo gen5w.kr.consent > "$STATE/owner"
    echo owned-fixture > "$STATE/1.applied"
    cp "$STATE/1.applied" "$TARGET"
    echo "1|$TARGET|absent|$(md5sum "$TARGET" | cut -d' ' -f1)" > "$STATE/manifest"
    md5sum "$STATE/manifest" | cut -d' ' -f1 > "$STATE/manifest.md5"
    echo 1 > "$STATE/complete"
}
run() { (cd "$W/pkg" && SKIP_TEST_SYS=$W/sys SKIP_TEST_DATA=$W/data SKIP_TEST_NEM=$W/nemesis PATH=$W/bin:$PATH mksh scripts/preun.sh > "$W/out" 2>&1); }
fixture
echo foreign-edit > "$TARGET"
check 'previous local notice change refuses a foreign edit' eval '! run'
check 'foreign content retained' grep -qx foreign-edit "$TARGET"
cp "$STATE/1.applied" "$TARGET"
check 'previous local notice change restores after registration loss' run
check 'owned addition removed' test ! -e "$TARGET"
check 'owned durable backup removed' test ! -e "$STATE"
fixture
echo unknown-owner > "$STATE/owner"
check 'unknown ownership is never restored' eval '! run'
check 'unknown owned bytes retained' test -f "$TARGET"
done_tests legacy-notice
