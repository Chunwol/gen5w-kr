"""Execute the shipped format-list routine against a read-only private V039 image.

CF collection allocation is replaced by recording boundaries; selectors and the
original dictionary helper execute actual ARM code. No OEM bytes are stored.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import struct
from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_CODE
from unicorn.arm_const import *
from audio_native import load_segments

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--stock', required=True, type=Path)
a = p.parse_args()
stock = a.stock.read_bytes()
recipe = json.loads((ROOT/'tools/audio/recipe.json').read_text())
import hashlib
assert hashlib.sha256(stock).hexdigest() == recipe['original_sha256']
spec = importlib.util.spec_from_file_location('audio_build', ROOT/'tools/audio/build.py')
build = importlib.util.module_from_spec(spec); spec.loader.exec_module(build)
own = (ROOT/'.build/audio/formats.elf').read_bytes()
patched = bytearray(stock)
for patch in recipe['patches']:
    data = build.section(own, patch['section'])
    assert len(data) == patch['length']
    at = patch['offset']; patched[at:at+len(data)] = data

def run(base, transport, allocation_failure=False):
    u = Uc(UC_ARCH_ARM, UC_MODE_ARM)
    u.mem_map(base, 0x20000); u.mem_map(0x800000, 0x10000)
    load_segments(u, bytes(patched), base)
    log_delta = struct.unpack_from('<I', stock, 0x3df8)[0]
    u.mem_write(base+0x3cde+log_delta, struct.pack('<I',100))
    u.mem_write(base+0x9ebc, struct.pack('<I', 0x801000))
    u.mem_write(0x802000, struct.pack('<I', 123))
    entries = []; pending = {}; counter = [0]
    for r, value in [(UC_ARM_REG_SP,0x808000),(UC_ARM_REG_LR,0x809001),
                     (UC_ARM_REG_R0,transport),(UC_ARM_REG_R1,0x802000)]:
        u.reg_write(r,value)
    saved = [UC_ARM_REG_R4,UC_ARM_REG_R5,UC_ARM_REG_R6,UC_ARM_REG_R7,UC_ARM_REG_R8]
    for i,r in enumerate(saved): u.reg_write(r, 0x123400+i)
    def hook(uc, address, size, user):
        if address == 0x809000: uc.emu_stop(); return
        if address not in [base+x for x in (0x26c8,0x26d4,0x26e0,0x26ec,0x26a4,0x26b0,0x26bc)]: return
        assert uc.reg_read(UC_ARM_REG_SP)%8 == 0
        r0,r1,r2,r3 = [uc.reg_read(r) for r in (UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3)]
        if address == base+0x26c8:
            assert (r0,r1,r2)==(0,0,0x801000)
            result = 0 if allocation_failure else 0x803000
        elif address == base+0x26ec:
            result=int(r0==r1)
        elif address == base+0x26a4:
            counter[0]+=1; result=0x804000+counter[0]*16
            pending[result]={'ints':[],'role':None}
        elif address == base+0x26b0:
            pending[r0]['ints'].append((r1-base,r2|(r3<<32)));result=0
        elif address == base+0x26bc:
            pending[r0]['role']=r2-base;result=0
        elif address == base+0x26d4:
            assert r0==0x803000 and r1 in pending
            item=pending[r1]
            entries.append((item['ints'][0][1],item['role'],tuple(item['ints']))); result=0
        else:
            assert r0 in pending; del pending[r0]; result=0
        uc.reg_write(UC_ARM_REG_R0,result)
        uc.reg_write(UC_ARM_REG_PC,uc.reg_read(UC_ARM_REG_LR))
    u.hook_add(UC_HOOK_CODE,hook)
    u.emu_start(base+0x3e1d,0,count=10000)
    assert u.reg_read(UC_ARM_REG_PC)==0x809000
    assert u.reg_read(UC_ARM_REG_SP)==0x808000 and not pending
    for i,r in enumerate(saved): assert u.reg_read(r)==0x123400+i
    status = struct.unpack('<i',u.mem_read(0x802000,4))[0]
    if allocation_failure:
        assert u.reg_read(UC_ARM_REG_R0)==0 and status==-6728
    else:
        assert status==0 and u.reg_read(UC_ARM_REG_R0)==0x803000
    return entries

for base in (0x100000,0x230000):
    wired=run(base,0); wireless=run(base,1)
    assert len(wired)==8
    assert [(e[0],e[1]) for e in wireless[:8]]==[(e[0],e[1]) for e in wired]
    by_pair={(e[0],e[1]): dict(e[2]) for e in wireless}
    assert by_pair[(100,0x73f4)][0x746c]==0x70000054 and by_pair[(100,0x73f4)][0x7488]==0x70c08854
    assert by_pair[(100,0x740c)][0x7488]==0x00c08800
    assert by_pair[(100,0x744c)][0x7488]==0x70000400
    assert by_pair[(101,0x745c)][0x7488]==0x40000400
    assert len(wireless)==9 and wireless[8][0:2]==(102,0x740c)
    assert [v for key,v in wireless[8][2]]==[102,0xc08800]
    assert run(base,2)==wired and run(base,999)==wired
    run(base,1,True)
print('PASS real V039 advertised dictionaries: existing 8 wired preserved, wireless AAC/Opus48k/MainHigh, ASLR, ABI, allocation failure')
