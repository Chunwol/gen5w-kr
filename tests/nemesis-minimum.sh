#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
W=$(mktemp -d)
cat > "$W/nemesis" <<'EOF'
#!/bin/sh
[ "$1" = version ] || exit 1
printf '%s\n' "$QV"
exit "${QRC:-0}"
EOF
chmod +x "$W/nemesis"
repo=$PWD
run() { (cd "$W" && QV="$1" QRC="${2:-0}" mksh -c '. "$1/tools/integrated/services.sh"; NEM=$2; report() { echo "$*"; }; q_install_version' _ "$repo" "$W/nemesis"); }
for version in 1.14 1.15 1.16 1.16.0 1.16.3 1.16.4 1.16.5 1.16.6 0.99.99; do
    check "install refuses old $version" eval '! run "$version"'
done
for version in 1.16.7 1.16.8 1.16.10 1.17.0 1.100.0 2.0.0; do
    check "install admits numeric $version" run "$version"
done
for version in '' unknown 1.16.7-rc.1 1.16.7.1 1.016.7 999999999999999999999999.0.0; do
    check "install refuses malformed [$version]" eval '! run "$version"'
done
check 'version command failure refuses even with valid output' eval '! run 1.16.7 1'
echo I_ACCEPT_UNKNOWN_NEMESIS_VERSION > "$W/GEN5W-ALLOW-UNKNOWN-NEMESIS"
check 'explicit acknowledgement permits unreadable version with warning' eval 'run unknown > "$W/out" && grep -q WARNING "$W/out"'
check 'acknowledgement cannot bypass known old version' eval '! run 1.16.6'
check 'acknowledgement cannot bypass short old version' eval '! run 1.15'
check 'failed version command can be explicitly acknowledged' run 1.16.7 1
rm "$W/GEN5W-ALLOW-UNKNOWN-NEMESIS"
echo I_ACCEPT_UNKNOWN_NEMESIS_VERSION > "$W/foreign"
ln -s "$W/foreign" "$W/GEN5W-ALLOW-UNKNOWN-NEMESIS"
check 'linked acknowledgement does not grant consent' eval '! run unknown'
rm "$W/GEN5W-ALLOW-UNKNOWN-NEMESIS"
echo wrong > "$W/GEN5W-ALLOW-UNKNOWN-NEMESIS"
check 'incorrect acknowledgement text does not grant consent' eval '! run unknown'
printf 'I_ACCEPT_UNKNOWN_NEMESIS_VERSION\nextra\n' > "$W/GEN5W-ALLOW-UNKNOWN-NEMESIS"
check 'extra acknowledgement lines do not grant consent' eval '! run unknown'
# Exercise the real entry routing as well as the policy helper. Only the
# subsequent mutating actions are replaced at the OS boundary.
mkdir -p "$W/usb" "$W/bin" "$W/data/nemesis/gen5w-kr-integrated"
cp tools/integrated/{NEMESIS.sh,errors.sh,history.sh,services.sh} "$W/usb/"
cat > "$W/bin/getprop" <<'EOF'
#!/bin/sh
echo 1
EOF
chmod +x "$W/bin/getprop"
echo install > "$W/usb/GEN5W-ACTION"
echo 74b3441 > "$W/usb/BUILD-REVISION"
echo recovery-required > "$W/data/nemesis/gen5w-kr-integrated/state"
echo I_ACCEPT_UNKNOWN_NEMESIS_VERSION > "$W/usb/GEN5W-ALLOW-UNKNOWN-NEMESIS"
echo 'echo recovered > route' > "$W/usb/stock-recover.sh"
echo 'echo installed > route' > "$W/usb/install.sh"
entry() { (cd "$W/usb" && QV=unknown IT_NEM="$W/nemesis" IT_DATA="$W/data" IT_SHELL=$(command -v mksh) ERR_PERSIST=no PATH="$W/bin:$PATH" mksh NEMESIS.sh > "$W/entry.out" 2>&1); }
check 'acknowledged unknown entry routes recovery before installation' eval 'entry && grep -qx recovered "$W/usb/route"'
rm -rf "$W"
done_tests nemesis-minimum
