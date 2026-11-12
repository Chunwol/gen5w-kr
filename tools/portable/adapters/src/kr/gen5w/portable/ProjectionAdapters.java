package kr.gen5w.portable;
import android.content.Context;
import java.lang.reflect.InvocationTargetException;
/**
 * Dispatch has no DiPO/OEM references, so GPM verification cannot resolve DiPO
 * classes.
 */
public final class ProjectionAdapters {
  private ProjectionAdapters() {}
  public static boolean install(Context context) throws Throwable {
    if (context == null)
      throw new NullPointerException("context");
    String name = context.getPackageName(), implementation;
    if ("com.daudio.app.dipo".equals(name))
      implementation = "kr.gen5w.portable.DipoAdapters";
    else if ("com.google.android.projection.sink".equals(name))
      implementation = "kr.gen5w.portable.GpmAdapters";
    else
      return false;
    try {
      Class<?> type = Class.forName(implementation, true,
                                    ProjectionAdapters.class.getClassLoader());
      return (Boolean)type.getMethod("install", Context.class)
          .invoke(null, context);
    } catch (InvocationTargetException failure) {
      throw failure.getCause();
    }
  }
}
