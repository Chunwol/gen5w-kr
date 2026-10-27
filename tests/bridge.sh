#!/bin/bash
set -u
cd "$(dirname "$0")/.."
. tests/lib.sh
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/pkg/scripts" "$W/pkg/bin" "$W/pkg/app" "$W/sys/app" "$W/sys/framework" "$W/data" "$W/bin" "$W/fixture"
cp packages/wireless-bridge/scripts/*.sh "$W/pkg/scripts/" 2>/dev/null || true
printf 'stock035\n' > "$W/fixture/v035-original"; printf 'patched035\n' > "$W/fixture/v035-patched"
printf 'stock039\n' > "$W/fixture/v039-original"; printf 'patched039\n' > "$W/fixture/v039-patched"
printf 'apk035\n' > "$W/fixture/v035-apk"; printf 'apk039\n' > "$W/fixture/v039-apk"
for version in v035 v039; do
    echo "dipo-$version-original" > "$W/fixture/dipo-$version-original"
    echo "dipo-$version-patched" > "$W/fixture/dipo-$version-patched"
    echo "dipo-$version-apk" > "$W/fixture/dipo-$version-apk"
done
echo "gpm-v039-original" > "$W/fixture/gpm-v039-original"
echo "gpm-v039-patched" > "$W/fixture/gpm-v039-patched"
echo "gpm-v039-apk" > "$W/fixture/gpm-v039-apk"
cat > "$W/pkg/scripts/recipe.sh" <<'EOF'
BRIDGE_APK_V035_SHA=v035-apk
BRIDGE_APK_V039_SHA=v039-apk
BRIDGE_DIPO_APK_V035_SHA=dipo-v035-apk
BRIDGE_DIPO_APK_V039_SHA=dipo-v039-apk
BRIDGE_GPM_APK_V039_SHA=gpm-v039-apk
EOF
for version in v035 v039; do
cat > "$W/pkg/bin/iap2-patch-$version" <<'EOF'
#!/bin/sh
version=${0##*-}
case "$1" in
original|patched) cmp -s "$2" "$BRIDGE_TEST_FIXTURE/$version-$1";;
verify) cmp -s "$2" "$BRIDGE_TEST_FIXTURE/$3";;
apply) cmp -s "$2" "$BRIDGE_TEST_FIXTURE/$version-original" && cp "$BRIDGE_TEST_FIXTURE/$version-patched" "$3";;
*) exit 2;;
esac
EOF
done
for version in v035 v039; do
cat > "$W/pkg/bin/dipo-patch-$version" <<'EOF'
#!/bin/sh
version=${0##*-}
case "$1" in
original|patched) cmp -s "$2" "$BRIDGE_TEST_FIXTURE/dipo-$version-$1";;
verify) cmp -s "$2" "$BRIDGE_TEST_FIXTURE/$3";;
apply) cmp -s "$2" "$BRIDGE_TEST_FIXTURE/dipo-$version-original" && cp "$BRIDGE_TEST_FIXTURE/dipo-$version-patched" "$3";;
*) exit 2;;
esac
EOF
done
cat > "$W/pkg/bin/gpm-patch-v039" <<'EOF'
#!/bin/sh
case "$1" in
original|patched) cmp -s "$2" "$BRIDGE_TEST_FIXTURE/gpm-v039-$1";;
verify) cmp -s "$2" "$BRIDGE_TEST_FIXTURE/$3";;
apply) cmp -s "$2" "$BRIDGE_TEST_FIXTURE/gpm-v039-original" && cp "$BRIDGE_TEST_FIXTURE/gpm-v039-patched" "$3";;
*) exit 2;;
esac
EOF
cat > "$W/bin/nemesis" <<'EOF'
#!/bin/sh
echo "$*" >> "$BRIDGE_TEST_FIXTURE/calls"
[ "$2" != "${BRIDGE_TEST_REMOUNT_FAIL:-never}" ]
EOF
cat > "$W/bin/mv" <<'EOF'
#!/bin/sh
case "$2" in
*Iap2ServerApp.odex)
if [ -f "$BRIDGE_TEST_FIXTURE/fail-mv" ]; then rm "$BRIDGE_TEST_FIXTURE/fail-mv"; exit 1; fi;;
*HKMC_DiPO.odex)
if [ -f "$BRIDGE_TEST_FIXTURE/fail-dipo-mv" ]; then rm "$BRIDGE_TEST_FIXTURE/fail-dipo-mv"; exit 1; fi;;
esac
exec /bin/mv "$@"
EOF
cat > "$W/bin/getprop" <<'EOF'
#!/bin/sh
echo 1
EOF
chmod +x "$W/bin/"*
# Deliberately leave extracted native helpers 0644; lifecycle must make them executable.
chmod 644 "$W/pkg/bin/"*
export PATH="$W/bin:$PATH" BRIDGE_TEST_SYS="$W/sys" BRIDGE_TEST_DATA="$W/data"
export BRIDGE_TEST_NEM="$W/bin/nemesis" BRIDGE_TEST_FIXTURE="$W/fixture"
TARGET=$W/sys/app/Iap2ServerApp.odex; APK=$W/sys/app/Iap2ServerApp.apk
DIPO=$W/sys/app/HKMC_DiPO.odex; DIPOAPK=$W/sys/app/HKMC_DiPO.apk
GPM=$W/sys/app/HKMC_GPM.odex; GPMAPK=$W/sys/app/HKMC_GPM.apk
PERSIST=$W/sys/etc/gen5w-kr-backup/bridge; MARK=$W/data/nemesis/backup/gen5w.kr.bridge
run() { mksh "$W/pkg/scripts/$1.sh" >/dev/null 2>&1; }
cp "$W/fixture/v035-original" "$TARGET"; cp "$W/fixture/v035-apk" "$APK"
cp "$W/fixture/dipo-v035-original" "$DIPO"; cp "$W/fixture/dipo-v035-apk" "$DIPOAPK"
if run pre; then bad 'missing daemon payload refused'; else ok 'missing daemon payload refused'; fi
touch "$W/pkg/app/bridge.dex" "$W/sys/framework/com.tcc.iap2.jar"
for version in v035 v039; do
cp "$W/fixture/$version-original" "$TARGET"; cp "$W/fixture/$version-apk" "$APK"
cp "$W/fixture/dipo-$version-original" "$DIPO"; cp "$W/fixture/dipo-$version-apk" "$DIPOAPK"
if [ "$version" = v039 ]; then
    cp "$W/fixture/gpm-$version-original" "$GPM"; cp "$W/fixture/gpm-$version-apk" "$GPMAPK"
fi
chmod 600 "$DIPO"
chmod 640 "$TARGET"
check "$version pre accepts exact pair" run pre
check "$version helpers made executable" test -x "$W/pkg/bin/iap2-patch-$version"
check "$version install" run post
check "$version patched exact" cmp -s "$TARGET" "$W/fixture/$version-patched"
check "$version DiPO patched exact" cmp -s "$DIPO" "$W/fixture/dipo-$version-patched"
if [ "$version" = v039 ]; then
    check "$version GPM patched exact" cmp -s "$GPM" "$W/fixture/gpm-$version-patched"
    check "$version durable GPM original" cmp -s "$PERSIST/gpmoriginal" "$W/fixture/gpm-$version-original"
fi
check "$version DiPO metadata preserved" test "$(stat -c %a "$DIPO")" = 600
check "$version metadata preserved" test "$(stat -c %a "$TARGET")" = 640
check "$version durable original" cmp -s "$PERSIST/original" "$W/fixture/$version-original"
check "$version durable DiPO original" cmp -s "$PERSIST/dipooriginal" "$W/fixture/dipo-$version-original"
check "$version reinstall" run post
rm -rf "$MARK"
check "$version reset recovery" run post
check "$version runtime original restored" cmp -s "$MARK/original" "$W/fixture/$version-original"
echo foreign > "$TARGET"
if run preun; then bad "$version foreign target refused"; else ok "$version foreign target refused"; fi
cp "$W/fixture/$version-patched" "$TARGET"
check "$version uninstall" run preun
check "$version original identity" cmp -s "$TARGET" "$W/fixture/$version-original"
check "$version DiPO original identity" cmp -s "$DIPO" "$W/fixture/dipo-$version-original"
if [ "$version" = v039 ]; then
    check "$version GPM original identity" cmp -s "$GPM" "$W/fixture/gpm-$version-original"
fi
check "$version DiPO original mode" test "$(stat -c %a "$DIPO")" = 600
check "$version uninstall mode restored" test "$(stat -c %a "$TARGET")" = 640
check "$version owned state removed" test ! -d "$PERSIST"
done
cp "$W/fixture/v039-original" "$TARGET"; cp "$W/fixture/v039-apk" "$APK"
cp "$W/fixture/dipo-v039-original" "$DIPO"; cp "$W/fixture/dipo-v039-apk" "$DIPOAPK"
echo unknown > "$TARGET"; run pre; rc=$?
check 'unknown stock is skip77' test "$rc" = 77
check 'unknown creates no backup' test ! -d "$PERSIST"
cp "$W/fixture/v039-original" "$TARGET"; cp "$W/fixture/v035-apk" "$APK"
run pre; rc=$?; check 'mismatched APK skip77' test "$rc" = 77
cp "$W/fixture/v039-apk" "$APK"
touch "$W/fixture/fail-mv"
if run post; then bad 'rename failure rejected'; else ok 'rename failure rejected'; fi
check 'rename failure target stock' cmp -s "$TARGET" "$W/fixture/v039-original"
check 'interrupted install retry' run post
# Simulate an interrupted owned stage after durable originals were written.
echo incomplete > "$TARGET.gen5w-kr-bridge.tmp"
echo gen5w.kr.bridge:v039-1 > "$PERSIST/staging"
check 'interrupted owned stage recovered' run post
check 'uninstall after recovery' run preun
mkdir -p "$PERSIST"; echo foreign > "$PERSIST/owner"
if run post; then bad 'foreign ownership refused'; else ok 'foreign ownership refused'; fi
check 'foreign ownership preserved' test "$(cat "$PERSIST/owner")" = foreign
rm -rf "$PERSIST"
export BRIDGE_TEST_REMOUNT_FAIL=rw
if run post; then bad 'rw failure refused'; else ok 'rw failure refused'; fi
check 'rw failure unchanged' cmp -s "$TARGET" "$W/fixture/v039-original"
unset BRIDGE_TEST_REMOUNT_FAIL
check 'install for backup corruption test' run post
echo corrupt > "$PERSIST/original"
if run preun; then bad 'corrupt backup refuses uninstall'; else ok 'corrupt backup refuses uninstall'; fi
check 'corrupt backup target retained' cmp -s "$TARGET" "$W/fixture/v039-patched"
cp "$W/fixture/v039-original" "$PERSIST/original"
check 'cleanup corruption fixture' run preun
cp "$W/fixture/v039-original" "$TARGET"
ln -s "$W/fixture/v039-original" "$TARGET.gen5w-kr-bridge.tmp"
if run post; then bad 'symlink stage refused'; else ok 'symlink stage refused'; fi
check 'symlink target preserved' cmp -s "$W/fixture/v039-original" "$TARGET"
rm "$TARGET.gen5w-kr-bridge.tmp"
check 'retry after stage symlink removed' run post
check 'read-only remount issued' grep -q '^remount ro$' "$W/fixture/calls"
touch "$W/pkg/app/bridge.dex"
export BRIDGE_TEST_ONCE=1
export BRIDGE_TEST_PROFILE_READY=$W/profile-ready.sh BRIDGE_TEST_SHELL=$(command -v mksh)
printf '#!/bin/sh\nexit 0\n' > "$BRIDGE_TEST_PROFILE_READY"
rm -f "$W/data/nemesis/gen5wkr.bridge.stopping"
check 'service starts system-uid daemon' run service
check 'daemon classpath and class exact' grep -q 'root 1000 -c CLASSPATH=.*/app/bridge.dex:/system/framework/com.tcc.iap2.jar app_process /system/bin kr.gen5w.wireless.WirelessBridge' "$W/fixture/calls"
before=$(wc -l < "$W/fixture/calls")
touch "$W/data/nemesis/gen5wkr.noreboot"
check 'bridge waits while installation needs a reboot' run service
check 'pending reboot launches no daemon' test "$(wc -l < "$W/fixture/calls")" = "$before"
rm "$W/data/nemesis/gen5wkr.noreboot"
printf '#!/bin/sh\nexit 1\n' > "$BRIDGE_TEST_PROFILE_READY"
check 'bridge waits until native profile patch is ready' run service
check 'unready profile launches no daemon' test "$(wc -l < "$W/fixture/calls")" = "$before"
printf '#!/bin/sh\nexit 0\n' > "$BRIDGE_TEST_PROFILE_READY"
touch "$W/data/nemesis/gen5wkr.wireless-disabled"
check 'wired-only supervisor stays available without wireless daemon' run service
check 'wired-only launches no Bluetooth daemon' test "$(wc -l < "$W/fixture/calls")" = "$before"
rm "$W/data/nemesis/gen5wkr.wireless-disabled"
touch "$W/data/nemesis/gen5wkr.bridge.stopping"
check 'stopping marker exits supervisor' run service
check 'stopping marker launches no daemon' test "$(wc -l < "$W/fixture/calls")" = "$before"
check 'post clears stopping marker' run post
check 'stopping marker removed on success' test ! -e "$W/data/nemesis/gen5wkr.bridge.stopping"
echo foreign > "$TARGET"
before=$(wc -l < "$W/fixture/calls")
if run service; then bad 'service refuses changed firmware'; else ok 'service refuses changed firmware'; fi
check 'changed firmware launches no daemon' test "$(wc -l < "$W/fixture/calls")" = "$before"
cp "$W/fixture/v039-patched" "$TARGET"
cp "$W/fixture/dipo-v039-original" "$DIPO"
check 'resume iAP patched DiPO original pair' run post
check 'resumed DiPO patched exact' cmp -s "$DIPO" "$W/fixture/dipo-v039-patched"
cp "$W/fixture/v039-original" "$TARGET"
check 'resume iAP original DiPO patched pair' run post
check 'resumed iAP patched exact' cmp -s "$TARGET" "$W/fixture/v039-patched"
check 'cleanup partial pairs' run preun
touch "$W/fixture/fail-dipo-mv"
if run post; then bad 'second target failure rejected'; else ok 'second target failure rejected'; fi
check 'second failure rolls iAP back' cmp -s "$TARGET" "$W/fixture/v039-original"
check 'second failure leaves DiPO original' cmp -s "$DIPO" "$W/fixture/dipo-v039-original"
check 'retry second target failure' run post
echo corrupt > "$PERSIST/dipooriginal"
if run preun; then bad 'corrupt DiPO backup refuses pair restore'; else ok 'corrupt DiPO backup refuses pair restore'; fi
check 'corrupt DiPO backup leaves iAP patched' cmp -s "$TARGET" "$W/fixture/v039-patched"
cp "$W/fixture/dipo-v039-original" "$PERSIST/dipooriginal"
cp "$W/fixture/dipo-v035-apk" "$DIPOAPK"
if run post; then bad 'DiPO APK drift refused'; else ok 'DiPO APK drift refused'; fi
check 'DiPO APK drift leaves iAP patched' cmp -s "$TARGET" "$W/fixture/v039-patched"
cp "$W/fixture/dipo-v039-apk" "$DIPOAPK"
cp "$W/fixture/dipo-v039-original" "$DIPO"
before=$(wc -l < "$W/fixture/calls")
if run service; then bad 'partial pair refuses daemon startup'; else ok 'partial pair refuses daemon startup'; fi
check 'partial pair launches no daemon' test "$(wc -l < "$W/fixture/calls")" = "$before"
check 'resume partial pair after boot refusal' run post
echo foreign > "$DIPO"
if run preun; then bad 'foreign DiPO refuses restore pair'; else ok 'foreign DiPO refuses restore pair'; fi
check 'foreign DiPO leaves iAP intact' cmp -s "$TARGET" "$W/fixture/v039-patched"
cp "$W/fixture/dipo-v039-patched" "$DIPO"
check 'cleanup foreign fixture' run preun
cp "$W/fixture/dipo-v035-original" "$DIPO"; cp "$W/fixture/dipo-v035-apk" "$DIPOAPK"
run pre; rc=$?; check 'crossversion pair skipped' test "$rc" = 77
done_tests bridge
