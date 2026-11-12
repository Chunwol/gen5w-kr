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

    def load(self):
        spec = importlib.util.spec_from_file_location('dipo_builder', BUILDER)
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        return module

    LISTENER = """.class final Lcom/daudio/app/dipo/e/g;
.super Lcom/tcc/iap2/IIap2Listener$Stub;

.field private synthetic mM:Lcom/daudio/app/dipo/e/a;

.method public final connected(ILjava/lang/String;)V
    .registers 6

    const/4 v1, 0x1

    if-nez p2, :cond_11

    :cond_11
    if-ne p1, v1, :cond_51

    invoke-static {v0, v1}, Lcom/daudio/app/dipo/e/b;->a(Lcom/daudio/app/dipo/e/b;Z)Z

    :cond_51
    return-void
.end method

.method public final disconnected(I)V
    .registers 5

    return-void
.end method

.method public final notify(IIILcom/tcc/iap2/Iap2NotiMsg;)V
    .registers 8

    return-void
.end method
"""

    FEATURE = """.method public final isSupportWirelessCarPlay()Z
    .registers 3

    const/4 v0, 0x0

    const-string v1, "com.hkmc.software.connectivity.carplay_wireless"

    invoke-static {v1}, Lcom/hkmc/Feature;->hasFeature(Ljava/lang/String;)Z

    move-result v1

    if-nez v1, :cond_11

    iget-object v1, p0, Lcom/daudio/app/dipo/i/e;->nP:Ljava/lang/Boolean;

    invoke-virtual {v1}, Ljava/lang/Boolean;->booleanValue()Z

    move-result v1

    if-eqz v1, :cond_12

    :cond_11
    const/4 v0, 0x1

    :cond_12
    return v0
.end method
"""

    def test_stock_listener_hooks_sit_before_the_component_one_gate(self):
        module = self.load()
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'g.smali'; path.write_text(self.LISTENER)
            module.patch_stock_listener(path)
            text = path.read_text()
            connected = text[text.index('.method public final connected'):]
            self.assertLess(connected.index('RelayBridge;->listenerComponent(I)I'), connected.index('if-ne p1, v1, :cond_51'))
            self.assertIn('move-result p1', connected)
            self.assertIn('if-gez p1, :gen5w_listener_stock', connected)
            notify_on = connected[:connected.index(chr(10) + '    :gen5w_listener_stock')]
            self.assertIn('invoke-static {v0, v1}, Lcom/daudio/app/dipo/e/b;->a(Lcom/daudio/app/dipo/e/b;Z)Z', notify_on)
            self.assertIn('RelayBridge;->ignoreListenerDisconnect(I)Z', text)
            self.assertIn('RelayBridge;->dropListenerNotify(I)Z', text)
            with self.assertRaises(ValueError): module.patch_stock_listener(path)
            path.write_text(self.LISTENER.replace('if-ne p1, v1, :cond_51', 'if-eq p1, v1, :cond_51'))
            with self.assertRaises(ValueError): module.patch_stock_listener(path)

    def test_wireless_feature_is_off_inside_dipo_only(self):
        module = self.load()
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'e.smali'; path.write_text('.class public final Lcom/daudio/app/dipo/i/e;\n\n' + self.FEATURE)
            module.patch_wireless_feature(path)
            text = path.read_text()
            body = text[text.index('isSupportWirelessCarPlay()Z'):text.index('.end method')]
            self.assertNotIn('hasFeature', body)
            self.assertIn('const/4 v0, 0x0', body); self.assertIn('return v0', body)
            with self.assertRaises(ValueError): module.patch_wireless_feature(path)

    def test_builder_is_exact_hash_gated_and_patches_all_reviewed_edges(self):
        text = BUILDER.read_text(encoding="utf-8")
        self.assertIn("0859b0a5d87320935f2a06ac70baa7e3e30498b29bdafccd6c8ccc51343d5f3f", text)
        self.assertIn("950b5575603e50aea9894b3568e80e21b3a354a6c812c3991010ab3e0cb9fe90", text)
        for hook in ("sessionCreated", "sessionStarted", "sessionFinalized", "fromCarPlay",
                     "RelayBridge;->bind", "RelayBridge;->connected", "RelayBridge;->disconnected",
                     "patch_stock_listener(", "patch_wireless_feature("):
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
