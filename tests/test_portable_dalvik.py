"""Host signature checks; ARM/actual V039 VM fixtures are separate and explicit."""
import glob
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

# Host harness for hook.c's process-environment and probe-marker behaviour. It
# builds hook.c for the host with the NDK's self-contained jni.h (the 32-bit
# Dalvik Method layout assertion is the only thing disabled), then runs a
# driver inside a private user/mount namespace whose chroot provides the real
# /data/data/com.daudio.app.dipo/files marker path. Nothing touches a device.
NATIVE_HARNESS = r'''
set -euo pipefail
src=$1 jni=$2
w=$(mktemp -d /tmp/gen5w-hook.XXXXXX)
trap 'rm -rf "$w"' EXIT
mkdir "$w/include"
cp "$jni" "$w/include/jni.h"
printf '#define _Static_assert(...) extern int gen5w_host_layout_check_skipped\n' > "$w/prelude.h"
gcc -shared -fPIC -O1 -I"$w/include" -include "$w/prelude.h" "$src/tools/portable/dalvik/hook.c" -o "$w/libgen5whook.so" -ldl
printf 'void gen5w_other(void) {}\n' > "$w/other.c"
gcc -shared -fPIC "$w/other.c" -o "$w/libother.so"
# Stand-in for libdvm: records VM options, the Bootstrap.start signature and
# arguments, and the environment visible while Bootstrap starts.
cat > "$w/fakevm.c" <<'C'
#include <jni.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
extern char **environ;
/* FAKEVM_FAIL=<n> makes the n-th JNI call fail with a pending exception; any
 * later JNI call other than the ones allowed while pending is reported. */
static int pending, calls, fail_at;
static int step(const char *what) {
    if (pending) printf("vm JNI-while-pending %s\n", what);
    if (++calls == fail_at) { pending = 1; printf("vm throw at %d %s\n", calls, what); return 1; }
    return 0;
}
static jclass find_class(JNIEnv *env, const char *name) { (void)env; printf("vm FindClass %s\n", name); return step("FindClass") ? 0 : (jclass)1; }
static jmethodID static_method(JNIEnv *env, jclass type, const char *name, const char *signature) {
    (void)env; (void)type;
    printf("vm GetStaticMethodID %s%s\n", name, signature);
    if (step("GetStaticMethodID")) return 0;
    if (!strcmp(name, "getSystemClassLoader")) return (jmethodID)3;
    return strcmp(signature, "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V") ? 0 : (jmethodID)1;
}
static jstring new_string(JNIEnv *env, const char *text) { (void)env; return step("NewStringUTF") ? 0 : (jstring)strdup(text); }
static void call_static_void(JNIEnv *env, jclass type, jmethodID method, ...) {
    va_list arguments;
    (void)env; (void)type;
    va_start(arguments, method);
    const char *library = va_arg(arguments, const char *), *adapter = va_arg(arguments, const char *), *owner = va_arg(arguments, const char *);
    va_end(arguments);
    printf("vm start library=%s adapter=%s owner=%s\n", library ? library : "(null)", adapter ? adapter : "(null)", owner ? owner : "(null)");
    for (char **entry = environ; *entry; entry++)
        if (!strncmp(*entry, "GEN5W_", 6) || !strncmp(*entry, "LD_PRELOAD=", 11)) printf("vm during-start environ %s\n", *entry);
    step("CallStaticVoidMethod");
}
static jmethodID method(JNIEnv *env, jclass type, const char *name, const char *signature) {
    (void)env; (void)type; printf("vm GetMethodID %s%s\n", name, signature); return step("GetMethodID") ? 0 : (jmethodID)2;
}
static jobject call_static_object(JNIEnv *env, jclass type, jmethodID id, ...) {
    (void)env; (void)type; (void)id; printf("vm getSystemClassLoader\n"); return step("CallStaticObjectMethod") ? 0 : (jobject)3;
}
static jobject call_object(JNIEnv *env, jobject self, jmethodID id, ...) {
    va_list arguments; (void)env; (void)id;
    va_start(arguments, id);
    if (self == (jobject)3) printf("vm getParent\n");
    else { const char *name = va_arg(arguments, const char *); printf("vm loadClass %s\n", name); }
    va_end(arguments);
    return step("CallObjectMethod") ? 0 : (jobject)4;
}
static jobject new_object(JNIEnv *env, jclass type, jmethodID id, ...) {
    va_list arguments; (void)env; (void)type; (void)id;
    va_start(arguments, id);
    const char *jar = va_arg(arguments, const char *), *cache = va_arg(arguments, const char *), *library = va_arg(arguments, const char *);
    jobject parent = va_arg(arguments, jobject);
    va_end(arguments);
    printf("vm DexClassLoader jar=%s cache=%s library=%s parent=%d\n", jar, cache, library ? library : "(null)", (int)(long)parent);
    return step("NewObject") ? 0 : (jobject)5;
}
static jint push_frame(JNIEnv *env, jint capacity) { (void)env; printf("vm PushLocalFrame %d\n", (int)capacity); return step("PushLocalFrame") ? -1 : 0; }
static jobject pop_frame(JNIEnv *env, jobject result) { (void)env; printf("vm PopLocalFrame result=%d\n", (int)(long)result); return result; }
static jboolean exception_check(JNIEnv *env) { (void)env; return pending; }
static void describe(JNIEnv *env) { (void)env; printf("vm ExceptionDescribe\n"); }
static void clear(JNIEnv *env) { (void)env; pending = 0; printf("vm ExceptionClear\n"); }
static void delete_local(JNIEnv *env, jobject object) { (void)env; (void)object; }
static struct JNINativeInterface table;
static JNIEnv fake = &table;
jint JNI_CreateJavaVM(JavaVM **vm, JNIEnv **env_out, void *arguments) {
    JavaVMInitArgs *init = arguments;
    fail_at = getenv("FAKEVM_FAIL") ? atoi(getenv("FAKEVM_FAIL")) : 0;
    for (int i = 0; i < init->nOptions; i++) printf("vm option %s\n", init->options[i].optionString);
    table.FindClass = find_class; table.GetStaticMethodID = static_method; table.NewStringUTF = new_string;
    table.CallStaticVoidMethod = call_static_void; table.ExceptionCheck = exception_check;
    table.GetMethodID = method; table.CallStaticObjectMethod = call_static_object; table.CallObjectMethod = call_object; table.NewObject = new_object;
    table.PushLocalFrame = push_frame; table.PopLocalFrame = pop_frame;
    table.ExceptionDescribe = describe; table.ExceptionClear = clear; table.DeleteLocalRef = delete_local;
    *vm = 0; *env_out = &fake;
    return JNI_OK;
}
C
gcc -shared -fPIC -I"$w/include" "$w/fakevm.c" -o "$w/libfakevm.so"
cat > "$w/driver.c" <<'C'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <jni.h>
extern char **environ;
static const char *names[] = {"GEN5W_PACKAGE", "GEN5W_ENGINE_JAR", "GEN5W_ENGINE_CACHE", "GEN5W_ADAPTER_JAR", "GEN5W_HOOK_LIBRARY", "GEN5W_PROBE", "GEN5W_EXTRA", 0};
static void dump(const char *who) {
    for (char **entry = environ; *entry; entry++)
        if (!strncmp(*entry, "GEN5W_", 6) || !strncmp(*entry, "LD_PRELOAD=", 11)) printf("%s environ %s\n", who, *entry);
}
static void run(const char *mode) {
    fflush(stdout);
    pid_t child = fork();
    if (!child) { execl("/w/driver", "driver", mode, (char *)0); _exit(127); }
    int status = 0;
    waitpid(child, &status, 0);
    printf("%s exit %d\n", mode, WIFEXITED(status) ? WEXITSTATUS(status) : 128);
}
static void start(char *out, size_t size) {
    char line[512] = {0}, *p;
    FILE *file = fopen("/proc/self/stat", "r");
    if (!file || !fgets(line, sizeof line, file)) exit(2);
    fclose(file);
    p = strrchr(line, ')') + 1;
    for (int field = 0; field < 19; field++) p = strchr(p + 1, ' ');
    snprintf(out, size, "%.*s", (int)strcspn(p + 1, " "), p + 1);
}
static void marker(void) {
    char line[256];
    FILE *file = fopen("/data/data/com.daudio.app.dipo/files/gen5w-portable-probe", "r");
    if (!file) { printf("marker absent\n"); return; }
    while (fgets(line, sizeof line, file)) printf("marker %s", line);
    fclose(file);
}
int main(int argc, char **argv) {
    const char *mode = argc > 1 ? argv[1] : "";
    char begun[32];
    if (!strcmp(mode, "hook-parent")) {
        JavaVM *vm = 0;
        JNIEnv *env = 0;
        JavaVMOption option = {"-Xstock", 0};
        JavaVMInitArgs init = {JNI_VERSION_1_6, 1, &option, JNI_FALSE};
        printf("vm status %d\n", (int)JNI_CreateJavaVM(&vm, &env, &init));
        for (int i = 0; names[i]; i++) { const char *value = getenv(names[i]); printf("parent getenv %s=%s\n", names[i], value ? value : "(null)"); }
        dump("parent");
        run("child");
    } else if (!strcmp(mode, "child")) {
        dump("child");
    } else if (!strcmp(mode, "launch-probe")) {
        setenv("GEN5W_PROBE", "1", 1); setenv("GEN5W_PACKAGE", "com.daudio.app.dipo", 1);
        setenv("LD_PRELOAD", "/w/libgen5whook.so", 1);
        execl("/w/driver", "com.daudio.app.dipo", "probe-parent", (char *)0);
        return 127;
    } else if (!strcmp(mode, "probe-parent")) {
        start(begun, sizeof begun);
        printf("parent pid=%d\nparent start=%s\n", (int)getpid(), begun);
        dump("parent");
        run("child");
        /* A descendant that re-acquires the probe environment must not replace
         * the live DiPO owner's marker. */
        setenv("GEN5W_PROBE", "1", 1); setenv("GEN5W_PACKAGE", "com.daudio.app.dipo", 1);
        setenv("LD_PRELOAD", "/w/libgen5whook.so", 1);
        run("child");
        unsetenv("GEN5W_PROBE"); unsetenv("GEN5W_PACKAGE"); unsetenv("LD_PRELOAD");
        marker();
    } else return 64;
    return 0;
}
C
gcc -O1 -I"$w/include" "$w/driver.c" -o "$w/driver" -L"$w" -lfakevm -Wl,-rpath,/w
unshare -rm bash -s "$w" <<'NS'
set -euo pipefail
w=$1 r=$1/root
mkdir "$r"
mount -t tmpfs none "$r"
mkdir -p "$r/usr" "$r/proc" "$r/dev" "$r/w" "$r/data/data/com.daudio.app.dipo/files"
mount --rbind /usr "$r/usr"; mount --rbind /proc "$r/proc"; mount --rbind /dev "$r/dev"; mount --bind "$w" "$r/w"
for name in lib lib32 lib64 libx32 bin sbin; do
    if [ -L "/$name" ]; then ln -s "$(readlink "/$name")" "$r/$name"
    elif [ -d "/$name" ]; then mkdir "$r/$name"; mount --rbind "/$name" "$r/$name"; fi
done
echo '== hook'
chroot "$r" /usr/bin/env -i PATH=/usr/bin LD_PRELOAD=/w/libgen5whook.so:/w/libother.so \
    GEN5W_PACKAGE=com.daudio.app.dipo GEN5W_ENGINE_JAR=/w/engine.jar GEN5W_ADAPTER_JAR=/w/adapter.jar \
    GEN5W_HOOK_LIBRARY=/w/libgen5whook.so GEN5W_ENGINE_CACHE=/w/engine-cache GEN5W_EXTRA=kept /w/driver hook-parent
[ -d "$w/engine-cache" ] && echo 'engine cache created'
echo '== no-cache'
chroot "$r" /usr/bin/env -i PATH=/usr/bin LD_PRELOAD=/w/libgen5whook.so:/w/libother.so \
    GEN5W_PACKAGE=com.daudio.app.dipo GEN5W_ENGINE_JAR=/w/engine.jar GEN5W_ADAPTER_JAR=/w/adapter.jar \
    GEN5W_HOOK_LIBRARY=/w/libgen5whook.so /w/driver hook-parent
# A cache directory open to others (or not a real directory) leaves the VM stock.
mkdir -m 0777 "$w/open-cache"; chmod 0777 "$w/open-cache"; ln -s /w/open-cache "$w/link-cache"; mkdir "$w/ro-cache"; chmod 0500 "$w/ro-cache"
for cache in open-cache link-cache ro-cache; do
    echo "== cache-$cache"
    chroot "$r" /usr/bin/env -i PATH=/usr/bin LD_PRELOAD=/w/libgen5whook.so:/w/libother.so \
        GEN5W_PACKAGE=com.daudio.app.dipo GEN5W_ENGINE_JAR=/w/engine.jar GEN5W_ADAPTER_JAR=/w/adapter.jar \
        GEN5W_HOOK_LIBRARY=/w/libgen5whook.so GEN5W_ENGINE_CACHE=/w/$cache /w/driver hook-parent
done
# Each JNI failure is followed by no further JNI call and is cleared.
for call in $(seq 1 24); do
    echo "== fail-$call"
    chroot "$r" /usr/bin/env -i PATH=/usr/bin LD_PRELOAD=/w/libgen5whook.so:/w/libother.so FAKEVM_FAIL=$call \
        GEN5W_PACKAGE=com.daudio.app.dipo GEN5W_ENGINE_JAR=/w/engine.jar GEN5W_ADAPTER_JAR=/w/adapter.jar \
        GEN5W_HOOK_LIBRARY=/w/libgen5whook.so GEN5W_ENGINE_CACHE=/w/engine-cache /w/driver hook-parent
done
echo '== overflow'
chroot "$r" /usr/bin/env -i PATH=/usr/bin LD_PRELOAD=/w/libgen5whook.so:/w/libother.so \
    GEN5W_PACKAGE=com.daudio.app.dipo GEN5W_ENGINE_JAR=/w/engine.jar GEN5W_ADAPTER_JAR=/w/adapter.jar \
    GEN5W_HOOK_LIBRARY=/w/libgen5whook.so GEN5W_A=a GEN5W_B=b GEN5W_C=c GEN5W_D=d GEN5W_E=e /w/driver hook-parent
echo '== long-input'
long=$(printf '%0600d' 0)
chroot "$r" /usr/bin/env -i PATH=/usr/bin LD_PRELOAD=/w/libgen5whook.so:/w/libother.so \
    GEN5W_PACKAGE=com.daudio.app.dipo GEN5W_ENGINE_JAR=/w/engine.jar GEN5W_ADAPTER_JAR=/w/adapter.jar \
    GEN5W_HOOK_LIBRARY=/w/libgen5whook.so GEN5W_EXTRA="$long" /w/driver hook-parent
echo '== probe1'
chroot "$r" /usr/bin/env -i PATH=/usr/bin /w/driver launch-probe
echo '== probe2'
chroot "$r" /usr/bin/env -i PATH=/usr/bin /w/driver launch-probe
NS
'''


