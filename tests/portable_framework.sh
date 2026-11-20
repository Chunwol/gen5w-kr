#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/g5p-framework.XXXXXX)
child=
trap 'rc=$?; [ -z "$child" ] || { kill "$child" 2>/dev/null || :; wait "$child" 2>/dev/null || :; }; rm -rf "$t"; exit $rc' EXIT
mkdir "$t/bin"
cat > "$t/bin/getprop" <<'SH'
#!/bin/sh
case "$1" in init.svc.zygote) echo running;; sys.boot_completed) echo 1;; esac
SH
cat > "$t/bin/service" <<'SH'
#!/bin/sh
[ ! -f "$FIXTURE/no-package" ] || exit 1
echo "Service $2: found"
SH
cat > "$t/bin/dumpsys" <<'SH'
#!/bin/sh
[ "$#" = 2 ] && [ "$1" = activity ] && [ "$2" = p ] || exit 1
[ ! -f "$FIXTURE/hang" ] || sleep 30
[ ! -f "$FIXTURE/delay" ] || sleep 9
cat "$FIXTURE/activity"
SH
chmod +x "$t/bin/"*
export FIXTURE=$t PATH=$t/bin:$PATH
bash -c 'exec -a system_server sleep 30' & child=$!
for unused in $(seq 1 100); do
    key=$(mksh tools/portable/framework.sh identity) && break
    sleep .01
done
[ "${key%%:*}" = "$child" ]

# Per-PID command matching must remain usable without spawning a grep for every
# process. Under ARM system emulation that scan alone exhausted the 8s guard.
cat > "$t/bin/grep" <<'SH'
#!/bin/sh
if [ "$1" = -aq ]; then
    echo external-process-match >> "$FIXTURE/identity-execs"
    exit 1
fi
exec /usr/bin/grep "$@"
SH
chmod +x "$t/bin/grep"
fast_key=$(mksh tools/portable/framework.sh identity) || { echo 'FAIL identity depends on per-process external matching'; exit 1; }
[ "$fast_key" = "$key" ]
[ ! -e "$t/identity-execs" ]
echo 'PASS identity preserves PID/start time without per-process helper execution'
echo 'mBooting=true mBooted=false' > "$t/activity"
if mksh tools/portable/framework.sh ready; then echo 'FAIL trusted stale sys.boot_completed'; exit 1; fi
echo 'mBooting=false mBooted=true' > "$t/activity"
mksh tools/portable/framework.sh ready
if mksh tools/portable/framework.sh ready "$key"; then echo 'FAIL accepted pre-restart system_server'; exit 1; fi
touch "$t/no-package"
if mksh tools/portable/framework.sh ready; then echo 'FAIL missing PackageManager'; exit 1; fi
echo 'PASS current system_server identity, actual ActivityManager booted flag, PackageManager and stale-property rejection'

# Discover restart dependencies from the local init service definition; never
# execute the stock onrestart write directives or hardcode a vendor daemon list.
mkdir "$t/init"
cat > "$t/init/init.rc" <<'RC'
service unrelated /system/bin/other
    onrestart restart unrelated-child
service zygote /system/bin/app_process --zygote
    class main
    onrestart write /sys/power/state on
    onrestart restart media
    onrestart restart netd
service next /system/bin/next
    onrestart restart never
RC
[ "$(mksh tools/portable/framework.sh dependencies "$t/init")" = "$(printf 'media\nnetd')" ]
echo 'service zygote /system/bin/other' > "$t/init/init.other.rc"
if mksh tools/portable/framework.sh dependencies "$t/init"; then echo 'FAIL ambiguous zygote definition'; exit 1; fi
echo 'PASS local stock zygote dependency discovery without executing arbitrary init actions'

# A complete healthy dump can take nine seconds on the one-core ARM VM.
# It must finish while still checking mBooted and the same server identity.
rm -f "$t/no-package"
export PORTABLE_TEST_FRAMEWORK_HELPER=$PWD/.build/portable/dex-patch-host
unset PORTABLE_TEST_FRAMEWORK_TIMEOUT
touch "$t/delay"
mksh tools/portable/framework.sh ready || { echo 'FAIL healthy nine-second readiness dump rejected'; exit 1; }
rm "$t/delay"
echo 'PASS slow healthy dump retains real booted and identity checks'

# Exercise the real native process-group timeout on a stalled Binder query.
rm -f "$t/no-package"
touch "$t/hang"
export PORTABLE_TEST_FRAMEWORK_HELPER=$PWD/.build/portable/dex-patch-host
export PORTABLE_TEST_FRAMEWORK_TIMEOUT=1
start=$SECONDS
if mksh tools/portable/framework.sh ready; then echo 'FAIL accepted hanging AMS'; exit 1; fi
[ "$((SECONDS-start))" -lt 5 ]
echo 'PASS stalled dumpsys is killed with descendants within wall-clock deadline'
