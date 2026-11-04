package kr.gen5w.wireless;

import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;

/** Source-verified, profile-scoped requests to the V039 PhoneProjection service. */
public final class PhoneProjectionAccess {
    public static final int TYPE_CARPLAY = 1;
    public static final int TYPE_ANDROID_AUTO = 2;
    private static final int STATE_NONE = 0;
    private static final int STATE_CANCEL = 1;
    private static final int STATE_CONNECTING = 2;
    private static final int STATE_CONNECTED = 3;
    public static final String OEM_PACKAGE = "com.daudio.app.phoneprojection";
    public static final String OEM_CONNECT_ACTION =
            "com.daudio.app.PhoneProjection.Wireless.SEND_CONNECTION_PHONEPROJECTION";
    public static final String OEM_DEVICE_ADDRESS_EXTRA = "deviceAddress";
    public static final String OEM_BOOTSTRAP_ACTION =
            "android.bluetooth.device.action.START_SPP_CONNECT_FOR_CONNECTIVITY";
    public static final String OEM_BOOTSTRAP_ADDRESS_EXTRA = "ADDRESS";

    public interface ServiceProvider { Object get(String name); }
    public interface ProfileProvider { Profile find(String address); }
    public interface ActionSender {
        boolean send(String action, String packageName, String extra, String address);
    }
    public interface BootstrapAdmission { boolean claim(); }

    public static final class Profile {
        public final String address;
        public final int type;
        public final boolean enabled;
        public final boolean autoConnect;

        public Profile(String address, int type, boolean enabled, boolean autoConnect) {
            this.address = address;
            this.type = type;
            this.enabled = enabled;
            this.autoConnect = autoConnect;
        }
    }

    private PhoneProjectionAccess() {}

    private static final class MethodUnavailableException extends RuntimeException {
        private static final long serialVersionUID = 1L;
    }

    public static StockProjectionSession.Observation inspect(ServiceProvider provider, String address) {
        return inspect(provider, null, address);
    }

    /** Observe the address selected by the current OEM profile, if one exists. */
    public static StockProjectionSession.Observation inspect(
            ServiceProvider provider, Object context, String address) {
        if (provider == null || address == null) return unavailable(StockProjectionSession.Result.INVOCATION);
        final Object manager;
        try { manager = provider.get("phoneprojection"); }
        catch (SecurityException e) { return unavailable(StockProjectionSession.Result.SECURITY); }
        catch (RuntimeException e) { return unavailable(StockProjectionSession.Result.INVOCATION); }
        if (manager == null) return unavailable(StockProjectionSession.Result.SERVICE_UNAVAILABLE);

        try {
            Profile profile = context instanceof ProfileProvider
                    ? ((ProfileProvider) context).find(address)
                    : context == null ? new Profile(address, TYPE_CARPLAY, true, true)
                    : readCurrentProfile(manager, context, address);
            if (profile == null) {
                Object stateValue = manager.getClass().getMethod("getWirelessConnectState").invoke(manager);
                if (!(stateValue instanceof Integer)) return unavailable(StockProjectionSession.Result.INVOCATION);
                int state = ((Integer) stateValue).intValue();
                return new StockProjectionSession.Observation(StockProjectionSession.Result.INVOKED,
                        true, 0, StockProjectionSession.ProfileState.MISSING, false, false,
                        state != STATE_NONE, StockProjectionSession.WifiCredentialState.UNKNOWN, 11);
            }
            if (profile.type != TYPE_CARPLAY && profile.type != TYPE_ANDROID_AUTO) {
                return new StockProjectionSession.Observation(StockProjectionSession.Result.INVOKED,
                        true, profile.type, StockProjectionSession.ProfileState.UNSUPPORTED, false,
                        false, true, StockProjectionSession.WifiCredentialState.UNKNOWN, 11);
            }
            if (profile.address == null || !profile.address.equalsIgnoreCase(address)) {
                return new StockProjectionSession.Observation(StockProjectionSession.Result.INVOKED,
                        true, profile.type, StockProjectionSession.ProfileState.UNKNOWN, false,
                        false, true, StockProjectionSession.WifiCredentialState.UNKNOWN, 11);
            }
            String getter = profile.type == TYPE_CARPLAY
                    ? "getCPConnectedBTAddress" : "getAAConnectedBTAddress";
            Object connectedValue = manager.getClass().getMethod(getter).invoke(manager);
            if (connectedValue != null && !(connectedValue instanceof String)) return unavailable(StockProjectionSession.Result.INVOCATION);
            String connected = connectedValue == null ? "" : (String) connectedValue;
            Object stateValue = manager.getClass().getMethod("getWirelessConnectState").invoke(manager);
            if (!(stateValue instanceof Integer)) return unavailable(StockProjectionSession.Result.INVOCATION);
            int wirelessState = ((Integer) stateValue).intValue();
            boolean addressMatches = connected.length() != 0 && connected.equalsIgnoreCase(address);
            boolean active = wirelessState == STATE_CONNECTED && addressMatches;
            boolean connecting = wirelessState == STATE_CONNECTING && addressMatches;
            // CANCEL, unknown states, or any non-idle state owned by another/unknown
            // address fail closed; only the same candidate's CONNECTING state is polled.
            boolean other = !active && !connecting && wirelessState != STATE_NONE;
            StockProjectionSession.ProfileState profileState = !profile.enabled
                    ? StockProjectionSession.ProfileState.DISABLED
                    : !profile.autoConnect ? StockProjectionSession.ProfileState.AUTO_CONNECT_DISABLED
                    : StockProjectionSession.ProfileState.READY;
            return new StockProjectionSession.Observation(StockProjectionSession.Result.INVOKED,
                    true, profile.type, profileState, active, connecting, other,
                    StockProjectionSession.WifiCredentialState.UNKNOWN, 11);
        } catch (NoSuchMethodException e) {
            return unavailable(StockProjectionSession.Result.METHOD_UNAVAILABLE);
        } catch (MethodUnavailableException e) {
            return unavailable(StockProjectionSession.Result.METHOD_UNAVAILABLE);
        } catch (InvocationTargetException e) {
            return unavailable(cause(e) instanceof SecurityException
                    ? StockProjectionSession.Result.SECURITY : StockProjectionSession.Result.INVOCATION);
        } catch (IllegalAccessException e) {
            return unavailable(StockProjectionSession.Result.SECURITY);
        } catch (SecurityException e) {
            return unavailable(StockProjectionSession.Result.SECURITY);
        } catch (RuntimeException e) {
            return unavailable(StockProjectionSession.Result.INVOCATION);
        }
    }

