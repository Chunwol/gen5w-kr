# Emergency restore manifest v1 and v2

The restore-only USB consumes the device-local file
`/data/local/gen5w-portable/persistent/recovery/manifest` and an immutable
backup tree at `.../recovery/originals/`. This is a fixed format, not a shell
program. One complete manifest must validate before `/system` is remounted.

Version 1 remains supported. The first line is exactly:

```text
GEN5W-RECOVERY-MANIFEST|1
```

Each following row has exactly twelve pipe-separated fields:

```text
target|kind|original_sha256|applied_sha256|original_uid|original_gid|original_mode_octal|original_selinux_label|applied_uid|applied_gid|applied_mode_octal|applied_selinux_label
```

`target` must be an explicitly supported `/system` file. `kind=file` means the
backup is stored under `originals/<target-with-leading-slash-removed>` and its
bytes must match `original_sha256`. Backup storage ownership, mode, and SELinux
label may differ from the `/system` original; restore applies the separately
recorded original ownership, mode, and label to the staged target before
replacement. `kind=absent` uses `-` for the four original fields and means
restore by removing the exact applied file. Live files are accepted only when
their hash and metadata match either the original or applied state. Symlinks,
duplicates, unknown targets, foreign content, and incomplete rows are rejected
before the first write.

The final complete row is processed even if the manifest ends at EOF without a
newline; an incomplete final row still fails the whole-file validation.

Version 2 adds a thirteenth field for a prior applied file hash:

```text
target|kind|original_sha256|applied_sha256|original_uid|original_gid|original_mode_octal|original_selinux_label|applied_uid|applied_gid|applied_mode_octal|applied_selinux_label|prior_applied_sha256
```

Its first line is `GEN5W-RECOVERY-MANIFEST|2`. The final field is either `-`
or a lowercase 64-character SHA-256 digest. It lets recovery recognize the
previous portable version during an interrupted atomic update. Both current
and prior applied hashes must have the same recorded applied metadata and
label; original-state checks still use the original metadata and label. A
version 1 manifest has exactly twelve fields and retains its original behavior.

The restore operation is retryable after interruption: already-restored
targets are accepted, while remaining patched targets are restored. The
completion marker binds the manifest digest to the boot ID in which restore
finished. It is durably written after content/metadata verification and
`/system` read-only verification, before requesting reboot, so a reboot that
terminates the script cannot cause the same restore USB to request another
reboot on the next boot. A later dispatch confirms completion only after the
boot ID changes. If the boot ID is unchanged, the report says reboot was not
confirmed and the script refuses another automatic reboot. A host fixture can
verify parser and filesystem behavior only; it does not establish NEMESIS
dispatch, toolbox/SELinux command availability, or safe recovery on the target
vehicle.

## Installation and removal completion

`restore.sh --verify-only` validates the complete live original state, the
manifest-bound completion marker, a different boot ID and `/system` read-only
state. It never restores files, remounts or requests reboot. The combined field
USB uses this verification before installation; missing live wrapper properties
alone are insufficient. Failure returns to recovery rather than installation.

Field recovery and the package removal caller set
`GEN5W_RECOVERY_RESTORE_SETTINGS=1` while Android is available. Portable admission
requires `wifi_ap_on=0` in both the USB installer and `ap.sh prepare` before
persistent writes. These callers restore that admitted saved value, verify it
and only then publish completion. Values other than 0/1 or an unavailable
settings service fail closed. Verification mode only checks the value and never
changes it. The pre-zygote boot guard leaves this option off because Android's
settings service is not running; subsequent field verification detects any
remaining saved setting before installation.

`boot.sh disable` also restores the immutable persistent manifest, even when
the legacy overlay/runtime journals report disabled. It uses
`GEN5W_RECOVERY_DEFER_REBOOT=1` so the removal caller can finish before reboot.
This mode succeeds only with verified originals and a read-only `/system`;
otherwise it reports failure and retains recovery data. Deferred completion is
not a confirmed cold boot and cannot pass the USB installation verifier until
the boot ID changes. The app UI continues to leave final package/app deletion
to NEMESIS Manager. NEMESIS versions that ignore a failed preuninstall hook
remain an external limitation; retained device-local recovery data must not be
deleted on failure.


The 0.3.87 allowlist includes `/system/lib/libautoreceiver_infobank.so` as
an ordinary immutable-original recovery row. Its expanded authored AA producer
is restored by the same metadata/hash checks as other system payloads.
A retained `/data/local/gen5w-portable/network-adb/journal` also prevents early
already-restored completion. The external owned `restore.sh` must reconcile
that journal before completion; a missing or unsafe helper fails closed.
Verification mode does not write ADB properties.
