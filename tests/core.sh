#!/bin/bash
# Read-only core installation gates: API availability and extension ownership.
. "$(dirname "$0")/lib.sh"
PKG=$(cd "$(dirname "$0")/../packages/core" && pwd)
W=$(mktemp -d)
mkdir -p "$W/sys/framework" "$W/sys/app" "$W/data"
mkdir -p "$W/bin"
echo '#!/bin/sh' > "$W/bin/getprop"
echo 'echo 999' >> "$W/bin/getprop"
chmod +x "$W/bin/getprop"
export PATH="$W/bin:$PATH"
: > "$W/sys/framework/com.tcc.iap2.jar"
: > "$W/sys/app/Iap2ServerApp.apk"
echo 'NavigationCluster updateTPTurnListNew updateLaneInfo updateTBTInfo' > "$W/sys/framework/automotive.odex"
run() { CORE_TEST_SYS=$W/sys CORE_TEST_DATA=$W/data mksh "$PKG/scripts/pre.sh" > "$W/result" 2>&1; }
snapshot() { (cd "$W/sys" && find . -type f -exec md5sum {} + | sort -k2); }
snapshot > "$W/before"
check "core accepts required APIs without wireless hardware" run
snapshot > "$W/after"
check "core gate changes no system files" cmp -s "$W/before" "$W/after"
rm "$W/sys/framework/com.tcc.iap2.jar"
check "core refuses missing iAP2 library" eval '! run'
: > "$W/sys/framework/com.tcc.iap2.jar"
echo 'NavigationCluster updateLaneInfo' > "$W/sys/framework/automotive.odex"
check "core refuses missing turn-list API" eval '! run'
echo 'NavigationCluster updateTPTurnListNew updateLaneInfo updateTBTInfo' > "$W/sys/framework/automotive.odex"
mkdir -p "$W/data/nemesis/apps/wireless.carplay.aa"
check "core refuses another installed HUD extension" eval '! run'
rm -d "$W/data/nemesis/apps/wireless.carplay.aa"
echo 'echo 110' > "$W/bin/getprop"
check "core refuses unpatched regional route capability" eval '! run'
mkdir -p "$W/data/nemesis/apps/gen5w.kr.bridge/bin"
cat > "$W/data/nemesis/apps/gen5w.kr.bridge/bin/iap2-patch-v039" <<'EOF'
#!/bin/sh
[ "$1" = patched ] && grep -q '^legacy$' "$2"
EOF
chmod +x "$W/data/nemesis/apps/gen5w.kr.bridge/bin/iap2-patch-v039"
echo legacy > "$W/sys/app/Iap2ServerApp.odex"
check "core refuses legacy wireless-control shim without route-only verifier" eval '! run'
cat > "$W/data/nemesis/apps/gen5w.kr.bridge/bin/iap2-route-patch-v039" <<'EOF'
#!/bin/sh
[ "$1" = patched ] && grep -q '^route-only$' "$2"
EOF
chmod +x "$W/data/nemesis/apps/gen5w.kr.bridge/bin/iap2-route-patch-v039"
echo route-only > "$W/sys/app/Iap2ServerApp.odex"
check "core accepts route-only capability with matching verifier" run
done_tests core
