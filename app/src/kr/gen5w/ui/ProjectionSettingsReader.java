package kr.gen5w.ui;

import android.content.ContentResolver;
import android.content.Context;
import android.provider.Settings;
import kr.gen5w.diag.SafeDiagnostic;

/**
 * Android ContentResolver reader for stock PhoneProjection Settings.System keys.
 * Matches V039 PhoneProjection profile lookup (no fallback to guest/base when _dr1/_dr2 is unset).
 */
public final class ProjectionSettingsReader {
    private static volatile Object cachedProfileManager;

    private ProjectionSettingsReader() { }

    public static ProjectionSettings.Snapshot read(Context context) {
        if (context == null) return ProjectionSettings.unknown();
        try {
            ContentResolver cr = context.getContentResolver();
            if (cr == null) return ProjectionSettings.unknown();
            int user = resolveUserType(context);
            return ProjectionSettings.fromValues(
                    getProfileInt(cr, "carplay_ss_osd", user),
                    getProfileInt(cr, "androidauto_ss_osd", user),
                    getProfileInt(cr, "carplay_information", user),
                    getProfileInt(cr, "androidauto_information", user),
                    getProfileInt(cr, "carplya_rhd", user));
        } catch (LinkageError e) {
            SafeDiagnostic.failure("ui.pp.read", e);
            return ProjectionSettings.unknown();
        } catch (RuntimeException e) {
            SafeDiagnostic.failure("ui.pp.read", e);
            return ProjectionSettings.unknown();
        }
    }

    private static int resolveUserType(Context context) {
        try {
            Object mgr = cachedProfileManager;
            Class<?> cls = Class.forName("com.hkmc.userprofile.UserProfileManager");
            if (mgr == null || !cls.isInstance(mgr)) {
                Context appCtx = context.getApplicationContext();
                mgr = cls.getConstructor(Context.class).newInstance(appCtx != null ? appCtx : context);
                cachedProfileManager = mgr;
            }
            Object val = cls.getMethod("getUserType").invoke(mgr);
            if (val instanceof Number) {
                int user = ((Number) val).intValue();
                if (user == 1 || user == 2) return user;
            }
        } catch (LinkageError ignored) {
            // Fall back to user 0 when UserProfileManager fails to link cleanly.
        } catch (Exception ignored) {
            // Fall back to user 0 when UserProfileManager is unavailable or unset.
        }
        return 0;
    }

    private static Integer getProfileInt(ContentResolver cr, String baseKey, int user) {
        String key = (user == 1 || user == 2) ? (baseKey + "_dr" + user) : baseKey;
        int val = Settings.System.getInt(cr, key, -1);
        return val >= 0 ? Integer.valueOf(val) : null;
    }
}
