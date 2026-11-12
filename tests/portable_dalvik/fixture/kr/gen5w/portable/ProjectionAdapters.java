package kr.gen5w.portable;
import android.content.Context;
import java.io.File;
import java.io.FileOutputStream;
public final class ProjectionAdapters {
    public static boolean install(Context context) throws Exception {
        if (Hook.class.getClassLoader() != Context.class.getClassLoader()) throw new AssertionError("Hook must be shared boot class");
        FileOutputStream marker = new FileOutputStream(new File(context.getDir("gen5w-adapters", 0), "fixture-installed"));
        marker.close();
        return true;
    }
}
