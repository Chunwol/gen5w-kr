"""Independent dispatch/header checks for self-authored ODEX control recipes."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
import zlib

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools/iap2'))
from control_patch import Dex,make_recipe

def execute(data,intent):
    regs,ins,outs,tries,debug,count=struct.unpack_from('<HHHHII',data)
    assert (regs,ins,outs,tries,debug)==(8,4,3,0,0)
    words=struct.unpack_from('<'+'H'*count,data,16)
    r={4:'service',5:intent,6:0,7:1};pc=0;result=None;calls=[]
    for _ in range(100):
        word=words[pc];op=word&255
        if op==0x38:
            pc+=struct.unpack('<h',struct.pack('<H',words[pc+1]))[0] if not r.get(word>>8) else 2
        elif op==0x1a:r[word>>8]='component';pc+=2
        elif op==0x12:
            value=word>>12;r[(word>>8)&15]=value-16 if value>=8 else value;pc+=1
        elif op in (0x6e,0x70):
            packed=words[pc+2];args=[r[(packed>>(4*i))&15] for i in range(word>>12)]
            if op==0x6e:result=args[0].get(args[1],args[2])
            else:calls.append((words[pc+1],args))
            pc+=3
        elif op==0x0a:r[word>>8]=result;pc+=1
        elif op==0x33:
            delta=struct.unpack('<h',struct.pack('<H',words[pc+1]))[0]
            pc+=delta if r[(word>>8)&15]!=r[word>>12] else 2
        elif op==0x29:pc+=struct.unpack('<h',struct.pack('<H',words[pc+1]))[0]
        elif op==0x0f:return r[word>>8],calls
        else:raise AssertionError('unexpected own opcode '+hex(op))
    raise AssertionError('dispatch did not terminate')

def audit_private(path):
    raw=path.read_bytes();recipe,changed=make_recipe(raw)
    version=path.parent.parent.name.split('_')[0]
    assert json.loads((ROOT/'tools/iap2'/f'{version}.json').read_text())==recipe
    dex=Dex(changed);original=Dex(raw)
    assert dex.methods==original.methods and dex.fields==original.fields and dex.strings==original.strings
    base,length=dex.base,dex.length
    assert changed[base+12:base+32]==hashlib.sha1(changed[base+32:base+length]).digest()
    assert struct.unpack_from('<I',changed,base+8)[0]==zlib.adler32(changed[base+12:base+length])&0xffffffff
    deps=struct.unpack_from('<I',changed,16)[0];opt,size=struct.unpack_from('<II',changed,24)
    assert struct.unpack_from('<I',changed,36)[0]==zlib.adler32(changed[deps:opt+size])&0xffffffff
    assert len(changed)==len(raw)
    print('PASS private iAP2 metadata, identities and both checksums:',version)

def main():
    p=argparse.ArgumentParser();p.add_argument('--stock',type=Path,action='append',default=[]);a=p.parse_args()
    checks=0
    for version in ('v035','v039'):
        recipe=json.loads((ROOT/'tools/iap2'/f'{version}.json').read_text())
        code=bytes(recipe['patches'][0]['bytes'])
        for intent,expected in ((None,0),({},0),({'component':0},0),({'component':2},0),({'component':3},1),({'component':-3},1),({'component':99},0)):
            result,calls=execute(code,intent);assert result==1 and len(calls)==expected
            if calls:assert calls[0][1]==['service',3]
            checks+=1
        _,start=execute(code,{'component':3});_,stop=execute(code,{'component':-3})
        assert start[0][0]!=stop[0][0];checks+=1
        # Route + Wi-Fi assignments use the proven constant-one register v3.
        assert sum(bytes(x['bytes'])==b'\x67\x03' for x in recipe['patches'])==4;checks+=1
    for path in a.stock:audit_private(path)
    print('PASS iAP2 control:',checks,'dispatch/capability checks')
if __name__=='__main__':main()
