#!/bin/bash
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
SYS="$W/system"
DATA="$W/data"
CACHE="$W/cache"
BG="$DATA/nemesis/gen5wkr.bootguard"
mkdir -p "$SYS/framework" "$SYS/priv-app" "$SYS/app" "$SYS/lib" \
    "$SYS/etc/gen5w-kr-backup/hotspot" \
    "$SYS/etc/gen5w-kr-backup/notice" \
    "$SYS/etc/gen5w-kr-backup/bridge" \
    "$SYS/etc/gen5w-kr-backup/audio" \
    "$DATA/nemesis/gen5wkr.bootguard" "$CACHE/dalvik-cache" "$W/bin"
cat > "$W/nemesis" <<'SH'
#!/bin/sh
echo "nemesis $*" >> "$BG_TEST_DATA/calls"
exit 0
SH
chmod +x "$W/nemesis"
# Simulate the installed per-profile native tools without distributing OEM files.
for entry in 'gen5w.kr.hotspot:hotspot-patch-v039' 'gen5w.kr.notice:notice-patch-v039' \
    'gen5w.kr.bridge:iap2-patch-v039' 'gen5w.kr.bridge:dipo-patch-v039' \
    'gen5w.kr.bridge:gpm-patch-v039' 'gen5w.kr.audio:audio-patch'; do
    id=${entry%%:*}; tool=${entry#*:}
    mkdir -p "$DATA/nemesis/apps/$id/bin"
    cat > "$DATA/nemesis/apps/$id/bin/$tool" <<'SH'
#!/bin/sh
case "$1" in
    original) grep -q '^stock-' "$2";;
    patched) grep -q '^patched-' "$2";;
    *) exit 1;;
esac
SH
    chmod +x "$DATA/nemesis/apps/$id/bin/$tool"
done
write_pair() {
    local backup=$1 target=$2
    printf 'stock-%s\n' "$target" > "$backup"
    printf 'patched-%s\n' "$target" > "$target"
}
write_pair "$SYS/etc/gen5w-kr-backup/hotspot/original" "$SYS/framework/services.odex"
write_pair "$SYS/etc/gen5w-kr-backup/notice/original" "$SYS/priv-app/SystemUI.odex"
write_pair "$SYS/etc/gen5w-kr-backup/bridge/original" "$SYS/app/Iap2ServerApp.odex"
write_pair "$SYS/etc/gen5w-kr-backup/bridge/dipooriginal" "$SYS/app/HKMC_DiPO.odex"
write_pair "$SYS/etc/gen5w-kr-backup/bridge/gpmoriginal" "$SYS/app/HKMC_GPM.odex"
write_pair "$SYS/etc/gen5w-kr-backup/audio/original" "$SYS/lib/libCarPlayAudio.so"
chmod 640 "$SYS/etc/gen5w-kr-backup/hotspot/original"
for name in services SystemUI Iap2ServerApp HKMC_DiPO HKMC_GPM; do
    printf stale > "$CACHE/dalvik-cache/${name}.cache"
done
printf 0 > "$DATA/nemesis/gen5wkr.bootguard/count"
printf 3 > "$DATA/nemesis/gen5wkr.bootguard/max"
printf armed > "$DATA/nemesis/gen5wkr.bootguard/armed"
BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" \
BG_TEST_DALVIK="$CACHE/dalvik-cache" \
mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/out" 2>&1
check 'bootguard restores services ODEX' cmp -s "$SYS/framework/services.odex" "$SYS/etc/gen5w-kr-backup/hotspot/original"
check 'bootguard restores original file permissions' test "$(stat -c %a "$SYS/framework/services.odex")" = "$(stat -c %a "$SYS/etc/gen5w-kr-backup/hotspot/original")"
check 'bootguard restores SystemUI ODEX' cmp -s "$SYS/priv-app/SystemUI.odex" "$SYS/etc/gen5w-kr-backup/notice/original"
check 'bootguard restores bridge ODEX' cmp -s "$SYS/app/Iap2ServerApp.odex" "$SYS/etc/gen5w-kr-backup/bridge/original"
check 'bootguard restores DiPO ODEX' cmp -s "$SYS/app/HKMC_DiPO.odex" "$SYS/etc/gen5w-kr-backup/bridge/dipooriginal"
check 'bootguard restores GPM ODEX' cmp -s "$SYS/app/HKMC_GPM.odex" "$SYS/etc/gen5w-kr-backup/bridge/gpmoriginal"
check 'bootguard restores audio library' cmp -s "$SYS/lib/libCarPlayAudio.so" "$SYS/etc/gen5w-kr-backup/audio/original"
for name in services SystemUI Iap2ServerApp HKMC_DiPO HKMC_GPM; do
    check "bootguard removes stale ${name} cache" test ! -e "$CACHE/dalvik-cache/${name}.cache"
