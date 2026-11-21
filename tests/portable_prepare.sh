#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/gen5w-prepare.XXXXXX)
trap 'rc=$?; rm -rf "$t"; exit $rc' EXIT
mkdir -p "$t/bundle/permissions" "$t/bundle/dalvik" "$t/root/system/app" "$t/root/system/etc/permissions" "$t/root/data"
cp tools/portable/prepare.sh "$t/bundle/"
cp tools/portable/wrap-common.sh tools/portable/wrap-dipo.sh tools/portable/wrap-gpm.sh "$t/bundle/"
# Preparation validates these runtime payload paths but does not execute them.
# Use named non-empty stand-ins because generated Dalvik artifacts are build outputs.
printf 'fixture engine jar payload\n' > "$t/bundle/dalvik/engine.jar"
printf 'fixture adapter jar payload\n' > "$t/bundle/dalvik/adapter.jar"
printf 'fixture native hook payload\n' > "$t/bundle/dalvik/libgen5whook.so"
cp packages/wireless-enable/files/permissions/*wireless.xml packages/wireless-enable/files/permissions/*wifihotspot.xml "$t/bundle/permissions/"
cat > "$t/helper" <<'PY'
#!/usr/bin/python3
import hashlib,os,stat,sys
cmd,path=sys.argv[1:3]
def lab(p): return 'u:object_r:system_app_file:s0' if '/system/app/' in p else 'u:object_r:system_file:s0'
if cmd=='sha256': print(hashlib.sha256(open(path,'rb').read()).hexdigest())
elif cmd=='metadata':
 s=os.stat(path); print(f'{s.st_uid}|{s.st_gid}|{stat.S_IMODE(s.st_mode):o}')
elif cmd=='label': print(lab(path))
elif cmd=='ident':
 for p in sys.argv[2:]:
  s=os.stat(p,follow_symlinks=False)
  if not stat.S_ISREG(s.st_mode): sys.exit(1)
  print(f'{hashlib.sha256(open(p,"rb").read()).hexdigest()}|{s.st_uid}|{s.st_gid}|{stat.S_IMODE(s.st_mode):o}|{lab(p)}')
elif cmd=='setmeta':
 a=sys.argv[2:]
 for k in range(0,len(a),4):
  try: os.chown(a[k],int(a[k+1]),int(a[k+2]))
  except PermissionError:
   if (int(a[k+1]),int(a[k+2])) not in ((os.getuid(),os.getgid()),(0,0)): raise
  os.chmod(a[k],int(a[k+3],8))
else:
 data=open(path,'rb').read()
 if data not in (b'supported',b'stock-dipo-bytes\x00\xff'):sys.exit(1)
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
[ ! -e "$t/root/data/plan/stock-origins" ]
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

# Opt-in snapshots retain exact stock bytes and indexed file metadata. The
# permissions directory's own uid/gid/mode stay on the generated manifest row.
printf 'stock-dipo-bytes\000\377' > "$t/root/system/app/HKMC_DiPO.odex"
chmod 640 "$t/root/system/app/HKMC_DiPO.odex"
chmod 640 "$t/root/system/app/Iap2ServerApp.odex"
echo '<permissions><feature name="origin-stock" /></permissions>' > "$t/root/system/etc/permissions/stock.xml"
chmod 640 "$t/root/system/etc/permissions/stock.xml"
chmod 750 "$t/root/system/etc/permissions"
mkdir -p "$t/bin"
cat > "$t/bin/ls" <<'SH'
#!/bin/sh
if [ "$1" = -Zd ]; then
    case "$2" in
      *HKMC_DiPO.odex) echo u:object_r:system_app_file:s0;;
      *HKMC_GPM.odex) echo u:object_r:system_app_file:s0;;
      *build.prop) echo u:object_r:system_file:s0;;
      *stock.xml) echo u:object_r:system_file:s0;;
      */permissions) echo u:object_r:system_file:s0;;
      *) exit 1;;
    esac
