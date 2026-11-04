package kr.gen5w.wireless;

import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;

/** Read-only projection Wi-Fi credential-presence and AP-state observer. */
public final class ProjectionWifiAccess {
    public enum CredentialStatus { UNKNOWN, MISSING, PRESENT }
    public enum ApProgress { UNKNOWN, OFF, ENABLING, READY, FAILED }

    public static final class CredentialObservation {
        public final CredentialStatus status;

        private CredentialObservation(CredentialStatus status) {
            this.status = status;
        }
    }

    private ProjectionWifiAccess() {}

    public static CredentialObservation inspect(Object wifiManager) {
        if (wifiManager == null) return observation(CredentialStatus.UNKNOWN);
        try {
            Method getter = wifiManager.getClass().getMethod("getWifiApConfiguration");
            Object configuration = getter.invoke(wifiManager);
            if (configuration == null) return observation(CredentialStatus.UNKNOWN);

            Field ssidField = configuration.getClass().getField("ConnectivitySSID");
            Field pskField = configuration.getClass().getField("ConnectivityPSK");
            boolean ssidPresent = hasNonBlankText(ssidField.get(configuration));
            boolean pskPresent = hasNonBlankText(pskField.get(configuration));
            boolean present = ssidPresent && pskPresent;
            return observation(present ? CredentialStatus.PRESENT : CredentialStatus.MISSING);
        } catch (InvocationTargetException e) {
            return observation(CredentialStatus.UNKNOWN);
        } catch (ReflectiveOperationException e) {
            return observation(CredentialStatus.UNKNOWN);
        } catch (SecurityException e) {
            return observation(CredentialStatus.UNKNOWN);
        } catch (RuntimeException e) {
            return observation(CredentialStatus.UNKNOWN);
        }
    }

    public static ApProgress classifyApState(int state) {
        switch (state) {
            case 10:
            case 11:
                return ApProgress.OFF;
            case 12:
                return ApProgress.ENABLING;
            case 13:
                return ApProgress.READY;
            case 14:
                return ApProgress.FAILED;
            default:
                return ApProgress.UNKNOWN;
        }
    }

    private static CredentialObservation observation(CredentialStatus status) {
        return new CredentialObservation(status);
    }

    private static boolean hasNonBlankText(Object value) {
        if (value == null) return false;
        if (!(value instanceof String)) throw new IllegalStateException();
        return ((String) value).trim().length() != 0;
    }
}
