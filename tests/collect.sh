#!/bin/bash
# mock test for probe/package/bin/collect.sh
. "$(dirname "$0")/lib.sh"
S=$(cd "$(dirname "$0")/../probe/package/bin" && pwd)
W=$(mktemp -d); stubs; mkdir -p $W/usb $W/src
echo one > $W/src/probe.log; echo two > $W/src/probe.log.1
printf '#!/bin/sh\necho "I/Gen5wProbe( 1): notify what=0x1"\necho "I/Other( 2): noise"\n' > $W/bin/logcat; chmod +x $W/bin/logcat
GEN5W_TEST_PATH=$W/bin:$PATH PROBE_TEST_USB=$W/usb PROBE_TEST_SRC=$W/src mksh $S/collect.sh >/dev/null
D=$(ls -d $W/usb/GEN5WKR_PROBE_* | head -1)
check "log files copied" eval '[ "$(cat $D/probe.log)$(cat $D/probe.log.1)" = onetwo ]'
check "info written" grep -q files=2 $D/info.txt
check "only probe lines from logcat" eval 'grep -q Gen5wProbe $D/logcat.txt && ! grep -q noise $D/logcat.txt'
GEN5W_TEST_PATH=$W/bin:$PATH PROBE_TEST_USB=$W/nousb PROBE_TEST_SRC=$W/src mksh $S/collect.sh >/dev/null 2>&1
check "fails cleanly without a USB drive" [ $? != 0 ]
done_tests collect
