#ifndef DEX_PATCH_H
#define DEX_PATCH_H
#include <stddef.h>
/* Mutates only the supplied buffer; callers must discard it after failure. */
int dex_patch(const char *kind, unsigned char *data, size_t size);
#endif
