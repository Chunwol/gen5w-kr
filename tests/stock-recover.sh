#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
W=$(mktemp -d)
stubs
mkdir -p "$W/usb" "$W/data/nemesis/gen5w-kr-integrated/prior" "$W/system"
cp tools/integrated/*.sh "$W/usb/"
cp tools/integrated/bin/zipstore-host "$W/usb/zipstore"
TX=$W/data/nemesis/gen5w-kr-integrated
echo keep-original-snapshot > "$TX/prior/sentinel"
echo 1 > "$TX/prior/complete"
cat > "$W/nemesis" <<'EOF'
#!/bin/sh
echo "$*" >> "$IT_DATA/calls"
case "$1" in
 version) echo "${IT_NEM_VERSION:-1.16.3}";;
 service) [ "$2" = list ];;
 uninstall) rm -rf "$IT_DATA/nemesis/apps/$2";;
 remount) [ "$IT_RO_FAIL" != 1 ] || exit 1; [ "$IT_RO_LIES" != 1 ] || exit 0; echo "device $IT_SYSTEM ext4 ro,relatime 0 0" > "$IT_MOUNTS";;
 *) exit 1;;
esac
EOF
chmod +x "$W/nemesis"
# Each real bundle gate consumes a checksummed hook; simulate the system boundary.
for id in localhotspot drivelog bluelink timer core bridge audio wireless dongle; do
    tree="$W/usb/checks/gen5w.kr.$id"
    mkdir -p "$tree/scripts"
    printf '[nemesis]\nid=gen5w.kr.%s\npreuninstall=scripts/remove.sh\n' "$id" > "$tree/NEMESIS.data"
    printf '[ "$IT_HOOK_FAIL" != "%s" ] || exit 1\necho verified-%s >> "$IT_DATA/proofs"\n' "$id" "$id" > "$tree/scripts/remove.sh"
    (cd "$tree" && md5sum NEMESIS.data scripts/remove.sh > FILES.md5)
done
mkdir -p "$W/data/nemesis/apps/gen5w.kr.localhotspot"
cp -R "$W/usb/checks/gen5w.kr.localhotspot/." "$W/data/nemesis/apps/gen5w.kr.localhotspot/"
run() { (cd "$W/usb" && IT_DATA="$W/data" IT_SYSTEM="$W/system" IT_MOUNTS="$W/mounts" IT_NEM="$W/nemesis" IT_SHELL=$(command -v mksh) IT_NO_REBOOT=1 PATH="$W/bin:$PATH" mksh NEMESIS.sh > "$W/out" 2>&1); }
recover() { echo stock-recover > "$W/usb/GEN5W-ACTION"; run; }
direct() { (cd "$W/usb" && IT_DATA="$W/data" IT_SYSTEM="$W/system" IT_MOUNTS="$W/mounts" IT_NEM="$W/nemesis" IT_SHELL=$(command -v mksh) IT_NO_REBOOT=1 PATH="$W/bin:$PATH" mksh -c '. ./common.sh; acquire && "$1"' _ "$1" > "$W/out" 2>&1); }
echo 1 > "$W/props/sys.boot_completed"
echo stock-recover > "$W/usb/GEN5W-ACTION"
echo recovery-required > "$TX/state"
: > "$W/data/nemesis/gen5wkr.noreboot"
echo "device $W/system ext4 ro,relatime 0 0" > "$W/mounts"
check 'stock recovery entry succeeds without reinstalling prior hotspot' run
check 'stock recovery records completed state' grep -qx committed "$TX/state"
check 'stock recovery removes hotspot registration' test ! -e "$W/data/nemesis/apps/gen5w.kr.localhotspot"
check 'stock recovery never installs a prior ZIP' eval '! grep -q "^install " "$W/data/calls"'
check 'stock recovery preserves original transaction snapshot' grep -qx keep-original-snapshot "$TX/prior/sentinel"
check 'stock recovery clears suppression only after completion' test ! -e "$W/data/nemesis/gen5wkr.noreboot"
check 'stock recovery reports stock-specific success' grep -q '순정 복원 완료' "$W/usb/GEN5W-REPORT/RESULT.md"
echo recovery-required > "$TX/state"
: > "$W/data/nemesis/gen5wkr.noreboot"
export IT_HOOK_FAIL=bridge
check 'stock verification hook failure refuses completion' eval '! recover'
check 'hook failure keeps recovery state and suppression' eval 'grep -qx recovery-required "$TX/state" && test -f "$W/data/nemesis/gen5wkr.noreboot"'
unset IT_HOOK_FAIL
echo "device $W/system ext4 rw,relatime 0 0" > "$W/mounts"
export IT_RO_FAIL=1
check 'unresolved writable system refuses completion' eval '! recover'
check 'mount failure retains snapshot and recovery state' eval 'grep -qx recovery-required "$TX/state" && grep -qx keep-original-snapshot "$TX/prior/sentinel"'
unset IT_RO_FAIL
check 'recovery retries after mount failure resolves' recover
echo recovering > "$TX/state"
echo stock-recover > "$TX/stock-recovery-mode"
echo install > "$W/usb/GEN5W-ACTION"
export IT_NEM_VERSION=1.16.7
check 'installer automatically recovers interrupted stock transaction' run
check 'automatic recovery never installs snapshot and retains next install request' eval '! grep -q "^install " "$W/data/calls" && grep -qx install "$W/usb/GEN5W-ACTION" && grep -qx keep-original-snapshot "$TX/prior/sentinel"'
check 'next installation is refused until a different boot' eval '! run && grep -q "full reboot required" "$W/out"'
check 'direct rollback caller cannot bypass stock recovery intent' eval '! direct rollback_transaction && grep -q "stock-recover" "$W/out"'
check 'direct installer cannot bypass required cold reboot' eval '! direct install_transaction && grep -q "full reboot required" "$W/out"'
unset IT_NEM_VERSION
echo rollback > "$W/usb/GEN5W-ACTION"
check 'snapshot rollback refuses while stock recovery owns transaction' eval '! run && grep -q "stock-recover" "$W/out"'
echo stock-recover > "$W/usb/GEN5W-ACTION"
export IT_BOOTGUARD_FAIL=1
check 'boot guard failure keeps stock recovery retryable' eval '! recover && grep -qx recovery-required "$TX/state" && test -f "$W/data/nemesis/gen5wkr.noreboot"'
unset IT_BOOTGUARD_FAIL
check 'stock recovery can resume after finalization failure' recover
echo recovery-required > "$TX/state"
echo "device $W/system ext4 rw,relatime 0 0" > "$W/mounts"
export IT_RO_LIES=1
check 'successful remount command cannot hide writable mount flags' eval '! recover && grep -qx recovery-required "$TX/state"'
unset IT_RO_LIES
printf 'device %s ext4 ro 0 0\ndevice %s ext4 ro 0 0\n' "$W/system" "$W/system" > "$W/mounts"
export IT_RO_LIES=1
check 'duplicate system mounts refuse stock completion' eval '! recover && grep -qx recovery-required "$TX/state"'
unset IT_RO_LIES
echo "device $W/system ext4 ro,relatime 0 0" > "$W/mounts"
cat > "$W/bin/rm" <<'EOF'
#!/bin/sh
if [ "$IT_FAIL_HOLD_CLEAR" = 1 ] && [ "$1" = -f ] && [ "$2" = "$IT_DATA/nemesis/gen5wkr.install-hold" ]; then exit 1; fi
exec /bin/rm "$@"
EOF
chmod +x "$W/bin/rm"
export IT_NEM_VERSION=1.16.7 IT_FAIL_HOLD_CLEAR=1
check 'modern hold cleanup failure never publishes stock success' eval '! recover && grep -qx recovery-required "$TX/state" && test -f "$W/data/nemesis/gen5wkr.noreboot"'
unset IT_FAIL_HOLD_CLEAR
check 'modern recovery retries after hold cleanup is repaired' recover
unset IT_NEM_VERSION
cat > "$W/bin/mv" <<'EOF'
#!/bin/sh
case "$2" in */RESULT.md) [ "$IT_FAIL_REPORT" != 1 ] || exit 1;; esac
exec /bin/mv "$@"
EOF
chmod +x "$W/bin/mv"
export IT_FAIL_REPORT=1
check 'required report failure keeps recovery state and suppression' eval '! recover && grep -qx recovery-required "$TX/state" && test -f "$W/data/nemesis/gen5wkr.noreboot"'
unset IT_FAIL_REPORT
check 'report failure remains retryable' recover
# Only the failing install command boundary is replaced; entry orchestration and
# the entire stock recovery operation remain production code.
cp "$W/usb/install.sh" "$W/original-install.sh"
cat > "$W/usb/install.sh" <<'EOF'
echo recovery-required > "$IT_DATA/nemesis/gen5w-kr-integrated/state"
echo 'FAILED fixture install and previous-state rollback'
exit 1
EOF
echo committed > "$TX/state"
rm -f "$TX/stock-recovered-boot"
echo install > "$W/usb/GEN5W-ACTION"
export IT_NEM_VERSION=1.16.7
check 'failed install remains failed even when automatic stock fallback succeeds' eval '! run'
check 'automatic fallback restores stock and preserves first failure evidence' eval 'grep -qx committed "$TX/state" && grep -q "FAILED fixture install" "$W/usb/GEN5W-REPORT/EXEC_LOG.txt" && grep -q "automatic_stock_recovery_exit=0" "$W/usb/GEN5W-REPORT/EXEC_LOG.txt"'
cp "$W/original-install.sh" "$W/usb/install.sh"
unset IT_NEM_VERSION
echo recovery-required > "$TX/state"
echo install > "$W/usb/GEN5W-ACTION"
check 'legacy install is refused without running recovery implicitly' eval '! run && grep -qx recovery-required "$TX/state" && ! grep -q "AUTOMATIC STOCK" "$W/out"'
echo stock-recover > "$W/usb/GEN5W-ACTION"
# A USB stock restore must not depend on rotating an unused on-unit app runner.
# Verify the actual USB manifest while preserving unsafe/corrupt cache evidence.
mkdir -p "$W/data/nemesis/gen5wkr.recovery" "$W/foreign-cache"
echo preserve-cache-evidence > "$W/foreign-cache/sentinel"
ln -s "$W/foreign-cache" "$W/data/nemesis/gen5wkr.recovery/previous"
python3 - "$W/usb" <<'PY'
import hashlib,pathlib,sys
root=pathlib.Path(sys.argv[1])
entries=[p for p in sorted(root.rglob('*')) if p.is_file() and p.name not in ('RECOVERY.md5','RECOVERY.receipt','GEN5W-ACTION') and not p.parts[len(root.parts):][0]=='GEN5W-REPORT']
manifest=''.join(hashlib.md5(p.read_bytes()).hexdigest()+'  '+p.relative_to(root).as_posix()+'\n' for p in entries)
(root/'RECOVERY.md5').write_text(manifest)
(root/'RECOVERY.receipt').write_text(hashlib.md5(manifest.encode()).hexdigest()+'\n')
PY
echo recovery-required > "$TX/state"
check 'verified USB stock restore is independent of unused linked runner cache' recover
export IT_NEM_VERSION=1.16.8
check 'future numeric runtime supports explicit stock recovery' recover
export IT_NEM_VERSION=unknown
echo I_ACCEPT_UNKNOWN_NEMESIS_VERSION > "$W/usb/GEN5W-ALLOW-UNKNOWN-NEMESIS"
echo recovery-required > "$TX/state"
echo install > "$W/usb/GEN5W-ACTION"
check 'acknowledged unknown runtime routes pending installation through stock recovery' eval 'run && grep -q "action=stock-recover" "$W/usb/GEN5W-REPORT/STARTUP.txt" && grep -q "STOCK RECOVERY COMPLETE" "$W/usb/GEN5W-REPORT/EXEC_LOG.txt"'
rm "$W/usb/GEN5W-ALLOW-UNKNOWN-NEMESIS"
unset IT_NEM_VERSION
check 'USB stock restore never touches unused runner cache or its link target' eval 'test -L "$W/data/nemesis/gen5wkr.recovery/previous" && grep -qx preserve-cache-evidence "$W/foreign-cache/sentinel"'
# Mutating the USB hook after manifest creation must still refuse before restore.
echo '# corruption' >> "$W/usb/history.sh"
echo recovery-required > "$TX/state"
check 'untrusted USB still refuses despite ignoring the unused runner cache' eval '! recover && grep -qx recovery-required "$TX/state"'
rm -f "$W/usb/RECOVERY.md5" "$W/usb/RECOVERY.receipt"
echo future > "$TX/state"
check 'unknown state refuses stock mutation' eval '! run && grep -qx future "$TX/state"'
rm -rf "$W"
done_tests stock-recover
