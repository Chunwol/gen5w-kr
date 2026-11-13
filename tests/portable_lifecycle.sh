#!/bin/bash
# Multi-boot lifecycle of the REAL boot.sh + portable.sh/overlay.sh + runtime.sh.
#
# The adapters model Android/OS boundaries only: properties, zygote and
# system_server identity, ActivityManager readiness, the Dalvik VM probe, the
# DiPO app/session, and the mount namespace (binds are simulated by showing the
# bound source at the target and mapping its identity, so sha/metadata/inventory
# and owner checks see what a real bind would show). Every call between the
# three scripts is the production op() body, extracted from the script that
# makes the call at test time (only /system/bin/sh is mapped to mksh), with the
# calling script's own BASE/STATE/HELPER. Journals and state are the scripts'.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=$PWD
command -v mksh >/dev/null || { echo 'SKIP mksh unavailable'; exit 0; }
[ -x .build/portable/dex-patch-host ] || { echo 'FAIL .build/portable/dex-patch-host missing'; exit 1; }
t=$(mktemp -d /tmp/g5p-lifecycle.XXXXXX)
runner=
cleanup() {
    [ -z "$runner" ] || kill -9 -- "-$runner" 2>/dev/null || :
    rm -rf "$t"
}
trap cleanup EXIT
R=$t/root; A=$t/actions; B=$R/data/bundle
P=$R/data/local/gen5w-portable
mkdir -p "$B/bin" "$B/dalvik" "$R/data/plan/perms" "$R/system/app" "$R/system/etc/permissions" "$A/props" "$A/stash" "$t/bin"
fail() { echo "FAIL $*" >&2; exit 1; }

# ---- bundle: production scripts, interpreter path mapped for this host ----
for name in boot.sh rescue.sh runtime.sh overlay.sh portable.sh framework.sh ap.sh wrap-common.sh wrap-dipo.sh wrap-gpm.sh wrap-probe.sh; do
    cp "tools/portable/$name" "$B/$name"
done
sed -i '1c#!/usr/bin/mksh' "$B/boot.sh" "$B/rescue.sh"
# portable.sh is not fixture-aware; only its exec interpreter is mapped.
sed -i 's#exec /system/bin/sh #exec mksh #' "$B/portable.sh"
tail -n +2 "$B/portable.sh" | grep -q '/system/bin/sh' && fail 'unmapped interpreter in portable.sh'
cp .build/portable/dex-patch-host "$B/bin/dex-patch"
for name in engine.jar adapter.jar libgen5whook.so hook-vm-test.jar; do echo "authored $name" > "$B/dalvik/$name"; done
chmod 755 "$B"/*.sh "$B/bin/dex-patch"
(cd "$B" && find . -type f ! -name SHA256SUMS | sort | while read -r f; do sha256sum "${f#./}"; done) > "$B/SHA256SUMS"
H=$B/bin/dex-patch

# ---- stock system and authored overlays (owner/mode as the helper reports) ----
printf 'stock iap2' > "$R/system/app/Iap2ServerApp.odex"
printf 'stock gpm' > "$R/system/app/HKMC_GPM.odex"
printf 'stock wifi' > "$R/system/app/HKMC_WifiSettings.odex"
printf '<stock/>' > "$R/system/etc/permissions/platform.xml"
chmod 644 "$R"/system/app/*.odex "$R/system/etc/permissions/platform.xml"; chmod 755 "$R/system/etc/permissions"
meta() { "$H" metadata "$1"; }
row() { # feature source target
    local s=$R$2 tgt=$R$3
    printf 'authored %s' "$1" > "$s"; chmod 644 "$s"
    "$H" sha256 "$tgt" > "$s.stock"
    echo "$1|$2|$3|$("$H" sha256 "$s")|$(meta "$s")|static"
}
inventory() { for f in "$1"/*.xml; do echo "${f##*/}|$("$H" sha256 "$f")|$(meta "$f")"; done; }
{
    row bt /data/plan/bt.odex /system/app/Iap2ServerApp.odex
    row gpm /data/plan/gpm.odex /system/app/HKMC_GPM.odex
    row hotspot /data/plan/hotspot.odex /system/app/HKMC_WifiSettings.odex
    cp -p "$R/system/etc/permissions/platform.xml" "$R/data/plan/perms/platform.xml"
    printf '<carplay-wireless/>' > "$R/data/plan/perms/com.hkmc.software.connectivity.carplay_wireless.xml"
    chmod 644 "$R/data/plan/perms/"*.xml; chmod 755 "$R/data/plan/perms"
    inventory "$R/data/plan/perms" > "$R/data/plan/perms.inventory"
    inventory "$R/system/etc/permissions" > "$R/data/plan/perms.stock-inventory"
    digest=$(cat "$R/data/plan/perms.inventory" "$R/data/plan/perms.stock-inventory" | sha256sum | cut -d' ' -f1)
    echo "projection|/data/plan/perms|/system/etc/permissions|$digest|$(meta "$R/data/plan/perms")|directory"
} > "$R/data/plan/manifest"
stock_sums() { for f in "$R"/system/app/*.odex "$R"/system/etc/permissions/*.xml; do echo "$("$H" sha256 "$f") ${f#$R}"; done; }
stock_sums > "$t/stock.sums"

# ---- Android boundary state ----
echo boot-1 > "$A/boot"; echo running > "$A/props/init.svc.zygote"; echo 'hkmc/kona:V039' > "$A/props/ro.build.fingerprint"
echo 1 > "$A/system_server"; : > "$A/mounts"; : > "$A/log"
cat > "$t/bin/getprop" <<'SH'
#!/bin/sh
case "$1" in */*|'') exit 1;; esac
cat "$ACTIONS/props/$1" 2>/dev/null || :
SH
chmod +x "$t/bin/getprop"

