"""Execute actual authored ARM producer and validate hash-bound private output.
Requires the private stock image; no OEM bytes are stored in this test.
"""
from pathlib import Path
import argparse,json,hashlib,struct
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_THUMB,UC_HOOK_INTR,UC_HOOK_CODE
from unicorn.arm_const import *
R=Path(__file__).resolve().parents[1]
P=json.loads((R/'tools/aa-native/recipe.json').read_text(encoding='utf-8'))
def execute(image,base,type,data=b'\x0a\x00',failure=None,status=False,length=None,shared=False):
 u=Uc(UC_ARCH_ARM,UC_MODE_THUMB);u.mem_map(base,0x700000);u.mem_write(base,image)
 sp=base+0x4f0000;body=base+0x500000;u.mem_write(body,data or b'\0');sent=[];calls=[]
 regs=[UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3,UC_ARM_REG_R4,UC_ARM_REG_R5,UC_ARM_REG_R6,UC_ARM_REG_R7,UC_ARM_REG_R8,UC_ARM_REG_R9,UC_ARM_REG_R10,UC_ARM_REG_R11]
 for i,r in enumerate(regs):u.reg_write(r,0x100+i)
 u.reg_write(UC_ARM_REG_SP,sp);u.reg_write(UC_ARM_REG_LR,(base+0x600000)|1)
 if status:u.reg_write(UC_ARM_REG_R0,type)
 else:
  u.reg_write(UC_ARM_REG_R2,type);u.reg_write(UC_ARM_REG_R5,len(data) if length is None else length);u.reg_write(UC_ARM_REG_R6,body)
 before=[u.reg_read(r) for r in regs]
 def intr(uc,n,user):
  nr=uc.reg_read(UC_ARM_REG_R7);a=[uc.reg_read(r) for r in regs[:4]];calls.append(nr)
  if nr==281:
   assert a[:3]==[1,1|0x800|0x80000,0];result=-1 if failure=='socket' else 42
  elif nr==283:
   assert a[0]==42;address=bytes(uc.mem_read(a[1],a[2]));assert address==b'\x01\x00\x00gen5wkr.aa.tbt';result=-1 if failure=='connect' else 0
  elif nr==195:
   name=bytes(uc.mem_read(a[0],28)).split(b'\0')[0];assert name==b'/data/data/kr.gen5w.core'
   uc.mem_write(a[1]+24,struct.pack('<I',10023));result=-1 if failure=='stat' else 0
  elif nr==295:
   assert a[:3]==[42,1,17]
   uc.mem_write(a[3],struct.pack('<III',12,10024 if failure=='identity' else 10023,10023))
   result=-1 if failure=='credentials' else 0
  elif nr==289:
   assert a[0]==42 and a[3]==0x4040;sent.append(bytes(uc.mem_read(a[1],a[2])));result=a[2]-1 if failure=='partial' else a[2]
  elif nr==6:assert a[0]==42;result=0
  else:raise AssertionError('unexpected syscall '+str(nr))
  uc.reg_write(UC_ARM_REG_R0,result&0xffffffff)
 def stop(uc,address,size,user):
  if address in (base+0xb681c,base+0x1699dc,base+0x600000):uc.emu_stop()
 u.hook_add(UC_HOOK_INTR,intr);u.hook_add(UC_HOOK_CODE,stop)
 entry=((base+0x144efa if shared else base+0x1699d8) if status else base+0xb6818)|1
 u.emu_start(entry,base+0x600004,count=100000)
 after=[u.reg_read(r) for r in regs]
 assert u.reg_read(UC_ARM_REG_SP)==sp,'stack ABI'
 for i in ([4,5,6,7,8,9,10,11] if status else [0,1,2,3,6,7,8,9,10,11]):assert before[i]==after[i],('callee/register ABI',i)
 assert after[0 if status else 4]==((1 if type<=(2 if shared else 3) else 0) if status else (0 if type in (0x8006,0x8007) else 0xffffff03))
 return sent,calls

def main():
 a=argparse.ArgumentParser();a.add_argument('--stock',type=Path,required=True);a.add_argument('--patched',type=Path,required=True);x=a.parse_args()
 old=x.stock.read_bytes();image=x.patched.read_bytes();assert hashlib.sha256(old).hexdigest()==P['original_sha256'];assert hashlib.sha256(image).hexdigest()==P['patched_sha256']
 phoff=struct.unpack_from('<I',image,28)[0];n=struct.unpack_from('<H',image,44)[0]
 assert image[0x144efa:0x144f04]==old[0x144efa:0x144f04], 'shared radio/video/navigation enum validator was changed'
 ph=[struct.unpack_from('<8I',image,phoff+i*32) for i in range(n)];assert any(p[0]==1 and p[2]<=P['payload_address']<p[2]+p[5] and p[6]==5 for p in ph)
 for base in (0x1000000,0x31000000):
  for typ in (0x8006,0x8007):
   payload=b'\x0a\x04test';sent,calls=execute(image,base,typ,payload);assert b''.join(sent)==b'GAN1'+struct.pack('>II',typ,len(payload))+payload
   for fault in ('socket','connect','partial','stat','credentials','identity'):
    _,calls=execute(image,base,typ,payload,fault);assert calls[-1]==6 or calls==[281]
   sent,calls=execute(image,base,typ,b'a',length=-1);assert not sent and not calls
   sent,calls=execute(image,base,typ,b'a',length=65537);assert not sent and not calls
  sent,calls=execute(image,base,0x8008);assert not sent and not calls
  for status in range(5):
   sent,calls=execute(image,base,status,status=True)
   if status<=3:assert b''.join(sent)==b'GAN1'+struct.pack('>II',0x8003,2)+bytes([8,status])
   else:assert not sent and not calls
  for value in range(5):
   sent,calls=execute(image,base,value,status=True,shared=True);assert not sent and not calls
 print('PASS actual ARM native AA frame producer: 2 ASLR bases, 8006/8007/status, ABI, absent peer, partial send, length bounds, original unknown return; ELF executable segment and private hashes')
if __name__=='__main__':main()
