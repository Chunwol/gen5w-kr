"""Exercise the production boot preflight gate without Android mutations."""
import pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class Retry(unittest.TestCase):
 def run_gate(self,mode):
  source=(ROOT/'tools/portable/boot.sh').read_text()
  start=source.index('        preflight_result=0\n')
  end=source.index('        if [ "$(cat "$STATE/reconcile")"',start)
  section=source[start:end]
  with tempfile.TemporaryDirectory() as tmp:
   script=pathlib.Path(tmp)/'gate.sh'
   script.write_text('#!/usr/bin/mksh\nn=0; budget=0; is_enabled=1\nstage() { echo "stage:$*"; }\nbackoff() { echo "backoff:$*"; }\ndeadline() { budget=$1; }\nwithin() { [ "$budget" -gt 0 ]; }\nenabled() { [ "$is_enabled" = 1 ]; }\nop() {\n case "$1" in\n runtime-preflight)\n  n=$((n+1)); echo "call:$n"\n  case "$MODE" in\n   transient) [ "$n" -gt 1 ] && return 0; return 75;;\n   permanent) return 75;;\n   fatal) return 1;;\n   unsupported) return 77;;\n   cancelled) is_enabled=0; return 75;;\n  esac;;\n pause) budget=$((budget-1));;\n *) echo "UNEXPECTED_MUTATION:$*"; exit 99;;\n esac\n}\n'+section+'\necho GATE_PASSED\n')
   result=subprocess.run(['mksh',str(script)],env={**__import__('os').environ,'MODE':mode},text=True,capture_output=True,timeout=5)
   self.assertNotIn('UNEXPECTED_MUTATION',result.stdout)
   return result
 def test_transient(self):
  r=self.run_gate('transient');self.assertEqual(r.returncode,0,r.stdout);self.assertIn('call:2',r.stdout)
 def test_permanent_bounded(self):
  r=self.run_gate('permanent');self.assertNotEqual(r.returncode,0);self.assertLessEqual(r.stdout.count('call:'),32)
 def test_fatal_not_retried(self):
  r=self.run_gate('fatal');self.assertNotEqual(r.returncode,0);self.assertEqual(r.stdout.count('call:'),1)
 def test_unsupported_retains_fallback(self):
  r=self.run_gate('unsupported');self.assertEqual(r.returncode,0);self.assertEqual(r.stdout.count('call:'),1)
 def test_cancelled(self):
  r=self.run_gate('cancelled');self.assertEqual(r.returncode,0,r.stdout);self.assertNotIn('GATE_PASSED',r.stdout)
if __name__=='__main__':unittest.main()