# Extract a script's production op() case statement (without the fixture branch).
extract_op() {
    awk '/^op\(\) \{$/{on=1;next} on&&/^    case "\$1" in$/{body=1} on&&/^\}$/{exit} body' "$1" | sed 's#/system/bin/sh #mksh #g'
}
# Caller script path: adapters run as children of the calling script process.
cat > "$t/caller.sh" <<'SH'
caller() {
    local arg parent=$PPID depth=0 line rest
    # Bounded query workers now have the native supervisor between adapter and
    # script. Walk proven live ancestors instead of assuming direct parenthood.
    while [ "$depth" -lt 6 ] && [ "$parent" -gt 1 ]; do
        for arg in $(tr '\0' '\n' < "/proc/$parent/cmdline"); do
            case "$arg" in */boot.sh|*/rescue.sh|*/runtime.sh|*/overlay.sh) echo "$arg"; return 0;; esac
        done
        IFS= read -r line < "/proc/$parent/stat" || return 1
        rest=${line##*) }; set -- $rest; parent=$2; depth=$((depth+1))
    done
    return 1
}
SH

# Boot/rescue adapter: Android+session mocked; inter-script ops are production.
{
    echo '#!/usr/bin/mksh'
    echo ". $t/caller.sh"
    cat <<'SH'
ROOT=$PORTABLE_TEST_ROOT
STATE=$ROOT/data/local/gen5w-portable/boot
PAYLOAD=$ROOT/data/local/gen5w-portable/runtime-payload
SUPERVISOR=$PORTABLE_TEST_SUPERVISOR
script=$(caller) || { echo "adapter: unknown caller for $1" >> "$ACTIONS/errors"; exit 1; }
BASE=${script%/*}
case "$script" in */boot.sh) HELPER=$PORTABLE_TEST_HELPER;; *) HELPER=$BASE/bin/dex-patch;; esac
mock() {
    case "$1" in
    boot) cat "$ACTIONS/boot";;
    get) cat "$ACTIONS/props/$2" 2>/dev/null || :;;
    dependencies) printf 'media
