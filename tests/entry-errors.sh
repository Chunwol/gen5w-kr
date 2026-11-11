#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
work=$(mktemp -d /tmp/gen5w-entry-errors.XXXXXX)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/usb" "$work/bin"
cp tools/integrated/{NEMESIS.sh,errors.sh,history.sh,services.sh} "$work/usb/"
echo abcdef01 > "$work/usb/BUILD-REVISION"
cat > "$work/bin/getprop" <<'EOF'
#!/bin/sh
if [ "$MODE" = denied ];then echo 'Permission denied password=entry-secret' >&2;exit 13;fi
echo "$BOOTED"
EOF
cat > "$work/usb/install.sh" <<'EOF'
#!/bin/sh
echo 'FAILED synthetic operation'
exit 17
EOF
chmod +x "$work/bin/getprop"
export PATH=$work/bin:$PATH IT_SHELL=mksh ERR_DIR=$work/private MODE=ok BOOTED=0
run() { (cd "$work/usb";mksh NEMESIS.sh > "$work/output" 2>&1); }
if run;then echo 'FAIL preboot accepted';exit 1;fi
test ! -e "$ERR_DIR"
export MODE=denied
if run;then echo 'FAIL property query error accepted';exit 1;fi
grep -q 'rc=13.*reason=permission' "$work/usb/GEN5W-REPORT/ENTRY_STATUS.txt"
test ! -e "$ERR_DIR"
export MODE=ok BOOTED=1
status=0;run || status=$?
test "$status" = 17
grep -q 'stage=entry.*operation=install.*result=failed.*rc=17' "$ERR_DIR/first.integrated.2"
grep -q 'operation_exit=17' "$work/usb/GEN5W-REPORT/STARTUP.txt"
cat > "$work/usb/install.sh" <<'EOF'
#!/bin/sh
rm -f GEN5W-REPORT/EXEC_LOG.txt
mkdir GEN5W-REPORT/EXEC_LOG.txt
echo 'FAILED synthetic output write loss'
echo completed > producer-done
exit 17
EOF
status=0;run || status=$?
test "$status" = 17
test -f "$work/usb/producer-done"
grep -q 'operation_exit=17' "$work/usb/GEN5W-REPORT/STARTUP.txt"
grep -q 'report_exit=1' "$work/usb/GEN5W-REPORT/STARTUP.txt"
! grep -R -q entry-secret "$work/usb/GEN5W-REPORT"
echo 'PASS entry preboot read-only/acquisition failure/primary rc/first cause/privacy'
