package kr.gen5w.portable;
import android.content.ComponentName;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.Intent;
import java.lang.reflect.Method;
import kr.gen5w.gpm.PortableUsbPolicy;
/** GPM adapter loads independently from DiPO classes. */
public final class GpmAdapters {
  private static ProjectionAdapters.Transaction transaction;
  private GpmAdapters() {}
  public static synchronized boolean install(Context context) throws Exception {
    beginInstall(context).commit();
    return true;
  }
  public static synchronized ProjectionAdapters.Transaction beginInstall(Context context) throws Exception {
    if (context == null) throw new NullPointerException("context");
    if (transaction != null && !transaction.isRolledBack()) {
      if (transaction.isCommitted()) return transaction;
      throw new ProjectionAdapters.RollbackFailure(
          new IllegalStateException("previous adapter transaction is unresolved"));
    }
    Method target =
        ContextWrapper.class.getDeclaredMethod("startService", Intent.class);
    Method replacement = GpmAdapters.class.getDeclaredMethod(
        "startService", Object.class, Object.class, Integer.TYPE);
    transaction = new ProjectionAdapters.Transaction();
    try {
      transaction.add(target, replacement);
      return transaction;
    } catch (RuntimeException failure) {
      try { transaction.rollback(); }
      catch (ProjectionAdapters.RollbackFailure rollback) {
        rollback.addSuppressed(failure);
        throw rollback;
      }
      throw failure;
    } catch (Error failure) {
      try { transaction.rollback(); }
      catch (ProjectionAdapters.RollbackFailure rollback) {
        rollback.addSuppressed(failure);
        throw rollback;
      }
      throw failure;
    }
  }
  public static ComponentName startService(Object receiver, Object intent,
                                           int handle) throws Throwable {
    if (PortableUsbPolicy.suppress((Intent)intent))
      return null;
    return (ComponentName)Hook.original(handle, receiver,
                                        new Object[] {intent});
  }
}
