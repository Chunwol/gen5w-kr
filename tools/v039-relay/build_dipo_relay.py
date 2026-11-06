#!/usr/bin/env python3
"""Build a private exact-V039 DiPO APK from user-owned stock files.

The repository contains only independently authored adapter sources. OEM APK,
ODEX, framework files and the generated APK stay outside the repository.
"""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
V039_APK_SHA256 = "0859b0a5d87320935f2a06ac70baa7e3e30498b29bdafccd6c8ccc51343d5f3f"
V039_ODEX_SHA256 = "950b5575603e50aea9894b3568e80e21b3a354a6c812c3991010ab3e0cb9fe90"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def run(*args: object, cwd: Path | None = None) -> None:
    subprocess.run([str(a) for a in args], cwd=cwd, check=True)


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise ValueError(f"expected one exact hook anchor in {path}: {old[:80]!r}")
    path.write_text(text.replace(old, new), encoding="utf-8", newline="\n")


def insert_method_entry(path: Path, signature: str, body: str) -> None:
    text = path.read_text(encoding="utf-8")
    marker = signature + "\n"
    start = text.find(marker)
    if start < 0 or text.find(marker, start + 1) >= 0:
        raise ValueError(f"missing unique method {signature} in {path}")
    registers = text.find("    .registers ", start)
    end = text.find("\n", registers)
    if registers < 0 or end < 0:
        raise ValueError(f"missing register declaration for {signature}")
    text = text[:end + 1] + "\n" + body + text[end + 1:]
    path.write_text(text, encoding="utf-8", newline="\n")


def patch_stock_smali(tree: Path) -> None:
    carplay = tree / "com/daudio/app/dipo/telechips/CarPlayService.smali"
    connection = tree / "com/daudio/app/dipo/e/h.smali"
    listener = tree / "com/daudio/app/dipo/e/a.smali"
    dipo_service = tree / "com/daudio/app/dipo/service/DipoService.smali"
    insert_method_entry(carplay, ".method public onSessionCreated()V",
        "    invoke-static {p0}, Lkr/gen5w/dipo/RelayBridge;->sessionCreated(Lcom/daudio/app/dipo/telechips/CarPlayService;)V\n")
    insert_method_entry(carplay, ".method public onSessionStarted(I)V",
        "    invoke-static {p1}, Lkr/gen5w/dipo/RelayBridge;->sessionStarted(I)V\n")
    insert_method_entry(carplay, ".method public onSessionFinalized(I)V",
        "    invoke-static {p0}, Lkr/gen5w/dipo/RelayBridge;->sessionFinalized(Lcom/daudio/app/dipo/telechips/CarPlayService;)V\n")
    insert_method_entry(carplay, ".method public oniAPSendMessage([BI)V",
        "    invoke-static {p0, p1, p2}, Lkr/gen5w/dipo/RelayBridge;->fromCarPlay(Lcom/daudio/app/dipo/telechips/CarPlayService;[BI)V\n")

    replace_once(connection,
        "    invoke-static {p2}, Lcom/tcc/iap2/IIap2Service$Stub;->asInterface(Landroid/os/IBinder;)Lcom/tcc/iap2/IIap2Service;\n\n    move-result-object v1\n",
        "    invoke-static {p2}, Lcom/tcc/iap2/IIap2Service$Stub;->asInterface(Landroid/os/IBinder;)Lcom/tcc/iap2/IIap2Service;\n\n    move-result-object v1\n\n    invoke-static {v1}, Lkr/gen5w/dipo/RelayBridge;->bind(Lcom/tcc/iap2/IIap2Service;)V\n")

    insert_method_entry(listener, ".method public final connected(ILjava/lang/String;)V",
        "    invoke-static {p1, p2}, Lkr/gen5w/dipo/RelayBridge;->connected(ILjava/lang/String;)Z\n\n"
        "    move-result v0\n\n    if-eqz v0, :gen5w_connected_stock\n\n    return-void\n\n    :gen5w_connected_stock\n")
    insert_method_entry(listener, ".method public final disconnected(I)V",
        "    invoke-static {p1}, Lkr/gen5w/dipo/RelayBridge;->disconnected(I)Z\n\n"
        "    move-result v0\n\n    if-eqz v0, :gen5w_disconnected_stock\n\n    return-void\n\n    :gen5w_disconnected_stock\n")
    # A missing wireless CallerList is reported as a negative state. Preserve
    # all stock 0..3 switch targets and unknown non-negative behavior; only the
    # negative default falls into the existing HookSwitch press/release case.
    text = dipo_service.read_text(encoding="utf-8")
    marker = "onKeyForService() performPhoneKey Call Key - hasn\\'t PTTKey during CarPlay Calling"
    method_start = text.find(".method private i(II)V\n")
    method_end = text.find(".end method", method_start)
    if method_start < 0 or method_end < 0:
        raise ValueError("missing exact call-key method")
    method_text = text[method_start:method_end]
    relative = method_text.find(marker)
    if relative < 0 or method_text.find(marker, relative + 1) >= 0:
        raise ValueError("missing unique no-PTT marker in call-key method")
    start = method_start + relative
    window = text[start:method_end]
    pattern = re.compile(r"(    packed-switch v0, :pswitch_data_[0-9a-f]+\n\n)"
                         r"(    goto(?:/16)? :goto_[0-9a-f]+\n\n)"
                         r"(    :pswitch_[0-9a-f]+\n)")
    match = pattern.search(window)
    if match is None:
        raise ValueError("missing no-PTT call-state switch")
    target = match.group(3).strip()
    replacement = match.group(1) + f"    if-ltz v0, {target}\n\n" + match.group(2) + match.group(3)
    absolute = start + match.start()
    text = text[:absolute] + replacement + text[absolute + len(match.group(0)):]
    dipo_service.write_text(text, encoding="utf-8", newline="\n")


