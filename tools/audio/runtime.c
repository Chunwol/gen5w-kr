/* Single-operation allocator and byte primitives for our freestanding helper. */
#include <stddef.h>
static unsigned char workspace[32*1024*1024];
void *malloc(size_t size) { return size<=sizeof(workspace) ? workspace : (void*)0; }
void free(void *data) { (void)data; }
void *memcpy(void *dest, const void *src, size_t size) {
 unsigned char *d=dest; const unsigned char *s=src; size_t i;
 for(i=0;i<size;i++) d[i]=s[i];
 return dest;
}
void __aeabi_memcpy(void *dest,const void *src,size_t size) { memcpy(dest,src,size); }
void __aeabi_memcpy4(void *dest,const void *src,size_t size) { memcpy(dest,src,size); }
int strcmp(const char *a,const char *b) {
 while(*a && *a==*b) { a++; b++; }
 return (unsigned char)*a-(unsigned char)*b;
}
