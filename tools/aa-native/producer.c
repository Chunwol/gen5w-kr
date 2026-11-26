/* Authored bounded process-local AA navigation tee. No OEM code or imports.
 * Each message uses a nonblocking AF_UNIX connection. Missing HUD consumers,
 * partial sends and backpressure never hold the projection receiver thread. */
typedef unsigned int u32;
static int call(int nr, int a, int b, int c, int d, int e) {
    register int r0 __asm__("r0")=a, r1 __asm__("r1")=b;
    register int r2 __asm__("r2")=c, r3 __asm__("r3")=d;
    register int r4 __asm__("r4")=e;
    register int r7 __asm__("r7")=nr;
    __asm__ volatile("svc 0" : "+r"(r0) : "r"(r1),"r"(r2),"r"(r3),"r"(r4),"r"(r7) : "memory","cc");
    return r0;
}
static int core_peer(int fd) {
    /* ARM EABI stat64: st_uid at byte24. The package manager owns /data/data;
     * neither a different app binding the same abstract name nor a renamed
     * process may receive navigation data. No app-private file is read. */
    unsigned char info[104];
    unsigned credentials[3], size=sizeof(credentials);
    if(call(195,(int)"/data/data/kr.gen5w.core",(int)info,0,0,0)) return 0;
    unsigned uid=(unsigned)info[24]|(unsigned)info[25]<<8|
                 (unsigned)info[26]<<16|(unsigned)info[27]<<24;
    return !call(295,fd,1,17,(int)credentials,(int)&size) &&
           size==sizeof(credentials) && credentials[1]==uid;
}
static void be32(unsigned char *p,u32 n) {
    p[0]=(unsigned char)(n>>24); p[1]=(unsigned char)(n>>16);
    p[2]=(unsigned char)(n>>8); p[3]=(unsigned char)n;
}
static void emit(u32 type,const unsigned char *data,u32 length) {
    if (!data || length>65536) return;
    unsigned char address[32]; /* AF_UNIX, abstract namespace */
    address[0]=1; address[1]=0; address[2]=0;
    const char *name="gen5wkr.aa.tbt";
    unsigned i=0;
    while(name[i]) { address[i+3]=(unsigned char)name[i]; i++; }
    unsigned char header[12]={'G','A','N','1'};
    be32(header+4,type); be32(header+8,length);
    int fd=call(281,1,1|0x800|0x80000,0,0,0);
    if (fd<0) return;
    if (!call(283,fd,(int)address,(int)(i+3),0,0) && core_peer(fd) &&
        call(289,fd,(int)header,12,0x4040,0)==12 && length)
        (void)call(289,fd,(int)data,(int)length,0x4040,0);
    (void)call(6,fd,0,0,0,0);
}
__attribute__((visibility("hidden"))) int aa_route(u32 type,const unsigned char *data,int length) {
    if(type!=0x8006 && type!=0x8007) return -253;
    if(length>=0) emit(type,data,(u32)length);
    /* The protocol message is recognized even if the optional HUD consumer is
     * absent. Stock video/audio and the phone's nav channel must keep running. */
    return 0;
}
__attribute__((visibility("hidden"))) int aa_status(u32 value) {
    if(value>3) return 0;
    unsigned char payload[2]={8,(unsigned char)value};
    emit(0x8003,payload,2);
    return 1;
}
