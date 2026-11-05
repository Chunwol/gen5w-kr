from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'tools/v039-relay/src/kr/gen5w/wireless/V039BtRelayAdapter.java'


class V039BtRelayAdapterStructureTest(unittest.TestCase):
    def test_uses_reviewed_oem_btcm_and_iap2_boundaries(self):
        text = SOURCE.read_text(encoding='utf-8')
        for token in (
            'HfDeviceBTCMManager.getLocalBTCMService',
            'IbtcmSppConnect',
            'IbtcmSppOutPutStreamWrite',
            'Iap2SvcTransportReadDone',
            'com.remote.service.IAP2SERVICE',
            'NOTI_BT_TRANSPORT_DATA = 80',
        ):
            self.assertIn(token, text)
        self.assertNotIn('BluetoothSocket', text)
        self.assertNotIn('createRfcommSocket', text)

    def test_component4_adapter_cannot_claim_blocked_component5(self):
        text = SOURCE.read_text(encoding='utf-8')
        self.assertIn('COMPONENT_BT_TRANSPORT = 4', text)
        self.assertNotIn('component == 5', text)
        self.assertNotIn('component != 5', text)


if __name__ == '__main__':
    unittest.main()
