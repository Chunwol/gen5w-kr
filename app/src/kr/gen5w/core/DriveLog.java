package kr.gen5w.core;

import android.os.SystemClock;
import android.util.Log;

/** Fixed numeric-only schema consumed by the optional USB logger. */
final class DriveLog {
    private DriveLog() {}
    static void core(int event, long a, long b, long c, long d, long e, long f) {
        write(2, event, a, b, c, d, e, f);
    }
    static void write(int source, int event, long a, long b, long c, long d, long e, long f) {
        Log.i("Gen5wDrive", "D1|" + SystemClock.elapsedRealtime() + "|" + source + "|" + event
                + "|" + a + "|" + b + "|" + c + "|" + d + "|" + e + "|" + f);
    }
}
