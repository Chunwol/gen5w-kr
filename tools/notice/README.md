# Stock warning timer

This module retains the native SystemUI warning and changes one existing timer
operand from 10000 ms to 3000 ms. It does not call confirmation directly, change
agreement settings, modify automotive-service, or enable a disabled auto-close
specification. The stock specification and visibility/vehicle-state checks still
decide whether and when scheduling is allowed. Specifications that require manual
confirmation retain that behavior; visible duration is not guaranteed in every
vehicle state. No vehicle execution has been verified.

Two exact SystemUI APK/ODEX pairs are recognized. V035 uses the private scheduling
method `F.dP()V`; V039 uses `F.dS()V`. The only changes are the two-byte delay
operand and the embedded DEX SHA-1/Adler-32 header. Instruction sizes, branches,
register usage, all other methods, and ODEX optimization/dependency data remain
unchanged. Full original and patched SHA-256 identities guard every operation.
Unknown versions return 77 before a remount or backup is created.

The package keeps an owned original both under `/system/etc/gen5w-kr-backup/notice`
and `/data/nemesis/backup/gen5w.kr.notice`. Removal verifies ownership and hashes,
then restores the exact original bytes. Foreign target changes and damaged
backups are refused. Reboot follows installation unless the integrated installer
owns its reboot-suppression marker. No process is killed and no Dalvik cache is
deleted.

Build without OEM inputs:

```sh
python -I tools/notice/build.py --ndk "$ANDROID_NDK_HOME"
bash tests/notice.sh
python -I tests/notice.py
```

The optional `tests/notice.py --private-root /outside/repo/consent_private`
reconstructs both recipes in memory, verifies unchanged code/data outside the
allowed operand/header, and executes the shipped ARM helpers with `qemu-arm`.
Temporary patched OEM files remain outside the repository and are deleted on
exit. The private directory contains V039 `SystemUI.odex`/`SystemUI.apk` and a
`v035` subdirectory with the V035 pair. No OEM bytes or private paths belong in
the public distribution. JSON recipes contain authored replacement data and
whole-file identities only.
