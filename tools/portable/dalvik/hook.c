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

/* Probe mode never loads Java code or changes a Method. The marker is private
 * to DiPO and records when the library, rather than just its wrapper, loaded. */
__attribute__((constructor)) static void startup_probe(void) {
    const char *probe = getenv("GEN5W_PROBE"), *package = getenv("GEN5W_PACKAGE");
    if (!probe || strcmp(probe, "1") || !package || strcmp(package, "com.daudio.app.dipo")) return;
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now)) return;
    int fd = open("/data/data/com.daudio.app.dipo/files/gen5w-portable-probe", O_WRONLY|O_CREAT|O_TRUNC|O_NOFOLLOW, 0600);
    if (fd < 0) return;
    char boot[48] = {0}, report[240];
    int bootfd = open("/proc/sys/kernel/random/boot_id", O_RDONLY|O_NOFOLLOW);
    if (bootfd < 0) { close(fd); return; }
    int length = read(bootfd, boot, sizeof(boot)-1);
    close(bootfd);
    if (length <= 0) { close(fd); return; }
    if (boot[length-1] == '\n') boot[length-1] = 0;
    int count = snprintf(report, sizeof(report), "pid=%d\nmonotonic=%ld.%09ld\nmode=no-hooks\nboot_id=%s\n", (int)getpid(), (long)now.tv_sec, (long)now.tv_nsec, boot);
    if (count > 0 && (size_t)count < sizeof(report)) { (void)write(fd, report, (size_t)count); (void)fsync(fd); }
    close(fd);
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

/* Process wrapper opt-in only. Preserve every caller VM option and append the
 * engine to an existing bootclasspath suffix rather than replacing it. */
JNIEXPORT jint JNICALL JNI_CreateJavaVM(JavaVM **vm, JNIEnv **env_out, void *arguments) {
    jint (*real_create)(JavaVM **, JNIEnv **, void *) = 0;
    *(void **)(&real_create) = dlsym(RTLD_NEXT, "JNI_CreateJavaVM");
    if (!real_create) {
        void *lib = dlopen("libdvm.so", RTLD_NOW);
        if (lib) *(void **)(&real_create) = dlsym(lib, "JNI_CreateJavaVM");
    }
    if (!real_create || real_create == JNI_CreateJavaVM) return JNI_ERR;
    const char *engine = getenv("GEN5W_ENGINE_JAR");
    if (!engine || engine[0] != '/') return real_create(vm, env_out, arguments);
    JavaVMInitArgs copy = *(JavaVMInitArgs *)arguments;
    if (copy.nOptions < 0 || copy.nOptions > 4096) return JNI_ERR;
    JavaVMOption *options = calloc((size_t)copy.nOptions + 2, sizeof(*options));
    if (!options) return JNI_ENOMEM;
    memcpy(options, copy.options, (size_t)copy.nOptions * sizeof(*options));
    const char prefix[] = "-Xbootclasspath/a:";
    int previous = -1;
    for (int i = 0; i < copy.nOptions; i++)
        if (options[i].optionString && !strncmp(options[i].optionString, prefix, sizeof(prefix)-1)) previous = i;
    const char *suffix = previous < 0 ? "" : options[previous].optionString + sizeof(prefix)-1;
    size_t capacity = sizeof(prefix) + strlen(suffix) + strlen(engine) + 2;
    char *classpath = malloc(capacity);
    if (!classpath) { free(options); return JNI_ENOMEM; }
    snprintf(classpath, capacity, "%s%s%s%s", prefix, suffix, *suffix ? ":" : "", engine);
    if (previous < 0) options[copy.nOptions++].optionString = classpath;
    else options[previous].optionString = classpath;
    options[copy.nOptions++].optionString = "-Xint";
    copy.options = options;
    jint status = real_create(vm, env_out, &copy);
    free(classpath); free(options);
    if (status != JNI_OK) return status;
    JNIEnv *env = (JNIEnv *)*env_out;
    jclass bootstrap = (*env)->FindClass(env, "kr/gen5w/portable/Bootstrap");
    if (bootstrap) {
        jmethodID start = (*env)->GetStaticMethodID(env, bootstrap, "start", "()V");
        if (start) (*env)->CallStaticVoidMethod(env, bootstrap, start);
    }
    if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionDescribe(env);
        (*env)->ExceptionClear(env);
    }
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