def add_classes_dex(stock_apk: Path, classes_dex: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(stock_apk, "r") as source:
        if "classes.dex" in source.namelist():
            raise ValueError("reviewed V039 stock APK unexpectedly contains classes.dex")
        with zipfile.ZipFile(output, "w") as target:
            for info in source.infolist():
                clone = zipfile.ZipInfo(info.filename, info.date_time)
                clone.compress_type = info.compress_type
                clone.comment = info.comment
                clone.extra = info.extra
                clone.internal_attr = info.internal_attr
                clone.external_attr = info.external_attr
                clone.create_system = info.create_system
                target.writestr(clone, source.read(info.filename))
            dex_info = zipfile.ZipInfo("classes.dex", (1980, 1, 1, 0, 0, 0))
            dex_info.compress_type = zipfile.ZIP_STORED
            dex_info.external_attr = 0o100644 << 16
            target.writestr(dex_info, classes_dex.read_bytes())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stock-apk", type=Path, required=True)
    parser.add_argument("--stock-odex", type=Path, required=True)
    parser.add_argument("--framework", type=Path, required=True)
    parser.add_argument("--baksmali", type=Path, required=True)
    parser.add_argument("--smali", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--work", type=Path)
    parser.add_argument("--delta-out", type=Path,
                        help="also write the head-unit delta (stock ODEX -> classes.dex) for release")
    args = parser.parse_args()
    if sha256(args.stock_apk) != V039_APK_SHA256:
        raise SystemExit("stock APK is not the reviewed exact V039 file")
    if sha256(args.stock_odex) != V039_ODEX_SHA256:
        raise SystemExit("stock ODEX is not the reviewed exact V039 file")

    sdk = Path(os.environ.get("ANDROID_SDK") or os.environ.get("ANDROID_HOME") or
               Path.home() / "AppData/Local/Android/Sdk")
    android_jar = sdk / "platforms/android-36/android.jar"
    build_tools = sdk / "build-tools/36.0.0"
    d8 = build_tools / ("d8.bat" if os.name == "nt" else "d8")
    javac = shutil.which("javac")
    jar = shutil.which("jar")
    if not javac or not jar or not android_jar.is_file() or not d8.is_file():
        raise SystemExit("Java and Android SDK 36 build tools are required")

    temp_owner = None
    if args.work:
        work = args.work.resolve(); work.mkdir(parents=True, exist_ok=True)
    else:
        temp_owner = tempfile.TemporaryDirectory(prefix="gen5w-v039-dipo-")
        work = Path(temp_owner.name)
    smali_tree = work / "stock-smali"
    adapter_classes = work / "adapter-classes"
    adapter_smali = work / "adapter-smali"
    adapter_dex_dir = work / "adapter-dex"
    for directory in (smali_tree, adapter_classes, adapter_smali, adapter_dex_dir):
        directory.mkdir(parents=True, exist_ok=True)

    run("java", "-jar", args.baksmali, "deodex", "-a", "18", "-j", "1",
        "-d", args.framework, "-o", smali_tree, args.stock_odex)
    source = ROOT / "tools/v039-relay/dipo-src/kr/gen5w/dipo/RelayBridge.java"
    sourcepath = os.pathsep.join((str(ROOT / "tools/v039-relay/dipo-src"),
                                  str(ROOT / "tools/v039-relay/dipo-stubs"),
                                  str(ROOT / "probe/stubs")))
    run(javac, "-encoding", "UTF-8", "-nowarn", "--release", "8", "-cp", android_jar,
        "-sourcepath", sourcepath, "-d", adapter_classes, source)
    adapter_jar = work / "adapter.jar"
    run(jar, "cf", adapter_jar, "-C", adapter_classes, "kr")
    run(d8, "--min-api", "18", "--release", "--lib", android_jar,
        "--classpath", adapter_classes, "--output", adapter_dex_dir, adapter_jar)
    run("java", "-jar", args.baksmali, "disassemble", "-a", "18", "-j", "1",
        "-o", adapter_smali, adapter_dex_dir / "classes.dex")
    authored = adapter_smali / "kr/gen5w/dipo"
    if not authored.is_dir():
        raise SystemExit("adapter compilation did not produce the expected package")
    shutil.copytree(authored, smali_tree / "kr/gen5w/dipo", dirs_exist_ok=False)
    patch_stock_smali(smali_tree)

    rebuilt = work / "classes.base.dex"
    run("java", "-jar", args.smali, "assemble", "-a", "18", "-j", "1",
        "-o", rebuilt, smali_tree)
    final_path = work / "classes.dex"
    final_path.write_bytes(rebuilt.read_bytes())
    add_classes_dex(args.stock_apk, final_path, args.output)
    if args.delta_out:
        run(sys.executable, ROOT / "tools/v039-relay/mkdelta.py", args.stock_odex, final_path, args.delta_out)
    print(f"built private V039 DiPO relay APK: {args.output}")
    print(f"sha256={sha256(args.output)}")
    if temp_owner is not None:
        temp_owner.cleanup()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
