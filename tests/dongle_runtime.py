"""Focused host tests of the actual HAL wait and root-service scripts."""
from pathlib import Path
import os
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
passed = 0
failed = 0


def check(name, condition):
    global passed, failed
    print(('PASS ' if condition else 'FAIL ') + name, flush=True)
    passed += bool(condition)
    failed += not condition


with tempfile.TemporaryDirectory(prefix='gen5w-dongle-runtime-') as work:
    work = Path(work)
    # No sleeping or real device access: compile the production C with host IO
    # substitutes. A five-second root startup used to outlast its three-second wait.
    harness = work / 'wait.c'
    harness.write_text(r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static unsigned long elapsed;
static int timeout_case;
int mock_access(const char *path, int mode) {
    (void)mode;
    return !strcmp(path, "/sys/class/net/wlan0") && !timeout_case
        && elapsed >= 5000000UL ? 0 : -1;
}
int mock_usleep(unsigned int duration) { elapsed += duration; return 0; }
uid_t mock_geteuid(void) { return 1000; }
int property_get(const char *key, char *value, const char *fallback) {
    const char *text = !strcmp(key, "persist.gen5w.wifi.backend") ? "dongle" : fallback;
    strcpy(value, text ? text : ""); return strlen(value);
}
int property_set(const char *key, const char *value) { (void)key; (void)value; return 0; }
int wifi_load_driver(void);
int main(int argc, char **argv) {
    (void)argv; timeout_case = argc > 1;
    int result = wifi_load_driver();
    if (!timeout_case) return result != 0 || elapsed < 5000000UL;
    return result != -1 || elapsed < 5000000UL || elapsed > 30000000UL;
}
''')
    binary = work / 'wait'
    built = subprocess.run(['cc', '-include', 'sys/types.h', '-Daccess=mock_access',
        '-Dusleep=mock_usleep', '-Dgeteuid=mock_geteuid',
        str(ROOT/'tools/usb-wifi/hal_adapter/wifi_hal_adapter.c'), str(harness),
        '-ldl', '-o', str(binary)], capture_output=True)
    check('HAL host harness compiles', built.returncode == 0)
    if built.returncode:
        print(built.stderr.decode(errors='replace'))
    else:
        check('HAL waits for a five-second root load', subprocess.run([str(binary)]).returncode == 0)
        check('HAL absence fails within a bounded deadline', subprocess.run([str(binary), 'timeout']).returncode == 0)

    for which in ('common', 'loader'):
        case = work / which
        case.mkdir()
        log = case / 'driver.log'
        log.write_bytes(b'x' * 40000)
        bindir = case / 'bin'
        bindir.mkdir()
        (bindir/'wc').write_text('#!/bin/sh\nexit 127\n')
        (bindir/'wc').chmod(0o755)
        if which == 'common':
            script = '. ' + shlex.quote(str(ROOT/'tools/usb-wifi/package/scripts/common.sh'))
        else:
            source = (ROOT/'tools/usb-wifi/package/bin/gen5w-dongle-load').read_text()
            script = source.split('# Already available')[0]
        script += '\nLOG_FILE=' + shlex.quote(str(log)) + '\nlog probe\n'
        env = dict(os.environ, PATH=str(bindir)+':'+os.environ['PATH'], DONGLE_TEST_DATA=str(case))
        subprocess.run(['mksh', '-c', script], env=env, check=True, capture_output=True)
        check(which + ' rotates oversized logs without wc', log.with_suffix('.log.1').exists()
              and log.read_bytes() == b'probe\n')

    def service_case(name, backend, request=False, ready=False, renew=False):
        case = work/name
        case.mkdir()
        net = case/'net'
        net.mkdir()
        usb = case/'usb/1-1'
        usb.mkdir(parents=True)
        (usb/'idVendor').write_text('0cf3\n')
        (usb/'idProduct').write_text('9271\n')
        if ready:
            (net/'wlan0').mkdir()
        props = case/'props'
        props.mkdir()
        (props/'persist.gen5w.wifi.backend').write_text(backend)
        (props/'wlan.driver.load.request').write_text('1' if request else '0')
        bindir = case/'bin'
        bindir.mkdir()
        scripts = {
            'getprop': 'cat "$CASE/props/$1" 2>/dev/null || true',
            'setprop': 'echo "$2" > "$CASE/props/$1"',
            'sleep': '''n=0
[ ! -f "$CASE/ticks" ] || n=$(cat "$CASE/ticks")
n=$((n+1)); echo "$n" > "$CASE/ticks"
if [ "$RENEW" = 1 ] && [ "$n" = 5 ]; then echo 1 > "$CASE/props/wlan.driver.load.request"; fi
[ "$n" -lt 12 ] || kill -TERM "$PPID"
''',
            'gen5w-dongle-load': 'echo attempt >> "$CASE/attempts"; exit 1',
        }
        for filename, body in scripts.items():
            p = bindir/filename
            p.write_text('#!/bin/sh\n'+body+'\n')
            p.chmod(0o755)
        env = dict(os.environ, CASE=str(case), RENEW='1' if renew else '0',
            PATH=str(bindir)+':'+os.environ['PATH'], DONGLE_TEST_SYS=str(case),
            DONGLE_TEST_DATA=str(case), DONGLE_TEST_SYS_BUS=str(usb.parent),
            DONGLE_TEST_NET_ROOT=str(net))
        # The production common script resolves the installed loader under SYS/bin.
        subprocess.run(['mksh', str(ROOT/'tools/usb-wifi/package/scripts/service.sh')],
                       env=env, capture_output=True, timeout=5)
        return len((case/'attempts').read_text().splitlines()) if (case/'attempts').exists() else 0

    check('inactive backend never loads modules', service_case('inactive', 'builtin') == 0)
    check('one attachment stops after three attempts', service_case('bounded', 'dongle') == 3)
    check('explicit load request can start the root loader', service_case('request', 'builtin', True) == 1)
    check('new request resets the bounded retry budget', service_case('renew', 'dongle', renew=True) == 6)
    check('an existing interface does not trigger a reload', service_case('ready', 'dongle', ready=True) == 0)

print('== dongle runtime:', passed, 'passed,', failed, 'failed')
raise SystemExit(1 if failed else 0)