done
check 'bootguard records recovery marker' grep -qx 'recovered rc=0' "$DATA/nemesis/gen5wkr.bootguard/recovered"

rm -f "$DATA/nemesis/gen5wkr.bootguard/armed"
rm -f "$DATA/nemesis/gen5wkr.bootguard/recovered"
check 'bootguard refuses unarmed recovery' eval '! BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh"'
check 'unarmed recovery leaves no success marker' test ! -e "$DATA/nemesis/gen5wkr.bootguard/recovered"

mkdir -p "$W/integrated" "$W/integrated-data" "$W/integrated-system"
cp "$ROOT/tools/integrated/common.sh" "$ROOT/tools/integrated/report.sh" "$ROOT/tools/integrated/hotspot-repair.sh" "$W/integrated/"
check 'bootguard arm creates an atomic armed marker' env IT_DATA="$W/integrated-data" IT_SYSTEM="$W/integrated-system" bash -c "cd '$W/integrated' && . ./common.sh && bootguard_arm"
rm -rf "$W/integrated-data/nemesis/gen5wkr.bootguard"
check 'bootguard arm failure is fail-closed' env IT_DATA="$W/integrated-data" IT_SYSTEM="$W/integrated-system" IT_BOOTGUARD_FAIL=1 bash -c "cd '$W/integrated' && . ./common.sh && ! bootguard_arm"
check 'failed arm leaves no guard directory' test ! -e "$W/integrated-data/nemesis/gen5wkr.bootguard.tmp" -a ! -e "$W/integrated-data/nemesis/gen5wkr.bootguard"

# A verifier must itself be present in the checked package manifest. A valid
# manifest for some unrelated file must not authenticate an injected verifier.
# Hotspot is not installed here, so arming must prove services.odex is stock.
mkdir -p "$W/integrated-system/framework"
printf 'stock-services\n' > "$W/integrated-system/framework/services.odex"
mkdir -p "$W/integrated/checks/gen5w.kr.hotspot/bin"
cp "$DATA/nemesis/apps/gen5w.kr.hotspot/bin/hotspot-patch-v039" "$W/integrated/checks/gen5w.kr.hotspot/bin/hotspot-patch-v039"
printf 'unrelated\n' > "$W/integrated/checks/gen5w.kr.hotspot/unrelated"
(cd "$W/integrated/checks/gen5w.kr.hotspot" && md5sum unrelated > FILES.md5)
check 'bootguard arm rejects unlisted verifier' env IT_DATA="$W/integrated-data" IT_SYSTEM="$W/integrated-system" bash -c "cd '$W/integrated' && . ./common.sh && ! bootguard_arm"
(cd "$W/integrated/checks/gen5w.kr.hotspot" && md5sum bin/hotspot-patch-v039 >> FILES.md5)
check 'bootguard arm retains listed verifier' env IT_DATA="$W/integrated-data" IT_SYSTEM="$W/integrated-system" bash -c "cd '$W/integrated' && . ./common.sh && bootguard_arm"
check 'retained verifier matches package' cmp -s "$W/integrated/checks/gen5w.kr.hotspot/bin/hotspot-patch-v039" "$W/integrated-data/nemesis/gen5wkr.bootguard/verifiers/hotspot-v039"

