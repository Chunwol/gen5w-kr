#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/gen5w-prepare.XXXXXX)
trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bundle/permissions" "$t/root/system/app" "$t/root/system/etc/permissions" "$t/root/data"
cp tools/portable/prepare.sh "$t/bundle/"
cp packages/wireless-enable/files/permissions/*wireless.xml packages/wireless-enable/files/permissions/*wifihotspot.xml "$t/bundle/permissions/"
cat > "$t/helper" <<'PY'
#!/usr/bin/python3
import hashlib,os,stat,sys
cmd,path=sys.argv[1:3]
if cmd=='sha256': print(hashlib.sha256(open(path,'rb').read()).hexdigest())
elif cmd=='metadata':
 s=os.stat(path); print(f'{s.st_uid}|{s.st_gid}|{stat.S_IMODE(s.st_mode):o}')
else:
 data=open(path,'rb').read()
 if data!=b'supported':sys.exit(1)
 with open(sys.argv[3],'xb') as f:f.write(b'patched:'+cmd.encode())
PY
chmod +x "$t/helper"
for file in Iap2ServerApp HKMC_DiPO HKMC_GPM HKMC_WifiSettings; do
    echo -n supported > "$t/root/system/app/$file.odex"
    chmod 644 "$t/root/system/app/$file.odex"
done
echo '<permissions><feature name="stock" /></permissions>' > "$t/root/system/etc/permissions/stock.xml"
chmod 644 "$t/root/system/etc/permissions/stock.xml"
echo 'rm /system/etc/permissions/com.hkmc.software.connectivity.carplay_wireless.xml' > "$t/root/system/etc/featurexml.cfg"
printf '%s\n' 'literal\ntext' >> "$t/root/system/etc/featurexml.cfg"
chmod 644 "$t/root/system/etc/featurexml.cfg"
export PORTABLE_TEST_ROOT=$t/root PORTABLE_TEST_HELPER=$t/helper PORTABLE_TEST_FEATUREXML=/system/etc/featurexml.cfg
shell=${SHELL_UNDER_TEST:-mksh}
"$shell" "$t/bundle/prepare.sh" /data/plan > "$t/report"
grep -q '^bt|prepared|structural$' "$t/report"
grep -q '^audio|skipped|missing-stock$' "$t/report"
grep -q '^projection|prepared|configuration-only$' "$t/report"
grep -q '^#rm ' "$t/root/data/plan/files/featurexml.cfg"
grep -Fx 'literal\ntext' "$t/root/data/plan/files/featurexml.cfg" >/dev/null
expected=$(printf supported | sha256sum | cut -d' ' -f1)
[ "$(cat "$t/root/data/plan/files/bt.odex.stock")" = "$expected" ]
cmp "$t/root/system/etc/permissions/stock.xml" "$t/root/data/plan/files/permissions/stock.xml"
[ "$(wc -l < "$t/root/data/plan/manifest")" = 6 ]
[ "$(cat "$t/root/system/app/Iap2ServerApp.odex")" = supported ]
if "$shell" "$t/bundle/prepare.sh" /data/plan route >/dev/null 2>&1; then echo 'FAIL overwrote existing plan'; exit 1; fi
if "$shell" "$t/bundle/prepare.sh" /data/conflict route bt >/dev/null 2>&1; then echo 'FAIL overlapping targets'; exit 1; fi
[ ! -e "$t/root/data/conflict" ]
if "$shell" "$t/bundle/prepare.sh" /data/duplicate route route >/dev/null 2>&1; then echo 'FAIL duplicate feature'; exit 1; fi
echo -n unsupported > "$t/root/system/app/HKMC_GPM.odex"
"$shell" "$t/bundle/prepare.sh" /data/partial route gpm > "$t/report"
grep -q '^gpm|skipped|unsupported-structure$' "$t/report"
grep -q '^route|prepared|structural$' "$t/report"
[ "$(wc -l < "$t/root/data/partial/manifest")" = 1 ]
ln -s "$t/root/data" "$t/root/data/foreign"
if "$shell" "$t/bundle/prepare.sh" /data/foreign/escape route >/dev/null 2>&1; then echo 'FAIL symlink parent'; exit 1; fi
mkdir -p "$t/root/system/onebin/osah_kr"
cp "$t/root/system/etc/featurexml.cfg" "$t/root/system/onebin/osah_kr/featurexml.cfg"
export PORTABLE_TEST_FEATUREXML=/system/onebin/osah_kr/featurexml.cfg
"$shell" "$t/bundle/prepare.sh" /data/onebin projection > "$t/report"
grep -q '|/system/onebin/osah_kr/featurexml.cfg|' "$t/root/data/onebin/manifest"
grep -Fx 'literal\ntext' "$t/root/data/onebin/files/featurexml.cfg" >/dev/null

echo 'PASS portable prepare: independent features, config inventory, stock unchanged, overlap/overwrite/symlink refusal'
