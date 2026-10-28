package kr.gen5w.core;

import android.content.Context;
import android.database.Cursor;
import android.net.LocalServerSocket;
import android.net.LocalSocket;
import android.net.Uri;
import android.os.Looper;
import android.os.Process;

/** System-uid NEMESIS service. Its sole operation reads one non-personal flag. */
public final class StockOwner {
    private static final Uri STATE = Uri.parse("content://com.mnsoft.navi/State_Table");

    private static int read(Context context) {
        Cursor cursor = null;
        try {
            cursor = context.getContentResolver().query(STATE,
                    new String[]{"State_Destination"}, null, null, null);
            if (cursor == null || cursor.getColumnCount() != 1) return '?';
            int rows = 0;
            while (cursor.moveToNext()) {
                if (++rows > 32 || cursor.isNull(0)) return '?';
                String state = cursor.getString(0);
                if ("1".equals(state)) return '1';
                if (!"0".equals(state)) return '?';
            }
            return '0';
        } catch (RuntimeException e) { return '?'; }
        finally {
            if (cursor != null) try { cursor.close(); } catch (RuntimeException ignored) { }
        }
    }

    public static void main(String[] args) throws Exception {
        if (Process.myUid() != 1000 || args.length != 0) System.exit(1);
        Looper.prepareMainLooper();
        Class<?> type = Class.forName("android.app.ActivityThread");
        Object thread = type.getMethod("systemMain").invoke(null);
        final Context context = (Context)type.getMethod("getSystemContext").invoke(thread);
        final int clientUid = context.getPackageManager().getApplicationInfo("kr.gen5w.core", 0).uid;
        final LocalServerSocket server = new LocalServerSocket(StockGuidance.SOCKET);
        new Thread(new Runnable() {
            public void run() {
                try {
                    while (true) {
                        LocalSocket client = server.accept();
                        try {
                            client.setSoTimeout(200);
                            if (client.getPeerCredentials().getUid() == clientUid
                                    && client.getInputStream().read() == '?') {
                                client.getOutputStream().write(read(context));
                            }
                        } catch (java.io.IOException ignored) { }
                        finally { try { client.close(); } catch (java.io.IOException ignored) { } }
                    }
                } catch (java.io.IOException e) { System.exit(1); }
            }
        }, "gen5w-stock-owner").start();
        Looper.loop();
    }
}
