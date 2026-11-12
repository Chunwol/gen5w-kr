package kr.gen5w.gpm;
import android.content.ComponentName;
import android.content.Intent;
import android.hardware.usb.UsbDevice;
/**
 * Shares the reviewed GPM USB classification without recursively starting a
 * service.
 */
public final class PortableUsbPolicy {
  private PortableUsbPolicy() {}
  public static boolean suppress(Intent intent) {
    try {
      ComponentName component = intent == null ? null : intent.getComponent();
      if (component == null ||
          !"com.google.android.projection.sink".equals(
              component.getPackageName()) ||
          !"com.google.android.projection.service.GalReceiverService".equals(
              component.getClassName()) ||
          intent.getIntExtra("startMode", -1) != 1)
        return false;
      Object device = intent.getParcelableExtra("device");
      return device instanceof UsbDevice &&
          GpmUsbGuard.storageOnly((UsbDevice)device);
    } catch (RuntimeException failure) {
      kr.gen5w.diag.SafeDiagnostic.failure("gpm.usb.metadata", failure);
      return false;
    }
  }
}