else exec /bin/ls "$@"; fi
SH
chmod +x "$t/bin/ls"
PATH="$t/bin:$PATH" "$shell" "$t/bundle/prepare.sh" /data/origin-plan --stock-origins bt projection > "$t/report"
cmp "$t/root/system/app/Iap2ServerApp.odex" "$t/root/data/origin-plan/stock-origins/system/app/Iap2ServerApp.odex"
cmp "$t/root/system/etc/permissions/stock.xml" "$t/root/data/origin-plan/stock-origins/system/etc/permissions/stock.xml"
origin_index="$t/root/data/origin-plan/stock-origins/index.tsv"
grep -Fx "/system/app/Iap2ServerApp.odex|$(sha256sum "$t/root/system/app/Iap2ServerApp.odex" | cut -d' ' -f1)|$(id -u)|$(id -g)|640|u:object_r:system_app_file:s0" "$origin_index" >/dev/null
grep -Fx "/system/etc/permissions/stock.xml|$(sha256sum "$t/root/system/etc/permissions/stock.xml" | cut -d' ' -f1)|$(id -u)|$(id -g)|640|u:object_r:system_file:s0" "$origin_index" >/dev/null
grep -Fx "/system/onebin/osah_kr/featurexml.cfg|$(sha256sum "$t/root/system/onebin/osah_kr/featurexml.cfg" | cut -d' ' -f1)|$(id -u)|$(id -g)|644|u:object_r:system_file:s0" "$origin_index" >/dev/null
[ "$(grep -c '^/system/' "$origin_index")" = 3 ]
awk -F'|' -v uid="$(id -u)" -v gid="$(id -g)" '$1=="projection" && $3=="/system/etc/permissions" && $5==uid && $6==gid && $7==750 && $8=="directory" {found=1} END {exit !found}' "$t/root/data/origin-plan/manifest"
[ "$(stat -c '%a' "$t/root/data/origin-plan/files/permissions")" = 750 ]

# Persistent wrapper properties belong in the origin-backed build.prop only
# for features whose structural patch actually succeeded. Preserve the exact
# original bytes and metadata, including unrelated lines and duplicate owned
# entries, in the immutable stock-origin snapshot.
DIPO_WRAP='W=/data/nemesis/apps/gen5w.kr.portable/wrap-dipo.sh;[ -f $W ]||W=;exec ${W:+sh $W}'
GPM_WRAP='W=/data/nemesis/apps/gen5w.kr.portable/wrap-gpm.sh;[ -f $W ]||W=;exec ${W:+sh $W}'
cat > "$t/root/system/build.prop" <<EOF
# keep this comment
persist.ium.support=stock
custom.device.flag=preserve-me
EOF
chmod 644 "$t/root/system/build.prop"
echo -n unsupported > "$t/root/system/app/HKMC_GPM.odex"
cp "$t/root/system/build.prop" "$t/build-prop-dipo-only.original"
PATH="$t/bin:$PATH" "$shell" "$t/bundle/prepare.sh" /data/wrapper-dipo-only --stock-origins dipo gpm > "$t/report"
grep -q '^dipo|prepared|structural$' "$t/report"
grep -q '^gpm|skipped|unsupported-structure$' "$t/report"
[ "$(grep -Fxc "wrap.com.daudio.app.dipo=$DIPO_WRAP" "$t/root/data/wrapper-dipo-only/files/build.prop")" = 1 ]
! grep -q '^wrap.com.google.android.project=' "$t/root/data/wrapper-dipo-only/files/build.prop"
grep -Fx '# keep this comment' "$t/root/data/wrapper-dipo-only/files/build.prop" >/dev/null
grep -Fx 'persist.ium.support=stock' "$t/root/data/wrapper-dipo-only/files/build.prop" >/dev/null
cmp "$t/build-prop-dipo-only.original" "$t/root/data/wrapper-dipo-only/stock-origins/system/build.prop"
wrapper_origin_index="$t/root/data/wrapper-dipo-only/stock-origins/index.tsv"
grep -Fx "/system/build.prop|$(sha256sum "$t/build-prop-dipo-only.original" | cut -d' ' -f1)|$(id -u)|$(id -g)|644|u:object_r:system_file:s0" "$wrapper_origin_index" >/dev/null
[ "$(grep -c '^/system/build.prop|' "$wrapper_origin_index")" = 1 ]
! grep -q '^/system/app/HKMC_GPM.odex|' "$wrapper_origin_index"
awk -F'|' '$3=="/system/build.prop" {n++} END {exit n != 1}' "$t/root/data/wrapper-dipo-only/manifest"

