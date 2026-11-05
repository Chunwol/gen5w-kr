package com.broadcom.bt.hfdevice.hfbtcm;

import android.bluetooth.BluetoothDevice;

/** Compile-only declaration from the V039 shared Bluetooth library. */
public class HfDeviceStatusListener {
    public void onBTCMDeviceConnectionEventChanged(BluetoothDevice device, int event, boolean[] profiles) { }
    public void onBTCMSppStatusChanged(BluetoothDevice device, int status) { }
    public void onBTCMSppInPutStreamChanged(BluetoothDevice device, byte[] buffer, int length) { }
}
