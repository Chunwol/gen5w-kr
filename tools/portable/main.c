#define _POSIX_C_SOURCE 200809L
#include "dex_patch.h"
#include "sha256.h"
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#ifdef _WIN32
#include <io.h>
#define fsync _commit
#ifndef O_NOFOLLOW
#define O_NOFOLLOW 0
#endif
#ifndef O_NONBLOCK
#define O_NONBLOCK 0
#endif
#else
#include <sys/mount.h>
#include <sys/file.h>
#include <poll.h>
#include <sys/xattr.h>
#define O_BINARY 0
#endif
int portable_supervise(int argc, char **argv);
static int metadata(const char *path, int identity) {
  struct stat st;
  int fd;
  char out[100];
  size_t n = 0;
  uint64_t values[3];
  unsigned i, count = identity ? 2 : 3;
#ifdef _WIN32
  fd = open(path, O_RDONLY | O_BINARY);
  if (fd < 0 || fstat(fd, &st)) {
    if (fd >= 0)
      close(fd);
    return 1;
  }
#else
  fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
  if (fd < 0 || fstat(fd, &st)) {
    if (fd >= 0)
      close(fd);
    return 1;
  }
#endif
  close(fd);
  values[0] = identity ? (uint64_t)st.st_dev : (uint64_t)st.st_uid;
  values[1] = identity ? (uint64_t)st.st_ino : (uint64_t)st.st_gid;
  values[2] = st.st_mode & 07777;
  for (i = 0; i < count; i++) {
    char digits[24];
    unsigned k = 0, radix = !identity && i == 2 ? 8 : 10;
    uint64_t v = values[i];
    do {
      unsigned bit, rem = 0;
      uint64_t q = 0;
      for (bit = 64; bit > 0; bit--) {
        rem = rem * 2 + ((v >> (bit - 1)) & 1);
        if (rem >= radix) {
          rem -= radix;
          q |= (uint64_t)1 << (bit - 1);
        }
      }
      digits[k++] = '0' + rem;
      v = q;
    } while (v);
    while (k)
      out[n++] = digits[--k];
    out[n++] = i + 1 == count ? '\n' : identity ? ':' : '|';
  }
  return write(1, out, n) == (int)n ? 0 : 1;
}
#ifndef _WIN32
static int number(const char *text, unsigned base, unsigned *value) {
  unsigned result = 0;
  if (!text || !*text) return 0;
  while (*text) {
    unsigned digit;
    if (*text < '0' || *text > '9') return 0;
    digit = (unsigned)(*text++ - '0');
    if (digit >= base || result > (0xffffffffu - digit) / base) return 0;
    result = result * base + digit;
  }
  *value = result;
  return 1;
}
static int set_metadata(const char *path, const char *uid_text,
                        const char *gid_text, const char *mode_text) {
  unsigned uid, gid, mode;
  int fd, rc;
  if (!number(uid_text, 10, &uid) || !number(gid_text, 10, &gid) ||
      !number(mode_text, 8, &mode) || mode > 07777) return 2;
  fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
  if (fd < 0) return 1;
  rc = fchown(fd, (uid_t)uid, (gid_t)gid);
  if (!rc) rc = fchmod(fd, (mode_t)mode);
  close(fd);
  return rc ? 1 : 0;
}
static int label(const char *path, int set, const char *value) {
  char buffer[256];
  ssize_t n;
  if (set) return setxattr(path, "security.selinux", value,
                           strlen(value) + 1, 0) == 0 ? 0 : 1;
  n = getxattr(path, "security.selinux", buffer, sizeof(buffer) - 1);
  if (n <= 0 || n >= (ssize_t)sizeof(buffer)) return 1;
  if (buffer[n - 1] == 0) n--;
  buffer[n] = 0;
  return write(1, buffer, (size_t)n) == n && write(1, "\n", 1) == 1 ? 0 : 1;
}
static int system_mount_state(void) {
  char line[2048], token[512];
  int fd = open("/proc/mounts", O_RDONLY), found = 0, rc = 1;
  size_t used = 0;
  if (fd < 0) return 1;
  while (1) {
    char c;
    ssize_t n = read(fd, &c, 1);
    if (n < 0) { rc = 1; break; }
    if (!n || c == '\n') {
      size_t i = 0, field = 0, start = 0;
      if (!used && !n) break;
      line[used] = 0;
      while (i <= used) {
        if (line[i] == ' ' || line[i] == 0) {
          size_t len = i - start;
          field++;
          if (field == 2 && len == 7 && !memcmp(line + start, "/system", 7)) found = 1;
          if (field == 4) {
            size_t j;
            token[0] = 0;
            if (len < sizeof(token)) { memcpy(token, line + start, len); token[len] = 0; }
            for (j = 0; token[j]; j++) {
              if ((j == 0 || token[j-1] == ',') && !memcmp(token+j, "ro", 2) &&
                  (token[j+2] == ',' || token[j+2] == 0)) { rc = 0; break; }
            }
            if (found) { close(fd); return rc; }
          }
          start = i + 1;
        }
        i++;
      }
      used = 0;
      found = 0;
      if (!n) break;
      continue;
    }
    if (used + 1 >= sizeof(line)) { used = 0; continue; }
    line[used++] = c;
  }
  close(fd);
  return 1;
}
#endif
int main(int argc, char **argv) {
  int in, out, rc = 1;
  if (argc >= 2 && !strcmp(argv[1], "supervise")) return portable_supervise(argc, argv);
#ifndef _WIN32
  if (argc >= 5 && (!strcmp(argv[1], "lock-run") || !strcmp(argv[1], "lock-wait"))) {
    struct stat st;
    int fd;
    if (argv[2][0] != '/' || argv[3][0] != '/') return 2;
    fd = open(argv[2], O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0600);
    if (fd < 0) return 1;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode)) { close(fd); return 1; }
    int remaining = !strcmp(argv[1], "lock-wait") ? 80 : 0;
    while (flock(fd, LOCK_EX | LOCK_NB)) {
      if (!remaining--) { close(fd); return 75; }
      poll(0, 0, 100);
    }
    if (fd != 9) {
      if (dup2(fd, 9) < 0) { close(fd); return 1; }
      close(fd);
      fd = 9;
    }
    /* Intentionally inherit this descriptor across exec: kernel ownership
     * survives shell descendants and releases on exit or abrupt process death.
     * Workers close descriptor 9 for detached/bounded captures. Never unlink
     * the lock inode while another caller could have it open. */
    execve(argv[3], argv + 3, argv + argc + 1);
    close(fd);
    return 1;
  }
  if (argc == 4 && !strcmp(argv[1], "bind"))
    return mount(argv[2], argv[3], 0, MS_BIND, 0) == 0 ? 0 : 1;
