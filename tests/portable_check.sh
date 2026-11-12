#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/gen5w-check.XXXXXX)
trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bundle" "$t/root/system/app" "$t/root/system/etc/permissions" "$t/root/data" "$t/props"
cp tools/portable/check.sh "$t/bundle/"
echo stock > "$t/root/system/app/HKMC_DiPO.odex"
echo '<permissions/>' > "$t/root/system/etc/permissions/stock.xml"
cat > "$t/adapter" <<'SH'
#!/bin/bash
case "$1" in boot) cat "$PROPS/boot";; prop) cat "$PROPS/$2" 2>/dev/null || :;; *) exit 1;; esac
SH
chmod +x "$t/adapter"
export PROPS=$t/props PORTABLE_TEST_ROOT=$t/root PORTABLE_TEST_CHECK_ADAPTER=$t/adapter
cat > "$t/helper" <<'PY'
#!/usr/bin/python3
import hashlib,os,stat,sys
command,path=sys.argv[1:3]
if command=='sha256': print(hashlib.sha256(open(path,'rb').read()).hexdigest())
elif command=='identity':
 value=os.stat(path); print(f'{value.st_dev}:{value.st_ino}')
elif command=='metadata':
 value=os.stat(path); print(f'{value.st_uid}|{value.st_gid}|{stat.S_IMODE(value.st_mode):o}')
else: sys.exit(1)
PY
chmod +x "$t/helper"
export PORTABLE_TEST_HELPER=$t/helper
echo boot1 > "$PROPS/boot"
echo usb > "$PROPS/persist.ium.support"
run() { mksh "$t/bundle/check.sh" "$@"; }
run snapshot /data/baseline
if run snapshot /data/baseline >/dev/null 2>&1; then echo 'FAIL baseline overwritten'; exit 1; fi
if run restored /data/baseline >/dev/null 2>&1; then echo 'FAIL accepted same boot'; exit 1; fi
run prepare-probe /data/probe
cmp "$t/root/system/app/HKMC_DiPO.odex" "$t/root/data/probe/dipo.odex"
grep -q '^probe|/data/probe/dipo.odex|' "$t/root/data/probe/manifest"
echo boot2 > "$PROPS/boot"
run restored /data/baseline
echo carplay > "$PROPS/persist.ium.support"
if run restored /data/baseline >/dev/null 2>&1; then echo 'FAIL ignored persistent property mutation'; exit 1; fi
echo usb > "$PROPS/persist.ium.support"
echo changed > "$t/root/system/app/HKMC_DiPO.odex"
if run restored /data/baseline >/dev/null 2>&1; then echo 'FAIL ignored changed stock'; exit 1; fi
echo stock > "$t/root/system/app/HKMC_DiPO.odex"
echo '<added/>' > "$t/root/system/etc/permissions/added.xml"
if run restored /data/baseline >/dev/null 2>&1; then echo 'FAIL ignored added XML'; exit 1; fi
rm "$t/root/system/etc/permissions/added.xml"
run restored /data/baseline
ln -s "$t/root/data/baseline" "$t/root/data/alias"
if run restored /data/alias >/dev/null 2>&1; then echo 'FAIL accepted symlink baseline'; exit 1; fi
echo 'PASS validation: byte-identical probe, boot identity, stock/property/XML changes and immutable baseline'

mkdir -p "$t/root/data/data/com.daudio.app.dipo/files" "$t/root/proc/42"
printf 'pid=42\nmonotonic=1.000\nmode=no-hooks\nboot_id=boot2\n' > "$t/root/data/data/com.daudio.app.dipo/files/gen5w-portable-probe"
printf 'com.daudio.app.dipo\0' > "$t/root/proc/42/cmdline"
inode=$(stat -c %i "$t/root/system/app/HKMC_DiPO.odex")
echo "1-2 r--p 0 00:01 $inode /system/app/HKMC_DiPO.odex" > "$t/root/proc/42/maps"
run probe-loaded
: > "$t/root/proc/42/maps"
if run probe-loaded >/dev/null 2>&1; then echo 'FAIL accepted unmapped ODEX'; exit 1; fi
echo "1-2 r--p 0 00:01 $inode /system/app/HKMC_DiPO.odex" > "$t/root/proc/42/maps"
echo boot3 > "$PROPS/boot"
if run probe-loaded >/dev/null 2>&1; then echo 'FAIL accepted stale probe marker'; exit 1; fi
echo 'PASS real-loader checks: current boot/PID, library marker, active ODEX mapping and stale/missing refusal'
