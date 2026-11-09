# Sourced only by bridge.sh's isolated fixture. Actual lifecycle scripts run in mksh.
touch "$W/pkg/app/bridge.dex" "$W/pkg/app/wireless-host.apk"
printf 'delta\n' > "$W/pkg/app/HKMC_DiPO.relay.lpd"
printf 'gpm-delta\n' > "$W/pkg/app/HKMC_GPM.guard.lpd"
cat > "$W/pkg/bin/lpatch" <<'EOF'
#!/bin/sh
case "$1" in
 delta)
  if cmp -s "$3" "$BRIDGE_TEST_FIXTURE/gpm-v039-original"; then
   [ "${GPM_DELTA_FAIL:-0}" != 1 ] || exit 9
   echo gpm-dex > "$4"
  elif cmp -s "$3" "$BRIDGE_TEST_FIXTURE/dipo-v039-original"; then echo dipo-dex > "$4"
  else exit 8; fi;;
 zipadd)
  if cmp -s "$2" "$BRIDGE_TEST_FIXTURE/gpm-v039-apk"; then echo gpm-guard-apk > "$4"
  elif cmp -s "$2" "$BRIDGE_TEST_FIXTURE/dipo-v039-apk"; then echo private-relay-apk > "$4"
  else exit 8; fi;;
 *) exit 2;;
esac
EOF
cat > "$W/bin/dexopt" <<'EOF'
#!/bin/sh
[ "$1" = --preopt ] && [ ! -e "$3" ] || exit 1
case "$BOOTCLASSPATH" in /system/framework/core.jar:*) ;; *) exit 2;; esac
if grep -q '^gpm-guard-apk' "$2" && [ "${GPM_DEXOPT_FAIL:-0}" = 1 ]; then echo 'gpm preopt failed' >&2;exit 7;fi
printf 'optimized:' > "$3";cat "$2" >> "$3"
EOF
chmod +x "$W/pkg/bin/lpatch" "$W/bin/dexopt"
export BRIDGE_TEST_DEXOPT="$W/bin/dexopt"
(cd "$W/pkg" && md5sum app/bridge.dex app/wireless-host.apk app/HKMC_DiPO.relay.lpd app/HKMC_GPM.guard.lpd bin/iap2-bt-patch-v039 bin/dipo-patch-v039 bin/gpm-patch-v039 bin/lpatch > app/relay-v039.md5)
echo gen5w.kr.bridge:v039-relay-4 > "$W/pkg/app/relay-v039.complete"
gpm_reset() {
    rm -rf "$PERSIST" "$MARK"
    for pair in "v039:$TARGET" "dipo-v039:$DIPO" "gpm-v039:$GPM"; do
        cp "$W/fixture/${pair%%:*}-original" "${pair#*:}"
    done
    cp "$W/fixture/v039-apk" "$APK";cp "$W/fixture/dipo-v039-apk" "$DIPOAPK";cp "$W/fixture/gpm-v039-apk" "$GPMAPK"
}
gpm_stock() { cmp -s "$GPM" "$W/fixture/gpm-v039-original" && cmp -s "$GPMAPK" "$W/fixture/gpm-v039-apk"; }
gpm_live() { grep -q '^gpm-guard-apk' "$GPMAPK" && grep -q '^optimized:gpm-guard-apk' "$GPM"; }
gpm_reset
check 'GPM guard fresh preflight' run pre
check 'GPM guard fresh install' run post
check 'GPM guard generated pair live' gpm_live
check 'GPM guard original APK saved' cmp -s "$PERSIST/gpmapkoriginal" "$W/fixture/gpm-v039-apk"
check 'GPM guard repeat install' run post
check 'GPM guard remove' run preun
check 'GPM pair restored byte for byte' gpm_stock
check 'GPM journal cleaned only after pair restored' test ! -e "$PERSIST"

for side in apk odex missing-odex missing-apk; do
    gpm_reset;run post || bad "GPM partial $side setup"
    case $side in
      apk) cp "$W/fixture/gpm-v039-apk" "$GPMAPK";;
      odex) cp "$W/fixture/gpm-v039-original" "$GPM";;
      missing-odex) rm "$GPM";;
      missing-apk) rm "$GPMAPK";;
    esac
    check "GPM partial $side recognized" run pre
    check "GPM partial $side restored" run preun
    check "GPM partial $side exact pair" gpm_stock
done
for side in apk odex; do
    gpm_reset;touch "$W/fixture/fail-gpm-$side-mv"
    if run post;then bad "GPM $side rename failure rejected";else ok "GPM $side rename failure rejected";fi
    check "GPM $side rename failure restores pair" gpm_stock
    check "GPM $side rename failure removable" run preun
done
gpm_reset;touch "$W/fixture/fail-gpm-odex-always"
if run post;then bad 'GPM rollback failure reported';else ok 'GPM rollback failure reported';fi
check 'GPM rollback primary and secondary retained' eval 'grep -q "GPM guard install failed" "$W/last-run" && grep -q "rollback incomplete" "$W/last-run"'
check 'GPM rollback failure keeps original pair backup' eval 'test -f "$PERSIST/gpmapkoriginal" && test -f "$PERSIST/gpmoriginal" && test -f "$PERSIST/owner" && test -f "$PERSIST/gpmrelaystaging"'
rm "$W/fixture/fail-gpm-odex-always"
check 'GPM rollback failure later removal' run preun
check 'GPM rollback failure later exact originals' gpm_stock
gpm_reset
for fault in GPM_DEXOPT_FAIL GPM_DELTA_FAIL; do
    export "$fault=1"
    if run post;then bad "$fault rejected";else ok "$fault rejected";fi
    unset "$fault"
    check "$fault leaves original GPM pair" gpm_stock
    check "$fault uninstall works" run preun
done
gpm_reset;run post || bad 'GPM corruption setup'
echo corrupt > "$PERSIST/gpmapkoriginal"
if run preun;then bad 'GPM corrupt original rejected';else ok 'GPM corrupt original rejected';fi
check 'GPM corrupt original retains journal' test -f "$PERSIST/owner"
gpm_reset;run post || bad 'GPM foreign setup'
echo foreign > "$GPMAPK"
if run preun;then bad 'GPM foreign live APK rejected';else ok 'GPM foreign live APK rejected';fi
check 'GPM foreign live APK untouched' grep -q '^foreign' "$GPMAPK"
gpm_reset
ln -s "$W/fixture/gpm-v039-apk" "$PERSIST-link"
mkdir -p "$PERSIST";echo gen5w.kr.bridge:v039-1 > "$PERSIST/owner"
ln -s "$W/fixture/gpm-v039-apk" "$PERSIST/gpmapkoriginal"
if run post;then bad 'GPM backup symlink rejected';else ok 'GPM backup symlink rejected';fi
check 'GPM symlink cannot mutate originals' gpm_stock
gpm_reset
# Own legacy HUD state from the normal ODEX-only install path.
rm "$W/pkg/app/relay-v039.complete"
check 'GPM legacy HUD install' run post
echo gen5w.kr.bridge:v039-relay-4 > "$W/pkg/app/relay-v039.complete"
check 'GPM legacy owned update' run post
check 'GPM legacy update uses original delta input' gpm_live
check 'GPM legacy update removal' run preun
check 'GPM legacy update exact originals' gpm_stock
gpm_reset
rm "$GPM" "$GPMAPK"
check 'GPM absent app install' run post
check 'GPM absent app remove' run preun
check 'GPM absent app not invented' eval '[ ! -e "$GPM" ] && [ ! -e "$GPMAPK" ]'