# Exact pre-existing owned values are normalized to one row each. The stock
# origin remains byte-for-byte identical to the source with duplicate rows.
echo -n supported > "$t/root/system/app/HKMC_GPM.odex"
cat > "$t/root/system/build.prop" <<EOF
# unrelated build properties stay in place
custom.device.flag=preserve-me
wrap.com.daudio.app.dipo=$DIPO_WRAP
wrap.com.daudio.app.dipo=$DIPO_WRAP
wrap.com.google.android.project=$GPM_WRAP
wrap.com.google.android.project=$GPM_WRAP
EOF
chmod 644 "$t/root/system/build.prop"
cp "$t/root/system/build.prop" "$t/build-prop-both.original"
PATH="$t/bin:$PATH" "$shell" "$t/bundle/prepare.sh" /data/wrapper-both --stock-origins dipo gpm > "$t/report"
grep -q '^dipo|prepared|structural$' "$t/report"
grep -q '^gpm|prepared|structural$' "$t/report"
[ "$(grep -Fxc "wrap.com.daudio.app.dipo=$DIPO_WRAP" "$t/root/data/wrapper-both/files/build.prop")" = 1 ]
[ "$(grep -Fxc "wrap.com.google.android.project=$GPM_WRAP" "$t/root/data/wrapper-both/files/build.prop")" = 1 ]
grep -Fx '# unrelated build properties stay in place' "$t/root/data/wrapper-both/files/build.prop" >/dev/null
grep -Fx 'custom.device.flag=preserve-me' "$t/root/data/wrapper-both/files/build.prop" >/dev/null
cmp "$t/build-prop-both.original" "$t/root/data/wrapper-both/stock-origins/system/build.prop"
wrapper_origin_index="$t/root/data/wrapper-both/stock-origins/index.tsv"
grep -Fx "/system/build.prop|$(sha256sum "$t/build-prop-both.original" | cut -d' ' -f1)|$(id -u)|$(id -g)|644|u:object_r:system_file:s0" "$wrapper_origin_index" >/dev/null
[ "$(grep -c '^/system/build.prop|' "$wrapper_origin_index")" = 1 ]
awk -F'|' '$3=="/system/build.prop" {n++} END {exit n != 1}' "$t/root/data/wrapper-both/manifest"

# The bootguard hook preserves every stock byte after the shebang.
qb="$t/root/system/etc/qb_runtime.sh"
printf '%s\n' '#!/system/bin/sh' '# stock comment' 'if [ "$1" = "check_fixed_uid" ]; then' '    echo stock' 'fi' > "$qb"
printf '# EOF without newline' >> "$qb"
cp "$qb" "$t/qb.stock"
"$shell" "$t/bundle/prepare.sh" /data/guard-valid --stock-origins dipo > "$t/report"
grep -qx 'bootguard|prepared|prezygote-qb-runtime' "$t/report"
line=$(sed -n "s/^BOOTGUARD_LINE='\(.*\)'$/\1/p" tools/portable/prepare.sh)
[ "$(sed -n '2p' "$t/root/data/guard-valid/files/qb_runtime.sh")" = "$line" ]
sed '2d' "$t/root/data/guard-valid/files/qb_runtime.sh" > "$t/qb.rest"
cmp "$t/qb.stock" "$t/qb.rest"
cmp "$qb" "$t/qb.stock"
grep -q '^bootguard|.*|/system/etc/qb_runtime.sh|' "$t/root/data/guard-valid/manifest"
sed '1d' "$t/qb.stock" > "$qb"
"$shell" "$t/bundle/prepare.sh" /data/guard-invalid --stock-origins dipo > "$t/report"
grep -qx 'bootguard|skipped|unrecognized-qb-runtime' "$t/report"
! grep -q '^bootguard|' "$t/root/data/guard-invalid/manifest"
[ ! -e "$t/root/data/guard-invalid/files/qb_runtime.sh" ]
rm "$qb"
echo 'PASS prepare bootguard hook line 2, exact stock remainder and missing-shebang skip'

