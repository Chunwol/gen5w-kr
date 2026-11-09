"""Private exact-V039 GPM delta builder; never distribute OEM working outputs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import sys
import zlib

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
sys.path.insert(0,str(HERE));sys.path.insert(0,str(ROOT/'tools/iap2'))
from build_dipo_relay import run, sha256
from gpm_patch import make_recipe, INIT
from control_patch import Dex
from dipo_patch import instructions

APK_SHA='8e7e9805f237f0690124af4b797466d716df12b55df065142a4f426a567f6bde'
ODEX_SHA='caee2cdf77a101d9b103d850658c85c4ed922e863d6566166b87037a11fd55c8'
GUARD='Lkr/gen5w/gpm/GpmUsbGuard;->startService(Landroid/content/Context;Landroid/content/Intent;)Landroid/content/ComponentName;'
INVENTORY={
 'com/google/android/projection/service/StartReceiver.smali|public onReceive(Landroid/content/Context;Landroid/content/Intent;)V':2,
 'com/google/android/projection/protocol/WirelessExplorer.smali|private sendStartServiceWireless()V':1,
}
START='->startService(Landroid/content/Intent;)Landroid/content/ComponentName;'
CALL=re.compile(r'invoke-virtual (\{[vp]\d+, [vp]\d+\}), Landroid/content/Context;'+re.escape(START))

def validate_inputs(apk:Path,odex:Path)->None:
    if sha256(apk)!=APK_SHA or sha256(odex)!=ODEX_SHA:
        raise ValueError('unreviewed GPM APK/ODEX pair')

def patch_service_starts(tree:Path)->dict[str,int]:
    edits={};inventory={}
    for path in tree.rglob('*.smali'):
        text=path.read_text(encoding='utf-8');count=0
        for method in re.findall(r'(?ms)^\.method .*?^\.end method',text):
            n=method.count(START)
            if not n:continue
            key=path.relative_to(tree).as_posix()+'|'+method.splitlines()[0][8:]
            if key in inventory or len(CALL.findall(method))!=n:raise ValueError('unreviewed GPM invocation')
            inventory[key]=n;count+=n
        if text.count(START)!=count:raise ValueError('unscoped GPM invocation')
        if count:edits[path]=CALL.sub(lambda m:'invoke-static '+m.group(1)+', '+GUARD,text)
    if inventory!=INVENTORY:raise ValueError('GPM service-start inventory drift')
    for path,text in edits.items():path.write_text(text,encoding='utf-8',newline='\n')
    return inventory

def refs(dex,method):
    off=dex.code[method][0];n=struct.unpack_from('<I',dex.data,off+12)[0]
    words=struct.unpack_from('<'+'H'*n,dex.data,off+16)
    return [dex.methods[words[pc+1]] for pc,op,_ in instructions(words) if op in (0x6e,0x6f,0x70,0x71,0x72,0x74,0x75,0x76,0x77,0x78)]

def audit_delta(stock:Path,delta:Path)->None:
    import mkdelta
    raw=stock.read_bytes();d=delta.read_bytes()
    assert hashlib.sha256(raw).hexdigest()==ODEX_SHA
    assert d[:4]==b'LPD1' and hashlib.md5(raw).digest()==d[8:24]
    rebuilt=mkdelta.apply(raw,d)
    assert len(rebuilt)==struct.unpack_from('<I',d,24)[0] and hashlib.md5(rebuilt).digest()==d[28:44]
    assert hashlib.sha1(rebuilt[32:]).digest()==rebuilt[12:32]
    assert zlib.adler32(rebuilt[12:])&0xffffffff==struct.unpack_from('<I',rebuilt,8)[0]
    dex=Dex(rebuilt);original=Dex(raw)
    assert set(original.code).issubset(dex.code)
    assert set(dex.class_names)-set(original.class_names)=={
        'Lkr/gen5w/gpm/GpmUsbGuard;', 'Lkr/gen5w/diag/SafeDiagnostic;',
        'Lkr/gen5w/diag/SafeDiagnostic$1;', 'Lkr/gen5w/diag/SafeDiagnostic$Sink;',
        'Lkr/gen5w/diag/SafeDiagnostic$Stamp;'}
    seen=0
    for key,count in INVENTORY.items():
        file,method=key.split('|');caller='L'+file[:-6]+';->'+method.split(' ')[-1]
        calls=refs(dex,caller);assert calls.count(GUARD)==count;seen+=count
    assert seen==3
    for method,(off,_,_) in original.code.items():
        if not off:assert dex.code[method][0]==0
    # Existing HUD recipe must already be applied, not lost in guard assembly.
    off=dex.code[INIT][0];n=struct.unpack_from('<I',dex.data,off+12)[0]
    words=struct.unpack_from('<'+'H'*n,dex.data,off+16);found=False
    for pc,op,_ in instructions(words):
        if op==0x71 and dex.methods[words[pc+1]].endswith(('->bJ()I','->bG()I')):
            if words[pc+4]&255==0x13 and words[pc+5]==999:
                assert words[pc+6:pc+8]==(0,0);found=True
    assert found,'HUD allocation gate changed'
    print('PASS exact GPM delta/guard/native/HUD sha256='+hashlib.sha256(rebuilt).hexdigest())

def main():
    p=argparse.ArgumentParser()
    for name in ('stock-apk','stock-odex','framework','baksmali','smali','work','delta-out'):p.add_argument('--'+name,type=Path,required=True)
    a=p.parse_args();validate_inputs(a.stock_apk,a.stock_odex)
    work=a.work.resolve();work.mkdir(parents=True,exist_ok=True)
    tree=work/'stock-smali';classes=work/'classes';adapter=work/'adapter-smali';out=work/'adapter-dex'
    if any(x.exists() for x in (tree,classes,adapter,out)):raise ValueError('use a fresh private work directory')
    classes.mkdir();out.mkdir()
    recipe,hud=make_recipe(a.stock_odex.read_bytes())
    if recipe!=json.loads((ROOT/'tools/iap2/gpm-v039.json').read_text()):raise ValueError('HUD recipe drift')
    hudpath=work/'gpm-hud.odex';hudpath.write_bytes(hud)
    run('java','-jar',a.baksmali,'deodex','-a','18','-j','1','-d',a.framework,'-o',tree,hudpath)
    patch_service_starts(tree)
    sdk=Path(os.environ.get('ANDROID_SDK') or os.environ.get('ANDROID_HOME') or Path.home()/'AppData/Local/Android/Sdk')
    android=sdk/'platforms/android-36/android.jar';d8=sdk/'build-tools/36.0.0'/('d8.bat' if os.name=='nt' else 'd8')
    source=HERE/'gpm-src/kr/gen5w/gpm/GpmUsbGuard.java'
    run('javac','-encoding','UTF-8','-Xlint:-options','--release','8','-cp',android,'-sourcepath',os.pathsep.join((str(HERE/'gpm-src'),str(ROOT/'shared/src'))),'-d',classes,source)
    jar=work/'guard.jar';run('jar','cf',jar,'-C',classes,'kr')
    run(d8,'--min-api','18','--release','--lib',android,'--output',out,jar)
    run('java','-jar',a.baksmali,'disassemble','-a','18','-j','1','-o',adapter,out/'classes.dex')
    shutil.copytree(adapter/'kr',tree/'kr')
    target=work/'classes.dex';run('java','-jar',a.smali,'assemble','-a','18','-j','1','-o',target,tree)
    run(sys.executable,HERE/'mkdelta.py',a.stock_odex,target,a.delta_out)
    audit_delta(a.stock_odex,a.delta_out)

if __name__=='__main__':main()