#endif
  long n;
  size_t i, size;
  unsigned char *data;
  if (argc == 3 && !strcmp(argv[1], "metadata"))
    return metadata(argv[2], 0);
  if (argc == 3 && !strcmp(argv[1], "identity"))
    return metadata(argv[2], 1);
#ifndef _WIN32
  if (argc == 3 && !strcmp(argv[1], "label")) return label(argv[2], 0, 0);
  if (argc == 4 && !strcmp(argv[1], "setlabel")) return label(argv[2], 1, argv[3]);
  if (argc == 6 && !strcmp(argv[1], "setmeta"))
    return set_metadata(argv[2], argv[3], argv[4], argv[5]);
  if (argc == 2 && !strcmp(argv[1], "is-ro")) return system_mount_state();
  if (argc == 2 && (!strcmp(argv[1], "remount-ro") || !strcmp(argv[1], "remount-rw"))) {
    unsigned long flags = MS_REMOUNT;
    if (!strcmp(argv[1], "remount-ro")) flags |= MS_RDONLY;
    return mount(0, "/system", 0, flags, 0) == 0 ? 0 : 1;
  }
  if (argc == 6 && !strcmp(argv[1], "setmeta"))
    return set_metadata(argv[2], argv[3], argv[4], argv[5]);
#endif
  if (argc == 3 && !strcmp(argv[1], "size")) {
    struct stat st;
#ifdef _WIN32
    int fd = open(argv[2], O_RDONLY | O_BINARY);
#else
    int fd = open(argv[2], O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
#endif
    if (fd < 0 || fstat(fd, &st)) { if (fd >= 0) close(fd); return 1; }
    close(fd);
    {
      char digits[24], output[26]; unsigned long long size = (unsigned long long)st.st_size;
      unsigned i = 0, n = 0;
      do { digits[i++] = (char)('0' + size % 10); size /= 10; } while (size && i < sizeof(digits));
      while (i) output[n++] = digits[--i];
      output[n++] = '\n';
      return write(1, output, n) == (int)n ? 0 : 1;
    }
  }
  if (argc != 4 && !(argc == 3 && !strcmp(argv[1], "sha256")))
    return 2;
  in = open(argv[2], O_RDONLY | O_BINARY);
  if (in < 0)
    return 1;
  n = (long)lseek(in, 0, SEEK_END);
  if (n < 0 || n > 32 * 1024 * 1024 || lseek(in, 0, SEEK_SET)) {
    close(in);
    return 1;
  }
  size = n;
  data = malloc(size ? size : 1);
  if (!data) {
    close(in);
    return 1;
  }
  for (i = 0; i < size;) {
    int k = read(in, data + i, size - i);
    if (k <= 0)
      break;
    i += k;
  }
  close(in);
  if (i != size) {
    free(data);
    return 1;
  }
  if (argc == 3) {
    char digest[65];
    sha256(data, size, digest);
    digest[64] = 10;
    rc = write(1, digest, 65) == 65 ? 0 : 1;
    free(data);
    return rc;
  }
  if (!dex_patch(argv[1], data, size)) {
    free(data);
    return 1;
  }
  out = open(argv[3], O_WRONLY | O_CREAT | O_EXCL | O_BINARY, 0600);
  if (out < 0) {
    free(data);
    return 1;
  }
  for (i = 0; i < size;) {
    int k = write(out, data + i, size - i);
    if (k <= 0)
      break;
    i += k;
  }
  if (i == size && !fsync(out))
    rc = 0;
  if (close(out))
    rc = 1;
  if (rc)
    unlink(argv[3]);
  free(data);
  return rc;
}