def _ndk_jni_header():
    roots = [os.environ.get(name) for name in ("ANDROID_NDK_HOME", "ANDROID_NDK_ROOT")]
    local = os.environ.get("LOCALAPPDATA")
    if local: roots += sorted(glob.glob(os.path.join(local, "Android", "Sdk", "ndk", "*")), reverse=True)
    home = os.path.expanduser("~")
    roots += sorted(glob.glob(os.path.join(home, "Android", "Sdk", "ndk", "*")), reverse=True)
    for root in filter(None, roots):
        found = glob.glob(os.path.join(root, "toolchains", "llvm", "prebuilt", "*", "sysroot", "usr", "include", "jni.h"))
        if found: return Path(found[0])
    return None


def _wsl_path(path):
    text = str(Path(path).resolve()).replace("\\", "/")
    match = re.match(r"^([A-Za-z]):/(.*)$", text)
    return f"/mnt/{match.group(1).lower()}/{match.group(2)}" if match else text


def _run_native_harness(jni):
    shell = ["wsl.exe", "-e", "bash"] if os.name == "nt" else ["bash"]
    if not shutil.which(shell[0]): return None
    command = shell + ["-s", "--"] + ([_wsl_path(ROOT), _wsl_path(jni)] if os.name == "nt" else [str(ROOT), str(jni)])
    available = shell + ["-c", "command -v gcc && command -v unshare && unshare -rm true"]
    if subprocess.run(available, capture_output=True).returncode != 0: return None
    completed = subprocess.run(command, input=NATIVE_HARNESS.encode(), capture_output=True, timeout=180)
    output = completed.stdout.decode("utf-8", "replace").replace("\r", "")
    errors = completed.stderr.decode("utf-8", "replace").replace("\r", "")
    return completed.returncode, output, errors


