package com.tcc.iap2;

import android.os.IInterface;
import android.os.RemoteException;

public interface IIap2Listener extends IInterface {
    void connected(int type, String name) throws RemoteException;
    void disconnected(int type) throws RemoteException;
    void notify(int what, int arg1, int arg2, Iap2NotiMsg msg) throws RemoteException;

    abstract class Stub extends android.os.Binder implements IIap2Listener {
        public Stub() { throw new RuntimeException("stub"); }
        public android.os.IBinder asBinder() { throw new RuntimeException("stub"); }
    }
}
