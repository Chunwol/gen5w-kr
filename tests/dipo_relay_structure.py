"""Private V039 structure audit for the blocked DiPO component-5 hook.

This test records only method identities and recipe invariants. It never emits
OEM code or embeds private ODEX bytes in the repository.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/iap2'))
from control_patch import Dex
from dipo_patch import make_recipe, instructions

V039_SHA256 = '950b5575603e50aea9894b3568e80e21b3a354a6c812c3991010ab3e0cb9fe90'
CARPLAY = 'Lcom/daudio/app/dipo/telechips/CarPlayService;->'
IAP2 = 'Lcom/tcc/iap2/IIap2Service;->'
CALL_KEY_METHOD = 'Lcom/daudio/app/dipo/service/DipoService;->i(II)V'


def invoke_refs(dex, method):
    offset, _, _ = dex.code[method]
    count = struct.unpack_from('<I', dex.data, offset + 12)[0]
    words = struct.unpack_from('<' + 'H' * count, dex.data, offset + 16)
    refs = []
    for pc, opcode, _ in instructions(words):
        if opcode in (0x6e, 0x6f, 0x70, 0x71, 0x72, 0x74, 0x75, 0x76, 0x77, 0x78):
            refs.append(dex.methods[words[pc + 1]])
    return refs


def code_body(dex, method):
    offset, _, _ = dex.code[method]
    count = struct.unpack_from('<I', dex.data, offset + 12)[0]
    return dex.data[offset:offset + 16 + count * 2]


def audit_private_v039(path):
    raw = path.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == V039_SHA256, 'input is not reviewed exact V039 DiPO ODEX'
    original = Dex(raw)
    native_send = CARPLAY + 'TccCarPlayNativeMethod_iAPSendMessage([BI)I'
    send_wrapper = CARPLAY + 'iAPSendMessage([BI)Lcom/daudio/app/dipo/telechips/CarPlayReturn;'
    receive_callback = CARPLAY + 'oniAPSendMessage([BI)V'
    assert native_send in original.methods and original.code[native_send][0] == 0, \
        'native outbound boundary changed'
    assert receive_callback in original.code, 'native inbound callback boundary changed'
    assert native_send in invoke_refs(original, send_wrapper), 'send wrapper no longer reaches native outbound boundary'

    service_api = [name for name in original.methods if name.startswith(IAP2)]
    # This table contains only IIap2Service methods referenced by DiPO. The
    # exact Iap2ServerApp is audited separately and does expose
    # Iap2SvcTransportReadDone([BI)Z for component-4 input.
    raw_channel_api = [name for name in service_api if any(token in name.lower()
        for token in ('transport', 'sendraw', 'sendcomponent', 'channelwrite', 'socket'))]
    assert not raw_channel_api, 'unexpected raw component channel API; re-audit before generating adapter'

    recipe, changed = make_recipe(raw)
    profile = json.loads((ROOT / 'tools/iap2/dipo-v039.json').read_text(encoding='utf-8'))
    assert recipe == profile, 'V039 deterministic recipe differs from checked-in profile'
    assert len(changed) == len(raw)
    patched = Dex(changed)
    assert patched.methods == original.methods
    assert patched.fields == original.fields
    assert patched.strings == original.strings
    for method, (offset, _, _) in original.code.items():
        if not offset:
            continue
        if method != CALL_KEY_METHOD:
            assert code_body(patched, method) == code_body(original, method), \
                'non-call-key method changed: ' + method

    # Current profile has no component-5 call edge, so this is a boundary audit,
    # not evidence that the relay adapter is complete.
    assert not any('component5' in name.lower() or 'component-5' in name.lower()
        for name in patched.methods)
    return recipe


class DiPORelayStructureTest(unittest.TestCase):
    def test_profile_is_explicitly_incomplete_without_raw_channel_write(self):
        recipe = json.loads((ROOT / 'tools/iap2/dipo-v039.json').read_text(encoding='utf-8'))
        self.assertEqual(recipe['original_sha256'], V039_SHA256)
        self.assertEqual(recipe['id'], 'dipo-call-key-fallback-1')
        self.assertNotIn('component5', recipe['id'].lower())


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--stock-v039', type=Path)
    args = parser.parse_args()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(DiPORelayStructureTest)
    result = unittest.TextTestRunner().run(suite)
    if not result.wasSuccessful():
        sys.exit(1)
    if args.stock_v039:
        audit_private_v039(args.stock_v039)
        print('PASS exact V039 DiPO boundary/scope audit; component-5 adapter remains blocked')
