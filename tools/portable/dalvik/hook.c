/* Independently authored bounded Dalvik 32-bit hook engine.
 * ABI facts: AOSP android-4.4.4_r2 vm/oo/Object.h and vm/Thread.h;
 * V039 dvmSetNativeFunc disassembly: insns=0x20, nativeFunc=0x28.
 * Runtime validation and exact instruction fingerprint are mandatory.
 */
#include <jni.h>
#include <dlfcn.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <errno.h>
#include <sys/stat.h>

extern char **environ;

/* Wrapper inputs stay with the wrapped process only. The constructor copies
 * every inherited GEN5W_* entry, then removes them and this library's own
 * LD_PRELOAD entry from the environment before any other code runs, so
 * children (dexopt, am/pm, sh, ...) neither start the engine again nor rewrite
 * the probe marker. The preserved copies are read only by this library: the VM
 * interposer below hands GEN5W_HOOK_LIBRARY, GEN5W_ADAPTER_JAR and
 * GEN5W_PACKAGE to Bootstrap.start as arguments, so no Java code reads them from
 * the environment. Nothing is removed unless this library is listed in
 * LD_PRELOAD (the wrapper case); a capacity overflow declines the engine and still removes the inherited
 * inputs so a child cannot start it again. */
#define INPUT_SLOTS 8
#define INPUT_BYTES 512
static char inputs[INPUT_SLOTS][INPUT_BYTES];
static int input_count;
static int inputs_blocked;
static char kept_preload[1024];

static const char *entry_value(const char *entry, const char *name, size_t length) {
    return !strncmp(entry, name, length) && entry[length] == '=' ? entry + length + 1 : 0;
}
static const char *environment_value(const char *name) {
    size_t length = strlen(name);
    if (!environ) return 0;
    for (char **entry = environ; *entry; entry++) {
        const char *value = entry_value(*entry, name, length);
        if (value) return value;
    }
    return 0;
}
static const char *input_value(const char *name) {
    if (!name) return 0;
    if (!strncmp(name, "GEN5W_", 6)) {
        if (inputs_blocked) return 0;
        size_t length = strlen(name);
        for (int i = 0; i < input_count; i++) {
            const char *value = entry_value(inputs[i], name, length);
            if (value) return value;
        }
    }
    return environment_value(name);
}

static int own_preload(const char *item, size_t length) {
    static const char own[] = "libgen5whook.so";
    size_t size = sizeof(own) - 1;
    return length >= size && !memcmp(item + length - size, own, size) &&
           (length == size || item[length - size - 1] == '/');
}
/* 1 when this library is preloaded; other entries are kept in order. */
static int split_preload(const char *preload) {
    size_t used_bytes = 0;
    int listed = 0, overflow = 0;
    kept_preload[0] = 0;
    for (const char *p = preload; *p;) {
        size_t length = strcspn(p, ": ");
        if (length && own_preload(p, length)) listed = 1;
        else if (length && used_bytes + length + 2 <= sizeof(kept_preload)) {
            if (used_bytes) kept_preload[used_bytes++] = ':';
            memcpy(kept_preload + used_bytes, p, length);
            used_bytes += length;
            kept_preload[used_bytes] = 0;
        } else if (length) overflow = 1;
        p += length;
        if (*p) p++;
    }
    if (overflow) kept_preload[0] = 0; /* never pass this library on to a child */
    return listed;
}
static void scrub_inherited(void) {
    const char *preload = environment_value("LD_PRELOAD");
    if (!preload || split_preload(preload) != 1) return;
    int count = 0;
    for (char **entry = environ; *entry; entry++) {
        if (strncmp(*entry, "GEN5W_", 6)) continue;
        size_t length = strlen(*entry);
        if (count == INPUT_SLOTS || length >= INPUT_BYTES || !strchr(*entry, '=')) { inputs_blocked = 1; break; }
        memcpy(inputs[count++], *entry, length + 1);
    }
    input_count = inputs_blocked ? 0 : count;
    /* Remove all matching entries even on overflow, without allocating a name
     * buffer proportional to untrusted input. Constructor runs before threads.
     * Shift pointers only; the inherited string storage remains owned by libc. */
    for (char **entry = environ; *entry;) {
        if (!strncmp(*entry, "GEN5W_", 6)) {
            for (char **next = entry; *next; next++) *next = *(next + 1);
        } else entry++;
    }
    if (kept_preload[0]) setenv("LD_PRELOAD", kept_preload, 1);
    else unsetenv("LD_PRELOAD");
}