def _section(output, name):
    lines, active = [], False
    for line in output.splitlines():
        if line.startswith("== "): active = line == "== " + name; continue
        if active: lines.append(line)
    return lines


class DalvikHostValidation(unittest.TestCase):
    def test_signature_rejection_and_reference_widening(self):
        javac = shutil.which("javac")
        java = shutil.which("java")
        if os.environ.get("JAVA_HOME"):
            suffix = ".exe" if os.name == "nt" else ""
            javac = str(Path(os.environ["JAVA_HOME"]) / "bin" / ("javac" + suffix))
            java = str(Path(os.environ["JAVA_HOME"]) / "bin" / ("java" + suffix))
        if not javac or not java: self.skipTest("JDK required for actual Java validation")
        with tempfile.TemporaryDirectory() as output:
            subprocess.run([javac, "--release", "8", "-Xlint:-options", "-d", output,
                str(ROOT / "tools/portable/dalvik/src/kr/gen5w/portable/Hook.java"),
                str(ROOT / "tests/portable_dalvik/HookValidationTest.java")], check=True, capture_output=True)
            completed = subprocess.run([java, "-cp", output, "HookValidationTest"], check=True, capture_output=True, text=True)
            self.assertIn("PASS host signature validation widening invalid handle", completed.stdout)