# Simulate a failed final rename during re-arm. The previous guard must still
# be reachable for the next boot rather than being deleted before replacement.
mkdir -p "$W/fail-mv"
cat > "$W/fail-mv/mv" <<'SH'
#!/bin/sh
case "$1:$2" in *.bootguard.tmp.*:*.bootguard) exit 1;; esac
exec /bin/mv "$@"
SH
chmod +x "$W/fail-mv/mv"
printf 'prior-state\n' > "$W/integrated-data/nemesis/gen5wkr.bootguard/sentinel"
check 'failed replacement refuses rearm' env PATH="$W/fail-mv:$PATH" IT_DATA="$W/integrated-data" IT_SYSTEM="$W/integrated-system" bash -c "cd '$W/integrated' && . ./common.sh && ! bootguard_arm"
check 'failed replacement retains previous guard' test -f "$W/integrated-data/nemesis/gen5wkr.bootguard/sentinel" -o -f "$W/integrated-data/nemesis/gen5wkr.bootguard.previous/sentinel"

# The next transaction must reconcile a retained generation before it mutates
# packages. A completed rollback selects the old guard; a committed update keeps
# the new one. Ambiguous state leaves both untouched for recovery.
IG="$W/integrated-data/nemesis/gen5wkr.bootguard"
mkdir -p "$IG.previous"
cp "$IG/armed" "$IG/count" "$IG/max" "$IG.previous/"
printf old > "$IG.previous/sentinel"
printf new > "$IG/sentinel"
check 'rolled-back rearm reconciles previous generation' env IT_DATA="$W/integrated-data" IT_SYSTEM="$W/integrated-system" bash -c "cd '$W/integrated' && . ./common.sh && bootguard_reconcile_previous rolled-back"
check 'rollback keeps old guard' grep -qx old "$IG/sentinel"
check 'rollback reconciliation removes previous path' test ! -e "$IG.previous"
mkdir -p "$IG.previous"
cp "$IG/armed" "$IG/count" "$IG/max" "$IG.previous/"
printf new > "$IG/sentinel"
check 'committed rearm reconciles previous generation' env IT_DATA="$W/integrated-data" IT_SYSTEM="$W/integrated-system" bash -c "cd '$W/integrated' && . ./common.sh && bootguard_reconcile_previous committed"
check 'committed reconciliation keeps new guard' grep -qx new "$IG/sentinel"
check 'committed reconciliation removes previous path' test ! -e "$IG.previous"
mkdir -p "$IG.previous"
check 'ambiguous rearm preserves both generations' env IT_DATA="$W/integrated-data" IT_SYSTEM="$W/integrated-system" bash -c "cd '$W/integrated' && . ./common.sh && ! bootguard_reconcile_previous capturing"
check 'ambiguous previous remains' test -d "$IG.previous"
rm -rf "$IG.previous"

# Exercise begin(), including its interrupted-transaction branch, rather than
# checking reconciliation only as an isolated helper.
mkdir -p "$IG.previous" "$W/integrated-data/nemesis/gen5w-kr-integrated/prior"
cp "$IG/armed" "$IG/count" "$IG/max" "$IG.previous/"
printf old > "$IG.previous/sentinel"
printf new > "$IG/sentinel"
printf applying > "$W/integrated-data/nemesis/gen5w-kr-integrated/state"
touch "$W/integrated-data/nemesis/gen5w-kr-integrated/prior/complete"
check 'interrupted transaction reconciles guard before new snapshot' env IT_DATA="$W/integrated-data" IT_SYSTEM="$W/integrated-system" bash -c "cd '$W/integrated' && . ./common.sh && rollback_transaction() { set_state rolled-back; } && snapshot() { test \"\$(cat \"\$BOOTGUARD/sentinel\")\" = old; } && begin"
check 'interrupted transaction restores prior guard' grep -qx old "$IG/sentinel"
check 'interrupted transaction leaves a complete new snapshot' test -f "$W/integrated-data/nemesis/gen5w-kr-integrated/prior/complete"

# A lost original must never produce a success marker or allow any restoration.
printf armed > "$BG/armed"
rm -f "$BG/recovered" "$BG/recovery-required"
printf 'patched-services\n' > "$SYS/framework/services.odex"
printf 'patched-systemui\n' > "$SYS/priv-app/SystemUI.odex"
rm -f "$SYS/etc/gen5w-kr-backup/hotspot/original"
if BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" \
    mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/missing.out" 2>&1; then
    bad 'missing original refuses recovery'
else
    ok 'missing original refuses recovery'
fi
check 'missing original leaves all targets untouched' grep -qx 'patched-systemui' "$SYS/priv-app/SystemUI.odex"
check 'missing original never records success' test ! -e "$BG/recovered"
check 'missing original records recovery required' test -f "$BG/recovery-required"

