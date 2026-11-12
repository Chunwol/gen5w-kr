package kr.gen5w.portable;
import android.content.ComponentName;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.Intent;
import java.lang.reflect.Method;
import kr.gen5w.gpm.PortableUsbPolicy;
/** GPM adapter loads independently from DiPO classes. */
public final class GpmAdapters {
  private static boolean installed;
  private GpmAdapters() {}
  public static synchronized boolean install(Context context) throws Exception {
    if (installed)
      return true;
    Method target =
        ContextWrapper.class.getDeclaredMethod("startService", Intent.class);
    Method replacement = GpmAdapters.class.getDeclaredMethod(
        "startService", Object.class, Object.class, Integer.TYPE);
    Hook.install(target, replacement);
    installed = true;
    return true;
  }
  public static ComponentName startService(Object receiver, Object intent,
                                           int handle) throws Throwable {
    if (PortableUsbPolicy.suppress((Intent)intent))
      return null;
    return (ComponentName)Hook.original(handle, receiver,
                                        new Object[] {intent});
  }
}
