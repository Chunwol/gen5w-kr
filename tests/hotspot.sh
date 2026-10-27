#!/bin/bash
# mock test for packages/hotspot-match (the service + gate logic; the Wi-Fi calls
# themselves need a car). A fake app_process returns scripted check/apply output.
. "$(dirname "$0")/lib.sh"
PKG=$(cd "$(dirname "$0")/../packages/hotspot-match" && pwd)

setup() { # $1 = scenario the fake app_process plays
    W=$(mktemp -d); cp -r "$PKG" "$W/app"; stubs
    mkdir -p "$W/data/nemesis"
    mkdir -p "$W/app/app"
    echo compiled-test-payload > "$W/app/app/match.dex"
    # fake app_process: reads $W/scene and the mode arg (last arg), prints a RESULT
    cat > "$W/bin/app_process" <<FAKE
#!/bin/sh
[ -f "\$CLASSPATH" ] || exit 88
for last; do :; done
scene=\$(cat "$W/scene")
case "\$scene:\$last" in
    match:*)        echo "before ssid_match=true psk_match=true carplay_ssid_set=true carplay_psk_len=12 ap_state=13 ap_mode=2"; echo "RESULT ready";;
    mismatch:check) echo "before ssid_match=false psk_match=false carplay_ssid_set=true carplay_psk_len=12 ap_state=13 ap_mode=2"; echo "RESULT mismatch";;
    mismatch:apply) echo "after ssid_match=true psk_match=true carplay_ssid_set=true carplay_psk_len=12 ap_state=13 ap_mode=2"; echo "RESULT applied";;
    notready:check) echo "RESULT error no-ap-config";;
    nocp:check)     echo "before ssid_match=false psk_match=false carplay_ssid_set=false carplay_psk_len=-1 ap_state=11 ap_mode=2"; echo "RESULT error carplay-settings-missing";;
    *) echo "RESULT error unexpected";;
esac
FAKE
    chmod +x "$W/bin/app_process"
    echo '#!/bin/sh' > "$W/bin/sleep"; chmod +x "$W/bin/sleep"
    echo "${1:-match}" > "$W/scene"
    # Native profile transaction has its own lifecycle fixture tests.
    echo 'exit 0' > "$W/app/scripts/profile-pre.sh"
}
svc() { (cd "$W/app" && HM_TEST_PATH=$W/bin:$PATH HM_TEST_DEX=$W/app/app/match.dex HM_TEST_LOG=$W/log PATH=$W/bin:$PATH mksh svc/match.sh >/dev/null 2>&1); }
pre() { (cd "$W/app" && PROFILE_TEST_SHELL=mksh HM_TEST_PATH=$W/bin:$PATH HM_TEST_DEX=$W/app/app/match.dex HM_TEST_LOG=$W/log PATH=$W/bin:$PATH mksh scripts/pre.sh >/dev/null 2>&1); }

setup match
check "service exits ok when already matched" svc
check "no apply logged when already matched" eval '! grep -q "apply:" "$W/log"'

setup mismatch
check "service observes differing profiles without taking over AP" svc
check "ordinary hotspot is never changed at boot" eval '! grep -q "apply:" "$W/log"'

setup nocp
check "cold CarPlay settings defer to exact native gate" pre
echo 'exit 77' > "$W/app/scripts/profile-pre.sh"
check "deferred credentials never bypass unknown native gate" eval '! pre'

setup match
check "preinstall accepts when CarPlay values exist" pre

setup match
check 'installed service locates its dex from an unrelated working directory' eval '(cd / && HM_TEST_PATH=$W/bin:$PATH HM_TEST_LOG=$W/log mksh "$W/app/svc/match.sh" >/dev/null 2>&1)'
check 'installed command locates its dex from an unrelated working directory' eval '(cd / && PATH=$W/bin:$PATH mksh "$W/app/bin/run.sh" check >/dev/null 2>&1)'

done_tests hotspot
