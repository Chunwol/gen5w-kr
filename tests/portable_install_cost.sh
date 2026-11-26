#!/bin/bash
# Install cost budget: prepare.sh on a vehicle-sized synthetic /system
# (87 permission XMLs, four odex targets, build.prop, qb_runtime.sh) must not
# spawn the native helper once per check. Every helper call is a process
# start on the head unit, and in the emulator it costs ~1 s.
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/gen5w-cost.XXXXXX)
trap 'rc=$?; rm -rf "$t"; exit $rc' EXIT
XML_COUNT=${COST_XML_COUNT:-87}
mkdir -p "$t/bundle/permissions" "$t/bundle/dalvik" "$t/root/system/app" "$t/root/system/etc/permissions" "$t/root/data" "$t/bin"
cp tools/portable/prepare.sh tools/portable/wrap-common.sh tools/portable/wrap-dipo.sh tools/portable/wrap-gpm.sh tools/portable/wrap-navi.sh "$t/bundle/"
for f in engine.jar adapter.jar libgen5whook.so; do printf 'fixture %s\n' "$f" > "$t/bundle/dalvik/$f"; done
cp packages/wireless-enable/files/permissions/*wireless.xml packages/wireless-enable/files/permissions/*wifihotspot.xml "$t/bundle/permissions/"
cat > "$t/helper" <<'PY'
#!/usr/bin/python3
import hashlib,os,stat,sys
cmd=sys.argv[1]
with open(os.environ['COST_LOG'],'a') as log: log.write(cmd+'\n')
def ident(path):
    s=os.stat(path)
    return '%s|0|0|%o|system_file' % (hashlib.sha256(open(path,'rb').read()).hexdigest(), stat.S_IMODE(s.st_mode))
if cmd=='sha256': print(hashlib.sha256(open(sys.argv[2],'rb').read()).hexdigest())
elif cmd=='metadata':
    s=os.stat(sys.argv[2]); print(f'0|0|{stat.S_IMODE(s.st_mode):o}')
elif cmd=='label': print('system_file')
elif cmd=='ident':
    for p in sys.argv[2:]: print(ident(p))
elif cmd=='setmeta':
    a=sys.argv[2:]
    for k in range(0,len(a),4):
        os.chmod(a[k],int(a[k+3],8))
elif cmd in ('bt','route','dipo','gpm','hotspot'):
    data=open(sys.argv[2],'rb').read()
    if data!=b'supported': sys.exit(1)
    with open(sys.argv[3],'xb') as f: f.write(b'patched:'+cmd.encode())
else: sys.exit(64)
PY
chmod +x "$t/helper"
for file in Iap2ServerApp HKMC_DiPO HKMC_GPM HKMC_WifiSettings; do
    printf supported > "$t/root/system/app/$file.odex"
done
i=0
while [ "$i" -lt "$XML_COUNT" ]; do
    printf '<permissions><feature name="com.hkmc.fixture.%03d" /></permissions>\n' "$i" > "$t/root/system/etc/permissions/com.hkmc.fixture.$(printf %03d "$i").xml"
    i=$((i+1))
done
printf 'ro.build.id=fixture\n' > "$t/root/system/build.prop"
printf '%s\n' '#!/system/bin/sh' 'if [ "$1" == "check_fixed_uid" ]; then' '    :' 'fi' > "$t/root/system/etc/qb_runtime.sh"
printf 'rm /system/etc/permissions/com.hkmc.software.connectivity.carplay_wireless.xml\n' > "$t/root/system/etc/featurexml.cfg"
chmod -R u=rwX,go=rX "$t/root/system"
export PORTABLE_TEST_ROOT=$t/root PORTABLE_TEST_HELPER=$t/helper PORTABLE_TEST_FEATUREXML=/system/etc/featurexml.cfg COST_LOG=$t/calls
shell=${SHELL_UNDER_TEST:-mksh}
[ -z "${COST_TRACE:-}" ] || shell="$shell -x"

measure() {  # label plan
    : > "$t/calls"
    local start end
    start=$(date +%s%N)
    $shell "$t/bundle/prepare.sh" "$2" --stock-origins > "$t/report-$1" 2>&1 || { echo "FAIL prepare ($1)"; cat "$t/report-$1"; exit 1; }
    end=$(date +%s%N)
    printf 'COST %-6s helper=%-5s ms=%s  (%s)\n' "$1" "$(wc -l < "$t/calls")" $(( (end-start)/1000000 )) \
        "$(sort "$t/calls" | uniq -c | awk '{printf "%s=%s ", $2, $1}')"
}

measure fresh /data/plan-fresh
fresh_calls=$(wc -l < "$t/calls")
grep -q '^projection|prepared|configuration-only$' "$t/report-fresh"

# Update mode: a previous persistent install recorded every captured origin.
rec=$t/root/data/local/gen5w-portable/persistent/recovery
mkdir -p "$rec/originals"
printf 'GEN5W-RECOVERY-MANIFEST|2\n' > "$rec/manifest"
while IFS='|' read -r target hash uid gid mode label; do
    mkdir -p "$rec/originals${target%/*}"
    cp -p "$t/root/data/plan-fresh/stock-origins$target" "$rec/originals$target"
    printf '%s|file|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|-\n' "$target" "$hash" "$hash" "$uid" "$gid" "$mode" "$label" "$uid" "$gid" "$mode" "$label" >> "$rec/manifest"
done < "$t/root/data/plan-fresh/stock-origins/index.tsv"
measure update /data/plan-update
update_calls=$(wc -l < "$t/calls")
# Same plan either way: the origins and manifest rows must not depend on the mode.
cmp "$t/root/data/plan-fresh/stock-origins/index.tsv" "$t/root/data/plan-update/stock-origins/index.tsv"
sed 's#/data/plan-fresh/#/data/plan/#' "$t/root/data/plan-fresh/manifest" > "$t/m1"
sed 's#/data/plan-update/#/data/plan/#' "$t/root/data/plan-update/manifest" > "$t/m2"
cmp "$t/m1" "$t/m2"

# persistent-migrate applies the fresh plan through the host /system adapter.
mkdir -p "$t/root/$t"
printf '#!/bin/sh
echo "$1" >> "$COST_LOG"
exec python3 %s --adapter "$@"
' "$PWD/tests/portable_persistent_migrate.py" > "$t/madapter"
chmod +x "$t/madapter"; cp "$t/madapter" "$t/root/$t/madapter"
echo ro > "$t/root/.mount-state"; echo 100000000 > "$t/root/.free-bytes"; echo '{}' > "$t/root/.labels.json"
rm -rf "$rec" "$t/root/data/local/gen5w-portable/persistent"
: > "$t/calls"
start=$(date +%s%N)
PORTABLE_TEST_MIGRATE_ADAPTER=$t/madapter $shell tools/portable/persistent-migrate.sh apply /data/plan-fresh/manifest /data/plan-fresh/stock-origins > "$t/report-migrate" 2>&1 ||
    { echo 'FAIL migrate'; tail -5 "$t/report-migrate"; exit 1; }
end=$(date +%s%N)
migrate_calls=$(wc -l < "$t/calls")
printf 'COST %-6s helper=%-5s ms=%s  (%s)
' migrate "$migrate_calls" $(( (end-start)/1000000 ))     "$(sort "$t/calls" | uniq -c | awk '{printf "%s=%s ", $2, $1}')"
cmp "$t/root/data/plan-fresh/files/permissions/com.hkmc.fixture.000.xml" "$t/root/system/etc/permissions/com.hkmc.fixture.000.xml"
[ -f "$t/root/system/etc/permissions/com.hkmc.software.wifihotspot.xml" ]
[ "$(cat "$t/root/system/app/HKMC_DiPO.odex")" = patched:dipo ]

# persistent-start verify (run at install, at commit and on every boot).
mkdir -p "$t/bundle/bin"
cp tools/portable/persistent-start.sh "$t/bundle/"
printf '#!/bin/sh
exec %s "$@"
' "$t/helper" > "$t/bundle/bin/dex-patch"; chmod +x "$t/bundle/bin/dex-patch"
: > "$t/calls"
$shell "$t/bundle/persistent-start.sh" verify > "$t/report-start" 2>&1 || { echo 'FAIL persistent-start verify'; cat "$t/report-start"; exit 1; }
start_calls=$(wc -l < "$t/calls")
printf 'COST %-6s helper=%-5s (%s)
' start "$start_calls" "$(sort "$t/calls" | uniq -c | awk '{printf "%s=%s ", $2, $1}')"

# Budgets: before this change the same fixture needed 1805/2178 (prepare),
# 3430 (migrate) and ~400 (verify) helper processes.
[ "$fresh_calls" -le 60 ] && [ "$update_calls" -le 60 ] || { echo "FAIL prepare helper calls over budget (fresh=$fresh_calls update=$update_calls)"; exit 1; }
# The host adapter adds one 'visible' call per target that the unit answers in-shell.
[ "$migrate_calls" -le 260 ] || { echo "FAIL migrate helper calls over budget ($migrate_calls)"; exit 1; }
[ "$start_calls" -le 5 ] || { echo "FAIL persistent-start helper calls over budget ($start_calls)"; exit 1; }
echo 'PASS install cost measured'
