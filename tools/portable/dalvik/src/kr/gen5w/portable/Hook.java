package kr.gen5w.portable;

import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.lang.reflect.InvocationTargetException;
import java.util.ArrayList;

/** Explicit process-local installation. Loading this class never installs a hook. */
public final class Hook {
    private static final ArrayList<Method> originals = new ArrayList<Method>();
    private static final ArrayList<Method> replacements = new ArrayList<Method>();
    private static final ArrayList<Boolean> active = new ArrayList<Boolean>();
    private Hook() {}
    public static synchronized int install(Method target, Method replacement) {
        if (target == null || replacement == null) throw new NullPointerException();
        for (int i = 0; i < originals.size(); i++)
            if (active.get(i).booleanValue() && originals.get(i).equals(target))
                throw new IllegalStateException("method already hooked");
        if (Modifier.isNative(target.getModifiers()) || Modifier.isAbstract(target.getModifiers()))
            throw new IllegalArgumentException("target must be a concrete managed method");
        if (!Modifier.isStatic(replacement.getModifiers()) || target.getReturnType() != replacement.getReturnType())
            throw new IllegalArgumentException("replacement must be static with identical return type");
        Class<?>[] from = target.getParameterTypes();
        Class<?>[] to = replacement.getParameterTypes();
        int receiver = Modifier.isStatic(target.getModifiers()) ? 0 : 1;
        if (to.length != from.length + receiver + 1 || to[to.length - 1] != Integer.TYPE)
            throw new IllegalArgumentException("replacement arguments/handle mismatch");
        if (receiver == 1 && !to[0].isAssignableFrom(target.getDeclaringClass()))
            throw new IllegalArgumentException("replacement receiver mismatch");
        for (int i = 0; i < from.length; i++) if (!to[i + receiver].isAssignableFrom(from[i]))
            throw new IllegalArgumentException("replacement parameter mismatch");
        int handle = originals.size();
        target.setAccessible(true);
        replacement.setAccessible(true);
        originals.add(target);
        replacements.add(replacement);
        active.add(Boolean.TRUE);
        try { installNative(target, replacement, handle); }
        catch (RuntimeException e) { originals.remove(handle); replacements.remove(handle); active.remove(handle); throw e; }
        catch (Error e) { originals.remove(handle); replacements.remove(handle); active.remove(handle); throw e; }
        return handle;
    }
    public static Object original(int handle, Object receiver, Object[] args) throws Throwable {
        Method target;
        synchronized (Hook.class) {
            if (handle < 0 || handle >= originals.size()) throw new IllegalArgumentException("unknown hook handle");
            target = originals.get(handle);
            if (target == null) throw new IllegalArgumentException("inactive hook handle");
        }
        try { return originalNative(handle, target.getParameterTypes(), target.getReturnType(), receiver, args); }
        catch (InvocationTargetException wrapped) { throw wrapped.getCause(); }
    }
    private static native void installNative(Method target, Method replacement, int handle);
    public static synchronized void uninstall(int handle) {
        if (handle < 0 || handle >= originals.size() || !active.get(handle).booleanValue())
            throw new IllegalArgumentException("inactive hook handle");
        uninstallNative(handle);
        active.set(handle, Boolean.FALSE);
        // Retain replacement and original metadata: a suspended caller can still finish its frame.
    }
    private static native void uninstallNative(int handle);
    private static native Object originalNative(int handle, Class<?>[] parameters, Class<?> returns,
                                                Object receiver, Object[] args) throws InvocationTargetException;
}
