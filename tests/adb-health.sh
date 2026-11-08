#!/bin/bash
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/data/nemesis/logs" "$W/ui" "$W/net"
cat > "$W/bin/getprop" <<EOF
#!/bin/sh
case "\$1" in service.adb.tcp.port) cat "$W/port" 2>/dev/null;; init.svc.adbd) cat "$W/daemon" 2>/dev/null;; esac
EOF
cat > "$W/bin/setprop" <<EOF
#!/bin/sh
[ ! -e "$W/failprop" ] || exit 1
echo "\$2" > "$W/port"
EOF
cat > "$W/bin/stop" <<EOF
#!/bin/sh
echo stopped > "$W/daemon"; : > "$W/net/tcp"; echo stop >> "$W/calls"
EOF
cat > "$W/bin/start" <<EOF
#!/bin/sh
echo start >> "$W/calls"
[ ! -e "$W/failstart" ] || exit 1
echo running > "$W/daemon"
if [ -e "$W/listen" ]; then echo '0: 00000000:15B3 00000000:0000 0A 0 0 0' > "$W/net/tcp"; fi
EOF
printf '#!/bin/sh\nexit 0\n' > "$W/bin/logcat"; cp "$W/bin/logcat" "$W/bin/pm"
chmod +x "$W/bin/"*; export PATH="$W/bin:$PATH"
request() { printf 'boot=%s\nexpires=%s\nadb=%s\n' "$(cat /proc/sys/kernel/random/boot_id)" "$(($(cut -d. -f1 /proc/uptime) + 30))" "$1" > "$W/request"; }
run() { UILOG_TEST_DATA=$W/data UILOG_TEST_DIR=$W/ui UILOG_TEST_REQUEST=$W/request UILOG_TEST_PROCNET=$W/net UILOG_TEST_ONCE=1 mksh "$ROOT/packages/core/scripts/uilog.sh" > "$W/out" 2>&1; }
echo 5555 > "$W/port"; echo stopped > "$W/daemon"; : > "$W/net/tcp"; run
check 'configured port with dead daemon is not reported as listening' grep -qx 'adb_health=daemon-down' "$W/ui/status"
echo running > "$W/daemon"; run
check 'running daemon without a listener is distinguished' grep -qx 'adb_health=not-listening' "$W/ui/status"
printf '0: 00000000:15B3 00000000:0000 0A 0 0 0\n' > "$W/net/tcp"; run
check 'actual TCP LISTEN socket is observed' grep -qx 'adb_health=listening' "$W/ui/status"
: > "$W/failprop"; echo 0 > "$W/port"; request on:11; run
check 'failed property update is acknowledged as a failure' grep -qx 'adb_result=11:failed' "$W/ui/status"
rm -f "$W/failprop"; : > "$W/listen"; request on:12; run
check 'fresh retry after failure starts the listener' grep -qx 'adb_health=listening' "$W/ui/status"
check 'successful command is acknowledged' grep -qx 'adb_result=12:applied' "$W/ui/status"
: > "$W/net/tcp"; echo stopped > "$W/daemon"; request on:13; run
check 'same configured port can recover an unhealthy daemon' grep -qx 'adb_health=listening' "$W/ui/status"
echo 0 > "$W/port"; rm -f "$W/listen"; request off:14; run
check 'off stops a stale TCP listener even if property was already zero' grep -qx 'adb_health=off' "$W/ui/status"
done_tests adb-health
