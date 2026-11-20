#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d "${TMPDIR:-/tmp}/g5p-label.XXXXXX")
trap 'rc=$?; rm -rf "$t"; exit $rc' EXIT
cat > "$t/getxattr.c" <<'C'
#define _GNU_SOURCE
#include <errno.h>
#include <string.h>
#include <sys/types.h>
#include <sys/xattr.h>
ssize_t getxattr(const char *path, const char *name, void *value, size_t size) {
  static const char context[] = "u:object_r:system_file:s0";
  if (strcmp(name, "security.selinux") || strcmp(path, "/fixture")) {
    errno = ENODATA;
    return -1;
  }
  if (size < sizeof(context)) {
    errno = ERANGE;
    return -1;
  }
  memcpy(value, context, sizeof(context));
  return sizeof(context);
}
C
cc -shared -fPIC -o "$t/getxattr.so" "$t/getxattr.c"
printf 'u:object_r:system_file:s0\n' > "$t/expected"
LD_PRELOAD="$t/getxattr.so" .build/portable/dex-patch-host label /fixture > "$t/actual"
cmp -s "$t/expected" "$t/actual" || {
  echo 'FAIL SELinux label output must omit the xattr terminator byte'
  od -An -tx1 "$t/actual"
  exit 1
}
echo 'PASS SELinux label output is plain text without an embedded NUL'