rm -f "$BG/recovery-required"
printf 'corrupt-backup\n' > "$SYS/etc/gen5w-kr-backup/hotspot/original"
if BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" \
    mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/corrupt.out" 2>&1; then
    bad 'corrupt original refuses recovery'
else
    ok 'corrupt original refuses recovery'
fi
check 'corrupt original leaves all targets untouched' grep -qx 'patched-systemui' "$SYS/priv-app/SystemUI.odex"
check 'corrupt original never records success' test ! -e "$BG/recovered"
check 'corrupt original records recovery required' test -f "$BG/recovery-required"

# Wireless settings have a separate journal; do not claim full recovery while
# this guard does not yet validate and restore that journal.
rm -f "$BG/recovery-required"
printf 'stock-services\n' > "$SYS/etc/gen5w-kr-backup/hotspot/original"
mkdir -p "$SYS/etc/gen5w-kr-backup/wireless"
if BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" \
    mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/wireless.out" 2>&1; then
    bad 'wireless recovery without integration is refused'
else
    ok 'wireless recovery without integration is refused'
fi
check 'wireless refusal leaves targets untouched' grep -qx 'patched-systemui' "$SYS/priv-app/SystemUI.odex"
check 'wireless refusal never records success' test ! -e "$BG/recovered"
check 'wireless refusal records recovery required' test -f "$BG/recovery-required"

rm -rf "$SYS/etc/gen5w-kr-backup/wireless"
rm -f "$BG/recovery-required" "$SYS/framework/services.odex" "$SYS/etc/gen5w-kr-backup/hotspot/original"
if BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" \
    mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/both-missing.out" 2>&1; then
    bad 'missing target and original refuse recovery without inventory'
else
    ok 'missing target and original refuse recovery without inventory'
fi
check 'missing target never records success' test ! -e "$BG/recovered"

rm -f "$BG/recovery-required" "$BG/recovered"
write_pair "$SYS/etc/gen5w-kr-backup/hotspot/original" "$SYS/framework/services.odex"
mkdir -p "$DATA/nemesis/backup/gen5w.kr.wireless"
if BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" \
    mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/wireless-data.out" 2>&1; then
    bad 'wireless data backup alone refuses incomplete recovery'
else
    ok 'wireless data backup alone refuses incomplete recovery'
fi
check 'wireless data backup refusal never records success' test ! -e "$BG/recovered"

# Exercise the actual wireless journal together with the guard, including runtime
# properties. A successful file restore must keep the journal for later recovery.
rm -rf "$DATA/nemesis/backup/gen5w.kr.wireless"
rm -f "$BG/recovery-required" "$BG/recovered"
mkdir -p "$SYS/etc/permissions" "$DATA/nemesis/apps"
stubs
echo 'persist.ium.support=stock' > "$SYS/build.prop"
echo stock > "$W/props/persist.ium.support"
echo 1 > "$W/props/persist.wifi.state"
echo '#!/bin/sh' > "$W/bin/dmesg"
echo 'echo "Firmware up"' >> "$W/bin/dmesg"
chmod +x "$W/bin/dmesg"
echo 'patched-carplay_wireless ConnectivitySSID' > "$SYS/app/HKMC_DiPO.odex"
cp -r "$ROOT/packages/wireless-enable" "$DATA/nemesis/apps/gen5w.kr.wireless"
echo 'wifi_client_wanted() { return 0; }' >> "$DATA/nemesis/apps/gen5w.kr.wireless/scripts/common.sh"
check 'bootguard wireless fixture applies real journal' bash -c 'cd "$1/nemesis/apps/gen5w.kr.wireless" && PATH="$2/bin:$PATH" EN_TEST_SYS="$3" EN_TEST_DATA="$1" EN_TEST_NEM="$2/nemesis" mksh scripts/pre.sh && PATH="$2/bin:$PATH" EN_TEST_SYS="$3" EN_TEST_DATA="$1" EN_TEST_NEM="$2/nemesis" mksh scripts/post.sh' _ "$DATA" "$W" "$SYS"
rm -f "$BG/recovery-required" "$BG/recovered"
printf 'patched-services\n' > "$SYS/framework/services.odex"
mv "$DATA/nemesis/apps" "$DATA/nemesis/apps-real"
ln -s "$DATA/nemesis/apps-real" "$DATA/nemesis/apps"
if PATH="$W/bin:$PATH" BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" \
    mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/wireless-app-link.out" 2>&1; then
    bad 'linked package parent refuses recovery'
