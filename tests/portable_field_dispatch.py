"""Combined field USB must verify restored originals before installation."""
from pathlib import Path
import os, subprocess, tempfile

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'tools/portable/recovery-usb/field-dispatch.sh'

def main():
    with tempfile.TemporaryDirectory() as temp:
        root=Path(temp); data=root/'data'; usb=root/'usb'; usb.mkdir()
        recovery=data/'local/gen5w-portable/persistent/recovery'
        recovery.mkdir(parents=True); (recovery/'manifest').write_text('manifest\n')
        (root/'getprop').write_text('#!/bin/sh\ncat "'+str(root/'wrap')+'"\n')
        (root/'getprop').chmod(0o755); (root/'wrap').write_text('')
        for name,body in {
            'NEMESIS-install.sh':'echo install >> calls\n',
            'NEMESIS-recover.sh':'echo recover >> calls\n',
            'recovery-restore.sh':'echo "$*" >> verify-calls\nexit $(cat verify-rc)\n',
        }.items(): (usb/name).write_text(body)
        (usb/'verify-rc').write_text('7')
        text=SOURCE.read_text().replace('/system/bin/sh','/bin/sh').replace('/data/local/',str(data)+'/local/')
        script=usb/'NEMESIS.sh'; script.write_text(text)
        env=dict(os.environ,PATH=str(root)+':'+os.environ['PATH'])
        def run(): return subprocess.run(['sh',str(script)],env=env,capture_output=True,text=True)
        result=run(); assert result.returncode==0, result.stdout
        assert (usb/'calls').read_text().strip()=='recover', 'must recover rather than install after failed verification'
        (usb/'calls').unlink()
        assert (usb/'verify-calls').read_text().strip()=='--verify-only'
        (usb/'verify-rc').write_text('0'); assert run().returncode==0
        assert (usb/'calls').read_text().strip()=='install'
        (usb/'calls').unlink(); (root/'wrap').write_text('owned wrapper')
        assert run().returncode==0
        assert (usb/'calls').read_text().strip()=='recover'
        (usb/'calls').unlink(); (root/'wrap').write_text(''); (recovery/'manifest').unlink()
        assert run().returncode==0
        assert (usb/'calls').read_text().strip()=='install'
        print('PASS field USB: no install on failed restore verification; verified, recovery and clean paths')

if __name__=='__main__': main()
