"""Execute our Thumb selectors using Unicorn; optional private OEM differential.
Usage: python tests/audio_native.py [--stock /private/libCarPlayAudio.so]
No stock file or bytes are saved. Build tools/audio/build.py first.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_CODE
from unicorn.arm_const import *
ROOT = Path(__file__).resolve().parents[1]
ROLES = [0x73f4,0x740c,0x741c,0x7430,0x744c,0x745c,0x7500]
EXPECTED = {
 100: ([0x30000054,0,0x30000054,0x20000040,0,0x30000050,0],
       [0x30c08854,0xc00800,0x30000054,0x20000040,0x400,0x30000050,0]),
 101: ([0]*7,[0x8800,0,0,0,0,0x400,0]),
 102: ([0]*7,[0]*7), 999: ([0]*7,[0]*7)}

def load_segments(uc, data, base):
 phoff=struct.unpack_from('<I',data,28)[0]
 entsize,count=struct.unpack_from('<HH',data,42)
 for i in range(count):
  kind,offset,vaddr,_,filesz,_,_,_=struct.unpack_from('<IIIIIIII',data,phoff+i*entsize)
  if kind==1: uc.mem_write(base+vaddr,data[offset:offset+filesz])

def execute(data,base,entry,stream,role,transport,stock=False):
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(base,0x20000);u.mem_map(0x800000,0x10000)
 load_segments(u,data,base)
 if stock:
  # Stock log-category object pointer is PC-relative. Suppress optional logs.
  literal=struct.unpack_from('<I',data,0x3b5c)[0]
  u.mem_write(base+0x3ab6+literal,struct.pack('<I',100))
 u.reg_write(UC_ARM_REG_SP,0x808000);u.reg_write(UC_ARM_REG_LR,0x809001)
 u.reg_write(UC_ARM_REG_R0,stream);u.reg_write(UC_ARM_REG_R1,base+role);u.reg_write(UC_ARM_REG_R2,transport)
 saved=[UC_ARM_REG_R4,UC_ARM_REG_R5,UC_ARM_REG_R6,UC_ARM_REG_R7,UC_ARM_REG_R8,UC_ARM_REG_R9,UC_ARM_REG_R10,UC_ARM_REG_R11]
 for i,r in enumerate(saved):u.reg_write(r,0x123400+i)
 def hook(uc,address,size,user):
  if address==base+0x26ec:
   assert uc.reg_read(UC_ARM_REG_SP)%8==0
   uc.reg_write(UC_ARM_REG_R0,int(uc.reg_read(UC_ARM_REG_R0)==uc.reg_read(UC_ARM_REG_R1)))
   uc.reg_write(UC_ARM_REG_PC,uc.reg_read(UC_ARM_REG_LR))
  elif address==0x809000: uc.emu_stop()
 u.hook_add(UC_HOOK_CODE,hook)
 u.emu_start(base+entry+1,0,count=2000)
 assert u.reg_read(UC_ARM_REG_PC)==0x809000, 'did not return'
 assert u.reg_read(UC_ARM_REG_SP)==0x808000
 for i,r in enumerate(saved):assert u.reg_read(r)==0x123400+i, 'callee-saved register changed'
 return u.reg_read(UC_ARM_REG_R0)|(u.reg_read(UC_ARM_REG_R1)<<32)

def main():
 p=argparse.ArgumentParser();p.add_argument('--stock',type=Path);p.add_argument('--core',type=Path);p.add_argument('--profile',type=Path,default=ROOT/'tools/audio/recipe.json');a=p.parse_args()
 own=(ROOT/'.build/audio/formats.elf').read_bytes(); stock=a.stock.read_bytes() if a.stock else None
 recipe=json.loads(a.profile.read_text())
 if stock: assert hashlib.sha256(stock).hexdigest()==recipe['original_sha256']
 n=0
 for base in [0x100000,0x230000]:
  for stream,masks in EXPECTED.items():
   for direction,entry in enumerate([0x3aac,0x3b74]):
    for index,role in enumerate(ROLES):
     for transport in [0,1,2,3,999]:
      actual=execute(own,base,entry,stream,role,transport)
      assert actual==masks[direction][index],(stream,index,direction,hex(actual))
      if stock:
       previous=execute(stock,base,entry,stream,role,transport,True)
       assert actual&previous==previous,('lost PCM format',stream,index,direction,hex(previous),hex(actual))
      n+=1
 print('PASS audio Thumb ABI/format cases:',n,'; private OEM PCM differential:',bool(stock))
 if a.core:
  core=a.core.read_bytes()
  assert hashlib.sha256(core).hexdigest()==recipe['dependencies']['core']
  # ABI facts: this stock uses a uint32 sample rate, then FourCC and 7 words.
  for bit,rate,fourcc,frames,channels in [(22,44100,0x61616320,1024,2),(23,48000,0x61616320,1024,2),(28,16000,0x6f707573,320,1),(29,24000,0x6f707573,480,1)]:
   u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x100000,0x30000);u.mem_map(0x800000,0x10000)
   load_segments(u,core,0x100000)
   for reg,value in [(UC_ARM_REG_SP,0x808000),(UC_ARM_REG_LR,0x809001),(UC_ARM_REG_R0,1<<bit),(UC_ARM_REG_R1,0),(UC_ARM_REG_R2,0x801000),(UC_ARM_REG_R3,0x802000)]:u.reg_write(reg,value)
   def stop(uc,address,size,user):
    if address==0x809000:uc.emu_stop()
   u.hook_add(UC_HOOK_CODE,stop);u.emu_start(0x100000+recipe.get('abi',{}).get('converter',0x152fc)+1,0,count=2000)
   assert u.reg_read(UC_ARM_REG_PC)==0x809000 and u.reg_read(UC_ARM_REG_R0)==0
   assert struct.unpack('<9I',bytes(u.mem_read(0x801000,36)))==(rate,fourcc,0,0,frames,0,channels,0,0)
   assert struct.unpack('<I',bytes(u.mem_read(0x802000,4)))[0]==16
  print('PASS private stock converter: AAC-LC 44.1/48 kHz stereo, Opus 16/24 kHz mono')
if __name__=='__main__': main()