#define PROBE_MARKER "/data/data/com.daudio.app.dipo/files/gen5w-portable-probe"
static int read_small(const char *path, char *buffer, size_t size) {
    int fd = open(path, O_RDONLY|O_NOFOLLOW|O_CLOEXEC);
    if (fd < 0) return -1;
    size_t total = 0;
    ssize_t count;
    while (total + 1 < size && (count = read(fd, buffer + total, size - 1 - total)) > 0) total += (size_t)count;
    close(fd);
    buffer[total] = 0;
    return (int)total;
}
/* Field 22 (starttime) of /proc/PID/stat: PID plus start time names one process. */
static int process_start(long pid, char *out, size_t size) {
    char path[48], stat[512];
    snprintf(path, sizeof(path), "/proc/%ld/stat", pid);
    if (read_small(path, stat, sizeof(stat)) <= 0) return -1;
    char *p = strrchr(stat, ')');
    if (!p) return -1;
    p++;
    for (int field = 0; field < 20; field++) {
        while (*p == ' ') p++;
        size_t length = strcspn(p, " \n");
        if (!length) return -1;
        if (field == 19) {
            if (length >= size || strspn(p, "0123456789") < length) return -1;
            memcpy(out, p, length);
            out[length] = 0;
            return 0;
        }
        p += length;
    }
    return -1;
}
static int runs_dipo(long pid) {
    static const char name[] = "com.daudio.app.dipo";
    char path[48], line[64];
    snprintf(path, sizeof(path), "/proc/%ld/cmdline", pid);
    int length = read_small(path, line, sizeof(line));
    return length >= (int)sizeof(name) - 1 && !memcmp(line, name, sizeof(name) - 1) &&
           (length == (int)sizeof(name) - 1 || !line[sizeof(name) - 1]);
}
/* A marker written in this boot by a different, still-running DiPO process
 * belongs to that process (this one would be a descendant that regained the
 * probe environment). A dead or reused owner may be replaced by a restart. */
static int marker_owned_by_live_dipo(const char *boot) {
    char text[320], actual[32], *line, *save = 0;
    const char *start = 0, *owner_boot = 0;
    long pid = 0;
    if (read_small(PROBE_MARKER, text, sizeof(text)) <= 0) return 0;
    for (line = strtok_r(text, "\n", &save); line; line = strtok_r(0, "\n", &save)) {
        if (!strncmp(line, "pid=", 4)) pid = strtol(line + 4, 0, 10);
        else if (!strncmp(line, "start=", 6)) start = line + 6;
        else if (!strncmp(line, "boot_id=", 8)) owner_boot = line + 8;
    }
    if (pid <= 1 || pid == (long)getpid() || !owner_boot || strcmp(owner_boot, boot)) return 0;
    if (start && (process_start(pid, actual, sizeof(actual)) || strcmp(actual, start))) return 0;
    return runs_dipo(pid);
}
/* Probe mode never loads Java code or changes a Method. The marker is private
 * to DiPO and records when the library, rather than just its wrapper, loaded. */