else
    ok 'linked package parent refuses recovery'
fi
check 'linked package parent is rejected before any restoration' grep -qx 'patched-services' "$SYS/framework/services.odex"
rm "$DATA/nemesis/apps"
mv "$DATA/nemesis/apps-real" "$DATA/nemesis/apps"
rm -f "$BG/recovery-required" "$BG/recovered"
ln -s "$W/foreign-temp" "$SYS/build.prop.gen5wkr.tmp"
if PATH="$W/bin:$PATH" BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" \
    mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/wireless-temp-link.out" 2>&1; then
    bad 'linked wireless staging path refuses recovery'
else
    ok 'linked wireless staging path refuses recovery'
fi
check 'linked staging path is detected before other module restoration' grep -qx 'patched-services' "$SYS/framework/services.odex"
rm -f "$SYS/build.prop.gen5wkr.tmp" "$BG/recovery-required"
cp "$SYS/etc/gen5w-kr-backup/wireless/manifest" "$W/wireless-manifest.saved"
cp "$SYS/etc/gen5w-kr-backup/wireless/manifest.md5" "$W/wireless-manifest.md5.saved"
cp "$SYS/etc/gen5w-kr-backup/wireless/1.applied" "$SYS/etc/unrelated.cfg"
sed "s|$SYS/build.prop|$SYS/etc/unrelated.cfg|" "$W/wireless-manifest.saved" > "$SYS/etc/gen5w-kr-backup/wireless/manifest"
md5sum "$SYS/etc/gen5w-kr-backup/wireless/manifest" | cut -d ' ' -f 1 > "$SYS/etc/gen5w-kr-backup/wireless/manifest.md5"
if PATH="$W/bin:$PATH" BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" \
    mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/wireless-path.out" 2>&1; then
    bad 'wireless journal cannot restore unrelated system files'
else
    ok 'wireless journal cannot restore unrelated system files'
fi
check 'invalid wireless target never records success' test ! -e "$BG/recovered"
cp "$W/wireless-manifest.saved" "$SYS/etc/gen5w-kr-backup/wireless/manifest"
cp "$W/wireless-manifest.md5.saved" "$SYS/etc/gen5w-kr-backup/wireless/manifest.md5"
rm -f "$BG/recovery-required" "$BG/recovered"
mkdir -p "$W/outside"
ln -s "$W/outside" "$SYS/etc/linked"
cp "$SYS/etc/gen5w-kr-backup/wireless/1.applied" "$W/outside/featurexml.cfg"
sed "s|$SYS/build.prop|$SYS/etc/linked/featurexml.cfg|" "$W/wireless-manifest.saved" > "$SYS/etc/gen5w-kr-backup/wireless/manifest"
md5sum "$SYS/etc/gen5w-kr-backup/wireless/manifest" | cut -d ' ' -f 1 > "$SYS/etc/gen5w-kr-backup/wireless/manifest.md5"
if PATH="$W/bin:$PATH" BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" \
    mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/wireless-parent-link.out" 2>&1; then
    bad 'wireless journal cannot follow a linked parent outside system'
else
    ok 'wireless journal cannot follow a linked parent outside system'
fi
check 'linked wireless parent never records success' test ! -e "$BG/recovered"
cp "$W/wireless-manifest.saved" "$SYS/etc/gen5w-kr-backup/wireless/manifest"
cp "$W/wireless-manifest.md5.saved" "$SYS/etc/gen5w-kr-backup/wireless/manifest.md5"
rm -f "$BG/recovery-required" "$BG/recovered"
mv "$SYS/etc/gen5w-kr-backup/wireless/runtime.wifi" "$W/runtime.wifi.saved"
if PATH="$W/bin:$PATH" BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" \
    mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/wifi-missing.out" 2>&1; then
    bad 'missing optional wifi runtime payload blocks recovery when its digest exists'
else
    ok 'missing optional wifi runtime payload blocks recovery when its digest exists'
