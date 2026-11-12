import pathlib, subprocess, sys, tempfile, os, hashlib, struct, stat
ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools/iap2'))
import bt_patch,route_patch,dipo_patch,gpm_patch,hotspot_patch
from control_patch import Dex
BIN=ROOT/'.build/portable'/('dex-patch-host.exe' if os.name=='nt' else 'dex-patch-host')
if '--arm' in sys.argv:
 BIN=ROOT/'.build/portable/dex-patch'
# A candidate helper built elsewhere (e.g. /tmp) can be checked without replacing
# the shared .build binary that other suites execute.
if os.environ.get('PORTABLE_PATCHER_BIN'):
 BIN=pathlib.Path(os.environ['PORTABLE_PATCHER_BIN'])
RUN=['qemu-arm',str(BIN)] if '--arm' in sys.argv else [str(BIN)]
PRIVATE=ROOT.parent/'analysis_private/hud-v039/sys/app'
INFO='Lcom/tcc/iap2server/Iap2InitInformationMsg;'
CAP=INFO+'->checkSupportsFeatures()V'
UNUSED_OPCODES=(0x3e,0x3f,0x40,0x41,0x42,0x43,0x73,0x79,0x7a,0xec,0xff)
def method_words(raw,name):
 dex=Dex(raw);code=dex.code[name][0];count=struct.unpack_from('<I',dex.data,code+12)[0]
 return dex.base+code+16,list(struct.unpack_from('<'+'H'*count,dex.data,code+16))
def with_words(raw,start,changes):
 data=bytearray(raw)
 for pc,word in changes.items(): struct.pack_into('<H',data,start+pc*2,word)
 return bytes(data)
def shape_regressions(tmp):
 """Future/unknown method shapes must leave no output; harmless edits stay exact."""
 raw=(PRIVATE/'Iap2ServerApp.odex').read_bytes()
 variant=tmp/'shape';dest=tmp/'shapeout';checked=0
 def refused(kind,data,why):
  nonlocal checked
  variant.write_bytes(data)
  assert subprocess.run([*RUN,kind,str(variant),str(dest)],capture_output=True).returncode!=0,kind+' accepted '+why
  assert not dest.exists(),kind+' left output for '+why
  checked+=1
 start,words=method_words(raw,CAP)
 decoded=list(dipo_patch.instructions(words))
 boundaries={pc for pc,_,_ in decoded}
 first_result=next(pc for pc,op,_ in decoded if op==0x0a and pc>1)
 # Control: a destination change that cannot reach v3 is still patched exactly
 # like the reference oracle, so the proof is not a blanket "any edit" refusal.
 harmless=with_words(raw,start,{first_result:0x010a})
 variant.write_bytes(harmless)
 assert subprocess.run([*RUN,'route',str(variant),str(dest)]).returncode==0,'route refused a shape that keeps v3=1'
 assert dest.read_bytes()==route_patch.make_capability_recipe(harmless)[1],'harmless route variant differs from oracle'
 dest.unlink()
 # A future build that reuses v3 before the patched sput stores would make the
 # rewritten 'sput v3' publish an unrelated value; both bt and route must refuse.
 clobbers={'narrow move-result v3':{first_result:0x030a}}
 wide=next((pc for pc,op,_ in decoded if op==0x13 and words[pc]>>8==1),None)
 assert wide is not None,'stock const/16 v1 anchor missing'
 clobbers['wide const-wide/16 v2:v3']={wide:0x0216}
 late=max(pc for pc,op,_ in decoded if op==0x1a and pc>1)
 clobbers['const-string v3 on a late branch']={late:(words[late]&0x00ff)|0x0300}
 for why,change in clobbers.items():
  for kind in ('route','bt'): refused(kind,with_words(raw,start,change),why)
 # Branches that land inside an instruction could execute a hidden stream.
 branch=next(pc for pc,op,_ in decoded if 0x38<=op<=0x3d)
 target=branch+struct.unpack('<h',struct.pack('<H',words[branch+1]))[0]
 inside=next(t for t in range(target+1,len(words)) if t not in boundaries)
 refused('route',with_words(raw,start,{branch+1:(inside-branch)&0xffff}),'branch into an instruction')
 refused('route',with_words(raw,start,{branch+1:0x7fff}),'branch outside the method')
 # Payload/switch data is outside the reviewed shape.
 invoke=next(pc for pc,op,w in decoded if op==0x6e and w==3)
 refused('route',with_words(raw,start,{invoke:0x0026,invoke+1:2,invoke+2:0}),'fill-array-data in capability method')
 # Unused/breakpoint opcodes have no reviewed width or effect.
 ret=next(pc for pc,op,_ in decoded if op==0x0e)
 for op in UNUSED_OPCODES:
  refused('route',with_words(raw,start,{ret:op}),'unused opcode %#x'%op)
 for kind,name,method in [('bt','Iap2ServerApp','Lcom/tcc/iap2server/Iap2Service;->debugTrigger()V'),
                          ('dipo','HKMC_DiPO',dipo_patch.SERVICE+'->i(II)V'),('gpm','HKMC_GPM',gpm_patch.INIT),
                          ('hotspot','HKMC_WifiSettings',hotspot_patch.TARGETS[0])]:
  stock=(PRIVATE/(name+'.odex')).read_bytes();begin,body=method_words(stock,method)
  # Replace one single-unit instruction so the old width table stays in sync.
  pc=next(p for p,op,w in dipo_patch.instructions(body) if w==1 and op)
  for op in (0x3e,0x73,0xff):
   refused(kind,with_words(stock,begin,{pc:(body[pc]&0xff00)|op}),'unused opcode %#x in %s'%(op,method.split('->')[1]))
 return checked