static void write_probe_marker(void) {
    struct timespec now;
    char boot[48], start[32], report[320], temporary[sizeof(PROBE_MARKER) + 24];
    if (clock_gettime(CLOCK_MONOTONIC, &now)) return;
    int length = read_small("/proc/sys/kernel/random/boot_id", boot, sizeof(boot));
    if (length <= 0) return;
    if (boot[length-1] == '\n') boot[length-1] = 0;
    if (process_start(getpid(), start, sizeof(start)) || marker_owned_by_live_dipo(boot)) return;
    int count = snprintf(report, sizeof(report), "pid=%d\nstart=%s\nmonotonic=%ld.%09ld\nmode=no-hooks\nboot_id=%s\n",
                         (int)getpid(), start, (long)now.tv_sec, (long)now.tv_nsec, boot);
    if (count <= 0 || (size_t)count >= sizeof(report)) return;
    snprintf(temporary, sizeof(temporary), "%s.%d.tmp", PROBE_MARKER, (int)getpid());
    unlink(temporary);
    int fd = open(temporary, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC, 0600);
    if (fd < 0) return;
    int written = write(fd, report, (size_t)count) == count && !fsync(fd);
    close(fd);
    if (!written || rename(temporary, PROBE_MARKER)) unlink(temporary);
}
__attribute__((constructor)) static void startup(void) {
    const char *probe = environment_value("GEN5W_PROBE"), *package = environment_value("GEN5W_PACKAGE");
    int probe_role = probe && !strcmp(probe, "1") && package && !strcmp(package, "com.daudio.app.dipo");
    scrub_inherited();
    if (probe_role) write_probe_marker();
}

typedef union { int32_t i; int64_t j; float f; double d; void *l; } Value;
typedef struct Method Method;
typedef void (*Bridge)(const uint32_t *, Value *, const Method *, void *);
struct Method {
    void *owner; uint32_t access; uint16_t index, registers, outs, ins;
    const char *name; void *dex; uint32_t proto; const char *shorty;
    const uint16_t *code; int32_t jni; Bridge native;
    uint8_t fast, no_ref, trace, padding; void *gc_map; uint8_t profile, tail[3];
};
_Static_assert(sizeof(Method) == 56, "32-bit Dalvik Method required");
typedef struct { Method original; Method *target, *replacement; int active; jobject target_ref, replacement_ref; } Entry;
static Entry entries[64];
static int used;
static void *(*thread_self)(void);
static void (*call_a)(void *, const Method *, void *, int, Value *, const jvalue *);
static void *(*invoke)(void *, const Method *, void *, void *, void *, int);
static void (*set_native)(Method *, Bridge, const uint16_t *);
static void (*suspend_all)(int);
static void (*resume_all)(int);
static void (*lock_object)(void *, void *);
static int (*unlock_object)(void *, void *);
static int ready;

/* Load the engine through a process-local DexClassLoader. The bootclasspath is
 * never changed: V039 libdvm records the exact bootclasspath in every cached
 * dex ("deps"); any extra entry makes each cache this process opens stale, and
 * a stale cache is truncated and rebuilt in place. On the vehicle that
 * truncated the shared com.broadcom.bt dex cache under every other app (mass
 * SIGBUS in dexFindClass, 2026-11-13). The optimized engine DEX goes to an
 * app-private directory with deps for the stock bootclasspath. */
/* The optimized engine DEX directory must be a real directory owned by this
 * uid and closed to everyone else; checked (and created) before the VM starts
 * so that any problem leaves the VM completely stock, without even -Xint. */
static int cache_ready(const char *cache) {
    struct stat info;
    if (!cache || cache[0] != '/' || strstr(cache, "/..") || strlen(cache) > 400) return 0;
    if (mkdir(cache, 0700) != 0 && errno != EEXIST) return 0;
    if (lstat(cache, &info) != 0 || !S_ISDIR(info.st_mode)) return 0;
    return info.st_uid == getuid() && (info.st_mode & 0777) == 0700;
}
/* Every JNI call is followed by a failure check: nothing else is called while
 * an exception is pending (the caller describes and clears it). Local
 * references live in one frame; only the Bootstrap class survives it. */
