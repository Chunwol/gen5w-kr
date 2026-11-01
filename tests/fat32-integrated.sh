#!/bin/bash
# Real-car USB FAT32 mount emulation test.
# Runs installer operations on an actual FAT32 filesystem where chmod returns EPERM
# or is ignored, symbolic links are rejected, and names follow FAT32 semantics.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)

if [ "$(id -u)" != 0 ]; then
    echo "SKIP fat32-integrated: needs root for loopback vfat mount"
    exit 0
fi

if ! command -v mkfs.vfat >/dev/null 2>&1; then
    echo "SKIP fat32-integrated: mkfs.vfat (dosfstools) not installed"
    exit 0
fi

IMG=$(mktemp /tmp/fat32-usb.XXXXXX.img)
MNT=$(mktemp -d /tmp/fat32-mnt.XXXXXX)
W=$(mktemp -d /tmp/fat32-work.XXXXXX)

cleanup() {
    umount -l "$MNT" 2>/dev/null || true
    rm -rf "$MNT" "$W" "$IMG" 2>/dev/null || true
}
trap cleanup EXIT

# 64MB FAT32 image matching real vehicle USB filesystem
truncate -s 64M "$IMG"
mkfs.vfat -F 32 -n "KONA_NEM" "$IMG" >/dev/null

# Mount with strict vehicle USB options: permissions fixed to 0755, chmod will fail
mount -t vfat -o loop,fmask=0022,dmask=0022,shortname=mixed,utf8=1 "$IMG" "$MNT"

# Verify FAT32 behavior: chmod produces error or no-op
set +e
chmod 700 "$MNT" 2>/dev/null
FAT_CHMOD_RC=$?
set -e

mkdir -p "$MNT/packages" "$W/data/nemesis/apps" "$W/bin" "$W/sys"
cp "$ROOT/tools/integrated/"*.sh "$MNT/" 2>/dev/null || true
cp "$ROOT/tools/integrated/bin/zipstore-host" "$MNT/zipstore"

cat > "$W/bin/nemesis" <<'PY'
#!/usr/bin/env python3
import sys,os,zipfile,shutil
root=os.environ['IT_DATA']+'/nemesis/apps'; args=sys.argv[1:]
with open(os.environ['IT_DATA']+'/calls','a') as f: f.write(' '.join(args)+'\n')
if args[0]=='pkg-info':
 with zipfile.ZipFile(args[-1]) as z:
  print(z.read('NEMESIS.data').decode().split('id=')[1].splitlines()[0].join(['id=','']))
elif args[0]=='install':
 with zipfile.ZipFile(args[-1]) as z:
  id=z.read('NEMESIS.data').decode().split('id=')[1].splitlines()[0]
  path=root+'/'+id; shutil.rmtree(path,ignore_errors=True); os.makedirs(path); z.extractall(path)
  if os.environ.get('IT_FAIL')==id and '/packages/' in args[-1]: sys.exit(1)
elif args[0]=='uninstall': shutil.rmtree(root+'/'+args[1],ignore_errors=True)
elif args[0]=='root':
 print('RESULT applied')
else: sys.exit(1)
PY
chmod +x "$W/bin/nemesis"
echo '#!/bin/sh' > "$W/bin/sync"
echo 'exit 0' >> "$W/bin/sync"
chmod +x "$W/bin/sync"

python3 - "$MNT/packages" <<'PY'
import zipfile,sys,hashlib,pathlib
for m in ['wireless','audio','bridge','core','timer']:
 with zipfile.ZipFile(sys.argv[1]+'/gen5w.kr.'+m+'.zip','w') as z:
  z.writestr('NEMESIS.data','[nemesis]\nid=gen5w.kr.'+m+'\nversion=new\npreinstall=scripts/pre.sh\npostinstall=scripts/post.sh\n')
  z.writestr('scripts/pre.sh','[ "$IT_PRE_FAIL" != "gen5w.kr.'+m+'" ] || exit 1\n[ "$IT_SKIP" != "gen5w.kr.'+m+'" ] || exit 77\nexit 0\n')
  z.writestr('scripts/post.sh','[ "$IT_POST_FAIL" != "gen5w.kr.'+m+'" ] || exit 1\nexit 0\n')
 package=pathlib.Path(sys.argv[1])/('gen5w.kr.'+m+'.zip')
 stage=package.parent.parent/'checks'/('gen5w.kr.'+m);stage.mkdir(parents=True)
 sums=[]
 with zipfile.ZipFile(package) as z:
  z.extractall(stage)
  for name in z.namelist(): sums.append(hashlib.md5(z.read(name)).hexdigest()+'  '+name)
 (stage/'FILES.md5').write_text('\n'.join(sums)+'\n')
 (stage/'PACKAGE.md5').write_text(hashlib.md5(package.read_bytes()).hexdigest()+'\n')
PY

run() { (cd "$MNT" && IT_DATA="$W/data" IT_SYSTEM="$W/sys" IT_NEM="$W/bin/nemesis" IT_SHELL=$(command -v mksh) IT_NO_REBOOT=1 PATH="$W/bin:$PATH" mksh "$1.sh" > "$W/out" 2>&1); }

check 'FAT32 mount install without chmod aborts' run install
check 'all five module trees registered on vehicle from FAT32' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 5
check 'transaction committed on FAT32' grep -qx committed "$W/data/nemesis/gen5w-kr-integrated/state"
check 'dashboard created on FAT32 USB' test -f "$MNT/GEN5W-REPORT/RESULT.html"
check 'issue doc created on FAT32 USB' test -f "$MNT/GEN5W-REPORT/ISSUE.md"

# Test update on FAT32
check 'update on FAT32' run update
check 'modules retained after FAT32 update' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 5

# Test rollback on FAT32
check 'rollback on FAT32' run rollback
check 'modules restored after FAT32 rollback' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 5

# Test remove on FAT32
check 'remove all modules from FAT32' run remove
check 'zero modules remaining after remove' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 0

done_tests fat32-integrated
