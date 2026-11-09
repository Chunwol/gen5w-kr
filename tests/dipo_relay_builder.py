"""Public invariants for the private exact-V039 DiPO relay builder."""
from pathlib import Path
import importlib.util
import unittest
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "tools/v039-relay/build_dipo_relay.py"
BRIDGE = ROOT / "tools/v039-relay/dipo-src/kr/gen5w/dipo/RelayBridge.java"


class DiPORelayBuilderTest(unittest.TestCase):
    def test_reconnect_patch_is_local_and_rejects_ambiguous_inputs(self):
        spec = importlib.util.spec_from_file_location('dipo_builder', BUILDER)
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        original = '''.method public final a(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
    .registers 11
    invoke-virtual {v1}, Lcom/daudio/app/dipo/e/b;->K()Ljava/lang/String;

    move-result-object v1

    invoke-virtual {v1}, Ljava/lang/String;->toUpperCase()Ljava/lang/String;

    move-result-object v1

    invoke-virtual {p1, v1}, Ljava/lang/String;->equalsIgnoreCase(Ljava/lang/String;)Z
    :goto_62
    return-void
.end method
'''
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'q.smali'; path.write_text(original)
            self.assertTrue(hasattr(module, 'patch_reconnect'), 'missing scoped reconnect hook')
            module.patch_reconnect(path)
            text = path.read_text()
            self.assertIn('if-eqz v1, :goto_62', text)
            self.assertIn('RelayBridge;->reconnectAddress', text)
            self.assertIn('invoke-virtual {v1, p1}', text)
            with self.assertRaises(ValueError): module.patch_reconnect(path)
            path.write_text(original+original)
            with self.assertRaises(ValueError): module.patch_reconnect(path)

    def test_builder_is_exact_hash_gated_and_patches_all_reviewed_edges(self):
        text = BUILDER.read_text(encoding="utf-8")
        self.assertIn("0859b0a5d87320935f2a06ac70baa7e3e30498b29bdafccd6c8ccc51343d5f3f", text)
        self.assertIn("950b5575603e50aea9894b3568e80e21b3a354a6c812c3991010ab3e0cb9fe90", text)
        for hook in ("sessionCreated", "sessionStarted", "sessionFinalized", "fromCarPlay",
                     "RelayBridge;->bind", "RelayBridge;->connected", "RelayBridge;->disconnected"):
            self.assertIn(hook, text)

    def test_handover_request_is_emitted_before_waiting_for_component_five(self):
        text = BRIDGE.read_text(encoding="utf-8")
        notify = text.index("if (requestNow) notifySession(owner, token, HANDOVER_REQUESTED);")
        waiting_return = text.index("if (!sendNow) return;", notify)
        self.assertLess(notify, waiting_return)
        self.assertIn("MAX_PENDING = 64", text)
        self.assertIn("new Intent(action).setPackage(HOST_PACKAGE)", text)


if __name__ == "__main__":
    unittest.main()