#define NEED(value) do { if ((*env)->ExceptionCheck(env) || !(value)) goto done; } while (0)
static jclass load_engine(JNIEnv *env, const char *engine, const char *cache) {
    jobject result = 0;
    if ((*env)->PushLocalFrame(env, 16) != JNI_OK) return 0;
    jclass loader_type = (*env)->FindClass(env, "java/lang/ClassLoader"); NEED(loader_type);
    jclass dex_type = (*env)->FindClass(env, "dalvik/system/DexClassLoader"); NEED(dex_type);
    jmethodID system = (*env)->GetStaticMethodID(env, loader_type, "getSystemClassLoader", "()Ljava/lang/ClassLoader;"); NEED(system);
    jmethodID up = (*env)->GetMethodID(env, loader_type, "getParent", "()Ljava/lang/ClassLoader;"); NEED(up);
    jmethodID load = (*env)->GetMethodID(env, loader_type, "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;"); NEED(load);
    jmethodID create = (*env)->GetMethodID(env, dex_type, "<init>",
        "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/ClassLoader;)V"); NEED(create);
    /* Parent is the boot loader: engine classes never resolve from a copy on
     * the application classpath, and nothing joins the bootclasspath. */
    jobject system_loader = (*env)->CallStaticObjectMethod(env, loader_type, system); NEED(system_loader);
    jobject boot_loader = (*env)->CallObjectMethod(env, system_loader, up); NEED(boot_loader);
    jstring jar = (*env)->NewStringUTF(env, engine); NEED(jar);
    jstring dir = (*env)->NewStringUTF(env, cache); NEED(dir);
    jstring name = (*env)->NewStringUTF(env, "kr.gen5w.portable.Bootstrap"); NEED(name);
    jobject loader = (*env)->NewObject(env, dex_type, create, jar, dir, (jstring)0, boot_loader); NEED(loader);
    result = (*env)->CallObjectMethod(env, loader, load, name);
    if ((*env)->ExceptionCheck(env)) result = 0;
done:
    /* PopLocalFrame is allowed with a pending exception. */
    return (jclass)(*env)->PopLocalFrame(env, result);
}
#undef NEED

/* Bootclasspath guard (2026-11-19 vehicle: a stale engine build appended
 * engine.jar, the live list grew to 17, and the shared com.broadcom.bt cache was
 * rebuilt under every app). Expected = entries of the inherited BOOTCLASSPATH,
 * live = dvm's own count (the same walk its deps check uses). Any difference
 * ends this process before a single application dex is opened, so a shared
 * cache can never be rewritten from here: only this app fails to start. */
static int boot_entries_expected(void) {
    const char *path = environment_value("BOOTCLASSPATH");
    int count = 0, inside = 0;
    if (!path) return -1;
    for (const char *p = path; *p; p++) {
        if (*p == ':') inside = 0;
        else if (!inside) { inside = 1; count++; }
    }
    return count;
}
static int boot_entries_live(JNIEnv *env) {
    jint count = -1;
    if ((*env)->ExceptionCheck(env)) return -1;
    jclass type = (*env)->FindClass(env, "java/lang/VMClassLoader");
    if (!type || (*env)->ExceptionCheck(env)) { (*env)->ExceptionClear(env); return -1; }
    jmethodID size = (*env)->GetStaticMethodID(env, type, "getBootClassPathSize", "()I");
    if (size && !(*env)->ExceptionCheck(env)) count = (*env)->CallStaticIntMethod(env, type, size);
    if ((*env)->ExceptionCheck(env)) { (*env)->ExceptionClear(env); count = -1; }
    (*env)->DeleteLocalRef(env, type);
    return count;
}
static void bootpath_abort(const char *stage, int expected, int live) {
    const char *package = input_value("GEN5W_PACKAGE");
    char path[192], text[128];
    if (package && strlen(package) < 96 && !strchr(package, '/') && package[0] != '.') {
        snprintf(path, sizeof(path), "/data/data/%s/files/gen5w-portable-bootpath-guard", package);
        int fd = open(path, O_WRONLY|O_CREAT|O_TRUNC|O_NOFOLLOW|O_CLOEXEC, 0600);
        if (fd >= 0) {
            int count = snprintf(text, sizeof(text), "stage=%s\nexpected=%d\nlive=%d\n", stage, expected, live);
            if (count > 0 && (size_t)count < sizeof(text)) { ssize_t ignored = write(fd, text, (size_t)count); (void)ignored; }
            close(fd);
        }
    }
    _exit(78);
}
/* Process wrapper opt-in only. Preserve every caller VM option and its
 * bootclasspath unchanged; only force the interpreter. */