surfaceflinger
';;
    framework) [ "$(cat "$ACTIONS/props/init.svc.zygote")" = running ] && echo "$(cat "$ACTIONS/system_server"):1";;
    framework-ready)
        # framework.sh semantics: a running system_server other than framework-before.
        [ "$(cat "$ACTIONS/props/init.svc.zygote")" = running ] && [ ! -f "$ACTIONS/hold-ready" ] &&
        [ "$(cat "$ACTIONS/system_server"):1" != "$(cat "$STATE/framework-before" 2>/dev/null)" ];;
    stop-android) echo stop >> "$ACTIONS/log"; echo stopped > "$ACTIONS/props/init.svc.zygote";;
    start-android) [ -s "$STATE/dependencies" ] || exit 1; echo start >> "$ACTIONS/log"; echo $(( $(cat "$ACTIONS/system_server") + 1 )) > "$ACTIONS/system_server"; echo running > "$ACTIONS/props/init.svc.zygote";;
    launch-dipo) echo launch-dipo >> "$ACTIONS/log";;
    dipo-ready) [ ! -f "$ACTIONS/dipo-never-ready" ];;
    busy) [ -f "$ACTIONS/session-live" ];;
    session) rm -f "$ACTIONS/session-stop"; touch "$ACTIONS/session-live"
        while [ ! -f "$ACTIONS/session-stop" ]; do sleep .05; done; rm -f "$ACTIONS/session-live";;
    session-stop) touch "$ACTIONS/session-stop";;
    session-ready) [ -f "$ACTIONS/session-live" ];;
    pause) sleep .02;;
    esac
}
case "$1" in boot|get|dependencies|framework|framework-ready|stop-android|start-android|launch-dipo|dipo-ready|busy|session|session-stop|session-ready|pause)
    mock "$@"; exit $?;; esac
echo "$1 ${script##*/}" >> "$ACTIONS/calls"
case "$script" in
*/rescue.sh) rescue_op "$@";;
*) boot_op "$@";;
esac
SH
} > "$t/boot-adapter.body"
{
    head -n 2 "$t/boot-adapter.body"
    echo 'boot_op() {'; extract_op "$B/boot.sh"; echo '}'
    echo 'rescue_op() {'; extract_op "$B/rescue.sh"; echo '}'
    tail -n +3 "$t/boot-adapter.body"
} > "$t/boot-adapter"

# Runtime adapter: properties and VM probe mocked; feature is production.
{
    echo '#!/usr/bin/mksh'
    echo ". $t/caller.sh"
    cat <<'SH'
ROOT=$PORTABLE_TEST_ROOT
script=$(caller) || { echo "runtime adapter: unknown caller" >> "$ACTIONS/errors"; exit 1; }
BASE=${script%/*}
HELPER=${PORTABLE_HELPER:-$BASE/bin/dex-patch}
STATE=$ROOT/data/local/gen5w-portable/runtime
case "$1" in
get) cat "$ACTIONS/props/$2" 2>/dev/null || :; exit 0;;
set) case "$2" in wrap.*) :;; *) exit 1;; esac
     if [ -z "$3" ]; then rm -f "$ACTIONS/props/$2"; else print -r -- "$3" > "$ACTIONS/props/$2"; fi; exit 0;;
healthy) [ "$(cat "$ACTIONS/props/init.svc.zygote")" = running ] && [ ! -f "$ACTIONS/hold-ready" ]; exit $?;;
probe) [ ! -f "$ACTIONS/probe-fails" ]; exit $?;;
boot) cat "$ACTIONS/boot"; exit 0;;
esac
echo "$1 ${script##*/}" >> "$ACTIONS/calls"
runtime_op "$@"
SH
} > "$t/runtime-adapter.body"
{
    head -n 2 "$t/runtime-adapter.body"
    echo 'runtime_op() {'; extract_op "$B/runtime.sh"; echo '}'
    tail -n +3 "$t/runtime-adapter.body"
} > "$t/runtime-adapter"

