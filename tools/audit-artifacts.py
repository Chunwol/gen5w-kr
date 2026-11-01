"""Check distribution contents without proprietary/private test inputs."""
import configparser
from io import BytesIO
from pathlib import Path
import struct
import sys
import zipfile

def classes(data):
    assert data[:4]==b'dex\n', 'invalid app dex'
    count,off=struct.unpack_from('<II',data,56);strings=[]
    for i in range(count):
        pos=struct.unpack_from('<I',data,off+i*4)[0]
        while data[pos]&128:pos+=1
        pos+=1;strings.append(data[pos:data.index(0,pos)].decode('utf-8',errors='replace'))
    count,off=struct.unpack_from('<II',data,64)
    types=[strings[struct.unpack_from('<I',data,off+i*4)[0]] for i in range(count)]
    count,off=struct.unpack_from('<II',data,96)
    assert count>0, 'empty app dex'
    assert all(types[struct.unpack_from('<I',data,off+i*32)[0]].startswith('Lkr/gen5w/') for i in range(count)), 'foreign implementation in dex'

def audit(path):
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None, 'corrupt ZIP'
        meta=configparser.ConfigParser(interpolation=None)
        meta.read_string(z.read('NEMESIS.data').decode())
        assert meta['nemesis']['id']==path.stem, 'package identity differs'
        assert z.read('LICENSE').startswith(b' '), 'license missing'
        assert len(z.read('BUILD-REVISION').strip())==40, 'source revision missing'
        assert 'SOURCE.md' in z.namelist(), 'source notice missing'
        for name in z.namelist():
            p=Path(name);parts=set(p.parts)
            assert not parts.intersection({'src','stubs','private','.build','__pycache__'}), 'development/private content in ZIP'
            assert p.suffix not in {'.odex','.so','.java','.class','.keystore','.pass','.img','.ext4'}, 'forbidden artifact '+name
            data=z.read(name)
            if p.suffix=='.dex':classes(data)
            if p.suffix=='.apk':
                assert p.name in {'gen5w-core.apk','gen5w-probe.apk'}, 'unexpected APK'
                with zipfile.ZipFile(BytesIO(data)) as apk:classes(apk.read('classes.dex'))
            if data[:4]==b'\x7fELF':
                assert data[4]==1 and struct.unpack_from('<H',data,18)[0]==40, 'non-ARM shipped binary'
                offset=struct.unpack_from('<I',data,28)[0];size,count=struct.unpack_from('<HH',data,42)
                assert all(struct.unpack_from('<I',data,offset+i*size)[0] not in (2,3) for i in range(count)), 'dynamic ABI dependency'
    print('AUDITED',path.name)

def audit_dongle(path):
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None, 'corrupt dongle ZIP'
        names = set(z.namelist())
        modules = {'ath', 'ath9k_common', 'ath9k_htc', 'ath9k_hw', 'ccm',
                   'ctr', 'gen5w-average', 'mac80211', 'seqiv'}
        required = {'files/libhardware_legacy.so', 'files/firmware/htc_7010.fw',
                    'files/firmware/htc_9271.fw', 'bin/gen5w-dongle-load',
                    'scripts/service.sh', 'scripts/pre.sh', 'scripts/preun.sh'}
        required.update('files/modules/'+name+'.ko' for name in modules)
        assert required <= names, 'missing dongle payload: '+str(required-names)
        assert not any('libcutils' in n for n in names), 'link-only stub shipped'
        for name in required:
            assert len(z.read(name)) > 0, 'empty dongle payload '+name
            if name.endswith(('.ko', '.so')):
                data = z.read(name)
                assert data[:5] == b'\x7fELF\x01', 'non-ELF32 payload '+name
                assert struct.unpack_from('<H', data, 18)[0] == 40, 'non-ARM payload '+name
        # Resolve DT_NEEDED through ELF32 PT_LOAD/PT_DYNAMIC, without host readelf.
        data = z.read('files/libhardware_legacy.so')
        offset = struct.unpack_from('<I', data, 28)[0]
        size, count = struct.unpack_from('<HH', data, 42)
        headers = [struct.unpack_from('<IIIIIIII', data, offset+i*size) for i in range(count)]
        dynamic = next(h for h in headers if h[0] == 2)
        entries = []
        for pos in range(dynamic[1], dynamic[1]+dynamic[4], 8):
            tag, value = struct.unpack_from('<II', data, pos)
            if tag == 0: break
            entries.append((tag, value))
        address = next(v for t, v in entries if t == 5)
        segment = next(h for h in headers if h[0] == 1 and h[2] <= address < h[2]+h[4])
        strings = segment[1]+address-segment[2]
        needed = {data[strings+v:data.index(0, strings+v)].decode('ascii')
                  for t, v in entries if t == 1}
        assert needed == {'libcutils.so','liblog.so','libdl.so','libc.so'}, str(needed)
    print('AUDITED dongle payload and HAL dynamic dependencies')