def main():
 assert BIN.exists(), 'native structural patcher is missing'
 with tempfile.TemporaryDirectory(dir=ROOT/'.build') as tmp:
  tmp=pathlib.Path(tmp)
  for kind,name,oracle in [('bt','Iap2ServerApp',bt_patch.make_recipe),('route','Iap2ServerApp',route_patch.make_capability_recipe),('dipo','HKMC_DiPO',dipo_patch.make_recipe),('gpm','HKMC_GPM',gpm_patch.make_recipe),('hotspot','HKMC_WifiSettings',hotspot_patch.make_recipe)]:
   source=PRIVATE/(name+'.odex'); raw=source.read_bytes(); output=tmp/(kind+'.odex')
   r=subprocess.run([*RUN,kind,str(source),str(output)])
   assert r.returncode==0,kind
   assert output.read_bytes()==oracle(raw)[1],kind+' differs from Python oracle'
   assert subprocess.run([*RUN,kind,str(source),str(output)]).returncode!=0
   assert output.read_bytes()==oracle(raw)[1]
   changed=bytearray(raw);changed[36]^=1
   variant=tmp/'variant';variant.write_bytes(changed);variant_out=tmp/'variantout'
   assert subprocess.run([*RUN,kind,str(variant),str(variant_out)]).returncode==0,kind+' uses whole-file identity'
   assert variant_out.read_bytes()==output.read_bytes()
   variant_out.unlink()
   assert subprocess.run([*RUN,kind,str(source),str(source)]).returncode!=0
   assert source.read_bytes()==raw
   base=struct.unpack_from('<I',raw,8)[0]
   # A broken type index in any method must invalidate the entire container.
   mo=struct.unpack_from('<I',raw,base+92)[0]
   broken=bytearray(raw);struct.pack_into('<H',broken,base+mo,65535)
   bad=tmp/'bad';bad.write_bytes(broken);dest=tmp/'badout'
   assert subprocess.run([*RUN,kind,str(bad),str(dest)]).returncode!=0
   assert not dest.exists()
   fo=struct.unpack_from('<I',raw,base+84)[0]
   broken=bytearray(raw);struct.pack_into('<H',broken,base+fo+2,65535)
   bad.write_bytes(broken)
   assert subprocess.run([*RUN,kind,str(bad),str(dest)]).returncode!=0,kind+' accepted invalid field type'
   assert not dest.exists()
   first_code=next(c for c,_,_ in Dex(raw).code.values() if c)
   broken=bytearray(raw);struct.pack_into('<I',broken,base+first_code+12,0x80000000)
   bad.write_bytes(broken)
   assert subprocess.run([*RUN,kind,str(bad),str(dest)]).returncode!=0,kind+' accepted overflowing instruction count'
   assert not dest.exists()
   broken=bytearray(raw);struct.pack_into('<I',broken,16,0)
   bad.write_bytes(broken)
   assert subprocess.run([*RUN,kind,str(bad),str(dest)]).returncode!=0,kind+' accepted overlapping ODEX sections'
   assert not dest.exists()
   if kind=='hotspot':
    dex=Dex(raw);code=dex.code[hotspot_patch.TARGETS[0]][0];count=struct.unpack_from('<I',dex.data,code+12)[0]
    words=struct.unpack_from('<'+'H'*count,dex.data,code+16);check=dex.methods.index(hotspot_patch.CHECK)
    pc=next(p for p,op,_ in dipo_patch.instructions(words) if op==0x71 and words[p+1]==check)
    broken=bytearray(raw);struct.pack_into('<H',broken,base+code+16+pc*2,0x71);bad.write_bytes(broken)
    assert subprocess.run([*RUN,kind,str(bad),str(dest)]).returncode!=0,'hotspot accepted wrong invocation register count'
    assert not dest.exists()
   for n in [0,4,39,100,len(raw)//2]:
    bad=tmp/'bad';bad.write_bytes(raw[:n]); dest=tmp/'badout'
    assert subprocess.run([*RUN,kind,str(bad),str(dest)]).returncode!=0
    assert not dest.exists()
  shapes=shape_regressions(tmp)
  if os.name!='nt':
   for target in (source,tmp):
    st=target.stat()
    assert subprocess.check_output([*RUN,'metadata',str(target)]).decode().strip()==f'{st.st_uid}|{st.st_gid}|{stat.S_IMODE(st.st_mode):o}'
    assert subprocess.check_output([*RUN,'identity',str(target)]).decode().strip()==f'{st.st_dev}:{st.st_ino}'
   link=tmp/'symlink';link.symlink_to(source)
   for mode in ('metadata','identity'):
    result=subprocess.run([*RUN,mode,str(link)],capture_output=True)
    assert result.returncode!=0 and not result.stdout
 assert subprocess.check_output([*RUN,'sha256',str(source)]).decode().strip()==hashlib.sha256(raw).hexdigest()
 print('PASS: five differential fixtures, existing-output protection, 25 truncations, 20 metadata/overflow/layout rejections, invalid hotspot register count, structural identity and SHA')
 print(f'PASS: {shapes} future/unknown shape refusals without output (v3 clobber narrow/wide/late, misaligned/out-of-range branch, payload, unused opcodes in all five kinds) and an oracle-exact harmless variant')
if __name__=='__main__':main()
