"""Build authored PIC AA producer + hash-bound ARM installer from private stock.
No OEM code/bytes are emitted into source headers, helper, or recipe.
"""
import argparse,hashlib,json,struct,subprocess
from pathlib import Path
R=Path(__file__).resolve().parents[2]
def sha(b):return hashlib.sha256(b).hexdigest()
def branch(source,target,link=False):
 delta=target-source-4
 assert delta%2==0 and -(1<<24)<=delta<(1<<24)
 bits=delta&0x1ffffff;s=bits>>24; i1=(bits>>23)&1;i2=(bits>>22)&1
 return struct.pack('<HH',0xf000|(s<<10)|((bits>>12)&0x3ff),(0xd000 if link else 0x9000)|(((~i1)^s)&1)<<13|(((~i2)^s)&1)<<11|((bits>>1)&0x7ff))
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--ndk',type=Path,required=True);ap.add_argument('--stock',type=Path,required=True);a=ap.parse_args()
 b=a.stock.read_bytes();assert hashlib.md5(b).hexdigest()=='48ee793af8b86052503b8c952b034731','unsupported native ABI'
 out=R/'.build/aa-native';out.mkdir(exist_ok=True)
 host='windows-x86_64' if (a.ndk/'toolchains/llvm/prebuilt/windows-x86_64').exists() else 'linux-x86_64';suffix='.exe' if host.startswith('windows') else ''
 tool=a.ndk/'toolchains/llvm/prebuilt'/host/'bin'; clang=tool/('clang'+suffix)
 def run(args):subprocess.run(list(map(str,args)),cwd=R,check=True)
 flags=['--target=armv7a-linux-androideabi19','-mthumb','-Os','-ffreestanding','-fno-builtin','-fPIC','-fomit-frame-pointer','-fno-stack-protector','-fno-unwind-tables','-fno-asynchronous-unwind-tables','-nostdlib','-Wall','-Wextra','-Werror']
 run([clang,*flags,'tools/aa-native/producer.c','tools/aa-native/entry.S','-Wl,-T,tools/aa-native/layout.ld','-Wl,--build-id=none','-Wl,--no-undefined','-o',out/'payload.elf'])
 run([tool/('llvm-objcopy'+suffix),'-O','binary','--only-section=.payload',out/'payload.elf',out/'payload.bin'])
 nm=subprocess.check_output([str(tool/('llvm-nm'+suffix)),str(out/'payload.elf')],text=True)
 symbols={parts[2]:int(parts[0],16) for line in nm.splitlines() if len(parts:=line.split())==3 and parts[0]!='U'}
 payload=(out/'payload.bin').read_bytes();seg=0x1c4000;code=0x1c4400
 phoff=struct.unpack_from('<I',b,28)[0];phsize,phnum=struct.unpack_from('<HH',b,42);assert phsize==32 and phnum<16
 phdrs=[list(struct.unpack_from('<8I',b,phoff+i*32)) for i in range(phnum)]
 assert all(p[2]+p[5]<=seg for p in phdrs if p[0]==1)
 size=code+len(payload);newphnum=phnum+1;tablelen=newphnum*32;assert tablelen<=code-seg
 for p in phdrs:
  if p[0]==6:p[1]=p[2]=p[3]=seg;p[4]=p[5]=tablelen
 phdrs.append([1,seg,seg,seg,size-seg,size-seg,5,4096])
 patches=[(0xb1a2e,b'\x06'),(0xb6818,branch(0xb6818,symbols['route_entry']&~1)),(0x1699d8,branch(0x1699d8,symbols['status_entry']&~1,True)),(28,struct.pack('<I',seg)),(44,struct.pack('<H',newphnum)),(code,payload)]
 changed=bytearray(b)+bytearray(size-len(b));changed[seg:seg+tablelen]=b''.join(struct.pack('<8I',*p) for p in phdrs)
 for off,data in patches:changed[off:off+len(data)]=data
 # Private image is retained outside versioned source for ARM/loader checks only.
 private=a.stock.parent.parent.parent/'aa-native-patched.so';private.write_bytes(changed)
 profile={'id':'aa-modern-v039-1','original_sha256':sha(b),'patched_sha256':sha(changed),'original_size':len(b),'output_size':size,'segment':seg,'payload_address':code,'symbols':symbols,'patches':[{'offset':o,'length':len(d),'sha256':sha(d)} for o,d in patches]}
 (R/'tools/aa-native/recipe.json').write_text(json.dumps(profile,indent=2)+'\n',encoding='utf-8',newline='\n')
 h=['#define ORIGINAL_SHA "'+sha(b)+'"','#define PATCHED_SHA "'+sha(changed)+'"','#define OUTPUT_SIZE '+str(size)]
 for i,(off,data) in enumerate(patches):h.append('static const unsigned char p'+str(i)+'[]={'+','.join(map(str,data))+'};')
 h.append('static const struct patch patches[]={'+','.join('{'+str(o)+','+str(len(d))+',p'+str(i)+'}' for i,(o,d) in enumerate(patches))+'};')
 h.append('static unsigned get32(const unsigned char *p){return p[0]|p[1]<<8|p[2]<<16|(unsigned)p[3]<<24;}')
 h.append('static void put32(unsigned char *p,unsigned n){p[0]=n;p[1]=n>>8;p[2]=n>>16;p[3]=n>>24;}')
 h.append('static int expand_patch_image(unsigned char *data,size_t size){unsigned i,old=get32(data+28),n=data[44]|data[45]<<8;if(size!='+str(len(b))+'||n!='+str(phnum)+'||old!='+str(phoff)+')return 0;for(i=size;i<OUTPUT_SIZE;i++)data[i]=0;memcpy(data+'+str(seg)+',data+old,n*32);for(i=0;i<n;i++){unsigned char *p=data+'+str(seg)+'+i*32;if(get32(p)==6){put32(p+4,'+str(seg)+');put32(p+8,'+str(seg)+');put32(p+12,'+str(seg)+');put32(p+16,'+str(tablelen)+');put32(p+20,'+str(tablelen)+');}}unsigned char *p=data+'+str(seg)+'+n*32;')
 for i,value in enumerate(phdrs[-1]):h.append('put32(p+'+str(i*4)+','+str(value)+');')
 h.append('return 1;}')
 (out/'recipe.h').write_text('\n'.join(h)+'\n',encoding='utf-8',newline='\n')
 dest=R/'packages/core/bin/aa-native-patch';dest.parent.mkdir(exist_ok=True)
 run([clang,'--target=armv7a-linux-androideabi19','-std=c99','-Os','-Wall','-Wextra','-Werror','-fno-builtin','-fno-stack-protector','-fno-unwind-tables','-fno-asynchronous-unwind-tables','-fno-pie','-nostdlib','-static','-Wl,-e,_start','-Wl,--build-id=none','-I',out,'tools/audio/patch.c','tools/audio/runtime.c','tools/audio/syscalls.S','-o',dest])
 print('PASS authored AA producer/helper',sha(changed),'private',private)
if __name__=='__main__':main()