class HookProcessEnvironment(unittest.TestCase):
    """L1/L2: children must not inherit the engine or the probe, while the
    current process keeps every Bootstrap input that System.getenv reads."""

    @classmethod
    def setUpClass(cls):
        jni = _ndk_jni_header()
        if not jni: raise unittest.SkipTest("Android NDK jni.h required for the host hook harness")
        result = _run_native_harness(jni)
        if result is None: raise unittest.SkipTest("Linux gcc and unprivileged user/mount namespaces required")
        cls.returncode, cls.output, cls.errors = result

    def setUp(self):
        self.assertEqual(self.returncode, 0, self.output + self.errors)

    def test_bootstrap_receives_preserved_inputs(self):
        hook = _section(self.output, "hook")
        # The VM interposer still appends the engine and -Xint to caller options.
        # The engine is loaded by a process-local DexClassLoader under the boot
        # loader; the bootclasspath is never changed (V039 dex cache deps).
        self.assertFalse(any("-Xbootclasspath" in line for line in hook), hook)
        self.assertIn("engine cache created", hook)
        for line in ("vm option -Xstock", "vm option -Xint", "vm status 0",
                     "vm getSystemClassLoader", "vm getParent",
                     "vm DexClassLoader jar=/w/engine.jar cache=/w/engine-cache library=(null) parent=4",
                     "vm loadClass kr.gen5w.portable.Bootstrap",
                     "vm GetStaticMethodID start(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V",
                     "vm start library=/w/libgen5whook.so adapter=/w/adapter.jar owner=com.daudio.app.dipo",
                     "vm during-start environ LD_PRELOAD=/w/libother.so"):
            self.assertIn(line, hook)
        # Nothing reaches Java through the environment any more.
        self.assertEqual([line for line in hook if line.startswith("vm during-start environ GEN5W_")], [], hook)
        for name in ("PACKAGE", "ENGINE_JAR", "ENGINE_CACHE", "ADAPTER_JAR", "HOOK_LIBRARY", "EXTRA", "PROBE"):
            self.assertIn(f"parent getenv GEN5W_{name}=(null)", hook)

    def test_missing_engine_cache_leaves_vm_stock(self):
        lines = _section(self.output, "no-cache")
        self.assertIn("vm option -Xstock", lines)
        self.assertIn("vm status 0", lines)
        self.assertFalse(any("-Xint" in line or "-Xbootclasspath" in line or "DexClassLoader" in line or "vm start library=" in line for line in lines), lines)
        self.assertIn("child exit 0", lines)

    def test_unsafe_engine_cache_leaves_vm_stock(self):
        for name in ("cache-open-cache", "cache-link-cache", "cache-ro-cache"):
            lines = _section(self.output, name)
            self.assertIn("vm status 0", lines)
            self.assertFalse(any("-Xint" in line or "DexClassLoader" in line or "vm start library=" in line for line in lines), lines)

    def test_jni_failure_stops_and_clears(self):
        # A failure is injected at every JNI call in turn, until a run makes
        # fewer calls than the injection point (every call was covered).
        thrown = []
        for index in range(1, 25):
            lines = _section(self.output, f"fail-{index}")
            self.assertIn("vm status 0", lines)
            self.assertIn("child exit 0", lines)
            throw = [line for line in lines if line.startswith("vm throw at ")]
            if not throw: break
            thrown.append(throw[0].split()[-1])
            self.assertFalse(any(line.startswith("vm JNI-while-pending") for line in lines), lines)
            self.assertIn("vm ExceptionClear", lines)
            if not throw[0].endswith("CallStaticVoidMethod"):
                self.assertFalse(any(line.startswith("vm start library=") for line in lines), lines)
        else:
            self.fail("injection range does not cover every JNI call")
        for call in ("PushLocalFrame", "FindClass", "GetStaticMethodID", "GetMethodID", "CallStaticObjectMethod",
                     "CallObjectMethod", "NewStringUTF", "NewObject", "CallStaticVoidMethod"):
            self.assertIn(call, thrown)

    def test_inherited_environment_is_cleared_for_children(self):
        hook = _section(self.output, "hook")
        self.assertEqual([line for line in hook if " environ GEN5W_" in line], [], hook)
        # Only this library's preload entry is removed; another preload survives.
        self.assertIn("parent environ LD_PRELOAD=/w/libother.so", hook)
        self.assertIn("child environ LD_PRELOAD=/w/libother.so", hook)
        self.assertIn("child exit 0", hook)

    def test_input_overflow_declines_engine_and_scrubs_children(self):
        for name in ("overflow", "long-input"):
            lines = _section(self.output, name)
            self.assertIn("vm option -Xstock", lines)
            self.assertIn("vm status 0", lines)
            self.assertFalse(any("-Xint" in line or "-Xbootclasspath" in line or "vm start library=" in line for line in lines), lines)
            self.assertFalse(any(" environ GEN5W_" in line for line in lines), lines)
            self.assertIn("child environ LD_PRELOAD=/w/libother.so", lines)
            self.assertIn("child exit 0", lines)

    def test_probe_marker_names_the_wrapped_process_only(self):
        for name in ("probe1", "probe2"):
            probe = _section(self.output, name)
            fields = dict(line.split(" ", 1)[1].split("=", 1) for line in probe
                          if line.startswith(("parent pid=", "parent start=")))
            marker = dict(line[len("marker "):].split("=", 1) for line in probe if line.startswith("marker ") and "=" in line)
            self.assertEqual(marker.get("pid"), fields["pid"], probe)
            self.assertEqual(marker.get("start"), fields["start"], probe)
            self.assertEqual(marker.get("mode"), "no-hooks", probe)
            self.assertEqual([line for line in probe if line.startswith("parent environ")], [], probe)
            self.assertEqual(probe.count("child exit 0"), 2, probe)
        # A restarted DiPO (previous owner gone) replaces the marker.
        first = [line for line in _section(self.output, "probe1") if line.startswith("parent pid=")]
        second = [line for line in _section(self.output, "probe2") if line.startswith("parent pid=")]
        self.assertNotEqual(first, second)


