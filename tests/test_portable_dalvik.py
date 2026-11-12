"""Host signature checks; ARM/actual V039 VM fixtures are separate and explicit."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class DalvikHostValidation(unittest.TestCase):
    def test_signature_rejection_and_reference_widening(self):
        javac = shutil.which("javac")
        java = shutil.which("java")
        if os.environ.get("JAVA_HOME"):
            suffix = ".exe" if os.name == "nt" else ""
            javac = str(Path(os.environ["JAVA_HOME"]) / "bin" / ("javac" + suffix))
            java = str(Path(os.environ["JAVA_HOME"]) / "bin" / ("java" + suffix))
        if not javac or not java: self.skipTest("JDK required for actual Java validation")
        with tempfile.TemporaryDirectory() as output:
            subprocess.run([javac, "--release", "8", "-Xlint:-options", "-d", output,
                str(ROOT / "tools/portable/dalvik/src/kr/gen5w/portable/Hook.java"),
                str(ROOT / "tests/portable_dalvik/HookValidationTest.java")], check=True, capture_output=True)
            completed = subprocess.run([java, "-cp", output, "HookValidationTest"], check=True, capture_output=True, text=True)
            self.assertIn("PASS host signature validation widening invalid handle", completed.stdout)

if __name__ == "__main__": unittest.main()
