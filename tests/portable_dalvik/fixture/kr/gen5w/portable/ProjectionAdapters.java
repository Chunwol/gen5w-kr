package kr.gen5w.portable;
import android.content.Context;
import java.io.File;
import java.io.FileOutputStream;
public final class ProjectionAdapters {
    public static final class Transaction {
        private final File marker;
        private boolean committed;
        Transaction(File marker) { this.marker = marker; }
        public void commit() { committed = true; }
        public void rollback() throws Exception {
            if (!committed && marker.exists() && !marker.delete())
                throw new IllegalStateException("fixture rollback failed");
        }
    }
    public static Transaction beginInstall(Context context) throws Exception {
        // Hook comes from the engine's own DexClassLoader directly under the
        // boot loader, never from the bootclasspath or the application loader.
        ClassLoader engine = Hook.class.getClassLoader();
        if (!(engine instanceof dalvik.system.DexClassLoader)) throw new AssertionError("Hook must come from the engine loader");
        if (engine.getParent() != Context.class.getClassLoader()) throw new AssertionError("engine loader parent must be boot");
        if (System.getProperty("java.boot.class.path", "").contains("engine")) throw new AssertionError("engine on bootclasspath");
        File installed = new File(context.getDir("gen5w-adapters", 0), "fixture-installed");
        FileOutputStream marker = new FileOutputStream(installed);
        marker.close();
        return new Transaction(installed);
    }
}
