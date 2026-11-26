package kr.gen5w.portable;
import android.content.Context;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.ArrayList;
/**
 * Dispatch has no DiPO/OEM references, so GPM verification cannot resolve DiPO
 * classes.
 */
public final class ProjectionAdapters {
  private ProjectionAdapters() {}
  /** Cross-loader failure contract: the process still owns active hooks. */
  public static final class RollbackFailure extends IllegalStateException {
    public RollbackFailure(Throwable cause) {
      super("adapter rollback incomplete; hooks remain active", cause);
    }
  }
  /** Owns only one provisional group until its readiness marker is published. */
  public static final class Transaction {
    private final ArrayList<Integer> handles = new ArrayList<Integer>();
    private boolean committed, rolledBack, rollbackFailed;
    private Runnable onCommit;
    void add(Method target, Method replacement) {
      handles.add(Hook.install(target, replacement));
    }
    synchronized void setOnCommit(Runnable action) { onCommit = action; }
    synchronized boolean isCommitted() { return committed; }
    synchronized boolean isRolledBack() { return rolledBack; }
    public synchronized void commit() {
      if (rolledBack || rollbackFailed)
        throw new IllegalStateException("adapter transaction cannot commit");
      committed = true;
      if (onCommit != null) {
        Runnable action = onCommit;
        onCommit = null;
        action.run();
      }
    }
    public synchronized void rollback() {
      // An earlier successful installation belongs to its original caller.
      if (committed || rolledBack) return;
      RollbackFailure failure = null;
      for (int i = handles.size() - 1; i >= 0; i--) {
        try {
          Hook.uninstall(handles.get(i));
          handles.remove(i);
        } catch (Throwable cause) {
          if (failure == null)
            failure = new RollbackFailure(cause);
          else failure.addSuppressed(cause);
        }
      }
      rollbackFailed = failure != null;
      if (failure != null) throw failure;
      rolledBack = true;
    }
  }
  public static boolean install(Context context) throws Throwable {
    Transaction transaction = beginInstall(context);
    if (transaction == null) return false;
    transaction.commit();
    return true;
  }
  public static Transaction beginInstall(Context context) throws Throwable {
    if (context == null)
      throw new NullPointerException("context");
    String name = context.getPackageName(), implementation;
    if ("com.daudio.app.dipo".equals(name))
      implementation = "kr.gen5w.portable.DipoAdapters";
    else if ("com.google.android.projection.sink".equals(name))
      implementation = "kr.gen5w.portable.GpmAdapters";
    else if ("com.mnsoft.navi".equals(name))
      implementation = "kr.gen5w.portable.NaviAdapters";
    else
      return null;
    try {
      Class<?> type = Class.forName(implementation, true,
                                    ProjectionAdapters.class.getClassLoader());
      return (Transaction)type.getMethod("beginInstall", Context.class)
          .invoke(null, context);
    } catch (InvocationTargetException failure) {
      throw failure.getCause();
    }
  }
}
