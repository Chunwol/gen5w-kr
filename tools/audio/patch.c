/* Original implementation: bounded whole-file SHA-256 guarded binary recipe.
 * No manufacturer content is compiled into this program. */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#ifdef _WIN32
#include <io.h>
#define fsync _commit
#else
#define O_BINARY 0
#endif
struct patch { size_t offset, length; const unsigned char *bytes; };
#include <recipe.h>
static uint32_t rotate(uint32_t n, unsigned bits) { return (n >> bits) | (n << (32-bits)); }
static const uint32_t k[64] = {
 0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
 0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
 0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
 0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
 0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
 0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
 0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
 0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2 };
static void sha256(const unsigned char *data, size_t size, char hex[65]) {
 uint32_t h[8]={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
 size_t blocks=(size+9+63)/64, block, i;
 for(block=0;block<blocks;block++) {
  uint32_t w[64],a,b,c,d,e,f,g,j;
  for(i=0;i<16;i++) {
   unsigned n; w[i]=0;
   for(n=0;n<4;n++) {
    size_t pos=block*64+i*4+n;
    unsigned char v=pos<size ? data[pos] : pos==size ? 128 : 0;
    if(pos>=blocks*64-8) v=(unsigned char)(((uint64_t)size*8) >> ((blocks*64-1-pos)*8));
    w[i]=(w[i]<<8)|v;
   }
  }
  for(i=16;i<64;i++) {
   uint32_t x=w[i-15], y=w[i-2];
   w[i]=w[i-16]+(rotate(x,7)^rotate(x,18)^(x>>3))+w[i-7]+(rotate(y,17)^rotate(y,19)^(y>>10));
  }
  a=h[0];b=h[1];c=h[2];d=h[3];e=h[4];f=h[5];g=h[6];j=h[7];
  for(i=0;i<64;i++) {
   uint32_t t=j+(rotate(e,6)^rotate(e,11)^rotate(e,25))+((e&f)^((~e)&g))+k[i]+w[i];
   uint32_t u=(rotate(a,2)^rotate(a,13)^rotate(a,22))+((a&b)^(a&c)^(b&c));
   j=g;g=f;f=e;e=d+t;d=c;c=b;b=a;a=t+u;
  }
  h[0]+=a;h[1]+=b;h[2]+=c;h[3]+=d;h[4]+=e;h[5]+=f;h[6]+=g;h[7]+=j;
 }
 for(i=0;i<32;i++) { unsigned v=(h[i/4]>>(24-(i%4)*8))&255; hex[i*2]="0123456789abcdef"[v>>4]; hex[i*2+1]="0123456789abcdef"[v&15]; }
 hex[64]=0;
}
int main(int argc, char **argv) {
 long length; size_t size,i; unsigned char *data; char digest[65]; int in,fd,rc=1;
 if(argc<3 || (strcmp(argv[1],"original") && strcmp(argv[1],"patched") && strcmp(argv[1],"apply") && strcmp(argv[1],"verify"))) return 2;
 if((!strcmp(argv[1],"apply") || !strcmp(argv[1],"verify")) ? argc!=4 : argc!=3) return 2;
 in=open(argv[2],O_RDONLY|O_BINARY); if(in<0) return 1;
 if((length=(long)lseek(in,0,SEEK_END))<0 || length>32*1024*1024 || lseek(in,0,SEEK_SET)!=0) { close(in); return 1; }
 size=(size_t)length; data=malloc(size?size:1); if(!data) { close(in); return 1; }
 for(i=0;i<size;) { int n=(int)read(in,data+i,(unsigned)(size-i)); if(n<=0) break; i+=(size_t)n; }
 close(in); if(i!=size) { free(data); return 1; }
 sha256(data,size,digest);
 if(!strcmp(argv[1],"verify")) { rc=strcmp(digest,argv[3])!=0; free(data); return rc; }
 if(!strcmp(argv[1],"patched")) { rc=strcmp(digest,PATCHED_SHA)!=0; free(data); return rc; }
 if(strcmp(digest,ORIGINAL_SHA)) { free(data); return 1; }
 if(!strcmp(argv[1],"original")) { free(data); return 0; }
 for(i=0;i<sizeof(patches)/sizeof(patches[0]);i++) {
  if(patches[i].offset>size || patches[i].length>size-patches[i].offset) { free(data); return 1; }
  memcpy(data+patches[i].offset,patches[i].bytes,patches[i].length);
 }
 sha256(data,size,digest); if(strcmp(digest,PATCHED_SHA)) { free(data); return 1; }
 fd=open(argv[3],O_WRONLY|O_CREAT|O_EXCL|O_BINARY,0600); if(fd<0) { free(data); return 1; }
 for(i=0;i<size;) { int n=(int)write(fd,data+i,(unsigned)(size-i)); if(n<=0) break; i+=(size_t)n; }
 if(i==size && !fsync(fd)) rc=0;
 if(close(fd)) rc=1;
 if(rc) unlink(argv[3]);
 free(data); return rc;
}