# Updating an already persistent installation must resolve each current live
# target through its recovery row and immutable original backup. v1 has 12
# fields; v2 adds the prior applied SHA as field 13. The live build.prop has
# old wrapper values, while the original backup has only stock properties.
# Persistent migration retains each original file's uid/gid/mode/label, so the
# applied metadata fields below match the original metadata fields exactly.
hash_file() { sha256sum "$1" | awk '{print $1}'; }
run_recovery_origin_update() {
    local version=$1 name=$2 state="$t/root/data/local/gen5w-portable/persistent/recovery"
    local originals="$state/originals/system" dipo="$t/root/system/app/HKMC_DiPO.odex"
    local gpm="$t/root/system/app/HKMC_GPM.odex" build="$t/root/system/build.prop"
    local dipo_backup="$originals/app/HKMC_DiPO.odex" gpm_backup="$originals/app/HKMC_GPM.odex"
    local prop_backup="$originals/build.prop" dipo_original dipo_applied gpm_original gpm_applied
    local prop_original prop_applied uid gid origin_row
    rm -rf "$state"
    mkdir -p "$originals/app"
    printf supported > "$dipo_backup"
    printf supported > "$gpm_backup"
    printf 'persist.ium.support=stock\nunrelated.keep=from-stock\n' > "$prop_backup"
    chmod 640 "$dipo_backup" "$gpm_backup" "$prop_backup"
    printf 'prior-dipo-applied-v%s' "$version" > "$dipo"
    printf 'prior-gpm-applied-v%s' "$version" > "$gpm"
    cat > "$build" <<EOF
persist.ium.support=stock
unrelated.keep=from-stock
wrap.com.daudio.app.dipo=/system/bin/sh /data/old-portable/wrap-dipo.sh
wrap.com.google.android.project=/system/bin/sh /data/old-portable/wrap-gpm.sh
EOF
    chmod 640 "$dipo" "$gpm" "$build"
    uid=$(id -u); gid=$(id -g)
    dipo_original=$(hash_file "$dipo_backup"); dipo_applied=$(hash_file "$dipo")
    gpm_original=$(hash_file "$gpm_backup"); gpm_applied=$(hash_file "$gpm")
    prop_original=$(hash_file "$prop_backup"); prop_applied=$(hash_file "$build")
    : > "$state/manifest"
    printf 'GEN5W-RECOVERY-MANIFEST|%s\n' "$version" >> "$state/manifest"
    for origin_row in \
        "/system/app/HKMC_DiPO.odex|file|$dipo_original|$dipo_applied|$uid|$gid|640|u:object_r:system_app_file:s0|$uid|$gid|640|u:object_r:system_app_file:s0" \
        "/system/app/HKMC_GPM.odex|file|$gpm_original|$gpm_applied|$uid|$gid|640|u:object_r:system_app_file:s0|$uid|$gid|640|u:object_r:system_app_file:s0" \
        "/system/build.prop|file|$prop_original|$prop_applied|$uid|$gid|640|u:object_r:system_file:s0|$uid|$gid|640|u:object_r:system_file:s0"; do
        if [ "$version" = 1 ]; then
            printf '%s\n' "$origin_row" >> "$state/manifest"
        else
            printf '%s|-\n' "$origin_row" >> "$state/manifest"
        fi
    done

    PATH="$t/bin:$PATH" "$shell" "$t/bundle/prepare.sh" "/data/recovered-$name" --stock-origins dipo gpm > "$t/report"
    grep -q '^dipo|prepared|structural$' "$t/report"
    grep -q '^gpm|prepared|structural$' "$t/report"
    [ "$(cat "$t/root/data/recovered-$name/files/dipo.odex")" = 'patched:dipo' ]
    [ "$(cat "$t/root/data/recovered-$name/files/gpm.odex")" = 'patched:gpm' ]
    grep -Fxc "wrap.com.daudio.app.dipo=$DIPO_WRAP" "$t/root/data/recovered-$name/files/build.prop" | grep -qx 1
    grep -Fxc "wrap.com.google.android.project=$GPM_WRAP" "$t/root/data/recovered-$name/files/build.prop" | grep -qx 1
    ! grep -q '/data/old-portable/' "$t/root/data/recovered-$name/files/build.prop"
    grep -Fx 'unrelated.keep=from-stock' "$t/root/data/recovered-$name/files/build.prop" >/dev/null
    cmp "$dipo_backup" "$t/root/data/recovered-$name/stock-origins/system/app/HKMC_DiPO.odex"
    cmp "$gpm_backup" "$t/root/data/recovered-$name/stock-origins/system/app/HKMC_GPM.odex"
    cmp "$prop_backup" "$t/root/data/recovered-$name/stock-origins/system/build.prop"
    origin_index="$t/root/data/recovered-$name/stock-origins/index.tsv"
    grep -Fx "/system/app/HKMC_DiPO.odex|$dipo_original|$uid|$gid|640|u:object_r:system_app_file:s0" "$origin_index" >/dev/null
    grep -Fx "/system/app/HKMC_GPM.odex|$gpm_original|$uid|$gid|640|u:object_r:system_app_file:s0" "$origin_index" >/dev/null
    grep -Fx "/system/build.prop|$prop_original|$uid|$gid|640|u:object_r:system_file:s0" "$origin_index" >/dev/null
    [ "$(grep -c '^/system/' "$origin_index")" = 3 ]
    awk -F'|' '$3=="/system/app/HKMC_DiPO.odex" || $3=="/system/app/HKMC_GPM.odex" || $3=="/system/build.prop" {n++} END {exit n != 3}' "$t/root/data/recovered-$name/manifest"
    # Planning reads the old applied state but does not rewrite live files.
    [ "$(hash_file "$dipo")" = "$dipo_applied" ]
    [ "$(hash_file "$gpm")" = "$gpm_applied" ]
    [ "$(hash_file "$build")" = "$prop_applied" ]
}
run_recovery_origin_update 1 v1
run_recovery_origin_update 2 v2

