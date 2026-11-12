#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/g5p-framework.XXXXXX)
child=
trap '[ -z "$child" ] || { kill "$child" 2>/dev/null || :; wait "$child" 2>/dev/null || :; }; rm -rf "$t"' EXIT
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