JNIEXPORT jint JNICALL JNI_CreateJavaVM(JavaVM **vm, JNIEnv **env_out, void *arguments) {
    jint (*real_create)(JavaVM **, JNIEnv **, void *) = 0;
    *(void **)(&real_create) = dlsym(RTLD_NEXT, "JNI_CreateJavaVM");
    if (!real_create) {
        void *lib = dlopen("libdvm.so", RTLD_NOW);
        if (lib) *(void **)(&real_create) = dlsym(lib, "JNI_CreateJavaVM");
    }
    if (!real_create || real_create == JNI_CreateJavaVM) return JNI_ERR;
    const char *engine = input_value("GEN5W_ENGINE_JAR");
    const char *cache = input_value("GEN5W_ENGINE_CACHE");
    if (!engine || engine[0] != '/' || !cache_ready(cache)) return real_create(vm, env_out, arguments);
    JavaVMInitArgs copy = *(JavaVMInitArgs *)arguments;
    if (copy.nOptions < 0 || copy.nOptions > 4096) return JNI_ERR;
    JavaVMOption *options = calloc((size_t)copy.nOptions + 1, sizeof(*options));
    if (!options) return JNI_ENOMEM;
    memcpy(options, copy.options, (size_t)copy.nOptions * sizeof(*options));
    options[copy.nOptions++].optionString = "-Xint";
    copy.options = options;
    jint status = real_create(vm, env_out, &copy);
    free(options);
    if (status != JNI_OK) return status;
    JNIEnv *env = (JNIEnv *)*env_out;
    int expected = boot_entries_expected(), live = boot_entries_live(env);
    if (expected <= 0 || live != expected) bootpath_abort("vm", expected, live);
    jclass bootstrap = load_engine(env, engine, cache);
    if (bootstrap && !(*env)->ExceptionCheck(env)) {
        jmethodID start = (*env)->GetStaticMethodID(env, bootstrap, "start",
            "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V");
        if (start && !(*env)->ExceptionCheck(env)) {
            const char *values[3] = {input_value("GEN5W_HOOK_LIBRARY"), input_value("GEN5W_ADAPTER_JAR"), input_value("GEN5W_PACKAGE")};
            jstring text[3] = {0, 0, 0};
            for (int i = 0; i < 3 && !(*env)->ExceptionCheck(env); i++)
                if (values[i]) text[i] = (*env)->NewStringUTF(env, values[i]);
            /* Bootstrap rejects a missing input itself and the VM stays stock. */
            if (!(*env)->ExceptionCheck(env)) (*env)->CallStaticVoidMethod(env, bootstrap, start, text[0], text[1], text[2]);
            for (int i = 0; i < 3; i++) if (text[i]) (*env)->DeleteLocalRef(env, text[i]);
        }
    }
    if (bootstrap) (*env)->DeleteLocalRef(env, bootstrap);
    if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionDescribe(env);
        (*env)->ExceptionClear(env);
    }
    live = boot_entries_live(env);
    if (live != expected) bootpath_abort("engine", expected, live);
    return status;
}

