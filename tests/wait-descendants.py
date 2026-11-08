"""Linux test runner: join real orphaned grandchildren before inspecting files."""
import ctypes
import os
import signal
import subprocess
import sys
import time

# read_requests launches do_save in a grandchild, so a shell EXIT wait cannot
# join it. Adopt descendants in this test-only process; production stays async.
libc = ctypes.CDLL(None, use_errno=True)
if libc.prctl(36, 1, 0, 0, 0) != 0:  # PR_SET_CHILD_SUBREAPER
    raise OSError(ctypes.get_errno(), 'cannot enable test child subreaper')
child = subprocess.Popen(sys.argv[1:], start_new_session=True)
deadline = time.monotonic() + 20
timed_out = False
while True:
    try:
        pid, status = os.waitpid(-1, os.WNOHANG)
    except ChildProcessError:
        break
    if pid == child.pid:
        child.returncode = os.waitstatus_to_exitcode(status)
    if pid == 0:
        if time.monotonic() >= deadline and not timed_out:
            timed_out = True
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            print('FAIL test descendants exceeded 20s', file=sys.stderr)
        time.sleep(.01)
sys.exit(1 if timed_out else child.returncode)
