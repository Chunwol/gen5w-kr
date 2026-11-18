#!/bin/bash
# Host fixture for persistent-start's recovery-manifest detection and
# fail-closed validation. It invokes the production entrypoint in detect mode;
# it never starts Android or performs system writes.
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/g5p-pstart.XXXXXX)
trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin/bin" "$t/root/system/app" "$t/root/data/local/gen5w-portable/persistent/recovery/originals/system/app" "$t/root/data/local/gen5w-portable/persistent" "$t/binmock"
cp tools/portable/persistent-start.sh "$t/bin/persistent-start.sh"
cp .build/portable/dex-patch-host "$t/bin/bin/dex-patch.real"
cat > "$t/bin/bin/dex-patch" <<'SH'
#!/bin/sh
if [ "$1" = label ]; then
    if [ -f "$PORTABLE_TEST_LABEL_FAULT" ] && [ "${2##*/}" = HKMC_DiPO.odex ]; then echo wrong_label
    else echo system_file; fi
else exec "$0.real" "$@"; fi
SH
chmod 755 "$t/bin/bin/dex-patch"
cat > "$t/binmock/ls" <<'SH'
#!/bin/sh
[ "$1" = -Zd ] || exec /bin/ls "$@"
if [ -f "$PORTABLE_TEST_LABEL_FAULT" ] && [ "${2##*/}" = HKMC_DiPO.odex ]; then
    printf 'wrong_label %s\n' "$2"
else
    printf 'system_file %s\n' "$2"
fi
SH
chmod +x "$t/binmock/ls"
export PATH=$t/binmock:$PATH PORTABLE_TEST_ROOT=$t/root
script=$t/bin/persistent-start.sh
recovery=$t/root/data/local/gen5w-portable/persistent/recovery
owner=$t/root/data/local/gen5w-portable/persistent/manifest
live=$t/root/system/app/HKMC_DiPO.odex
backup=$recovery/originals/system/app/HKMC_DiPO.odex
fault=$t/label-fault
export PORTABLE_TEST_LABEL_FAULT=$fault

seed_valid() {
    rm -rf "$recovery" "$owner"; mkdir -p "${backup%/*}" "$recovery/originals/system" "$(dirname "$owner")"
    printf 'applied payload\n' > "$live"
    printf 'immutable stock original\n' > "$backup"
    printf 'applied properties\n' > "$t/root/system/build.prop"
    printf 'stock properties\n' > "$recovery/originals/system/build.prop"
    chmod 644 "$live" "$backup" "$t/root/system/build.prop" "$recovery/originals/system/build.prop"
    : > "$owner"
    orig=$(sha256sum "$backup" | cut -d' ' -f1)
    applied=$(sha256sum "$live" | cut -d' ' -f1)
    uid=$(stat -c %u "$live"); gid=$(stat -c %g "$live"); mode=$(stat -c %a "$live")
    printf 'GEN5W-RECOVERY-MANIFEST|1\n/system/app/HKMC_DiPO.odex|file|%s|%s|%s|%s|%s|system_file|%s|%s|%s|system_file\n' \
        "$orig" "$applied" "$uid" "$gid" "$mode" "$uid" "$gid" "$mode" > "$recovery/manifest"
    prop_orig=$(sha256sum "$recovery/originals/system/build.prop" | cut -d' ' -f1)
    prop_applied=$(sha256sum "$t/root/system/build.prop" | cut -d' ' -f1)
    prop_uid=$(stat -c %u "$t/root/system/build.prop"); prop_gid=$(stat -c %g "$t/root/system/build.prop"); prop_mode=$(stat -c %a "$t/root/system/build.prop")
    printf '/system/build.prop|file|%s|%s|%s|%s|%s|system_file|%s|%s|%s|system_file\n' \
        "$prop_orig" "$prop_applied" "$prop_uid" "$prop_gid" "$prop_mode" "$prop_uid" "$prop_gid" "$prop_mode" >> "$recovery/manifest"
    mkdir -p "$t/root/system/etc" "$recovery/originals/system/etc"
    printf '#!/system/bin/sh\n# bootguard hook\n' > "$t/root/system/etc/qb_runtime.sh"
    printf '#!/system/bin/sh\n# stock\n' > "$recovery/originals/system/etc/qb_runtime.sh"
    chmod 644 "$t/root/system/etc/qb_runtime.sh" "$recovery/originals/system/etc/qb_runtime.sh"
    qb_orig=$(sha256sum "$recovery/originals/system/etc/qb_runtime.sh" | cut -d' ' -f1)
    qb_applied=$(sha256sum "$t/root/system/etc/qb_runtime.sh" | cut -d' ' -f1)
    printf '/system/etc/qb_runtime.sh|file|%s|%s|%s|%s|644|system_file|%s|%s|644|system_file\n' \
        "$qb_orig" "$qb_applied" "$prop_uid" "$prop_gid" "$prop_uid" "$prop_gid" >> "$recovery/manifest"
    rm -f "$fault"
}
detect() { mksh "$script" detect; }

# Only an absent recovery manifest is the legacy sentinel. Leftover owner or
# recovery state must not launch or be mistaken for a clean legacy install.
mkdir -p "$(dirname "$owner")" "$recovery/originals"
: > "$owner"
if detect >/dev/null 2>&1; then echo 'FAIL absent manifest detected as persistent'; exit 1; else rc=$?; fi
[ "$rc" = 3 ] || { echo "FAIL absent manifest returned $rc, expected 3"; exit 1; }

seed_valid
detect

for fault_kind in malformed hash metadata label partial; do
    seed_valid
    case "$fault_kind" in
      malformed) printf 'BAD\n' > "$recovery/manifest";;
      hash) printf 'tampered applied bytes\n' > "$t/root/system/build.prop";;
      metadata) chmod 600 "$live";;
      label) : > "$fault";;
      partial) printf 'stock payload\n' > "$live";;
    esac
    if detect >"$t/out" 2>&1; then echo "FAIL accepted manifest with $fault_kind state"; exit 1; fi
done
echo 'PASS persistent startup detection: absent-only exit 3; malformed, hash, metadata, label, and partial application fail closed'
