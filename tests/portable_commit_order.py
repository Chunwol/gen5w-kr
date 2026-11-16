"""Production startup must commit before the concurrent health reader starts."""
from pathlib import Path
import os,subprocess,tempfile,unittest

class CommitOrder(unittest.TestCase):
 def test_session_health_cannot_race_initial_commit(self):
  source=Path('tools/portable/boot.sh').read_text()
  session=source.index('    op session & child=$!')
  start=source.rfind('    cancelled\n',0,session)
  end=source.index('    sync\n',session)+len('    sync\n')
  body=source[start:end]
  with tempfile.TemporaryDirectory() as temp:
   script=Path(temp)/'run.sh'
   script.write_text(r'''child=; current=fixture; SESSION_READY_SECONDS=90
trap 'touch "$FIXTURE/stop"; [ -z "$child" ] || wait "$child"' EXIT
cancelled() { :; }
deadline() { :; }
within() { :; }
backoff() { echo "$1" > "$FIXTURE/failure"; }
stop_session() { touch "$FIXTURE/stop"; wait "$child"; }
bounded() { :; }
put() { echo "$2" > "$FIXTURE/$1"; }
op() {
 case "$1" in
 commit) [ ! -e "$FIXTURE/reader-lock" ] || return 1; touch "$FIXTURE/committed";;
 session) touch "$FIXTURE/reader-lock"; while [ ! -e "$FIXTURE/stop" ]; do sleep .01; done;;
 session-ready) [ -e "$FIXTURE/reader-lock" ];;
 pause) sleep .01;;
 *) return 1;;
 esac
}
''' + body)
   p=subprocess.run(['mksh',str(script)],env=dict(os.environ,FIXTURE=temp),capture_output=True,text=True,timeout=5)
   self.assertEqual(p.returncode,0,p.stderr)
   self.assertTrue((Path(temp)/'committed').exists())
   self.assertEqual((Path(temp)/'attempt').read_text().strip(),'fixture|healthy')
   self.assertEqual((Path(temp)/'reason').read_text().strip(),'startup-healthy')

if __name__=='__main__': unittest.main()
