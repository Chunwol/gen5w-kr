#!/bin/bash
# mock test for probe/package/bin/collect.sh
. "$(dirname "$0")/lib.sh"
S=$(cd "$(dirname "$0")/../probe/package/bin" && pwd)
W=$(mktemp -d); stubs; mkdir -p $W/usb $W/src
echo one > $W/src/probe.log; echo two > $W/src/probe.log.1
cat > $W/bin/logcat <<'EOF'
#!/bin/sh
case "$*" in
    *'-s ConsentScreen:V'*) echo 'D/ConsentScreen( 1): mScreenEnabled : true';;
    *'-b '*) echo "LOGCAT_BUFFER $*";;
    *) echo 'I/Gen5wProbe( 1): notify what=0x1'; echo 'I/Other( 2): noise';;
esac
EOF
printf '#!/bin/sh\necho "dmesg sample"\n' > $W/bin/dmesg
printf '#!/bin/sh\necho "dumpsys $*"\n' > $W/bin/dumpsys
chmod +x $W/bin/*
mkdir -p $W/src
echo 'timer: state accepted' > $W/src/timer.log
GEN5W_TEST_PATH=$W/bin:$PATH PROBE_TEST_USB=$W/usb PROBE_TEST_SRC=$W/src PROBE_TEST_STAMP=off PROBE_TEST_TIMER_LOG=$W/src/timer.log mksh $S/collect.sh >/dev/null
D=$W/usb/GEN5WKR_PROBE_off
check "log files copied" eval '[ "$(cat $D/probe.log)$(cat $D/probe.log.1)" = onetwo ]'
check "info written" grep -q files=2 $D/info.txt
check "only probe lines from logcat" eval 'grep -q Gen5wProbe $D/logcat.txt && ! grep -q noise $D/logcat.txt'
check "consent SystemUI log always collected" grep -q mScreenEnabled $D/consent.log
check "timer decision log always collected" grep -q 'timer: state accepted' $D/timer.log
check "debug is off by default" eval '! test -e "$D/DEBUG.txt" && grep -qx debug=off "$D/info.txt"'
touch $W/usb/GEN5W-DEBUG-ON
GEN5W_TEST_PATH=$W/bin:$PATH PROBE_TEST_USB=$W/usb PROBE_TEST_SRC=$W/src PROBE_TEST_STAMP=on PROBE_TEST_TIMER_LOG=$W/src/timer.log mksh $S/collect.sh >/dev/null
D=$W/usb/GEN5WKR_PROBE_on
check "debug mode collects system log buffer" grep -q '== logcat system ==' $D/DEBUG.txt
check "debug mode collects all logcat buffers" eval 'grep -q "== logcat main ==" "$D/DEBUG.txt" && grep -q "== logcat radio ==" "$D/DEBUG.txt" && grep -q "== logcat events ==" "$D/DEBUG.txt" && grep -q "== logcat crash ==" "$D/DEBUG.txt"'
check "debug mode captures system state" eval 'grep -q "== dmesg ==" "$D/DEBUG.txt" && grep -q "== dumpsys bluetooth_manager ==" "$D/DEBUG.txt" && grep -q "== dumpsys wifi ==" "$D/DEBUG.txt"'
touch $W/usb/GEN5W-DEBUG-OFF
GEN5W_TEST_PATH=$W/bin:$PATH PROBE_TEST_USB=$W/usb PROBE_TEST_SRC=$W/src PROBE_TEST_STAMP=off2 PROBE_TEST_TIMER_LOG=$W/src/timer.log mksh $S/collect.sh >/dev/null
D=$W/usb/GEN5WKR_PROBE_off2
check "explicit debug off disables expanded capture" eval '! test -e "$D/DEBUG.txt" && grep -qx debug=off "$D/info.txt"'
GEN5W_TEST_PATH=$W/bin:$PATH PROBE_TEST_USB=$W/nousb PROBE_TEST_SRC=$W/src mksh $S/collect.sh >/dev/null 2>&1
check "fails cleanly without a USB drive" [ $? != 0 ]
done_tests collect