class BootstrapContract(unittest.TestCase):
    """hook.c calls Bootstrap.start(String,String,String); Java never reads the
    environment that the native constructor has already cleared."""

    def test_bootstrap_takes_inputs_from_the_interposer(self):
        source = (ROOT / "tools/portable/dalvik/src/kr/gen5w/portable/Bootstrap.java").read_text(encoding="utf-8")
        self.assertNotIn("getenv", source)
        self.assertIn("public static synchronized void start(String library, String jar, String owner)", source)
        native = (ROOT / "tools/portable/dalvik/hook.c").read_text(encoding="utf-8")
        self.assertIn('"(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V"', native)


    def test_readiness_transaction_with_real_marker_io(self):
        if os.name == "nt" and not os.environ.get("PORTABLE_BOOTSTRAP_LINUX_JAVA"):
            self.skipTest("real /proc needs Linux Java or PORTABLE_BOOTSTRAP_LINUX_JAVA under WSL")
        if not shutil.which("javac"):
            self.skipTest("JDK required for production Bootstrap transaction regression")
        completed = subprocess.run(
            [os.sys.executable, str(ROOT / "tests/portable_bootstrap_transaction.py")],
            cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertEqual(completed.stdout.count("PASS bootstrap transaction "), 10,
                         completed.stdout + completed.stderr)


if __name__ == "__main__": unittest.main()