    /** Read the current user's saved profile using the same PPManager API used by V039. */
    public static Profile readCurrentProfile(ServiceProvider provider, Object context, String address) {
        if (provider == null || context == null || address == null) return null;
        Object manager = provider.get("phoneprojection");
        if (manager == null) return null;
        return readCurrentProfile(manager, context, address);
    }

    private static Profile readCurrentProfile(Object manager, Object context, String address) {
        try {
            ClassLoader loader = context.getClass().getClassLoader();
            Class<?> profileManagerType = Class.forName(
                    "com.hkmc.userprofile.UserProfileManager", true, loader);
            Object profileManager = newContextManager(profileManagerType, context);
            Object userTypeValue = profileManagerType.getMethod("getUserType").invoke(profileManager);
            if (!(userTypeValue instanceof Integer)) return null;
            int userType = ((Integer) userTypeValue).intValue();
            if (userType < 0 || userType > 2) return null;

            Method getInfo = manager.getClass().getMethod("getWLDeviceInfo",
                    String.class, String.class, Integer.TYPE);
            Object info = getInfo.invoke(manager, address, "", Integer.valueOf(userType));
            if (info == null) return null;
            Object storedAddress = info.getClass().getMethod("getWLDevBtAddr").invoke(info);
            Object type = info.getClass().getMethod("getWLDType").invoke(info);
            Object enabled = info.getClass().getMethod("getWLDOnOff").invoke(info);
            Object auto = info.getClass().getMethod("getWLDAutoConnection").invoke(info);
            if (!(storedAddress instanceof String) || !(type instanceof Integer) ||
                    !(enabled instanceof Boolean) || !(auto instanceof Boolean)) return null;
            return new Profile((String) storedAddress, ((Integer) type).intValue(),
                    ((Boolean) enabled).booleanValue(), ((Boolean) auto).booleanValue());
        } catch (InvocationTargetException e) {
            Throwable root = cause(e);
            if (root instanceof SecurityException) throw (SecurityException) root;
            throw new IllegalStateException();
        } catch (ReflectiveOperationException e) {
            if (e instanceof NoSuchMethodException) throw new MethodUnavailableException();
            throw new IllegalStateException();
        } catch (SecurityException e) {
            throw e;
        } catch (RuntimeException e) {
            throw new IllegalStateException();
        }
    }

    private static Object newContextManager(Class<?> type, Object context)
            throws ReflectiveOperationException {
        for (Constructor<?> constructor : type.getConstructors()) {
            Class<?>[] parameters = constructor.getParameterTypes();
            if (parameters.length == 1 && parameters[0].isAssignableFrom(context.getClass())) {
                return constructor.newInstance(context);
            }
        }
        throw new NoSuchMethodException();
    }