root=Path(sys.argv[1] if len(sys.argv)>1 else 'dist')
packages=[p for p in sorted(root.glob('gen5w.kr.*.zip')) if p.name != 'gen5w.kr.dongle.zip']
assert len(packages)==7, f'expected 7 packages, got {len(packages)}: {[p.name for p in packages]}'
for package in packages:audit(package)
audit_dongle(root/'gen5w.kr.dongle.zip')
assert not (root/'gen5w.kr.consent.zip').exists(), 'local notice-disabling package in distribution'
assert not (root/'gen5w-kr-skip-consent.zip').exists(), 'local edition in distribution'
# Only car editions are built; none may carry a boot-critical patch package.
for name in ['usb-integrated.zip', 'gen5w-kr-standard.zip', 'gen5w-kr-dongle.zip']:
    assert not (root/name).exists(), 'lab-only edition in distribution: ' + name
for variant,expected in [('safe',{'wireless','audio','bridge','core'}),
                         ('safe-wireless',{'wireless','audio','bridge','core'}),('check',set())]:
    with zipfile.ZipFile(root/('gen5w-kr-'+variant+'.zip')) as z:
        assert z.testzip() is None
        shipped={n[len('packages/gen5w.kr.'):-4] for n in z.namelist() if n.startswith('packages/') and n.endswith('.zip')}
        assert shipped==expected, (variant, shipped)
        assert z.read('GEN5W-VARIANT').decode().strip()==variant
        assert z.read('GEN5W-BACKEND') == b'builtin
'
        assert b'type=open' in z.read('NEMESIS.data'), 'automatic insertion installation'
        assert all(n in z.namelist() for n in ['LICENSE','NOTICE.md','SOURCE.md','BUILD-REVISION','report.sh','check.sh','docs/beginner-guide.md'])
        assert not any(n.endswith(('gen5w.kr.consent.zip','gen5w.kr.hotspot.zip','gen5w.kr.notice.zip','gen5w.kr.dongle.zip')) for n in z.namelist())
        assert not any(n.endswith('libhardware_legacy.so') or n.endswith('.ko') for n in z.namelist()), 'dongle payload in car edition'
        assert z.read('BUILD-REVISION')==zipfile.ZipFile(root/'gen5w.kr.core.zip').read('BUILD-REVISION')
print('AUDITED car editions: no boot-critical patch packages')
with zipfile.ZipFile(root/'gen5w-kr-source.zip') as z:
    assert all('gen5w-kr-source/'+p in z.namelist() for p in ['LICENSE','tools/build-all.sh','app/src/kr/gen5w/core/CoreService.java'])
    assert not any(Path(n).suffix in {'.odex','.so','.apk','.dex','.img','.keystore','.pass'} for n in z.namelist()), 'private/binary source content'
    assert not any('/consent-skip/' in n for n in z.namelist()), 'local notice-disabling source in public archive'
print('AUDITED car editions and corresponding source; local and lab editions excluded')