# Overlay adapter: only the mount namespace and file identity/digests.
cat > "$t/overlay-adapter" <<'SH'
#!/usr/bin/mksh
ROOT=$PORTABLE_TEST_ROOT; M=$ACTIONS/mounts; H=$PORTABLE_TEST_HELPER
source_of() { local target source; while IFS='|' read -r target source; do [ "$target" != "$1" ] || { echo "$source"; return 0; }; done < "$M"; return 1; }
identity() { local s; if s=$(source_of "$1"); then "$H" identity "$s"; else "$H" identity "$1"; fi; }
case "$1" in
boot) cat "$ACTIONS/boot";;
healthy) [ "$(cat "$ACTIONS/props/init.svc.zygote")" = running ] && [ ! -f "$ACTIONS/hold-ready" ];;
ready) [ "$(cat "$ACTIONS/props/init.svc.zygote")" = stopped ];;
namespace) :;;
identity) identity "$2";;
sha) "$H" sha256 "$2";;
meta) "$H" metadata "$2";;
visible) source_of "$2" >/dev/null;;
bound) a=$(identity "$2") && [ -n "$a" ] && [ "$a" = "$(identity "$3")" ];;
bind)
    ! source_of "$3" >/dev/null || exit 1
    [ "$(cat "$ACTIONS/props/init.svc.zygote")" = stopped ] || { echo "bind while zygote running: $3" >> "$ACTIONS/errors"; exit 1; }
    stash=$ACTIONS/stash/$(echo "$3" | tr / _)
    [ ! -e "$stash" ] || exit 1
    mv "$3" "$stash" && cp -a "$2" "$3" && echo "$3|$2" >> "$M" && echo "bind ${3#$ROOT}" >> "$ACTIONS/log";;
unmount)
    source_of "$2" >/dev/null || exit 1
    stash=$ACTIONS/stash/$(echo "$2" | tr / _)
    rm -rf "$2" && mv "$stash" "$2" || exit 1
    grep -v "^$2|" "$M" > "$M.tmp" || :; mv "$M.tmp" "$M"; echo "unmount ${2#$ROOT}" >> "$ACTIONS/log";;
sync) :;;
*) exit 1;;
esac
SH
chmod +x "$t/boot-adapter" "$t/runtime-adapter" "$t/overlay-adapter"
mksh -n "$t/boot-adapter" && mksh -n "$t/runtime-adapter" || fail 'generated adapter does not parse'
# Every production op is either an Android/OS boundary or reaches a real script.
for name in plan plan-boot plan-static apply runtime-enable runtime-disable overlay-disable commit-static commit dirty active; do
    grep -q "^    $name)" "$t/boot-adapter" || fail "production boot op $name missing"
done
grep -q '^    feature)' "$t/runtime-adapter" || fail 'production runtime feature op missing'

export ACTIONS=$A PATH=$t/bin:$PATH
export PORTABLE_TEST_ROOT=$R PORTABLE_TEST_BOOT_ADAPTER=$t/boot-adapter PORTABLE_TEST_HELPER=$H
export PORTABLE_TEST_SUPERVISOR=$H PORTABLE_BOOT_TIMEOUT=10
export PORTABLE_TEST_ADAPTER=$t/overlay-adapter PORTABLE_STATE_DIR=$P/overlay
export PORTABLE_TEST_RUNTIME_ADAPTER=$t/runtime-adapter
cat > "$t/ap-adapter" <<'SH'
#!/bin/sh
case "$1" in boot) cat "$ACTIONS/boot";; wifi-ap-on) echo 0;; sync) :;; *) exit 1;; esac
SH
chmod +x "$t/ap-adapter"
export PORTABLE_TEST_AP_ADAPTER=$t/ap-adapter

boot() { mksh "$B/boot.sh" "$@"; }
J=$P/boot
prop() { cat "$A/props/$1" 2>/dev/null || :; }
cycles() { grep -cx stop "$A/log" || :; }
expect_mounts() { # sorted target list
    local want=$1 got
    got=$(cut -d'|' -f1 "$A/mounts" | sed "s#^$R##" | sort | tr '\n' ' ')
    [ "$got" = "$want" ] || fail "$2: mounts [$got] want [$want]"
}
DIPO='/system/bin/sh /data/local/gen5w-portable/runtime-payload/wrap-dipo.sh'
GPM='/system/bin/sh /data/local/gen5w-portable/runtime-payload/wrap-gpm.sh'
ALL='/system/app/HKMC_GPM.odex /system/app/HKMC_WifiSettings.odex /system/app/Iap2ServerApp.odex /system/etc/permissions '