# Foreign values and conflicting duplicate keys refuse before any /system
# content or inode changes, even when the requested ODEX patch is supported.
system_snapshot() {
    local prefix=$1
    find "$t/root/system" -type f -exec stat -c '%n|%i|%s|%a|%u|%g|%Y' {} \; | sort > "$prefix.stat"
    find "$t/root/system" -type f -exec sha256sum {} \; | sort > "$prefix.sha"
}
system_unchanged() {
    local prefix=$1
    find "$t/root/system" -type f -exec stat -c '%n|%i|%s|%a|%u|%g|%Y' {} \; | sort > "$prefix.after.stat"
    find "$t/root/system" -type f -exec sha256sum {} \; | sort > "$prefix.after.sha"
    cmp "$prefix.stat" "$prefix.after.stat"
    cmp "$prefix.sha" "$prefix.after.sha"
}
refuse_missing_recovery_manifest() {
    local name=$1 residue=$2 persistent="$t/root/data/local/gen5w-portable/persistent"
    local recovery="$persistent/recovery" plan="$t/root/data/$name"
    rm -rf "$persistent"
    case "$residue" in
        originals)
            mkdir -p "$recovery/originals/system/app"
            printf immutable-original > "$recovery/originals/system/app/HKMC_DiPO.odex"
            ;;
        owner)
            mkdir -p "$persistent"
            printf 'GEN5W-PERSISTENT-OWNER|fixture\n' > "$persistent/manifest"
            ;;
        *) echo "FAIL unknown recovery residue: $residue"; exit 1;;
    esac
    [ ! -e "$recovery/manifest" ]
    echo -n supported > "$t/root/system/app/HKMC_DiPO.odex"
    cat > "$t/root/system/build.prop" <<EOF
unrelated.keep=stock
EOF
    chmod 644 "$t/root/system/app/HKMC_DiPO.odex" "$t/root/system/build.prop"
    local snapshot="$t/$name-system"
    system_snapshot "$snapshot"
    if PATH="$t/bin:$PATH" "$shell" "$t/bundle/prepare.sh" "/data/$name" --stock-origins dipo > "$t/report" 2>&1; then
        echo "FAIL $residue without recovery manifest was accepted"
        exit 1
    fi
    grep -q 'persistent recovery manifest missing' "$t/report"
    [ ! -e "$plan" ]
    [ ! -e "$plan/files" ]
    [ ! -e "$plan/manifest" ]
    system_unchanged "$snapshot"
}
refuse_missing_recovery_manifest missing-recovery-originals originals
refuse_missing_recovery_manifest missing-recovery-owner owner

echo -n supported > "$t/root/system/app/HKMC_DiPO.odex"
cat > "$t/root/system/build.prop" <<EOF
unrelated.keep=yes
wrap.com.daudio.app.dipo=/foreign/wrapper.sh
EOF
system_snapshot "$t/foreign-wrapper"
if PATH="$t/bin:$PATH" "$shell" "$t/bundle/prepare.sh" /data/foreign-wrapper --stock-origins dipo > "$t/report" 2>&1; then echo 'FAIL foreign build.prop wrapper accepted'; exit 1; fi
system_unchanged "$t/foreign-wrapper"

cat > "$t/root/system/build.prop" <<EOF
unrelated.keep=yes
wrap.com.daudio.app.dipo=$DIPO_WRAP
wrap.com.daudio.app.dipo=/foreign/wrapper.sh
EOF
system_snapshot "$t/conflicting-wrapper"
if PATH="$t/bin:$PATH" "$shell" "$t/bundle/prepare.sh" /data/conflicting-wrapper --stock-origins dipo > "$t/report" 2>&1; then echo 'FAIL conflicting duplicate wrapper keys accepted'; exit 1; fi
system_unchanged "$t/conflicting-wrapper"

