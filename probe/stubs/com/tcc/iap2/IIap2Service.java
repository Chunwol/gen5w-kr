package com.tcc.iap2;

import android.os.IBinder;
import android.os.IInterface;
import android.os.RemoteException;

/** Only the calls we use. */
public interface IIap2Service extends IInterface {
    boolean Iap2SvcInit(IIap2Listener listener, Iap2ListenerInfo info) throws RemoteException;
    boolean Iap2SvcStopMain(IIap2Listener listener) throws RemoteException;
    int Iap2SvcGetState() throws RemoteException;
    boolean Iap2SvcIsIap2Connected() throws RemoteException;
    boolean Iap2SvcTransportReadDone(byte[] data, int length) throws RemoteException;
    boolean Iap2SvcWiFiRequestInformation() throws RemoteException;
    int Iap2SvcGetRouteGuidanceRegisteredComponentCount() throws RemoteException;
    int Iap2SvcGetRouteGuidanceComponentNameIdList(int[] ids, String[] names) throws RemoteException;
    boolean Iap2SvcStartRouteGuidanceUpdate(String[] names, boolean sourceName, boolean sourceSupport) throws RemoteException;

    abstract class Stub extends android.os.Binder implements IIap2Service {
        public static IIap2Service asInterface(IBinder b) { throw new RuntimeException("stub"); }
    }
}
