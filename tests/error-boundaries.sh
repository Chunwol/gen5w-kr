#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
work=$(mktemp -d /tmp/gen5w-error-boundaries.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/nemesis" <<'EOF'
#!/bin/sh
echo 'remount: Permission denied SSID=secret-network' >&2
exit 13
EOF
printf '#!/bin/sh\nexit 0\n' > "$work/sleep"
chmod 755 "$work/nemesis" "$work/sleep"
export EN_TEST_NEM=$work/nemesis AUDIO_TEST_NEM=$work/nemesis BRIDGE_TEST_NEM=$work/nemesis DONGLE_TEST_NEM=$work/nemesis
export EN_TEST_DATA=$work/data AUDIO_TEST_DATA=$work/data BRIDGE_TEST_DATA=$work/data DONGLE_TEST_DATA=$work/data
export ERR_ATTEMPT=boundary-test ERR_DIR=$work/errors PATH=$work:$PATH
for entry in wireless-enable:wireless audio-format:audio wireless-bridge:bridge; do
 package=${entry%:*};module=${entry#*:}
 (cd "$ROOT/packages/$package"; SCRIPT_DIR="$ROOT/packages/$package/scripts" mksh -c '. "$SCRIPT_DIR/common.sh"; sys_ro' "$ROOT/packages/$package/scripts/test.sh") > "$work/out" 2>&1
 if ! grep -q "module=$module.*stage=mount.*operation=ro.*rc=13.*reason=permission" "$work/out"; then cat "$work/out"; echo "FAIL lost $module remount cause"; exit 1; fi
 if grep -q secret-network "$work/out"; then echo 'FAIL leaked stderr';exit 1;fi
done
(cd "$ROOT/tools/usb-wifi/package"; SCRIPT_DIR="$ROOT/tools/usb-wifi/package/scripts" mksh -c '. "$SCRIPT_DIR/common.sh"; sys_ro') > "$work/out" 2>&1
grep -q 'module=dongle.*rc=13.*reason=permission' "$work/out"
echo 'PASS module mount failure causes retained with original warning policy'
