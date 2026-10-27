"""Create our small service-control shim from stock metadata, never stock code.

Only two code_item bodies and their code_off operands change. A dormant native
debug trigger becomes a no-op; its larger slot holds our onStartCommand handler.
USB receivers and the connection manager remain untouched. Output recipes contain
only authored instructions, offsets and whole-file identities.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zlib

def uleb(data, pos):
    result = 0
    for i in range(5):
        b = data[pos+i]; result |= (b & 127) << (7*i)
        if b < 128: return result, pos+i+1
    raise ValueError('bad uleb')

def leb(value, width):
    result = []
    for i in range(width):
        result.append((value & 127) | (128 if i+1 < width else 0)); value >>= 7
    if value: raise ValueError('code offsets need different widths')
    return bytes(result)

class Dex:
    def __init__(self, raw):
        self.raw = raw
        if raw[:4] == b'dey\n': self.base, self.length = struct.unpack_from('<II', raw, 8)
        elif raw[:4] == b'dex\n': self.base, self.length = 0, len(raw)
        else: raise ValueError('expected original DEX/ODEX')
        self.data = raw[self.base:self.base+self.length]
        def table(offset, width):
            count, start = struct.unpack_from('<II', self.data, offset)
            return [self.data[start+i*width:start+(i+1)*width] for i in range(count)]
        self.strings = []
        for entry in table(56, 4):
            off = struct.unpack('<I', entry)[0]; _, off = uleb(self.data, off)
            end = self.data.index(0, off)
            self.strings.append(self.data[off:end].decode('utf-8', errors='replace'))
        self.types = [self.strings[struct.unpack('<I', x)[0]] for x in table(64, 4)]
        self.protos = []
        for entry in table(72, 12):
            _, ret, off = struct.unpack('<III', entry)
            params = []
            if off:
                count = struct.unpack_from('<I', self.data, off)[0]
                params = [self.types[struct.unpack_from('<H',self.data,off+4+i*2)[0]] for i in range(count)]
            self.protos.append('('+''.join(params)+')'+self.types[ret])
        self.methods = []
        for entry in table(88, 8):
            cls, proto, name = struct.unpack('<HHI', entry)
            self.methods.append(self.types[cls]+'->'+self.strings[name]+self.protos[proto])
        self.fields = []
        for entry in table(80, 8):
            cls, typ, name = struct.unpack('<HHI', entry)
            self.fields.append(self.types[cls]+'->'+self.strings[name]+':'+self.types[typ])
        self.code = {}
        self.class_names = [self.types[struct.unpack_from('<I',entry)[0]] for entry in table(96,32)]
        for entry in table(96, 32):
            off = struct.unpack_from('<I', entry, 24)[0]
            if not off: continue
            counts=[]
            for _ in range(4): v,off=uleb(self.data,off); counts.append(v)
            for _ in range(counts[0]+counts[1]):
                _,off=uleb(self.data,off); _,off=uleb(self.data,off)
            for count in counts[2:]:
                index=0
                for _ in range(count):
                    delta,off=uleb(self.data,off); index+=delta
                    _,off=uleb(self.data,off); start=off; value,off=uleb(self.data,off)
                    self.code[self.methods[index]]=(value,start,off-start)

def finalize(raw, dex, patches, changed_classes):
    """Disable stale GC maps only for modified classes and reseal both headers.

    Dalvik's RegisterMapClassPool uses zero for classes without a register map.
    Reusing a map after changing instructions/register counts would be unsafe.
    Other classes retain their original optimized maps and executable code.
    """
    if dex.base:
        opt, size = struct.unpack_from('<II',raw,24)
        pos=opt
        while pos+8<=opt+size:
            tag,length=struct.unpack_from('<II',raw,pos)
            if tag==0x41454e44: break
            if tag==0x524d4150:
                count=struct.unpack_from('<I',raw,pos+8)[0]
                if count!=len(dex.class_names): raise ValueError('register-map class count differs')
                for name in changed_classes:
                    index=dex.class_names.index(name)
                    patches.append((pos+12+index*4,b'\0'*4))
            pos=(pos+8+length+7)&~7
    result=bytearray(raw)
    for off,value in patches: result[off:off+len(value)]=value
    signature=hashlib.sha1(result[dex.base+32:dex.base+dex.length]).digest()
    result[dex.base+12:dex.base+32]=signature
    checksum=struct.pack('<I',zlib.adler32(result[dex.base+12:dex.base+dex.length])&0xffffffff)
    result[dex.base+8:dex.base+12]=checksum
    patches.append((dex.base+8,checksum+signature))
    if dex.base:
        deps=struct.unpack_from('<I',raw,16)[0]
        opt,size=struct.unpack_from('<II',raw,24)
        opt_checksum=struct.pack('<I',zlib.adler32(result[deps:opt+size])&0xffffffff)
        result[36:40]=opt_checksum;patches.append((36,opt_checksum))
    recipe={'original_sha256':hashlib.sha256(raw).hexdigest(),
            'patched_sha256':hashlib.sha256(result).hexdigest(),
            'patches':[{'offset':off,'bytes':list(value)} for off,value in patches]}
    return recipe,bytes(result)

def make_recipe(raw):
    d=Dex(raw); cls='Lcom/tcc/iap2server/Iap2Service;->'
    old_start, start_operand, start_width=d.code[cls+'onStartCommand(Landroid/content/Intent;II)I']
    old_debug, debug_operand, debug_width=d.code[cls+'debugTrigger()V']
    def method(name): return d.methods.index(name)
    getextra=method('Landroid/content/Intent;->getIntExtra(Ljava/lang/String;I)I')
    connect=method(cls+'receiveConnect(I)V'); disconnect=method(cls+'receiveDisconnect(I)V')
    key=d.strings.index('com.telechips.android.iap2.component')
    words=[]; labels={}; branches=[]
    def emit(*values): words.extend(values)
    def jump(op, label): branches.append((len(words),label)); emit(op,0)
    def call(op, index, regs):
        packed=sum(v << (4*i) for i,v in enumerate(regs[:4]))
        emit(op | len(regs)<<12, index, packed)
    # regs v0/v1 scratch; v4 service, v5 intent, v6 flags, v7 startId.
    jump(0x0538,'end') # if-eqz v5
    emit(0x001a,key,0x0112) # const-string v0, key; const/4 v1,0
    call(0x6e,getextra,[5,0,1]); emit(0x000a,0x3112) # move-result v0; const/4 v1,3
    jump(0x1033,'stop') # if-ne v0,v1
    call(0x70,connect,[4,1]); jump(0x0029,'end') # goto/16
    labels['stop']=len(words); emit(0xd112) # const/4 v1,-3
    jump(0x1033,'end'); emit(0x3112)
    call(0x70,disconnect,[4,1])
    labels['end']=len(words); emit(0x1012,0x000f) # START_STICKY=1; return v0
    for pos,label in branches: words[pos+1]=(labels[label]-pos)&65535
    def body(offset, registers, ins, instructions):
        _,_,_,tries,_,size=struct.unpack_from('<HHHHII',d.data,offset)
        if len(instructions)>size: raise ValueError('insufficient original method slot')
        return struct.pack('<HHHHII',registers,ins,3,0,0,size)+struct.pack('<'+'H'*size,*(instructions+[0]*(size-len(instructions))))
    patches=[(d.base+old_debug,body(old_debug,8,4,words)),
             (d.base+old_start,body(old_start,1,1,[0x000e])),
             (d.base+start_operand,leb(old_debug,start_width)),
             (d.base+debug_operand,leb(old_start,debug_width))]
    # Regional stock checkSupportsFeatures overrides the route property with 0
    # below step-of-spec 999. Enable the two existing protocol capabilities,
    # leaving native serializers and routing unchanged. v3 is its constant 1.
    info='Lcom/tcc/iap2server/Iap2InitInformationMsg;->'
    cap,_,_=d.code[info+'checkSupportsFeatures()V']
    cap_size=struct.unpack_from('<I',d.data,cap+12)[0]
    cap_words=struct.unpack_from('<'+'H'*cap_size,d.data,cap+16)
    if cap_words[:2] != (0x0212,0x1312): raise ValueError('capability constant registers changed')
    counts={}
    for field in ('iAP2UsedWifiInformation','iAP2UsedRouteGuidance'):
        index=d.fields.index(info+field+':I'); counts[field]=0
        for i in range(cap_size-1):
            if cap_words[i]&255==0x67 and cap_words[i+1]==index:
                patches.append((d.base+cap+16+i*2,struct.pack('<H',0x0367)))
                counts[field]+=1
    if counts!={'iAP2UsedWifiInformation':1,'iAP2UsedRouteGuidance':3}:
        raise ValueError('unexpected capability assignments: '+str(counts))
    return finalize(raw,d,patches,[cls[:-2],info[:-2]])

def main():
    p=argparse.ArgumentParser();p.add_argument('original');p.add_argument('recipe');p.add_argument('--private-output');a=p.parse_args()
    recipe,result=make_recipe(Path(a.original).read_bytes())
    Path(a.recipe).write_text(json.dumps(recipe,indent=2)+'\n',encoding='utf-8',newline='\n')
    if a.private_output: Path(a.private_output).write_bytes(result)
    print('Generated authored control shim, original='+recipe['original_sha256'])
if __name__=='__main__':main()
