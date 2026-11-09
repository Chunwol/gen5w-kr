package kr.gen5w.gpm;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbInterface;
import kr.gen5w.diag.SafeDiagnostic;

/** Narrow process-local guard for exact-V039 GPM service starts. */
public final class GpmUsbGuard {
    private GpmUsbGuard() {}

    public static ComponentName startService(Context context, Intent intent) {
        boolean suppress = false;
        try {
            ComponentName component = intent == null ? null : intent.getComponent();
            if (component != null
                    && "com.google.android.projection.sink".equals(component.getPackageName())
                    && "com.google.android.projection.service.GalReceiverService".equals(component.getClassName())
                    && intent.getIntExtra("startMode", -1) == 1) {
                Object device = intent.getParcelableExtra("device");
                suppress = device instanceof UsbDevice && storageOnly((UsbDevice) device);
            }
        } catch (RuntimeException failure) {
            SafeDiagnostic.failure("gpm.usb.metadata", failure);
        }
        if (suppress) return null;
        // Never catch/retry the delegated start: its exception belongs to the caller.
        return context.startService(intent);
    }

    static boolean storageOnly(UsbDevice device) {
        int count = device.getInterfaceCount();
        if (count <= 0) return false;
        for (int i = 0; i < count; i++) {
            UsbInterface item = device.getInterface(i);
            if (item == null) return false;
            int type = item.getInterfaceClass();
            if (type != 8 && type != 9) return false;
        }
        return true;
    }
}
