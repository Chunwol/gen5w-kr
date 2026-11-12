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
#else
#include <sys/mount.h>
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
int main(int argc, char **argv) {
  int in, out, rc = 1;
  if (argc >= 2 && !strcmp(argv[1], "supervise")) return portable_supervise(argc, argv);
#ifndef _WIN32
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
