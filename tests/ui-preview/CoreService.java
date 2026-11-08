package kr.gen5w.core;

/** Emulator boundary only: never start OEM/HUD services from a UI test. */
public final class CoreService extends android.app.Service {
    @Override public android.os.IBinder onBind(android.content.Intent intent) { return null; }
}
