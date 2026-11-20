#!/usr/bin/env python3
"""Build authored API19 ARM engine and VM fixtures without copying OEM files."""
import argparse
from pathlib import Path
import subprocess
import zipfile
import tempfile
import hashlib
import os

ROOT = Path(__file__).resolve().parents[3]

# Every input of the Dalvik artifacts. candidate.py refuses dalvik inputs whose
# recorded digest differs: the 2026-11-19 vehicle run shipped a stale
# libgen5whook.so (pre-fix -Xbootclasspath/a) for six releases.
SOURCE_ROOTS = ("tools/portable/dalvik/hook.c", "tools/portable/dalvik/build.py", "tools/portable/dalvik/src",
                "tests/portable_dalvik", "tools/portable/adapters/src", "tools/v039-relay/dipo-src",
                "tools/v039-relay/gpm-src", "shared/src", "probe/stubs", "tools/v039-relay/dipo-stubs")

def source_digest(root=ROOT):
    digest = hashlib.sha256()
    for relative in SOURCE_ROOTS:
        base = root / relative
        if base.is_file():
            files = [base]
        elif base.is_dir():
            files = sorted(p for p in base.rglob("*") if p.is_file() and p.suffix in (".c", ".h", ".java", ".py"))
        else:
            raise FileNotFoundError(base)
        for path in files:
            digest.update(path.relative_to(root).as_posix().encode() + bytes(1))
            digest.update(path.read_bytes().replace(bytes([13, 10]), bytes([10])) + bytes(1))
    return digest.hexdigest()

def build(java_home, ndk, d8, stock_system, output, android_jar=None):
    java_home, ndk, d8, stock_system, output = map(Path, (java_home, ndk, d8, stock_system, output))
    output.mkdir(parents=True, exist_ok=True)
    classes = output / "classes"
    classes.mkdir(exist_ok=True)
    host = "windows-x86_64" if (ndk / "toolchains/llvm/prebuilt/windows-x86_64").exists() else "linux-x86_64"
    suffix = ".exe" if host.startswith("windows") else ""
    clang = ndk / "toolchains/llvm/prebuilt" / host / "bin" / ("clang" + suffix)
    java = java_home / "bin" / ("java" + suffix)
    javac = java_home / "bin" / ("javac" + suffix)
    subprocess.run([str(clang), "--target=armv7a-linux-androideabi19", "-shared", "-nostdlib", "-fPIC", "-O2",
        "-Wall", "-Wextra", "-Werror", str(ROOT / "tools/portable/dalvik/hook.c"),
        str(stock_system / "lib/libc.so"), str(stock_system / "lib/libdl.so"), "-Wl,--no-undefined",
        "-o", str(output / "libgen5whook.so")], check=True)
    sources = list((ROOT / "tools/portable/dalvik/src").rglob("*.java")) + list((ROOT / "tests/portable_dalvik").glob("*.java"))
    if not android_jar: sources = [source for source in sources if source.name != "AdapterDiscoveryVmTest.java"]
    subprocess.run([str(javac), "--release", "8", "-Xlint:-options", *(["-cp", str(android_jar)] if android_jar else []), "-d", str(classes), *map(str, sources)], check=True)
    def dex_jar(name, inputs, classpath=None):
        with tempfile.TemporaryDirectory(prefix="gen5w-dex-") as temporary:
            subprocess.run([str(java), "-cp", str(d8), "com.android.tools.r8.D8", "--min-api", "19", "--output", temporary,
                *(["--lib", str(android_jar)] if android_jar else []),
                *(["--classpath", str(classpath)] if classpath else []),
                *map(str, inputs)], check=True)
            with zipfile.ZipFile(output / name, "w", zipfile.ZIP_DEFLATED) as archive:
                archive.write(Path(temporary) / "classes.dex", "classes.dex")
    engine = list((classes / "kr/gen5w/portable").rglob("*.class"))
    dex_jar("engine.jar", engine)
    dex_jar("hook-vm-test.jar", engine + list(classes.glob("*VmTest*.class")))
    dex_jar("loader-fixture.jar", [classes / "AdapterFixture.class"])
    if android_jar:
        adapter_classes = output / "adapter-classes"
        adapter_classes.mkdir(exist_ok=True)
        roots = [ROOT / name for name in ("tools/portable/adapters/src", "tools/v039-relay/dipo-src", "tools/v039-relay/gpm-src", "shared/src")]
        adapter_sources = [source for base in roots for source in base.rglob("*.java")]
        sourcepath = os.pathsep.join(map(str, roots + [ROOT / "probe/stubs", ROOT / "tools/v039-relay/dipo-stubs"]))
        subprocess.run([str(javac), "--release", "8", "-Xlint:-options", "-encoding", "UTF-8", "-cp", str(android_jar) + os.pathsep + str(classes),
            "-sourcepath", sourcepath, "-d", str(adapter_classes), *map(str, adapter_sources)], check=True)
        dex_jar("adapter.jar", list((adapter_classes / "kr").rglob("*.class")), adapter_classes)
        fixture = output / "fixture-classes"
        fixture.mkdir(exist_ok=True)
        subprocess.run([str(javac), "--release", "8", "-Xlint:-options", "-cp", str(android_jar) + (";" if suffix else ":") + str(classes),
            "-d", str(fixture), str(ROOT / "tests/portable_dalvik/fixture/kr/gen5w/portable/ProjectionAdapters.java")], check=True)
        dex_jar("bootstrap-fixture.jar", list(fixture.rglob("*.class")))
    (output / "abi.sha256").write_text(hashlib.sha256((stock_system / "lib/libdvm.so").read_bytes()).hexdigest() + "\n", encoding="ascii", newline="\n")
    if b"-Xbootclasspath" in (output / "libgen5whook.so").read_bytes():
        raise SystemExit("libgen5whook.so must never change the bootclasspath")
    (output / "source.sha256").write_text(source_digest() + "\n", encoding="ascii", newline="\n")
    (output / "engine.sha256").write_text(hashlib.sha256((output / "engine.jar").read_bytes()).hexdigest() + "\n", encoding="ascii", newline="\n")
    return output

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("java-home", "ndk", "d8", "stock-system", "output"):
        parser.add_argument("--" + name, required=True, type=Path)
    parser.add_argument("--android-jar", type=Path)
    args = parser.parse_args()
    build(args.java_home, args.ndk, args.d8, args.stock_system, args.output, args.android_jar)