echo 'PASS portable prepare: independent features, config inventory, stock unchanged, overlap/overwrite/symlink refusal'

# Portable-only region helper validates ABI roles, not complete dependency SHA.
mkdir -p "$t/bundle/bin" "$t/root/system/lib"
cat > "$t/bundle/bin/audio-region-patch" <<'SH'
#!/bin/sh
case "$1" in
original) [ "$(cat "$2")" = regional-stock ];;
verify) [ "$(cat "$2")" = "regional-$3" ];;
apply) [ "$(cat "$2")" = regional-stock ] && echo regional-patched > "$3";;
*) exit 2;;
esac
SH
chmod +x "$t/bundle/bin/audio-region-patch"
echo regional-stock > "$t/root/system/lib/libCarPlayAudio.so"
for pair in 'libCarPlayCore.so core' 'libCarPlayUtils.so utils' 'libopus.so opus'; do
    set -- $pair; echo "regional-$2" > "$t/root/system/lib/$1"
done
"$shell" "$t/bundle/prepare.sh" /data/regional-audio audio > "$t/report"
grep -q '^audio|prepared|reviewed-native-regions$' "$t/report"
[ "$(cat "$t/root/data/regional-audio/files/libCarPlayAudio.so")" = regional-patched ]
[ "$(cat "$t/root/system/lib/libCarPlayAudio.so")" = regional-stock ]
echo foreign-code > "$t/root/system/lib/libCarPlayUtils.so"
set +e
"$shell" "$t/bundle/prepare.sh" /data/unsupported-audio audio > "$t/report"
rc=$?
set -e
[ "$rc" = 77 ] && grep -q '^audio|skipped|unsupported-native-abi$' "$t/report"
[ ! -e "$t/root/data/unsupported-audio/files/libCarPlayAudio.so" ]
echo 'PASS regional audio preparation accepts reviewed ABI roles and skips unknown dependency without output'

# USB Wi-Fi dongle backend: only the reviewed stock bcmdhd.ko is replaced by the
# stand-in, with an immutable stock origin like every other persistent target.
rm -rf "$t/root/data/local/gen5w-portable"
mkdir -p "$t/root/system/wifi" "$t/bundle/dongle"
printf 'stock-bcmdhd-v039' > "$t/root/system/wifi/bcmdhd.ko"; chmod 644 "$t/root/system/wifi/bcmdhd.ko"
printf 'stand-in-bcmdhd' > "$t/bundle/dongle/bcmdhd.ko"
stock_ko=$(printf 'stock-bcmdhd-v039' | sha256sum | cut -d' ' -f1)
stand_in=$(printf 'stand-in-bcmdhd' | sha256sum | cut -d' ' -f1)
PORTABLE_TEST_BCMDHD_SHA256=$stock_ko "$shell" "$t/bundle/prepare.sh" /data/dongle-plan --stock-origins dongle > "$t/report"
grep -qx 'dongle|prepared|usb-wifi-stand-in' "$t/report"
grep -q "^dongle|/data/dongle-plan/files/bcmdhd.ko|/system/wifi/bcmdhd.ko|$stand_in|[0-9]*|[0-9]*|644|static\$" "$t/root/data/dongle-plan/manifest"
cmp "$t/root/system/wifi/bcmdhd.ko" "$t/root/data/dongle-plan/stock-origins/system/wifi/bcmdhd.ko"
grep -q "^/system/wifi/bcmdhd.ko|$stock_ko|" "$t/root/data/dongle-plan/stock-origins/index.tsv"
[ "$(cat "$t/root/system/wifi/bcmdhd.ko")" = stock-bcmdhd-v039 ]
if PORTABLE_TEST_BCMDHD_SHA256=$stand_in "$shell" "$t/bundle/prepare.sh" /data/dongle-foreign --stock-origins dongle > "$t/report" 2>&1; then
    echo 'FAIL dongle stand-in replaced an unreviewed Wi-Fi module'; exit 1
fi
grep -q 'not the reviewed V039 build' "$t/report"
[ "$(cat "$t/root/system/wifi/bcmdhd.ko")" = stock-bcmdhd-v039 ]
"$shell" "$t/bundle/prepare.sh" /data/no-dongle --stock-origins projection > "$t/report"
! grep -q bcmdhd "$t/root/data/no-dongle/manifest"
echo 'PASS dongle backend stages the stand-in only over the reviewed stock module; built-in installs never touch it'
