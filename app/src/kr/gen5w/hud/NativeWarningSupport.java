package kr.gen5w.hud;

import java.lang.reflect.Method;
import java.lang.reflect.Modifier;

/** Declaration-only discovery. Writer presence does not prove incoming native
 * warning data, a running navigation engine, or display during CarPlay.
 * No method discovered here is invoked and no warning values are retained.
 */
public final class NativeWarningSupport {
    private NativeWarningSupport() { }

    public static String inspect(Class<?> clusterType) {
        boolean trap = false, distance = false, speedLimit = false;
        try {
            if (clusterType != null) for (Method method : clusterType.getMethods()) {
                if (method.getReturnType() != Void.TYPE || Modifier.isStatic(method.getModifiers())) continue;
                Class<?>[] args = method.getParameterTypes();
                String name = method.getName();
                if ("updateTBTTrapInfo".equals(name) && integers(args, 17)) trap = true;
                if ("updateTBTTrapInfoNew".equals(name) && args.length == 1
                        && "com.hkmc.cluster.NavigationCluster$NaviTbtTrapInfo".equals(args[0].getName())) trap = true;
                if (("updateNaviWarnDist".equals(name) && integers(args, 3))
                        || ("updateNaviWarnDist2".equals(name) && integers(args, 10))) distance = true;
                if ("updateSLIFNaviInformation".equals(name)
                        && (integers(args, 5) || integers(args, 6) || integers(args, 11))) speedLimit = true;
            }
        } catch (RuntimeException e) { return "APIS_UNAVAILABLE_SOURCE_UNOBSERVED"; }
          catch (LinkageError e) { return "APIS_UNAVAILABLE_SOURCE_UNOBSERVED"; }
        if (trap && distance && speedLimit) return "APIS_PRESENT_SOURCE_UNOBSERVED";
        return trap || distance || speedLimit ? "APIS_INCOMPLETE_SOURCE_UNOBSERVED"
                : "APIS_UNAVAILABLE_SOURCE_UNOBSERVED";
    }

    private static boolean integers(Class<?>[] args, int count) {
        if (args.length != count) return false;
        for (Class<?> arg : args) if (arg != Integer.TYPE) return false;
        return true;
    }
}
