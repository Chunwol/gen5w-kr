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
