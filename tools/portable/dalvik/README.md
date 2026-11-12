# Opt-in process-local Dalvik adapter engine

This independently authored engine adds no OEM bytecode to source or output.
It supports the verified 32-bit V039 Dalvik ABI; other ABIs fail closed. Symbols
alone never enable support. The native engine checks the reviewed Thumb instruction
fingerprint of `dvmSetNativeFunc`, plus live reflected Method name, modifiers and
shorty. Candidate runtime runs an authored dispatch self-test on the local VM before enabling wrappers; the private source libdvm SHA256 is build provenance only.

ABI facts were checked against actual V039 disassembly and the primary AOSP
[Method declaration](https://android.googlesource.com/platform/dalvik/+/android-4.4.4_r2/vm/oo/Object.h)
and [thread suspension definitions](https://android.googlesource.com/platform/dalvik/+/android-4.4.4_r2/vm/Thread.h).
No hmg-api engine code was copied.

## Build

`python tools/portable/dalvik/build.py --java-home JDK --ndk NDK --d8 D8_JAR --stock-system PRIVATE_SYSTEM --android-jar ANDROID_JAR --output PRIVATE_OUTPUT`

NDK r27 no longer supplies API19 CRT objects, so the authored ARMv7 library uses
`-nostdlib` and links against the user's private API19 libc/libdl interfaces.
Only authored code is emitted. Compilation stubs under `com/**` are excluded
from adapter.jar. Outputs engine.jar, adapter.jar, libgen5whook.so, abi.sha256
(private libdvm digest), engine.sha256, and separate authored VM test jars.

## Loading and dispatch

The wrapper sets `GEN5W_ENGINE_JAR`, `GEN5W_HOOK_LIBRARY`, `GEN5W_ADAPTER_JAR`,
`GEN5W_PACKAGE`, and LD_PRELOAD for one stopped application process. The
JNI_CreateJavaVM interposer preserves existing VM options and bootclasspath
suffix, appends engine.jar, and forces `-Xint`. Interpreter mode is required:
existing JIT traces cannot safely be treated as patched dispatch. This costs
application execution performance and needs vehicle measurement.

After VM creation Bootstrap hooks Application.attach. It first calls the saved
original, checks the exact application package, and creates DexClassLoader with
the application class loader as parent and an application-private optimized DEX
directory. Thus adapter references resolve the original application's OEM
classes while every loader shares the boot-loaded Hook class. Discovery errors
are reported; adapter group installation must roll back before returning failure.

`Hook.install(target,replacement)` accepts a static replacement whose parameters
are the original receiver (for instance targets), original arguments, and an int
handle. Reference parameters may widen to Object; primitive and return types
must match. `Hook.original(handle,receiver,args)` invokes a saved Method copy,
unwraps InvocationTargetException and preserves the original throwable identity.
At most 64 installations occur per process lifetime. Metadata and global refs
remain pinned until process exit to let existing frames finish safely after
uninstall. Installation/uninstall suspend other Dalvik threads. Installation is
intended during bootstrap before application work starts.

## Verification evidence and limits

Actual private V039 ARM Dalvik under qemu-arm passed instance/static replacement,
saved-original dispatch, wide long, float/double/boolean, object identity with GC,
original exception identity, synchronized target, duplicate rejection,
uninstall/reinstall and uninstall while a replacement frame is running. Separate
VM fixtures passed DexClassLoader identity and the full JNI interposer ->
Application.attach -> app-local adapter loading sequence. Host Java tests verify
signature rejection and safe reference widening; they do not substitute for VM
tests. Test fixtures use authored classes; BootstrapVmTest allocates a synthetic
ContextImpl/LoadedApk exclusively inside the private PC VM.

The PC VM cannot prove Binder registration, real DiPO startup timing, transport
behavior or vehicle reliability. The complete portable package enables runtime only after its local VM probe;
no vehicle/USB installation has been activated during PC development. Actual stock adapter discovery is a
separate check from executing a real Android application lifecycle.

## Reproducible private PC suite

Run `PORTABLE_VM_RUNNER=PRIVATE_RUNNER PORTABLE_VM_ROOT=PRIVATE_ROOT bash tests/portable_vm.sh`
as PC root. The harness isolates PID/mount namespaces: the old bionic runtime
hung in the high-PID shared WSL environment and passed in a fresh PID namespace.
Java verification stays enabled; qemu uses a PC-only ashmem shim and disables
external dexopt, which does not establish the vehicle's optimizer behavior.
The suite includes real stock DiPO discovery (15 hooks) with the application's
private framework libraries on its loader path, and a no-hook preload marker.
A custom native bridge must explicitly preserve synchronized monitors; the ARM
regression caught this omission and now passes after the engine fix.