fi
check 'missing wifi runtime payload never records success' test ! -e "$BG/recovered"
mv "$W/runtime.wifi.saved" "$SYS/etc/gen5w-kr-backup/wireless/runtime.wifi"
rm -f "$BG/recovery-required"
cp "$SYS/etc/gen5w-kr-backup/wireless/1.original" "$W/wireless-original.saved"
echo corrupt >> "$SYS/etc/gen5w-kr-backup/wireless/1.original"
printf 'patched-services\n' > "$SYS/framework/services.odex"
if PATH="$W/bin:$PATH" BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" \
    mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/wireless-corrupt.out" 2>&1; then
    bad 'corrupt wireless journal blocks the complete recovery'
else
    ok 'corrupt wireless journal blocks the complete recovery'
fi
check 'wireless preflight failure leaves other modules unchanged' grep -qx 'patched-services' "$SYS/framework/services.odex"
check 'wireless preflight failure preserves its journal' test -f "$SYS/etc/gen5w-kr-backup/wireless/manifest"
check 'wireless preflight failure does not report recovery' test ! -e "$BG/recovered"
cp "$W/wireless-original.saved" "$SYS/etc/gen5w-kr-backup/wireless/1.original"
rm -f "$BG/recovery-required"
cp "$W/bin/setprop" "$W/setprop.saved"
printf '#!/bin/sh\nexit 1\n' > "$W/bin/setprop"
chmod +x "$W/bin/setprop"
if PATH="$W/bin:$PATH" BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" \
    mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/wireless-prop-fail.out" 2>&1; then
    bad 'property service failure refuses recovery success'
else
    ok 'property service failure refuses recovery success'
fi
check 'property failure preserves wireless journal' test -f "$SYS/etc/gen5w-kr-backup/wireless/manifest"
check 'property failure records recovery required' test -f "$BG/recovery-required"
check 'property failure does not report success' test ! -e "$BG/recovered"
cp "$W/setprop.saved" "$W/bin/setprop"
chmod +x "$W/bin/setprop"
rm -f "$BG/recovery-required"
if PATH="$W/bin:$PATH" BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" \
    mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/wireless-valid.out" 2>&1; then
    ok 'bootguard restores a valid wireless journal'
else
    bad 'bootguard restores a valid wireless journal'
fi
check 'bootguard restores wireless build property' grep -qx 'persist.ium.support=stock' "$SYS/build.prop"
check 'bootguard restores wireless runtime property' test "$(cat "$W/props/persist.ium.support")" = stock
check 'bootguard restores wifi runtime property' test "$(cat "$W/props/persist.wifi.state")" = 1
check 'bootguard preserves wireless recovery journal' test -s "$SYS/etc/gen5w-kr-backup/wireless/manifest"
check 'bootguard records full recovery after wireless restoration' test -f "$BG/recovered"

# In wired-only mode hotspot and audio packages are absent, but their stock
# targets can still be checked using the verifiers retained by the installer.
mkdir -p "$BG/verifiers"
cp "$DATA/nemesis/apps/gen5w.kr.hotspot/bin/hotspot-patch-v039" "$BG/verifiers/hotspot-v039"
cp "$DATA/nemesis/apps/gen5w.kr.audio/bin/audio-patch" "$BG/verifiers/audio-v039"
for helper in hotspot-v039 audio-v039; do
    md5sum "$BG/verifiers/$helper" | cut -d ' ' -f 1 > "$BG/verifiers/$helper.md5"
done
rm -rf "$SYS/etc/gen5w-kr-backup/hotspot" "$SYS/etc/gen5w-kr-backup/audio" \
    "$DATA/nemesis/apps/gen5w.kr.hotspot" "$DATA/nemesis/apps/gen5w.kr.audio" \
    "$SYS/etc/gen5w-kr-backup/wireless" "$DATA/nemesis/apps/gen5w.kr.wireless" \
    "$DATA/nemesis/backup/gen5w.kr.wireless"
printf 'stock-services\n' > "$SYS/framework/services.odex"
printf 'stock-audio\n' > "$SYS/lib/libCarPlayAudio.so"
printf 'patched-systemui\n' > "$SYS/priv-app/SystemUI.odex"
rm -f "$BG/recovered" "$BG/recovery-required"
if PATH="$W/bin:$PATH" BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" \
    mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/wired-guard.out" 2>&1; then
    ok 'wired-only recovery accepts verified stock hotspot and audio'