static void fail(JNIEnv *env, const char *type, const char *message) {
    jclass cls = (*env)->FindClass(env, type);
    if (cls) (*env)->ThrowNew(env, cls, message);
}
static void original_call(const uint32_t *args, Value *result, const Method *method, void *self) {
    (void)method; (void)self;
    /* Handles are checked by Hook.original before entering this internal native. */
    unsigned id = args[0];
    if (id >= (unsigned)used) { result->l = 0; return; }
    result->l = invoke((void *)(uintptr_t)args[3], &entries[id].original,
                       (void *)(uintptr_t)args[4], (void *)(uintptr_t)args[1],
                       (void *)(uintptr_t)args[2], 1);
}
static void dispatch(const uint32_t *raw, Value *result, const Method *method, void *self) {
    Entry *entry = 0;
    for (int i = used - 1; i >= 0; i--) if (entries[i].target == method && entries[i].active) { entry = &entries[i]; break; }
    if (!entry) for (int i = used - 1; i >= 0; i--) if (entries[i].target == method) { entry = &entries[i]; break; }
    if (!entry) { memset(result, 0, sizeof(*result)); return; } /* Cannot occur for a published bridge. */
    jvalue args[64];
    unsigned n = 0, word = 0;
    if (!(entry->original.access & 8)) args[n++].l = (jobject)(uintptr_t)raw[word++];
    for (const char *p = entry->original.shorty + 1; *p; p++, n++) {
        memset(&args[n], 0, sizeof(args[n]));
        if (*p == 'J' || *p == 'D') { memcpy(&args[n], raw + word, 8); word += 2; }
        else { memcpy(&args[n], raw + word, 4); word++; }
    }
    args[n].i = (jint)(entry - entries);
    Value returned;
    memset(&returned, 0, sizeof(returned));
    /* A custom native bridge bypasses dvmCallJNIMethod's monitor wrapper. */
    void *monitor = 0;
    if (entry->original.access & (0x20u | 0x20000u)) {
        monitor = (entry->original.access & 8) ? entry->original.owner : (void *)args[0].l;
        lock_object(self, monitor);
    }
    if (entry->active) call_a(self, entry->replacement, 0, 0, &returned, args);
    else {
        int receiver = !(entry->original.access & 8);
        call_a(self, &entry->original, receiver ? args[0].l : 0, 0, &returned, args + receiver);
    }
    if (monitor) unlock_object(self, monitor);
    *result = returned;
}

JNIEXPORT void JNICALL Java_kr_gen5w_portable_Hook_installNative(JNIEnv *env, jclass cls,
        jobject target_ref, jobject replacement_ref, jint handle) {
    (void)cls;
    if (!ready) { fail(env, "java/lang/UnsupportedOperationException", "unverified Dalvik ABI"); return; }
    Method *target = (Method *)(*env)->FromReflectedMethod(env, target_ref);
    Method *replacement = (Method *)(*env)->FromReflectedMethod(env, replacement_ref);
    if ((*env)->ExceptionCheck(env)) return;
    for (int i = 0; i < used; i++) if (entries[i].target == target && entries[i].active) {
        fail(env, "java/lang/IllegalStateException", "method already hooked"); return;
    }
    if (handle != used || used >= 64 || !target || !replacement || !target->shorty ||
        strlen(target->shorty) > 60 || target->ins > 120 || (target->access & 0x500) ||
        !(replacement->access & 8) || target->shorty[0] != replacement->shorty[0]) {
        fail(env, "java/lang/IllegalArgumentException", "unsupported method shape or hook capacity"); return;
    }
    /* JNI method-name/modifier checks independently validate critical layout fields. */
    jclass method_class = (*env)->GetObjectClass(env, target_ref);
    jmethodID get_name = (*env)->GetMethodID(env, method_class, "getName", "()Ljava/lang/String;");
    jmethodID get_modifiers = (*env)->GetMethodID(env, method_class, "getModifiers", "()I");
    jstring name = (jstring)(*env)->CallObjectMethod(env, target_ref, get_name);
    jint modifiers = (*env)->CallIntMethod(env, target_ref, get_modifiers);
    if ((*env)->ExceptionCheck(env)) return;
    const char *utf = (*env)->GetStringUTFChars(env, name, 0);
    int matches = utf && target->name && !strcmp(utf, target->name) &&
                  (target->access & 0x51f) == ((uint32_t)modifiers & 0x51f);
    if (utf) (*env)->ReleaseStringUTFChars(env, name, utf);
    if (!matches) { fail(env, "java/lang/UnsupportedOperationException", "Method layout mismatch"); return; }
    Entry *entry = &entries[used];
    entry->target_ref = (*env)->NewGlobalRef(env, target_ref);
    entry->replacement_ref = (*env)->NewGlobalRef(env, replacement_ref);
    if (!entry->target_ref || !entry->replacement_ref) {
        if (entry->target_ref) (*env)->DeleteGlobalRef(env, entry->target_ref);
        if (entry->replacement_ref) (*env)->DeleteGlobalRef(env, entry->replacement_ref);
        return;
    }
    entry->original = *target; entry->target = target; entry->replacement = replacement;
    entry->active = 1;
    /* Install only before application work starts, with interpreter (-Xint).
     * Stop other threads while publishing both access flags and bridge pointer. */
    suspend_all(2); /* AOSP SUSPEND_FOR_DEBUG */
    used++;
    target->registers = target->ins; target->outs = 0;
    set_native(target, dispatch, 0);
    __sync_synchronize();
    target->access |= 0x100;
    if (target->access & 0x20000) target->access |= 0x20;
    resume_all(2);
}