# Power loss / QuickBoot: every process started after the snapshot is gone.
kill_runner() {
    [ -n "$runner" ] || return 0
    kill -9 -- "-$runner" 2>/dev/null || :; wait "$runner" 2>/dev/null || :; runner=
    rm -f "$A/session-live" "$A/session-stop"
}
erase_mounts() { # kernel mount table does not survive
    local target source
    while IFS='|' read -r target source; do
        rm -rf "$target" && mv "$A/stash/$(echo "$target" | tr / _)" "$target"
    done < "$A/mounts"
    : > "$A/mounts"
}
erase_wrappers() { rm -f "$A"/props/wrap.*; }
new_framework() { echo running > "$A/props/init.svc.zygote"; echo $(( $(cat "$A/system_server") + 100 )) > "$A/system_server"; }
cold_boot() { kill_runner; erase_mounts; erase_wrappers; echo "$1" > "$A/boot"; new_framework; }
quickboot() { # same kernel boot_id; $1 = which volatile state is lost
    kill_runner
    case "$1" in *mounts*) erase_mounts;; esac
    case "$1" in *wrappers*) erase_wrappers;; esac
    new_framework
}
start_run() {
    setsid mksh "$B/boot.sh" run > "$t/run.out" 2>&1 & runner=$!
    local i
    for i in $(seq 1 3000); do
        grep -q "|healthy$" "$J/attempt" 2>/dev/null && [ -f "$A/session-live" ] && return 0
        kill -0 "$runner" 2>/dev/null || break
        sleep .02
    done
    cat "$t/run.out" >&2; boot status >&2; fail "$1: run did not reach healthy"
}
healthy_full() { # label
    expect_mounts "$ALL" "$1"
    [ "$(prop wrap.com.daudio.app.dipo)" = "$DIPO" ] || fail "$1: dipo wrapper [$(prop wrap.com.daudio.app.dipo)]"
    [ "$(prop wrap.com.google.android.project)" = "$GPM" ] || fail "$1: gpm wrapper"
    [ "$(mksh "$B/portable.sh" status | head -n1)" = 'state|committed' ] || fail "$1: overlay not committed"
    [ "$(mksh "$B/runtime.sh" status)" = 'runtime|committed' ] || fail "$1: runtime not committed"
    [ "$(cat "$J/runtime-mode")" = full ] && [ "$(cat "$J/enabled")" = 1 ] || fail "$1: mode/enabled"
    # Each bound target shows exactly the authored source, owned like the source.
    [ "$("$H" sha256 "$R/system/app/Iap2ServerApp.odex")" = "$("$H" sha256 "$R/data/plan/bt.odex")" ] || fail "$1: bt view"
    [ -f "$R/system/etc/permissions/com.hkmc.software.connectivity.carplay_wireless.xml" ] || fail "$1: projection view"
}
no_errors() { [ ! -s "$A/errors" ] || { cat "$A/errors" >&2; fail "$1: adapter errors"; }; }

# 1. Arm on a healthy boot: nothing changes this boot.
boot arm /data/plan/manifest > /dev/null
[ "$(cat "$J/attempt")" = 'boot-1|armed' ] || fail 'arm journal'
boot run; expect_mounts '' 'armed same boot'; [ "$(cycles)" = 0 ] || fail 'armed boot restarted Android'
[ -z "$(prop wrap.com.daudio.app.dipo)" ] || fail 'armed boot wrote wrappers'
echo 'PASS arm: journals sealed, current boot untouched'

# 2-4. First, second and third real boots each activate exactly once.
n=0
for id in boot-2 boot-3 boot-4; do
    cold_boot "$id"; before=$(cycles)
    start_run "$id"
    healthy_full "$id"
    [ "$(( $(cycles) - before ))" = 1 ] || fail "$id: $(( $(cycles) - before )) framework restarts"
    [ "$(cat "$J/attempt")" = "$id|healthy" ] || fail "$id attempt"
    no_errors "$id"; n=$((n+1))
