/* Minimal freestanding I/O for our snapshot writer, Linux ARM EABI/x86_64. */
typedef unsigned int uint32_t;
typedef unsigned long size_t;
#define NULL ((void *)0)
#define EOF (-1)
#define SEEK_SET 0
#ifdef __arm__
#define N_OPEN 5
#define N_CLOSE 6
#define N_READ 3
#define N_WRITE 4
#define N_SEEK 19
#define N_EXIT 1
#define NOFOLLOW 0x8000
#define DIRECTORY 0x4000
static long sys3(long n,long x,long y,long z) { register long r0 __asm__("r0")=x,r1 __asm__("r1")=y,r2 __asm__("r2")=z,r7 __asm__("r7")=n; __asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2),"r"(r7):"memory"); return r0; }
#else
#define N_OPEN 2
#define N_CLOSE 3
#define N_READ 0
#define N_WRITE 1
#define N_SEEK 8
#define N_EXIT 60
#define NOFOLLOW 0x20000
#define DIRECTORY 0x10000
static long sys3(long n,long x,long y,long z) { long r; __asm__ volatile("syscall":"=a"(r):"a"(n),"D"(x),"S"(y),"d"(z):"rcx","r11","memory"); return r; }
#endif
#define N_DENTS 217
static unsigned char heap[2097152]; static size_t used;
static void *calloc(size_t n,size_t s) { void *p; size_t total=n*s; if(n && total/n!=s) return NULL; total=(total+15)&~(size_t)15; if(total>sizeof(heap)-used) return NULL; p=heap+used; used+=total; return p; }
static size_t strlen(const char *s) { size_t n=0; while(s[n]) n++; return n; }
static int strcmp(const char *a,const char *b) { while(*a && *a==*b) { a++; b++; } return (unsigned char)*a-(unsigned char)*b; }
static char *strdup(const char *s) { size_t n=strlen(s),i; char *p=calloc(n+1,1); if(p) for(i=0;i<=n;i++) p[i]=s[i]; return p; }
static int snprintf(char *dst,size_t cap,const char *fmt,...) {
 __builtin_va_list ap; size_t n=0; __builtin_va_start(ap,fmt);
 while(*fmt) { if(fmt[0]=='%' && fmt[1]=='s') { const char *s=__builtin_va_arg(ap,const char *); while(*s) { if(n+1<cap) dst[n]=*s; s++; n++; } fmt+=2; }
 else { if(n+1<cap) dst[n]=*fmt; fmt++; n++; } }
 if(cap) dst[n<cap?n:cap-1]=0; __builtin_va_end(ap); return n;
}
typedef struct { int fd,error; } FILE;
static FILE errfile={2,0};
#define stderr (&errfile)
static FILE *fopen(const char *p,const char *mode) { long fd=sys3(N_OPEN,(long)p,mode[0]=='w' ? 0x241|NOFOLLOW : NOFOLLOW,0600); FILE *f; if(fd<0) return NULL; f=calloc(1,sizeof(*f)); if(!f) { sys3(N_CLOSE,fd,0,0); return NULL; } f->fd=fd; return f; }
static size_t fread(void *p,size_t s,size_t n,FILE *f) { long rc=sys3(N_READ,f->fd,(long)p,s*n); if(rc<0) { f->error=1; return 0; } return s?rc/s:0; }
static size_t fwrite(const void *p,size_t s,size_t n,FILE *f) { long rc=sys3(N_WRITE,f->fd,(long)p,s*n); if(rc<0) { f->error=1; return 0; } return s?rc/s:0; }
static int fputc(int c,FILE *f) { unsigned char b=c; return fwrite(&b,1,1,f)==1?c:EOF; }
static int fputs(const char *p,FILE *f) { size_t n=strlen(p); return fwrite(p,1,n,f)==n?0:EOF; }
static int ferror(FILE *f) { return f->error; }
static int fclose(FILE *f) { return sys3(N_CLOSE,f->fd,0,0)<0?-1:0; }
static int fseek(FILE *f,long p,int whence) { return sys3(N_SEEK,f->fd,p,whence)<0?-1:0; }
static long ftell(FILE *f) { return sys3(N_SEEK,f->fd,0,1); }
static void exit(int rc) { sys3(N_EXIT,rc,0,0); for(;;){} }
struct dirent { char d_name[1024]; };
typedef struct { int fd; unsigned at,end; char buf[4096]; struct dirent ent; } DIR;
static unsigned last_type;
static DIR *opendir(const char *p) { long fd=sys3(N_OPEN,(long)p,DIRECTORY|NOFOLLOW,0); DIR *d; if(fd<0) return NULL; d=calloc(1,sizeof(*d)); if(!d) { sys3(N_CLOSE,fd,0,0); return NULL; } d->fd=fd; return d; }
static struct dirent *readdir(DIR *d) {
 unsigned char *p; unsigned reclen,i;
 if(d->at==d->end) { long rc=sys3(N_DENTS,d->fd,(long)d->buf,sizeof(d->buf)); if(rc<0) exit(1); if(!rc) return NULL; d->at=0; d->end=rc; }
 p=(unsigned char *)d->buf+d->at; reclen=p[16]|(p[17]<<8);
 if(reclen<20 || d->at+reclen>d->end) exit(1); d->at+=reclen; last_type=p[18];
 for(i=0;i<sizeof(d->ent.d_name);i++) { if(19+i>=reclen) exit(1); d->ent.d_name[i]=p[19+i]; if(!p[19+i]) break; }
 if(i==sizeof(d->ent.d_name)) exit(1); return &d->ent;
}
static int closedir(DIR *d) { return sys3(N_CLOSE,d->fd,0,0); }
struct stat { unsigned st_mode; long st_size; };
#define S_ISDIR(m) ((m)==4)
#define S_ISREG(m) ((m)==8)
static int lstat(const char *p,struct stat *s) { long fd; s->st_mode=last_type; s->st_size=0; if(last_type!=8) return 0; fd=sys3(N_OPEN,(long)p,NOFOLLOW,0); if(fd<0) return -1; s->st_size=sys3(N_SEEK,fd,0,2); sys3(N_CLOSE,fd,0,0); return s->st_size<0?-1:0; }
int archive_main(int,char **);
void start_c(size_t *sp) { exit(archive_main(sp[0],(char **)(sp+1))); }
#ifdef __arm__
__asm__(".global _start\n_start:\nmov r0,sp\nb start_c\n");
#else
__asm__(".global _start\n_start:\nmov %rsp,%rdi\nandq $-16,%rsp\ncall start_c\n");
#endif