    public static StockProjectionSession.RequestResult requestProfileAction(
            ProfileProvider profiles, ActionSender sender, String address) {
        if (profiles == null || sender == null || address == null) {
            return StockProjectionSession.RequestResult.INVOCATION;
        }
        final Profile profile;
        try { profile = profiles.find(address); }
        catch (SecurityException e) { return StockProjectionSession.RequestResult.SECURITY; }
        catch (MethodUnavailableException e) { return StockProjectionSession.RequestResult.METHOD_UNAVAILABLE; }
        catch (RuntimeException e) { return StockProjectionSession.RequestResult.INVOCATION; }
        if (profile == null) return StockProjectionSession.RequestResult.PROFILE_UNAVAILABLE;
        if (profile.address == null || !profile.address.equalsIgnoreCase(address) ||
                (profile.type != TYPE_CARPLAY && profile.type != TYPE_ANDROID_AUTO)) {
            return StockProjectionSession.RequestResult.PROFILE_MISMATCH;
        }
        if (!profile.enabled) return StockProjectionSession.RequestResult.PROFILE_DISABLED;
        if (!profile.autoConnect) return StockProjectionSession.RequestResult.AUTO_CONNECT_DISABLED;
        try {
            if (!sender.send(OEM_CONNECT_ACTION, OEM_PACKAGE, OEM_DEVICE_ADDRESS_EXTRA, address)) {
                return StockProjectionSession.RequestResult.CANCELLED;
            }
            return StockProjectionSession.RequestResult.OEM_ACTION_SENT;
        } catch (SecurityException e) {
            return StockProjectionSession.RequestResult.SECURITY;
        } catch (RuntimeException e) {
            return StockProjectionSession.RequestResult.INVOCATION;
        }
    }

    public static StockProjectionSession.RequestResult requestCurrentProfile(
            ServiceProvider services, Object context, ActionSender sender, final String address) {
        if (services == null || context == null || sender == null || address == null) {
            return StockProjectionSession.RequestResult.INVOCATION;
        }
        final Object manager;
        try { manager = services.get("phoneprojection"); }
        catch (SecurityException e) { return StockProjectionSession.RequestResult.SECURITY; }
        catch (RuntimeException e) { return StockProjectionSession.RequestResult.INVOCATION; }
        if (manager == null) return StockProjectionSession.RequestResult.SERVICE_UNAVAILABLE;
        return requestProfileAction(new ProfileProvider() {
            public Profile find(String value) {
                return readCurrentProfile(manager, context, value);
            }
        }, sender, address);
    }

    /** Start the OEM first-registration path once; a request is not a profile or connection success. */
    public static StockProjectionSession.BootstrapResult bootstrap(
            ServiceProvider services, Object context, ActionSender sender, String address,
            BootstrapAdmission admission) {
        if (services == null || context == null || sender == null || address == null || admission == null) {
            return StockProjectionSession.BootstrapResult.INVOCATION;
        }
        final Object manager;
        final Method request;
        try {
            manager = services.get("phoneprojection");
        } catch (SecurityException e) {
            return StockProjectionSession.BootstrapResult.SECURITY;
        } catch (RuntimeException e) {
            return StockProjectionSession.BootstrapResult.INVOCATION;
        }
        if (manager == null) return StockProjectionSession.BootstrapResult.SERVICE_UNAVAILABLE;
        try {
            request = manager.getClass().getMethod("requestConnectSPP", String.class);
        } catch (NoSuchMethodException e) {
            return StockProjectionSession.BootstrapResult.METHOD_UNAVAILABLE;
        } catch (SecurityException e) {
            return StockProjectionSession.BootstrapResult.SECURITY;
        } catch (RuntimeException e) {
            return StockProjectionSession.BootstrapResult.INVOCATION;
        }
        try {
            if (!sender.send(OEM_BOOTSTRAP_ACTION, OEM_PACKAGE,
                    OEM_BOOTSTRAP_ADDRESS_EXTRA, address)) {
                return StockProjectionSession.BootstrapResult.CANCELLED;
            }
        } catch (SecurityException e) {
            return StockProjectionSession.BootstrapResult.SECURITY;
        } catch (RuntimeException e) {
            return StockProjectionSession.BootstrapResult.INVOCATION;
        }
        try {
            if (!admission.claim()) return StockProjectionSession.BootstrapResult.CANCELLED;
            request.invoke(manager, address);
            return StockProjectionSession.BootstrapResult.OEM_REQUESTED;
        } catch (InvocationTargetException e) {
            return cause(e) instanceof SecurityException
                    ? StockProjectionSession.BootstrapResult.SECURITY
                    : StockProjectionSession.BootstrapResult.INVOCATION;
        } catch (IllegalAccessException e) {
            return StockProjectionSession.BootstrapResult.SECURITY;
        } catch (SecurityException e) {
            return StockProjectionSession.BootstrapResult.SECURITY;
        } catch (RuntimeException e) {
            return StockProjectionSession.BootstrapResult.INVOCATION;
        }
    }

    private static Throwable cause(InvocationTargetException e) {
        return e.getCause() == null ? e : e.getCause();
    }

    private static StockProjectionSession.Observation unavailable(StockProjectionSession.Result result) {
        return new StockProjectionSession.Observation(result, false, false, false);
    }
}
