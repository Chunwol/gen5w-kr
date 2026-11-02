"""Focused host tests of the dongle root-service scripts."""
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

    def service_case(name, backend, request=False, ready=False, renew=False,
                     mark=False, block=False, loader_ok=False, unplug_at=0, replug_at=0):
        case = work/name
        case.mkdir()
        (case/'nemesis').mkdir()
        if mark:
            (case/'nemesis/gen5wkr.dongle-loading').write_text('loading\n')
        if block:
            (case/'nemesis/gen5wkr.dongle-blocked').write_text('blocked\n')
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
if [ "$n" = "$UNPLUG_AT" ]; then mv "$CASE/usb/1-1" "$CASE/usb-off"; fi
if [ "$n" = "$REPLUG_AT" ]; then mv "$CASE/usb-off" "$CASE/usb/1-1"; fi
[ "$n" -lt 12 ] || kill -TERM "$PPID"
''',
            'gen5w-dongle-load': ('echo attempt >> "$CASE/attempts"; '
                                  '[ -f "$CASE/nemesis/gen5wkr.dongle-loading" ] && echo marked >> "$CASE/marked"; '
                                  + ('mkdir -p "$CASE/net/wlan0"; exit 0' if loader_ok else 'exit 1')),
        }
        for filename, body in scripts.items():
            p = bindir/filename
            p.write_text('#!/bin/sh\n'+body+'\n')
            p.chmod(0o755)
        env = dict(os.environ, CASE=str(case), RENEW='1' if renew else '0',
            UNPLUG_AT=str(unplug_at), REPLUG_AT=str(replug_at), DONGLE_TEST_STABLE='6',
            PATH=str(bindir)+':'+os.environ['PATH'], DONGLE_TEST_SYS=str(case),
            DONGLE_TEST_DATA=str(case), DONGLE_TEST_SYS_BUS=str(usb.parent),
            DONGLE_TEST_NET_ROOT=str(net))
        # The production common script resolves the installed loader under SYS/bin.
        subprocess.run(['mksh', str(ROOT/'tools/usb-wifi/package/scripts/service.sh')],
                       env=env, capture_output=True, timeout=5)
        service_case.case = case
        return len((case/'attempts').read_text().splitlines()) if (case/'attempts').exists() else 0

    check('inactive backend never loads modules', service_case('inactive', 'builtin') == 0)
    check('one attachment stops after three attempts', service_case('bounded', 'dongle') == 3)
    check('explicit load request can start the root loader', service_case('request', 'builtin', True) == 1)
    check('new request resets the bounded retry budget', service_case('renew', 'dongle', renew=True) == 6)
    check('an existing interface does not trigger a reload', service_case('ready', 'dongle', ready=True) == 0)

    # Reboot-loop guard
    n = service_case('crashed', 'dongle', mark=True)
    c = service_case.case
    check('a load cut short by a restart blocks automatic loading', n == 0
          and (c/'nemesis/gen5wkr.dongle-blocked').exists()
          and not (c/'nemesis/gen5wkr.dongle-loading').exists())
    n = service_case('blocked-request', 'builtin', request=True, block=True)
    check('a blocked dongle ignores driver load requests', n == 0)
    n = service_case('clean-fail', 'dongle')
    c = service_case.case
    check('the mark is on disk during each load and cleared after a clean failure',
          (c/'marked').exists() and len((c/'marked').read_text().splitlines()) == n == 3
          and not (c/'nemesis/gen5wkr.dongle-loading').exists())
    n = service_case('stable', 'dongle', loader_ok=True)
    c = service_case.case
    check('a working dongle clears the mark after the stable period', n == 1
          and not (c/'nemesis/gen5wkr.dongle-loading').exists()
          and not (c/'nemesis/gen5wkr.dongle-blocked').exists())
    n = service_case('replug', 'dongle', mark=True, unplug_at=3, replug_at=6)
    c = service_case.case
    check('unplugging clears the block and the next attachment tries again', n >= 1
          and not (c/'nemesis/gen5wkr.dongle-blocked').exists())

print('== dongle runtime:', passed, 'passed,', failed, 'failed')
raise SystemExit(1 if failed else 0)