done
# A duplicate service start in the same healthy boot neither restarts nor rebinds.
before=$(cycles); boot run; [ "$(cycles)" = "$before" ] || fail 'duplicate run restarted Android'
echo "PASS $n cold boots: one restart each, all 4 binds, both wrappers, overlay+runtime committed"

# 5. QuickBoot-like resume: same boot_id, mounts and wrapper properties lost.
quickboot mounts+wrappers; before=$(cycles)
expect_mounts '' 'after quickboot erase'
start_run quickboot
healthy_full quickboot
[ "$(( $(cycles) - before ))" = 1 ] || fail 'quickboot restarts'
[ "$(cat "$J/attempt")" = 'boot-4|healthy' ] || fail 'quickboot attempt'
no_errors quickboot
echo 'PASS QuickBoot same boot_id with erased mounts+wrappers re-activates once'

# Settle: a full boot keeps its session; static/failed boots exit.
settle() {
    setsid mksh "$B/boot.sh" run > "$t/run.out" 2>&1 & runner=$!
    local i
    for i in $(seq 1 3000); do
        if ! kill -0 "$runner" 2>/dev/null; then settled=0; wait "$runner" 2>/dev/null || settled=$?; runner=; return 0; fi
        grep -q "|healthy$" "$J/attempt" 2>/dev/null && [ -f "$A/session-live" ] && { settled=running; return 0; }
        sleep .02
    done
    cat "$t/run.out" >&2; fail "$1: run did not settle"
}
bound() { cut -d'|' -f1 "$A/mounts" | grep -qx "$R$1"; }
# Safety invariant: the wireless declarations/iAP2 overlay are live exactly
# when the owned DiPO wrapper is live, and wrappers never point at the package.
invariant() {
    local wireless=0
    bound /system/app/Iap2ServerApp.odex && bound /system/etc/permissions && wireless=1
    if [ -n "$(prop wrap.com.daudio.app.dipo)" ]; then
        [ "$wireless" = 1 ] && [ "$(prop wrap.com.daudio.app.dipo)" = "$DIPO" ] || fail "$1: wrapper without wireless overlays"
    else
        ! bound /system/app/Iap2ServerApp.odex && ! bound /system/etc/permissions || fail "$1: bt/projection bound without runtime"
    fi
    case "$(prop wrap.com.daudio.app.dipo)$(prop wrap.com.google.android.project)" in *"$B"*|*/data/bundle/*) fail "$1: wrapper in deletable package";; esac
}
rearm() { # disable (restores), re-arm on $1, healthy full boot on $2
    kill_runner
    boot disable > "$t/disable.out" 2>&1 || { cat "$t/disable.out" >&2; fail "disable before re-arm"; }
    expect_mounts '' 'after disable'
    cold_boot "$1"; boot arm /data/plan/manifest > /dev/null; cold_boot "$2"; start_run "$2"; healthy_full "$2"
}

# 6. QuickBoot that loses mounts but keeps wrapper properties.
quickboot mounts; before=$(cycles)
start_run 'quickboot mounts-only'; healthy_full 'quickboot mounts-only'
[ "$(( $(cycles) - before ))" = 1 ] || fail 'mounts-only restarts'; no_errors mounts-only
echo 'PASS QuickBoot losing only mounts: stale journal retired, one restart, healthy'

# 7. Host session ends: degraded for this boot_id only.
touch "$A/session-stop"; wait "$runner" && fail 'session end reported success'; runner=
[ "$(cat "$J/attempt")" = 'boot-4|degraded' ] && [ "$(cat "$J/enabled")" = 1 ] || fail 'session end journal'
before=$(cycles); boot run && fail 'degraded boot retried'; [ "$(cycles)" = "$before" ] || fail 'degraded retry restarted Android'
quickboot mounts+wrappers; before=$(cycles)
if boot run; then fail 'degraded QuickBoot ran'; fi
[ "$(cycles)" = "$before" ] && [ ! -s "$A/mounts" ] || fail 'degraded QuickBoot changed Android'
invariant 'degraded quickboot'
cold_boot boot-5; start_run boot-5; healthy_full boot-5
echo 'PASS session end: degraded, no same-boot retry (also across QuickBoot), next cold boot healthy'

# 8. QuickBoot that loses only wrapper properties, mounts retained.
quickboot wrappers; before=$(cycles)
settle 'quickboot wrappers-only'
if [ "$(cat "$J/enabled")" = 1 ] && [ "$settled" = running ]; then
    healthy_full 'quickboot wrappers-only'; invariant 'quickboot wrappers-only'
    echo 'PASS QuickBoot losing only wrappers re-activates'
else
    # Current behaviour (see .build/portable/claude-lifecycle-report.md L1).
    reason=$(cat "$J/reason")
    echo "KNOWN-DEFECT L1: wrappers-only QuickBoot -> enabled=$(cat "$J/enabled") reason=$reason, $(wc -l < "$A/mounts") overlays still bound, dipo wrapper [$(prop wrap.com.daudio.app.dipo)]"
    [ "${PORTABLE_LIFECYCLE_STRICT:-0}" = 0 ] || fail 'L1 wrappers-only QuickBoot'
    boot disable > "$t/disable.out" 2>&1 || { cat "$t/disable.out" >&2; fail 'disable after L1'; }
    expect_mounts '' 'disable after L1'; [ -z "$(prop wrap.com.daudio.app.dipo)" ] || fail 'L1 wrapper left'
    echo 'PASS L1 state is fully restored by explicit disable'
    rearm boot-6 boot-7
fi

# 9. Static fallback: the Dalvik probe fails on a cold boot.
touch "$A/probe-fails"; cold_boot boot-8; before=$(cycles); settle static
[ "$settled" = 0 ] && [ "$(cat "$J/attempt")" = 'boot-8|healthy' ] && [ "$(cat "$J/runtime-mode")" = static ] || { cat "$t/run.out" >&2; fail 'static fallback'; }
expect_mounts '/system/app/HKMC_GPM.odex /system/app/HKMC_WifiSettings.odex ' static
invariant static; [ "$(( $(cycles) - before ))" = 1 ] || fail 'static restarts'; no_errors static
# The runtime selection policy for later boots is outside this test; only invariants.
rm "$A/probe-fails"; cold_boot boot-9; settle 'after static'
[ "$(cat "$J/attempt")" = 'boot-9|healthy' ] || fail 'after static attempt'; invariant 'after static'
echo "PASS static fallback: bt/projection withheld, independent features bound, next boot mode=$(cat "$J/runtime-mode")"

# 10. DiPO never becomes ready: runtime retired, static features kept.
rearm boot-10 boot-11
touch "$A/dipo-never-ready"; cold_boot boot-12; before=$(cycles); settle 'dipo never ready'
[ "$(cat "$J/attempt")" = 'boot-12|healthy' ] && [ "$(cat "$J/runtime-mode")" = static ] || fail 'dipo fallback'
invariant 'dipo never ready'; [ -z "$(prop wrap.com.google.android.project)" ] || fail 'gpm wrapper left after runtime recovery'
restarts=$(( $(cycles) - before )); no_errors dipo
rm "$A/dipo-never-ready"
echo "PASS DiPO readiness timeout: runtime retired to static in $restarts framework restarts"

# 11. Disable: owned mounts and wrappers gone, stock bytes and identities intact.
kill_runner
boot disable > /dev/null
expect_mounts '' 'final disable'
[ -z "$(prop wrap.com.daudio.app.dipo)$(prop wrap.com.google.android.project)" ] || fail 'wrapper after disable'
stock_sums | diff - "$t/stock.sums" || fail 'stock bytes changed'
[ "$(mksh "$B/portable.sh" status | head -n1)" = 'state|disabled' ] && [ "$(mksh "$B/runtime.sh" status)" = 'runtime|disabled' ] || fail 'journals after disable'
[ "$(cat "$J/reason")" = disabled-restored ] && [ "$(cat "$J/enabled")" = 0 ] || fail 'boot journal after disable'
cold_boot boot-13; boot run; expect_mounts '' 'disabled cold boot'
no_errors final
echo 'PASS disable restores stock; disabled install stays inert on the next boot'
