#include "zipruntime.h"
typedef struct Entry { char *name; uint32_t crc, size, offset; struct Entry *next; } Entry;
static FILE *out;
static Entry *first, **last=&first;
static unsigned count;
static void fail(void) { fputs("package snapshot failed\n", stderr); exit(1); }
static void word(uint32_t n, int bytes) { while(bytes--) { if(fputc(n&255,out)==EOF) fail(); n>>=8; } }
static uint32_t position(void) { long p=ftell(out); if(p<0 || (unsigned long)p>0x7fffffffUL) fail(); return (uint32_t)p; }
static void bytes(const void *p,size_t n) { if(fwrite(p,1,n,out)!=n) fail(); }
static void walk(const char *base,const char *relative) {
    char path[2048], name[2048]; DIR *d; struct dirent *de;
    if(snprintf(path,sizeof(path),"%s/%s",base,relative)>=(int)sizeof(path)) fail();
    d=opendir(path); if(!d) fail();
    while((de=readdir(d))) {
        struct stat st; FILE *in; Entry *e; unsigned char buf[4096]; size_t n; uint32_t crc=~0U, size=0;
        if(!strcmp(de->d_name,".") || !strcmp(de->d_name,"..")) continue;
        if(snprintf(name,sizeof(name),"%s%s%s",relative,*relative?"/":"",de->d_name)>=(int)sizeof(name)) fail();
        if(snprintf(path,sizeof(path),"%s/%s",base,name)>=(int)sizeof(path)) fail();
        if(lstat(path,&st)) fail();
        if(S_ISDIR(st.st_mode)) { walk(base,name); continue; }
        if(!S_ISREG(st.st_mode) || st.st_size<0 || st.st_size>0x7fffffff || ++count>65535) fail();
        in=fopen(path,"rb"); if(!in) fail();
        while((n=fread(buf,1,sizeof(buf),in))) {
            size_t i; if(size>0x7fffffffU-n) fail(); size+=(uint32_t)n;
            for(i=0;i<n;i++) { int b; crc^=buf[i]; for(b=0;b<8;b++) crc=(crc>>1)^((0U-(crc&1))&0xedb88320U); }
        }
        if(ferror(in) || fseek(in,0,SEEK_SET)) fail();
        e=calloc(1,sizeof(*e)); if(!e) fail(); e->name=strdup(name); if(!e->name) fail();
        e->crc=~crc; e->size=size; e->offset=position(); *last=e; last=&e->next;
        word(0x04034b50,4); word(20,2); word(0,2); word(0,2); word(0,2); word(33,2);
        word(e->crc,4); word(size,4); word(size,4); word(strlen(name),2); word(0,2); bytes(name,strlen(name));
        while((n=fread(buf,1,sizeof(buf),in))) bytes(buf,n);
        if(ferror(in) || fclose(in)) fail();
    }
    closedir(d);
}
int archive_main(int argc,char **argv) {
    Entry *e; uint32_t start,end;
    if(argc!=3) return 2;
    out=fopen(argv[2],"wb"); if(!out) fail(); walk(argv[1],""); start=position();
    for(e=first;e;e=e->next) {
        word(0x02014b50,4); word(20,2); word(20,2); word(0,2); word(0,2); word(0,2); word(33,2);
        word(e->crc,4); word(e->size,4); word(e->size,4); word(strlen(e->name),2);
        word(0,2); word(0,2); word(0,2); word(0,2); word(0,4); word(e->offset,4); bytes(e->name,strlen(e->name));
    }
    end=position(); word(0x06054b50,4); word(0,2); word(0,2); word(count,2); word(count,2);
    word(end-start,4); word(start,4); word(0,2);
    if(fclose(out)) fail(); return 0;
}