else
    bad 'wired-only recovery accepts verified stock hotspot and audio'
fi
check 'wired-only recovery restores remaining patched module' cmp -s "$SYS/priv-app/SystemUI.odex" "$SYS/etc/gen5w-kr-backup/notice/original"
check 'wired-only recovery records success only after verification' test -f "$BG/recovered"
rm -f "$BG/recovered" "$BG/recovery-required"
printf 'patched-systemui\n' > "$SYS/priv-app/SystemUI.odex"
mv "$BG" "$BG.previous"
if PATH="$W/bin:$PATH" BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" \
    mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/previous-guard.out" 2>&1; then
    ok 'recovery selects previous guard when replacement is interrupted'
else
    bad 'recovery selects previous guard when replacement is interrupted'
fi
check 'previous guard records recovery' test -f "$BG.previous/recovered"
check 'previous guard restores remaining module' cmp -s "$SYS/priv-app/SystemUI.odex" "$SYS/etc/gen5w-kr-backup/notice/original"
mv "$BG.previous" "$BG"
printf 'tampered\n' >> "$BG/verifiers/hotspot-v039"
printf 'patched-again\n' > "$SYS/priv-app/SystemUI.odex"
rm -f "$BG/recovered" "$BG/recovery-required"
if PATH="$W/bin:$PATH" BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" \
    mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/wired-tampered.out" 2>&1; then
    bad 'wired-only recovery refuses a modified stock verifier'
else
    ok 'wired-only recovery refuses a modified stock verifier'
fi
check 'modified verifier prevents other restoration' test "$(cat "$SYS/priv-app/SystemUI.odex")" = patched-again
check 'modified verifier never records recovery success' test ! -e "$BG/recovered"
# Safe edition: hotspot, audio AND notice are absent. SystemUI must be proven stock
# with the retained verifier, then the bridge ODEX files are restored.
cp "$DATA/nemesis/apps/gen5w.kr.hotspot/bin/hotspot-patch-v039" "$BG/verifiers/hotspot-v039" 2>/dev/null ||
    cp "$BG/verifiers/audio-v039" "$BG/verifiers/hotspot-v039"
md5sum "$BG/verifiers/hotspot-v039" | cut -d ' ' -f 1 > "$BG/verifiers/hotspot-v039.md5"
cp "$DATA/nemesis/apps/gen5w.kr.notice/bin/notice-patch-v039" "$BG/verifiers/notice-v039"
md5sum "$BG/verifiers/notice-v039" | cut -d ' ' -f 1 > "$BG/verifiers/notice-v039.md5"
rm -rf "$SYS/etc/gen5w-kr-backup/notice" "$DATA/nemesis/apps/gen5w.kr.notice"
printf 'stock-systemui\n' > "$SYS/priv-app/SystemUI.odex"
printf 'patched-iap2\n' > "$SYS/app/Iap2ServerApp.odex"
rm -f "$BG/recovered" "$BG/recovery-required"
if PATH="$W/bin:$PATH" BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" \
    mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/safe-guard.out" 2>&1; then
    ok 'safe edition recovery accepts verified stock SystemUI without notice package'
else
    bad 'safe edition recovery accepts verified stock SystemUI without notice package'
fi
check 'safe edition recovery restores bridge ODEX' cmp -s "$SYS/app/Iap2ServerApp.odex" "$SYS/etc/gen5w-kr-backup/bridge/original"
check 'safe edition recovery records success' test -f "$BG/recovered"
printf 'patched-systemui\n' > "$SYS/priv-app/SystemUI.odex"
printf 'patched-iap2\n' > "$SYS/app/Iap2ServerApp.odex"
rm -f "$BG/recovered" "$BG/recovery-required"
if PATH="$W/bin:$PATH" BG_TEST_SYS="$SYS" BG_TEST_DATA="$DATA" BG_TEST_NEM="$W/nemesis" BG_TEST_DALVIK="$CACHE/dalvik-cache" \
    mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-recover.sh" > "$W/safe-unknown.out" 2>&1; then
    bad 'safe edition recovery refuses an unowned modified SystemUI'
else
    ok 'safe edition recovery refuses an unowned modified SystemUI'
fi
check 'unowned SystemUI leaves recovery to the user' test -f "$BG/recovery-required"
done_tests bootguard
