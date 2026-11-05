package com.broadcom.bt.hfdevice.hfbtcm;

import android.bluetooth.BluetoothDevice;
import android.content.Context;

/** Compile-only declaration from the V039 shared Bluetooth library. */
public class HfDeviceBTCMManager {
    public interface BTCMServiceListener {
        void onBTCMServiceConnected();
        void onBTCMServiceDisconnected();
    }

    public static HfDeviceBTCMManager getLocalBTCMService(Context context, BTCMServiceListener listener) {
        throw new RuntimeException("stub");
    }
    public void registerHfDeviceStatusListener(HfDeviceStatusListener listener) { }
    public void unregisterHfDeviceStatusListener(HfDeviceStatusListener listener) { }
    public BluetoothDevice IbtcmGetHfpConnectedDevice() { return null; }
    public boolean IbtcmIsSppConnectedDevice(String address) { return false; }
    public boolean IbtcmSppConnect(String address) { return false; }
    public boolean IbtcmSppOutPutStreamWrite(String address, byte[] buffer) { return false; }
}
