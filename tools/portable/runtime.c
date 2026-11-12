#include <stddef.h>
int memcmp(const void *a, const void *b, size_t n) {
  const unsigned char *x = a, *y = b;
  size_t i;
  for (i = 0; i < n; i++)
    if (x[i] != y[i])
      return x[i] - y[i];
  return 0;
}
extern void *memcpy(void *, const void *, size_t);
void __aeabi_memcpy8(void *a, const void *b, size_t n) { memcpy(a, b, n); }
