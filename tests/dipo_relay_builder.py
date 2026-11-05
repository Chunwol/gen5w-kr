"""Public invariants for the private exact-V039 DiPO relay builder."""
from pathlib import Path
import importlib.util
import unittest

ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "tools/v039-relay/build_dipo_relay.py"
BRIDGE = ROOT / "tools/v039-relay/dipo-src/kr/gen5w/dipo/RelayBridge.java"


class DiPORelayBuilderTest(unittest.TestCase):
    def test_builder_is_exact_hash_gated_and_patches_all_reviewed_edges(self):
        text = BUILDER.read_text(encoding="utf-8")
        self.assertIn("0859b0a5d87320935f2a06ac70baa7e3e30498b29bdafccd6c8ccc51343d5f3f", text)
        self.assertIn("950b5575603e50aea9894b3568e80e21b3a354a6c812c3991010ab3e0cb9fe90", text)
        for hook in ("sessionCreated", "sessionStarted", "sessionFinalized", "fromCarPlay",
                     "RelayBridge;->bind", "RelayBridge;->connected", "RelayBridge;->disconnected"):
            self.assertIn(hook, text)

    def test_handover_request_is_emitted_before_waiting_for_component_five(self):
        text = BRIDGE.read_text(encoding="utf-8")
        notify = text.index("if (requestNow) notifyHost(HANDOVER_REQUESTED);")
        waiting_return = text.index("if (!sendNow) return;", notify)
        self.assertLess(notify, waiting_return)
        self.assertIn("MAX_PENDING = 64", text)
        self.assertIn("new Intent(action).setPackage(HOST_PACKAGE)", text)


if __name__ == "__main__":
    unittest.main()