JNIEXPORT void JNICALL Java_kr_gen5w_portable_Hook_uninstallNative(JNIEnv *env, jclass cls, jint id) {
    (void)cls;
    if (id < 0 || id >= used || !entries[id].active) {
        fail(env, "java/lang/IllegalArgumentException", "inactive hook handle"); return;
    }
    Entry *entry = &entries[id];
    if (entry->target->native != dispatch || !(entry->target->access & 0x100)) {
        fail(env, "java/lang/IllegalStateException", "method ownership changed"); return;
    }
    suspend_all(2);
    *entry->target = entry->original;
    entry->active = 0;
    __sync_synchronize();
    /* Keep target mapping for any already active dispatch frame. */
    resume_all(2);
}

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
    (void)reserved;
    JNIEnv *env = 0;
    if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;
    void *lib = dlopen("libdvm.so", RTLD_NOW);
    if (!lib) return JNI_ERR;
#define RESOLVE(slot, symbol) do { *(void **)(&slot) = dlsym(lib, symbol); if (!slot) return JNI_ERR; } while (0)
    RESOLVE(lock_object, "dvmLockObject");
    RESOLVE(unlock_object, "dvmUnlockObject");
    RESOLVE(thread_self, "_Z13dvmThreadSelfv");
    RESOLVE(call_a, "_Z14dvmCallMethodAP6ThreadPK6MethodP6ObjectbP6JValuePK6jvalue");
    RESOLVE(invoke, "_Z15dvmInvokeMethodP6ObjectPK6MethodP11ArrayObjectS5_P11ClassObjectb");
    RESOLVE(set_native, "_Z16dvmSetNativeFuncP6MethodPFvPKjP6JValuePKS_P6ThreadEPKt");
    RESOLVE(suspend_all, "_Z20dvmSuspendAllThreads12SuspendCause");
    RESOLVE(resume_all, "_Z19dvmResumeAllThreads12SuspendCause");
    const unsigned char expected[] = {0x12,0xb1,0x02,0x62,0xbf,0xf3,0x5f,0x8f,0x81,0x62,0x70,0x47};
    if (memcmp((void *)((uintptr_t)set_native & ~(uintptr_t)1), expected, sizeof(expected))) return JNI_ERR;
    jclass hook = (*env)->FindClass(env, "kr/gen5w/portable/Hook");
    if (!hook) return JNI_ERR;
    Method *original = (Method *)(*env)->GetStaticMethodID(env, hook, "originalNative",
        "(I[Ljava/lang/Class;Ljava/lang/Class;Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;");
    if (!original || (*env)->ExceptionCheck(env)) return JNI_ERR;
    if (strcmp(original->name, "originalNative") || strcmp(original->shorty, "LILLLL")) return JNI_ERR;
    set_native(original, original_call, 0);
    ready = 1;
    return JNI_VERSION_1_6;
}
