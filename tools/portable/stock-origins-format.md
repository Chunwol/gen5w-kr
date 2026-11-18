# Portable stock-origin snapshot format

`prepare.sh /data/PLAN --stock-origins [feature ...]` creates an optional
`/data/PLAN/stock-origins/` tree for a future persistent migration. The ordinary
prepare path does not make these copies.

Each original file is copied to the same relative path beneath
`stock-origins/`. `index.tsv` records one row for each existing original file:

```text
/system/target|sha256|uid|gid|mode-octal|selinux-context
```

For example:

```text
/system/app/HKMC_DiPO.odex|<64 lowercase hex digits>|0|0|644|u:object_r:system_file:s0
```

The hash and metadata are captured from the target before copying. The copied
file's `/data` ownership and SELinux label are not used as a substitute for
the original `/system` values. Targets that did not exist in stock are absent
from both the tree and index; a migration manifest records them as absent.

The migrator must reject a missing, duplicate, malformed, unsupported, linked,
or hash-mismatched index entry before any `/system` write. This format supplies
inputs for source development only. It does not authorize persistent writes or
vehicle use: Android-down emergency USB dispatch and exact restore remain
separate required vehicle gates.
